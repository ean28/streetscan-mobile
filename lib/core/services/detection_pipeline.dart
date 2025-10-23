import 'dart:async';
// dart:isolate not needed: using InferenceIsolateManager instead
import 'package:street_scan/core/services/inference_isolate.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:street_scan/core/services/config/detection_settings.dart';
import '../detection/detection.dart';

typedef DetectionCallback =
    void Function(List<Detection> detections, int detectionMs, int inferenceMs);
typedef DetectionMsCallback = void Function(int detectionMs);

class PotholeDetectionPipeline {
  final DetectionCallback onDetection;
  final DetectionMsCallback? onDetectionMs;
  final VoidCallback? onModelLoaded;
  final bool snapshotEveryFrame;

  // Queue for frames
  final _frameQueue = StreamController<CameraImage>.broadcast();

  // Isolate
  InferenceIsolateManager? _inferenceManager;

  bool _isProcessing = false;

  // Stats
  int _totalFrames = 0;
  int _totalDetectionMs = 0;
  int _lastDetectionTimes = 0;

  int get totalFrames => _totalFrames;
  int get totalDetectionMs => _totalDetectionMs;
  int get lastDetectionMs => _lastDetectionTimes;

  PotholeDetectionPipeline({
    required this.onDetection,
    this.onDetectionMs,
    this.onModelLoaded,
    this.snapshotEveryFrame = false,
  });

  // ---------------- Public API ----------------
  Future<void> init() async {
    // Load model bytes + labels in MAIN isolate
    final modelBytes = (await rootBundle.load(
      DetectionConfig.instance.currentModelAsset,
    )).buffer.asUint8List();
    final labels = await DetectionConfig.instance.loadLabels();

    // Create and start the inference manager (it spawns its own isolate internally)
    _inferenceManager = InferenceIsolateManager(
      minInterval: Duration(
        milliseconds: DetectionConfig.instance.processingIntervalMs,
      ),
    );
    // Result callback
    _inferenceManager!.onResult = (detections, detectionMs, inferenceMs) {
      _lastDetectionTimes = detectionMs;
      _totalFrames++;
      _totalDetectionMs += detectionMs;

      if (snapshotEveryFrame || detections.isNotEmpty) {
        onDetection(detections, detectionMs, inferenceMs);
      }
      onDetectionMs?.call(detectionMs);

      _isProcessing = false;
    };

    // Start manager and wait for it to be ready (it pre-warms inside)
    await _inferenceManager!.start(modelBytes, labels);
    if (kDebugMode) debugPrint('✅ Model loaded confirmed in main isolate');
    onModelLoaded?.call();

    // Frame listener - convert frames then send to inference manager
    _frameQueue.stream.listen((frame) async {
      if (_inferenceManager != null && !_isProcessing) {
        _isProcessing = true;
        try {
          final bytes = cameraImageToBytes(frame);
          await _inferenceManager!.sendFrame(bytes, frame.width, frame.height);
        } catch (e) {
          if (kDebugMode) debugPrint('Frame conversion failed: $e');
          _isProcessing = false;
        }
      } else {
        if (kDebugMode) debugPrint('Frame skipped to maintain speed');
      }
    });
  }

  void addFrame(CameraImage frame) {
    _frameQueue.add(frame);
  }

  double get averageDetectionMs =>
      _totalFrames > 0 ? _totalDetectionMs / _totalFrames : 0;

  Future<void> dispose() async {
    _frameQueue.close();
    try {
      await _inferenceManager?.stop();
    } catch (_) {}
  }

  /// Change the processing interval at runtime without restarting the isolate.
  void setProcessingIntervalMs(int ms) {
    _inferenceManager?.setInterval(Duration(milliseconds: ms));
    // update stats notifier too
    final notifier = _inferenceManager?.statsNotifier;
    if (notifier != null) {
      notifier.value = notifier.value.copyWith(currentIntervalMs: ms);
    }
  }

  /// Expose stats notifier for UI overlay
  ValueNotifier<ManagerStats>? get statsNotifier =>
      _inferenceManager?.statsNotifier;

  Future<void> runStaticImageTest(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    try {
      if (_inferenceManager != null) {
        await _inferenceManager!.sendFrame(bytes, width, height);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('runStaticImageTest failed: $e');
    }
  }
}

// ---------------- Helper: CameraImage → RGB bytes ----------------
Uint8List cameraImageToBytes(CameraImage image) {
  if (image.format.group == ImageFormatGroup.yuv420 &&
      image.planes.length >= 3) {
    final width = image.width;
    final height = image.height;
    final rgb = Uint8List(width * height * 3);
    int offset = 0;

    final yPlane = image.planes[0].bytes;
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final uvRow = y >> 1;
      for (int x = 0; x < width; x++) {
        final uvCol = x >> 1;
        final yIndex = y * yRowStride + x;
        final uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        final Y = yPlane[yIndex] & 0xFF;
        final U = uPlane[uvIndex] & 0xFF;
        final V = vPlane[uvIndex] & 0xFF;

        int R = (Y + 1.370705 * (V - 128)).round();
        int G = (Y - 0.698001 * (V - 128) - 0.337633 * (U - 128)).round();
        int B = (Y + 1.732446 * (U - 128)).round();

        rgb[offset++] = B.clamp(0, 255);
        rgb[offset++] = G.clamp(0, 255);
        rgb[offset++] = R.clamp(0, 255);
      }
    }

    return rgb;
  } else {
    throw Exception("Unsupported CameraImage format");
  }
}
