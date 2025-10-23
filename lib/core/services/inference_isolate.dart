// Cleaned, single implementation of the inference isolate manager.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../detection/detection.dart';
import 'pothole_detector.dart';
import 'config/detection_settings.dart';

/// Simple stats container for the inference manager.
class ManagerStats {
  final int framesSent;
  final int framesProcessed;
  final int framesDropped;
  final int lastInferenceMs;
  final int lastDetectionMs;
  final int currentIntervalMs;
  final int lastResultAt;

  ManagerStats({
    this.framesSent = 0,
    this.framesProcessed = 0,
    this.framesDropped = 0,
    this.lastInferenceMs = 0,
    this.lastDetectionMs = 0,
    this.currentIntervalMs = 200,
    this.lastResultAt = 0,
  });

  ManagerStats copyWith({
    int? framesSent,
    int? framesProcessed,
    int? framesDropped,
    int? lastInferenceMs,
    int? lastDetectionMs,
    int? currentIntervalMs,
    int? lastResultAt,
    int framesSentIncrement = 0,
    int framesProcessedIncrement = 0,
    int framesDroppedIncrement = 0,
  }) {
    return ManagerStats(
      framesSent: (framesSent ?? this.framesSent) + framesSentIncrement,
      framesProcessed:
          (framesProcessed ?? this.framesProcessed) + framesProcessedIncrement,
      framesDropped:
          (framesDropped ?? this.framesDropped) + framesDroppedIncrement,
      lastInferenceMs: lastInferenceMs ?? this.lastInferenceMs,
      lastDetectionMs: lastDetectionMs ?? this.lastDetectionMs,
      currentIntervalMs: currentIntervalMs ?? this.currentIntervalMs,
      lastResultAt: lastResultAt ?? this.lastResultAt,
    );
  }
}

