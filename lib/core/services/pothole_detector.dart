import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io' show Platform;

import '../detection/detection.dart';
import '../detection/image_preprocessor.dart';
import '../detection/yolo_output_parser.dart';
import 'config/detection_settings.dart';

enum InferenceBackend { cpu }

class PotholeDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _initialized = false;
  InferenceSize? _activeSize;
  final InferenceBackend _backendUsed = InferenceBackend.cpu;

  Tensor? _inputTensor;
  Tensor? _outputTensor;

  List<List<dynamic>>? _cachedNestedOutput;

  final ImagePreprocessor _preprocessor = ImagePreprocessor();
  YoloOutputParser? _outputParser;

  int _frameCount = 0;
  int _lastInferenceMs = 0;
  int _lastNmsMs = 0;
  int _lastPreprocessMs = 0;

  LetterboxInfo? _lastLetterbox;

  static final PotholeDetector instance = PotholeDetector._internal();
  PotholeDetector._internal();

  // Public getters
  bool get initialized => _initialized;
  InferenceSize? get activeSize => _activeSize;
  InferenceBackend get backendUsed => _backendUsed;
  int get frameCount => _frameCount;
  int get lastInferenceMs => _lastInferenceMs;
  int get lastNmsMs => _lastNmsMs;
  int get lastPreprocessMs => _lastPreprocessMs;

  /// Debug boxes in model-input coordinates (for visualization).
  List<Rect> get lastPadBoxes => _outputParser?.lastPadBoxes ?? const [];
  List<Rect> get lastAltPadBoxes => _outputParser?.lastAltPadBoxes ?? const [];

  Future<void> loadModel() async {
    if (_initialized) return;
    final modelBytes = (await rootBundle.load(
      DetectionConfig.instance.currentModelAsset,
    )).buffer.asUint8List();
    final labels = await DetectionConfig.instance.loadLabels();
    await loadModelFromBuffer(modelBytes, labels);
  }

  Future<void> loadModelFromBuffer(
    Uint8List modelBytes,
    List<String> labels,
  ) async {
    if (_initialized) return;

    try {
      final numThreads = _determineThreadCount();
      final options = _createInterpreterOptions(numThreads);

      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter!.allocateTensors();

      _labels = labels;
      _activeSize = DetectionConfig.instance.inputSize;
      _initialized = true;

      _inputTensor = _interpreter!.getInputTensor(0);
      _outputTensor = _interpreter!.getOutputTensor(0);

      // Initialize output parser with labels
      _outputParser = YoloOutputParser(labels: _labels);

      debugPrint(
        "✅ PotholeDetector: model loaded. "
        "Input: ${_inputTensor?.shape}, Output: ${_outputTensor?.shape}",
      );
    } catch (e, st) {
      debugPrint("❌ PotholeDetector: error loading model: $e\n$st");
      rethrow;
    }
  }

  /// Determine optimal thread count for inference.
  int _determineThreadCount() {
    int numThreads = 1;
    try {
      final int cpuCount = Platform.numberOfProcessors;
      numThreads = math.max(1, cpuCount - 1);
      if (kDebugMode) {
        debugPrint("Intended TFLite Interpreter threads: $numThreads");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Failed to determine CPU count for TFLite threads: $e");
      }
    }
    return numThreads;
  }

  /// Create interpreter options with XNNPACK delegate.
  InterpreterOptions _createInterpreterOptions(int numThreads) {
    final options = InterpreterOptions();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        options.addDelegate(
          XNNPackDelegate(
            options: XNNPackDelegateOptions(numThreads: numThreads),
          ),
        );
        if (kDebugMode) {
          debugPrint(
            "✅ XNNPACK delegate initialized with $numThreads threads.",
          );
        }
      }
    } catch (e) {
      debugPrint(
        "⚠️ XNNPACK delegate failed to initialize, falling back to CPU: $e",
      );
    }
    return options;
  }

  /// Release interpreter resources.
  void close() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _initialized = false;
    _labels = [];
    _cachedNestedOutput = null;
    _outputParser = null;
    _lastLetterbox = null;
  }

  /// Process an RGB frame and return detections.
  Future<List<Detection>> processFrameFromRgb(
    Uint8List rgbBytes,
    int srcWidth,
    int srcHeight,
  ) async {
    if (!_initialized || _interpreter == null) return [];

    _frameCount++;

    final inputShape = _inputTensor!.shape;
    final inputH = inputShape[1];
    final inputW = inputShape[2];
    final inputChannels = inputShape[3];

    final inputType = _inputTensor!.type;
    final bool isInt8 = inputType == TensorType.int8;
    final bool isUint8 = inputType == TensorType.uint8;
    final bool useQuantizedInput = isInt8 || isUint8;

    double inScale = 1.0;
    int inZero = 0;
    if (useQuantizedInput) {
      final params = _inputTensor!.params;
      inScale = params.scale;
      inZero = params.zeroPoint;
    }

    // Delegate preprocessing
    final preprocessResult = _preprocessor.preprocessRgb(
      rgbBytes: rgbBytes,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      inputW: inputW,
      inputH: inputH,
      inputChannels: inputChannels,
      useQuantizedInput: useQuantizedInput,
      isInt8: isInt8,
      inScale: inScale,
      inZero: inZero,
      useBgr: DetectionConfig.useBgrInput,
    );

    _lastPreprocessMs = preprocessResult.preprocessMs;
    _lastLetterbox = preprocessResult.letterbox;

    return _runInference(preprocessResult.inputBuffer);
  }

  /// Process YUV planes and return detections.
  Future<List<Detection>> processFrameFromYuv(
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int srcWidth,
    int srcHeight,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
  ) async {
    if (!_initialized || _interpreter == null) return [];

    _frameCount++;

    final inputShape = _inputTensor!.shape;
    final inputH = inputShape[1];
    final inputW = inputShape[2];
    final inputChannels = inputShape[3];

    final inputType = _inputTensor!.type;
    final bool isInt8 = inputType == TensorType.int8;
    final bool isUint8 = inputType == TensorType.uint8;
    final bool useQuantizedInput = isInt8 || isUint8;

    double inScale = 1.0;
    int inZero = 0;
    if (useQuantizedInput) {
      final params = _inputTensor!.params;
      inScale = params.scale;
      inZero = params.zeroPoint;
    }

    // Delegate preprocessing
    final preprocessResult = _preprocessor.preprocessYuv(
      yPlane: yPlane,
      uPlane: uPlane,
      vPlane: vPlane,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      yRowStride: yRowStride,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      inputW: inputW,
      inputH: inputH,
      inputChannels: inputChannels,
      useQuantizedInput: useQuantizedInput,
      isInt8: isInt8,
      inScale: inScale,
      inZero: inZero,
      useBgr: DetectionConfig.useBgrInput,
    );

    _lastPreprocessMs = preprocessResult.preprocessMs;
    _lastLetterbox = preprocessResult.letterbox;

    return _runInference(preprocessResult.inputBuffer);
  }

  /// Run inference on preprocessed input buffer.
  Future<List<Detection>> _runInference(Uint8List inputBuffer) async {
    final swInf = Stopwatch()..start();

    final outputShape = _outputTensor!.shape;
    final int channels = outputShape[1];
    final int numDetections = outputShape[2];

    // Prepare output buffer
    _ensureOutputBuffer(channels, numDetections);
    final nestedOutput = _cachedNestedOutput!;

    if (kDebugMode) {
      debugPrint("🧠 Running inference on output shape: $outputShape");
    }

    // Run inference
    _interpreter!.run(inputBuffer, nestedOutput);

    swInf.stop();
    _lastInferenceMs = swInf.elapsedMilliseconds;

    if (kDebugMode) {
      debugPrint("✅ Inference completed in $_lastInferenceMs ms");
    }

    // Get output quantization params
    final params = _outputTensor!.params;
    final double outScale = params.scale;
    final int outZero = params.zeroPoint;

    if (kDebugMode) {
      debugPrint("📊 Output quantization: scale=$outScale, zeroPoint=$outZero");
    }

    // Delegate output parsing
    final detections = _outputParser!.parseOutput(
      nestedOutput: nestedOutput,
      channels: channels,
      numDetections: numDetections,
      inputW: _inputTensor!.shape[2],
      inputH: _inputTensor!.shape[1],
      letterbox: _lastLetterbox!,
      lastInferenceMs: _lastInferenceMs,
      outScale: outScale,
      outZero: outZero,
    );

    // Apply NMS
    final swNms = Stopwatch()..start();
    final filtered = _outputParser!.nonMaxSuppression(detections);
    swNms.stop();
    _lastNmsMs = swNms.elapsedMilliseconds;

    if (kDebugMode) {
      for (var d in filtered) {
        debugPrint(
          'Box: ${d.box}, scale=${d.letterboxScale}, '
          'dx=${d.letterboxDx}, dy=${d.letterboxDy}',
        );
      }
    }

    return filtered;
  }

  /// Ensure output buffer is allocated with correct dimensions.
  void _ensureOutputBuffer(int channels, int numDetections) {
    bool nestedOk = false;
    if (_cachedNestedOutput != null && _cachedNestedOutput!.length == 1) {
      final row = _cachedNestedOutput![0];
      if (row.length == channels && row.isNotEmpty) {
        final first = row[0];
        if (first is List) {
          nestedOk = (first).length == numDetections;
        }
      }
    }

    if (!nestedOk) {
      _cachedNestedOutput = List.generate(
        1,
        (_) => List.generate(channels, (_) => Float32List(numDetections)),
      );
    }
  }
}
