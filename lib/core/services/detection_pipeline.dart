import 'dart:async';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:street_scan/core/services/config/detection_settings.dart';
import 'pothole_detector.dart';
import '../detection/detection.dart';

typedef DetectionCallback = void Function(List<Detection> detections, int detectionMs, int inferenceMs);
typedef DetectionMsCallback = void Function(int detectionMs);

class PotholeDetectionPipeline {
  final DetectionCallback onDetection;
  final DetectionMsCallback? onDetectionMs;
  final VoidCallback? onModelLoaded;
  final bool snapshotEveryFrame;

  // Queue for frames
  final _frameQueue = StreamController<CameraImage>.broadcast();

  // Isolate
  Isolate? _detectionIsolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

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
    _receivePort = ReceivePort();
    _detectionIsolate = await Isolate.spawn(
      _detectionIsolateEntry,
      _receivePort!.sendPort,
    );

    // Listen for messages from isolate
    _receivePort!.listen((message) async {
      if (message is SendPort) {
        _sendPort = message;

        // Load model bytes + labels in MAIN isolate
        final modelBytes = (await rootBundle
                .load(DetectionConfig.instance.currentModelAsset))
            .buffer
            .asUint8List();
        final labels = await DetectionConfig.instance.loadLabels();

        // Send init message to detection isolate
        _sendPort!.send({
          'type': 'init',
          'model': modelBytes,
          'labels': labels,
        });
      } else if (message is Map<String, dynamic>) {
        if (message['type'] == 'model_loaded') {
          if (kDebugMode) debugPrint('✅ Model loaded confirmed in main isolate');
          onModelLoaded?.call(); 
          return;
        }

        // Normal detection message
        final detections = message['detections'] as List<Detection>;
        final detectionMs = message['detectionMs'] as int;
        final inferenceMs = message['inferenceMs'] as int;

        _lastDetectionTimes = detectionMs;
        _totalFrames++;
        _totalDetectionMs += detectionMs;

        if (snapshotEveryFrame || detections.isNotEmpty) {
          onDetection(detections, detectionMs, inferenceMs);
        }
        onDetectionMs?.call(detectionMs);

        _isProcessing = false;
      }
    });

    // Frame listener
    _frameQueue.stream.listen((frame) async {
      if (_sendPort != null && !_isProcessing) {
        _isProcessing = true;
        try {
          final bytes = cameraImageToBytes(frame);
          _sendPort!.send({
            'type': 'frame',
            'bytes': bytes,
            'width': frame.width,
            'height': frame.height,
          });
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
    _receivePort?.close();
    _detectionIsolate?.kill(priority: Isolate.immediate);
  }

  // ---------------- Detection isolate entry ----------------
  static void _detectionIsolateEntry(SendPort mainSendPort) async {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    await for (final message in port) {
      if (message is Map<String, dynamic>) {
        if (message['type'] == 'init') {
          final modelBytes = message['model'] as Uint8List;
          final labels = (message['labels'] as List).cast<String>();
          await PotholeDetector.instance.loadModelFromBuffer(modelBytes, labels);
          debugPrint("✅ Model loaded in isolate");

          mainSendPort.send({'type': 'model_loaded'});
        } else if (message['type'] == 'frame') {
          final bytes = message['bytes'] as Uint8List;
          final width = message['width'] as int;
          final height = message['height'] as int;

          try {
            final stopwatch = Stopwatch()..start();
            final outputs = await PotholeDetector.instance.processImageBytes(bytes, width, height);
            stopwatch.stop();
            final stopwatchDetectMs = stopwatch.elapsedMilliseconds;

            final inferenceMs = PotholeDetector.instance.lastInferenceMs;

            mainSendPort.send({
              'detections': outputs,
              'detectionMs': stopwatchDetectMs,
              'inferenceMs': inferenceMs,
            });
          } catch (e, st) {
            if (kDebugMode) debugPrint('Isolate detection error: $e\n$st');
            mainSendPort.send({'detections': <Detection>[], 'detectionMs': 0});
          }
        }
      }
    }
  }
  Future<void> runStaticImageTest(Uint8List bytes, int width, int height) async {
    if (_sendPort != null) {
      _sendPort!.send({
        'type': 'frame',
        'bytes': bytes,
        'width': width,
        'height': height,
      });
    }
  }
}

// ---------------- Helper: CameraImage → RGB bytes ----------------
Uint8List cameraImageToBytes(CameraImage image) {
  if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
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