/// Manages a dedicated isolate for model inference. The isolate owns the
/// model and does preprocessing+inference; only detection maps are sent back.
class InferenceIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription? _receiveSub;

  final Duration minInterval;

  // user callback when detections are available
  void Function(List<Detection> detections, int detectionMs, int inferenceMs)?
  onResult;

  // live stats for UI
  final ValueNotifier<ManagerStats> statsNotifier = ValueNotifier(
    ManagerStats(),
  );

  InferenceIsolateManager({
    this.minInterval = const Duration(milliseconds: 200),
  });

  bool get isRunning => _isolate != null;

  Future<void> start(Uint8List modelBytes, List<String> labels) async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    final completer = Completer<void>();

    _isolate = await Isolate.spawn<_IsolateInitParams>(
      _isolateEntry,
      _IsolateInitParams(
        _receivePort!.sendPort,
        modelBytes,
        labels,
        minInterval.inMilliseconds,
      ),
      debugName: 'inference_isolate',
    );

    _receiveSub = _receivePort!.listen((dynamic message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
        return;
      }

      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        if (type == 'model_loaded') {
          if (kDebugMode) debugPrint('Inference isolate: model_loaded');
          return;
        }

        if (type == 'result') {
          final detections = (message['detections'] as List)
              .map((m) => _detectionFromMap(m as Map<String, dynamic>))
              .whereType<Detection>()
              .toList();
          final detectionMs = message['detectionMs'] as int? ?? 0;
          final inferenceMs = message['inferenceMs'] as int? ?? 0;

          // update stats
          final s = statsNotifier.value.copyWith(
            framesProcessedIncrement: 1,
            lastInferenceMs: inferenceMs,
            lastDetectionMs: detectionMs,
            lastResultAt: DateTime.now().millisecondsSinceEpoch,
          );
          statsNotifier.value = s;

          try {
            onResult?.call(detections, detectionMs, inferenceMs);
          } catch (e, st) {
            if (kDebugMode) debugPrint('onResult handler failed: $e\n$st');
          }
        } else if (type == 'dropped') {
          final s = statsNotifier.value.copyWith(framesDroppedIncrement: 1);
          statsNotifier.value = s;
        } else if (type == 'interval_set') {
          if (kDebugMode)
            debugPrint('Inference isolate: interval set acknowledged');
        }
      }
    });

    await completer.future;
  }

  Future<void> stop() async {
    try {
      _receiveSub?.cancel();
      _receiveSub = null;
      _receivePort?.close();
      _receivePort = null;
      _sendPort = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    } catch (e) {
      if (kDebugMode) debugPrint('InferenceIsolateManager.stop error: $e');
    }
  }

  /// Set processing interval at runtime without restarting the isolate.
  void setInterval(Duration interval) {
    if (_sendPort == null) return;
    final ms = interval.inMilliseconds;
    _sendPort!.send({'type': 'set_interval', 'minIntervalMs': ms});
    final s = statsNotifier.value.copyWith(currentIntervalMs: ms);
    statsNotifier.value = s;
  }

  /// notify that a frame was sent (for stats)
  void _noteFrameSent() {
    final s = statsNotifier.value.copyWith(framesSentIncrement: 1);
    statsNotifier.value = s;
  }

  Future<void> sendFrame(Uint8List rgbBytes, int width, int height) async {
    if (_sendPort == null) return;
    _noteFrameSent();
    _sendPort!.send({
      'type': 'frame',
      'bytes': rgbBytes,
      'width': width,
      'height': height,
    });
  }

  static Detection? _detectionFromMap(Map<String, dynamic> m) {
    try {
      final boxMap = m['box'] as Map<String, dynamic>;
      final rect = Rect.fromLTRB(
        (boxMap['left'] as num).toDouble(),
        (boxMap['top'] as num).toDouble(),
        (boxMap['right'] as num).toDouble(),
        (boxMap['bottom'] as num).toDouble(),
      );
      return Detection(
        box: rect,
        confidence: (m['confidence'] as num).toDouble(),
        classId: (m['classId'] as num).toInt(),
        label: m['label'] as String,
        inferenceTime: (m['inferenceTime'] as int?),
        letterboxScale: (m['letterboxScale'] as num).toDouble(),
        letterboxDx: (m['letterboxDx'] as num).toDouble(),
        letterboxDy: (m['letterboxDy'] as num).toDouble(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to convert detection map: $e');
      return null;
    }
  }
}

class _IsolateInitParams {
  final SendPort replyTo;
  final Uint8List modelBytes;
  final List<String> labels;
  final int minIntervalMs;
  _IsolateInitParams(
    this.replyTo,
    this.modelBytes,
    this.labels,
    this.minIntervalMs,
  );
}

Future<void> _isolateEntry(_IsolateInitParams params) async {
  final mainSend = params.replyTo;
  final port = ReceivePort();
  mainSend.send(port.sendPort);

  try {
    final detector = PotholeDetector.instance;
    await detector.loadModelFromBuffer(params.modelBytes, params.labels);

    // Prewarm
    try {
      final int sizeValue = DetectionConfig.instance.sizeValue;
      if (sizeValue > 0) {
        final dummy = Uint8List(sizeValue * sizeValue * 3);
        await detector.processImageBytes(dummy, sizeValue, sizeValue);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Prewarm failed: $e');
    }

    mainSend.send({'type': 'model_loaded'});
  } catch (e, st) {
    if (kDebugMode) debugPrint('Isolate model init failed: $e\n$st');
    mainSend.send({'type': 'model_loaded', 'error': e.toString()});
  }

  int lastProcessedAt = 0;
  int minIntervalMs = params.minIntervalMs;

  await for (final raw in port) {
    if (raw is Map<String, dynamic>) {
      final type = raw['type'] as String?;
      if (type == 'frame') {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastProcessedAt < minIntervalMs) {
          // notify dropped frame
          mainSend.send({'type': 'dropped'});
          continue;
        }
        lastProcessedAt = now;

        final bytes = raw['bytes'] as Uint8List;
        final width = raw['width'] as int;
        final height = raw['height'] as int;

        try {
          final sw = Stopwatch()..start();
          final dets = await PotholeDetector.instance.processImageBytes(
            bytes,
            width,
            height,
          );
          sw.stop();

          final detectionMs = sw.elapsedMilliseconds;
          final inferenceMs = PotholeDetector.instance.lastInferenceMs;

          final out = dets
              .map(
                (d) => {
                  'box': {
                    'left': d.box.left,
                    'top': d.box.top,
                    'right': d.box.right,
                    'bottom': d.box.bottom,
                  },
                  'confidence': d.confidence,
                  'classId': d.classId,
                  'label': d.label,
                  'inferenceTime': d.inferenceTime,
                  'letterboxScale': d.letterboxScale,
                  'letterboxDx': d.letterboxDx,
                  'letterboxDy': d.letterboxDy,
                },
              )
              .toList();

          mainSend.send({
            'type': 'result',
            'detections': out,
            'detectionMs': detectionMs,
            'inferenceMs': inferenceMs,
          });
        } catch (e, st) {
          if (kDebugMode) debugPrint('Isolate processing error: $e\n$st');
          mainSend.send({
            'type': 'result',
            'detections': <Map<String, dynamic>>[],
            'detectionMs': 0,
          });
        }
      } else if (type == 'set_interval') {
        final provided = raw['minIntervalMs'] as int?;
        if (provided != null) minIntervalMs = provided;
        mainSend.send({'type': 'interval_set'});
      }
    }
  }
}
