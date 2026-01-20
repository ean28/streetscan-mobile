import 'dart:async';
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
  // Buffer a single pending frame when frames arrive while we're processing.
  CameraImage? _pendingFrame;

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

      // Always notify UI of the latest detection results so overlays update
      // in real-time (including when there are no detections). Snapshot
      // behavior is still controlled by `snapshotEveryFrame` in the caller.
      try {
        onDetection(detections, detectionMs, inferenceMs);
      } catch (e, st) {
        if (kDebugMode) debugPrint('onDetection handler failed: $e\n$st');
      }
      onDetectionMs?.call(detectionMs);

      // Clear processing flag and flush any pending frame so we don't stall
      // when frames arrive faster than processing rate.
      _isProcessing = false;
      if (_pendingFrame != null) {
        final pending = _pendingFrame;
        _pendingFrame = null;
        if (pending != null) {
          try {
            addFrame(pending);
          } catch (e) {
            if (kDebugMode) debugPrint('Failed to requeue pending frame: $e');
          }
        }
      }
    };

    // Start manager and wait for it to be ready (it pre-warms inside)
    await _inferenceManager!.start(modelBytes, labels);
    if (kDebugMode) debugPrint('✅ Model loaded confirmed in main isolate');
    onModelLoaded?.call();

    // Frame listener - send raw YUV planes to the inference isolate so the
    // expensive YUV->RGB conversion occurs off the main isolate. This reduces
    // UI-thread CPU work and avoids long frame processing pauses.
    _frameQueue.stream.listen((frame) async {
      if (_inferenceManager != null && !_isProcessing) {
        _isProcessing = true;
        try {
          // Copy plane bytes (transferable) and send metadata; conversion will
          // happen inside the inference isolate.
          final y = Uint8List.fromList(frame.planes[0].bytes);
          final u = Uint8List.fromList(frame.planes[1].bytes);
          final v = Uint8List.fromList(frame.planes[2].bytes);
          await _inferenceManager!.sendFrame(
            {
              'y': y,
              'u': u,
              'v': v,
              'width': frame.width,
              'height': frame.height,
              'yRowStride': frame.planes[0].bytesPerRow,
              'uvRowStride': frame.planes[1].bytesPerRow,
              'uvPixelStride': frame.planes[1].bytesPerPixel ?? 1,
            },
            frame.width,
            frame.height,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('Frame conversion failed: $e');
          _isProcessing = false;
        }
      } else {
        // Buffer the most recent frame so it can be processed when current
        // work completes. This avoids starving the pipeline when frames
        // arrive faster than processing rate.
        _pendingFrame = frame;
        if (kDebugMode) {
          debugPrint('Frame buffered (pending) to maintain speed');
        }
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
