// lib/core/services/pothole_detector.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../detection/detection.dart';
import 'config/detection_settings.dart';

enum InferenceBackend { cpu }

class PotholeDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _initialized = false;

  InferenceSize? _activeSize;
  InferenceBackend _backendUsed = InferenceBackend.cpu;

  int _frameCount = 0;
  int _lastInferenceMs = 0;
  int _lastNmsMs = 0;
  int _lastPreprocessMs = 0;

  static final PotholeDetector instance = PotholeDetector._internal();
  PotholeDetector._internal();

  bool get initialized => _initialized;
  InferenceSize? get activeSize => _activeSize;
  InferenceBackend get backendUsed => _backendUsed;
  int get frameCount => _frameCount;
  int get lastInferenceMs => _lastInferenceMs;
  int get lastNmsMs => _lastNmsMs;
  int get lastPreprocessMs => _lastPreprocessMs;

  Future<void> loadModel() async {
    if (_initialized) return;

    final modelBytes =
        (await rootBundle.load(DetectionConfig.instance.currentModelAsset))
            .buffer
            .asUint8List();
    final labels = await DetectionConfig.instance.loadLabels();

    await loadModelFromBuffer(modelBytes, labels);
  }

  Future<void> loadModelFromBuffer(Uint8List modelBytes, List<String> labels) async {
    if (_initialized) return;

    try {
      final options = InterpreterOptions();
      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _labels = labels;
      _activeSize = DetectionConfig.instance.inputSize;
      _initialized = true;
      debugPrint("✅ PotholeDetector: model loaded (buffer). Labels: ${labels.length}");
    } catch (e, st) {
      debugPrint("❌ PotholeDetector: error loading model: $e\n$st");
      rethrow;
    }
  }

  void close() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _initialized = false;
    _labels = [];
  }

  Future<List<Detection>> processImageBytes(Uint8List rgbBytes, int width, int height) async {
    if (!_initialized || _interpreter == null) {
      throw Exception('PotholeDetector not initialized. Call loadModelFromBuffer first.');
    }

    _frameCount++;

    final swPre = Stopwatch()..start();
    final img.Image src = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbBytes.buffer,
      numChannels: 3,
    );
    swPre.stop();
    _lastPreprocessMs = swPre.elapsedMilliseconds;

    debugPrint("🖼️ Frame $_frameCount preprocessing done in $_lastPreprocessMs ms");

    final detections = await _runInference(_interpreter!, _labels, src);

    final remapped = detections.map((d) => remapBox(d, src.width, src.height)).toList();

    debugPrint("📊 Frame $_frameCount total detections after NMS: ${remapped.length}");

    return remapped;
  }

  Future<List<Detection>> _runInference(
      Interpreter interpreter, List<String> labels, img.Image srcImage) async {
    final inputTensor = interpreter.getInputTensor(0);
    final shape = inputTensor.shape;
    final batch = shape[0];
    final inputHeight = shape[1];
    final inputWidth = shape[2];
    debugPrint("Input tensor type: ${inputTensor.type}");
    debugPrint("🧮 Input tensor shape: $shape");
    debugPrint("Height $inputHeight, Width $inputWidth");

    final lb = letterbox(srcImage, inputWidth, inputHeight);

    // --- Preprocessing debug ---
    final inputList = List.generate(batch, (_) {
      return List.generate(inputHeight, (y) {
        return List.generate(inputWidth, (x) {
          final px = lb.image.getPixel(x, y);
          final r = px.r / 255.0;
          final g = px.g / 255.0;
          final b = px.b / 255.0;

          // Log top-left, center, bottom-right
          if ((x == 0 && y == 0) ||
              (x == inputWidth ~/ 2 && y == inputHeight ~/ 2) ||
              (x == inputWidth - 1 && y == inputHeight - 1)) {
            debugPrint("🟢 Pixel[$x,$y] after preprocessing: R=$r, G=$g, B=$b");
          }

          return [b, g, r]; // RGB mode
        });
      });
    });

    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final numDetections = outputShape[1];
    debugPrint("🧮 Output tensor shape: $outputShape");

    final output = List.generate(
      1,
      (_) => List.generate(numDetections, (_) => List.filled(6, 0.0)),
    );

    final swInf = Stopwatch()..start();
    try {
      interpreter.run(inputList, output);
    } catch (e, st) {
      debugPrint('❌ _runInference error: $e\n$st');
      return [];
    }
    swInf.stop();
    _lastInferenceMs = swInf.elapsedMilliseconds;
    debugPrint("⏱️ Frame $_frameCount inference time: $_lastInferenceMs ms");

    final rawDetections = <Detection>[];

    for (var row in output[0]) {
      if (row.length < 6) continue;
  
      final conf = row[4];
      if (conf <= 0) continue; // log only positive confidence
      debugPrint("RAW DET: conf=$conf, class=${row[5]}, box=(${row[0]},${row[1]},${row[2]},${row[3]})");

      final xIn = row[0];
      final yIn = row[1];
      final wIn = row[2];
      final hIn = row[3];

      final x1Pad = (xIn - wIn / 2) * inputWidth;
      final y1Pad = (yIn - hIn / 2) * inputHeight;
      final x2Pad = (xIn + wIn / 2) * inputWidth;
      final y2Pad = (yIn + hIn / 2) * inputHeight;

      rawDetections.add(Detection(
        box: Rect.fromLTRB(
          x1Pad.clamp(0.0, inputWidth.toDouble()),
          y1Pad.clamp(0.0, inputHeight.toDouble()),
          x2Pad.clamp(0.0, inputWidth.toDouble()),
          y2Pad.clamp(0.0, inputHeight.toDouble()),
        ),
        confidence: conf,
        classId: row[5].toInt().clamp(0, labels.length - 1),
        label: labels[row[5].toInt().clamp(0, labels.length - 1)],
        inferenceTime: _lastInferenceMs,
        letterboxScale: lb.scale,
        letterboxDx: lb.dx.toDouble(),
        letterboxDy: lb.dy.toDouble(),
      ));
    }

    debugPrint("📊 Frame $_frameCount raw detections count (conf>0): ${rawDetections.length}");

    final swNms = Stopwatch()..start();
    final filtered = nonMaxSuppression(rawDetections);
    swNms.stop();
    _lastNmsMs = swNms.elapsedMilliseconds;
    debugPrint("⏱️ Frame $_frameCount NMS time: $_lastNmsMs ms");

    return filtered;
  }

  LetterboxResult letterbox(img.Image src, int newWidth, int newHeight, {int padColor = 114}) {
    final double scale =
        (newWidth / src.width < newHeight / src.height) ? newWidth / src.width : newHeight / src.height;

    final int resizedW = (src.width * scale).round();
    final int resizedH = (src.height * scale).round();

    final img.Image resized = img.copyResize(src, width: resizedW, height: resizedH);
    final img.Image output = img.Image(width: newWidth, height: newHeight);
    final pad = img.ColorRgb8(padColor, padColor, padColor);
    img.fill(output, color: pad);

    final dx = ((newWidth - resizedW) / 2).round();
    final dy = ((newHeight - resizedH) / 2).round();
    img.compositeImage(output, resized, dstX: dx, dstY: dy);

    return LetterboxResult(
      image: output,
      scale: scale,
      dx: dx,
      dy: dy,
      resizedW: resizedW,
      resizedH: resizedH,
    );
  }

  Detection remapBox(Detection det, int origW, int origH) {
    final scale = det.letterboxScale ?? 1.0;
    final dx = det.letterboxDx ?? 0.0;
    final dy = det.letterboxDy ?? 0.0;

    double x1 = ((det.box.left - dx) / scale).clamp(0.0, origW - 1.0);
    double y1 = ((det.box.top - dy) / scale).clamp(0.0, origH - 1.0);
    double x2 = ((det.box.right - dx) / scale).clamp(0.0, origW - 1.0);
    double y2 = ((det.box.bottom - dy) / scale).clamp(0.0, origH - 1.0);

    return Detection(
      box: Rect.fromLTRB(x1, y1, x2, y2),
      confidence: det.confidence,
      classId: det.classId,
      label: det.label,
      inferenceTime: det.inferenceTime,
      letterboxScale: scale,
      letterboxDx: dx,
      letterboxDy: dy,
    );
  }

  List<Detection> nonMaxSuppression(List<Detection> detections,
      {double? iouThreshold, int? maxDetections}) {
    final double threshold = iouThreshold ?? DetectionConfig.iouThreshold;
    final int max = maxDetections ?? DetectionConfig.maxDetections;

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    final List<Detection> results = [];

    while (detections.isNotEmpty && results.length < max) {
      final best = detections.removeAt(0);
      results.add(best);

      detections.removeWhere((det) {
        if (det.classId != best.classId) return false;
        final double xx1 = best.box.left > det.box.left ? best.box.left : det.box.left;
        final double yy1 = best.box.top > det.box.top ? best.box.top : det.box.top;
        final double xx2 = best.box.right < det.box.right ? best.box.right : det.box.right;
        final double yy2 = best.box.bottom < det.box.bottom ? best.box.bottom : det.box.bottom;
        final double w = (xx2 - xx1).clamp(0.0, double.infinity);
        final double h = (yy2 - yy1).clamp(0.0, double.infinity);
        final double intersection = w * h;
        final double union = best.box.width * best.box.height + det.box.width * det.box.height - intersection;
        final double iou = union > 0 ? intersection / union : 0;
        return iou > threshold;
      });
    }

    return results;
  }
}

class LetterboxResult {
  final img.Image image;
  final double scale;
  final int dx;
  final int dy;
  final int resizedW;
  final int resizedH;

  LetterboxResult({
    required this.image,
    required this.scale,
    required this.dx,
    required this.dy,
    required this.resizedW,
    required this.resizedH,
  });
}
