import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

enum InferenceSize { s320, s416, s640 }

enum PreprocessMode { auto, int8, float32 }

class DetectionConfig extends ChangeNotifier {
  static final DetectionConfig instance = DetectionConfig._internal();
  DetectionConfig._internal();

  InferenceSize _inputSize = InferenceSize.s320;
  InferenceSize get inputSize => _inputSize;

  // Preprocess mode: auto-detect from model tensor type, or force int8/float32
  // Default to `auto` so preprocessing follows the model unless explicitly overridden.
  PreprocessMode _preprocessMode = PreprocessMode.auto;
  PreprocessMode get preprocessMode => _preprocessMode;
  void setPreprocessMode(PreprocessMode mode) {
    _preprocessMode = mode;
    notifyListeners();
  }

  // Processing interval in milliseconds for inference throttling (default 200ms => 5 FPS)
  int _processingIntervalMs = 200;
  int get processingIntervalMs => _processingIntervalMs;
  void setProcessingIntervalMs(int ms) {
    _processingIntervalMs = ms;
    notifyListeners();
  }

  // Snapshot interval (ms) to throttle automatic saves when detections occur
  // Default 1000ms (one snapshot per second max)
  int _snapshotIntervalMs = 1000;
  int get snapshotIntervalMs => _snapshotIntervalMs;
  void setSnapshotIntervalMs(int ms) {
    _snapshotIntervalMs = ms;
    notifyListeners();
  }

  // Confidence threshold for detections. Since model output is already
  // sigmoid-activated (YOLOv8/v11), this is the direct probability cutoff.
  // Increase this value to reduce false positives.
  // DIAGNOSTIC: Temporarily lowered to 0.05 to catch low-confidence detections
  static double get confThreshold => 0.03;
  static double get iouThreshold => 0.40;
  static int get maxDetections => 50;

  /// Whether to swap R and B channels (RGB → BGR).
  /// Some models are trained on BGR images (OpenCV default).
  /// Set to `true` if model expects BGR input.
  static bool get useBgrInput => true;

  /// Whether model output is already sigmoid-activated.
  /// Set to `false` for YOLOv8/v11 TFLite exports that output raw logits.
  /// Set to `true` if model includes sigmoid in the output layer.
  ///
  /// Diagnostic: If raw scores are ~0.000001-0.0001, model likely outputs
  /// raw logits (sigmoid needed). If scores are 0.1-0.9 range, it's activated.
  static bool get isOutputActivated =>
      true; // Raw values are 0-1, already activated

  final Map<InferenceSize, bool> _availableModels = {};

  Map<InferenceSize, bool> get availableModels => _availableModels;

  static const Map<InferenceSize, String> _modelAssets = {
    InferenceSize.s320: 'assets/models/float16_320.tflite',
    //InferenceSize.s416: 'assets/models/model_416_float32.tflite',
    //InferenceSize.s640: 'assets/models/model_640_float32.tflite',
  };

  String get currentModelAsset {
    return _modelAssets[_inputSize]!;
  }

  void setInputSize(InferenceSize size) {
    _inputSize = size;
    notifyListeners();
  }

  int get sizeValue {
    switch (_inputSize) {
      case InferenceSize.s320:
        return 320;
      case InferenceSize.s416:
        return 416;
      case InferenceSize.s640:
        return 640;
    }
  }

  static Future<Map<InferenceSize, bool>> checkAvailableModels() async {
    final availability = <InferenceSize, bool>{};
    for (final entry in _modelAssets.entries) {
      try {
        await rootBundle.load(entry.value);
        availability[entry.key] = true;
      } catch (_) {
        availability[entry.key] = false;
      }
    }
    instance._availableModels.clear();
    instance._availableModels.addAll(availability);
    return availability;
  }

  Future<List<String>> loadLabels() async {
    final data = await rootBundle.loadString('assets/model_clabels.txt');
    return data
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
