// lib/core/detection/yolo_output_parser.dart
//
// Handles YOLO model output parsing, NMS, and box remapping.
// Extracted from PotholeDetector to improve maintainability.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'detection.dart';
import '../services/config/detection_settings.dart';

/// Parsed letterbox information for coordinate remapping.
class LetterboxInfo {
  final double scale;
  final double dx;
  final double dy;
  final int srcWidth;
  final int srcHeight;

  const LetterboxInfo({
    required this.scale,
    required this.dx,
    required this.dy,
    required this.srcWidth,
    required this.srcHeight,
  });
}

/// Handles parsing YOLO-format model outputs into Detection objects.
class YoloOutputParser {
  final List<String> labels;

  // Debug boxes for visualization
  List<Rect> lastPadBoxes = [];
  List<Rect> lastAltPadBoxes = [];

  // Cached buffers to avoid per-frame allocation
  List<double>? _cachedMaxScores;
  List<int>? _cachedBestCls;

  YoloOutputParser({required this.labels});

  /// Parse nested output tensor [1, channels, numDetections] into Detection list.
  ///
  /// [nestedOutput] - The raw model output in nested format
  /// [channels] - Number of channels (typically 7 for 4 box coords + 3 classes)
  /// [numDetections] - Number of detection anchors (e.g., 2100)
  /// [inputW], [inputH] - Model input dimensions
  /// [letterbox] - Letterbox info for coordinate remapping
  /// [lastInferenceMs] - Inference time for metadata
  /// [outScale], [outZero] - Output quantization parameters
  List<Detection> parseOutput({
    required dynamic nestedOutput,
    required int channels,
    required int numDetections,
    required int inputW,
    required int inputH,
    required LetterboxInfo letterbox,
    required int lastInferenceMs,
    double outScale = 1.0,
    int outZero = 0,
  }) {
    final List<Detection> results = [];
    final double confThresh = DetectionConfig.confThreshold;

    if (kDebugMode) {
      debugPrint(
        'Parsing output: shape 1x${channels}x$numDetections, confThresh=$confThresh',
      );
      lastPadBoxes = [];
      lastAltPadBoxes = [];
    }

    // Fast raw reader for channel buffer elements
    double readRawFromChannel(dynamic ch, int idx) {
      if (ch is Float32List) return ch[idx].toDouble();
      if (ch is Int8List) return (ch[idx] - outZero) * outScale;
      if (ch is Uint8List) return (ch[idx] - outZero) * outScale;
      final dynamic v = ch[idx];
      if (v is double) return v;
      if (v is int) return (v - outZero) * outScale;
      return (v as num).toDouble();
    }

    // Fallback reader for flat output
    double readVal(int chan, int idx) {
      final int pos = chan * numDetections + idx;
      if (nestedOutput is Float32List) return nestedOutput[pos].toDouble();
      if (nestedOutput is Int8List) {
        return (nestedOutput[pos] - outZero) * outScale;
      }
      if (nestedOutput is Uint8List) {
        return (nestedOutput[pos] - outZero) * outScale;
      }
      final dynamic v = nestedOutput[pos];
      if (v is int) return (v - outZero) * outScale;
      return v.toDouble();
    }

    // Sigmoid for raw logits (only used if model output isn't pre-activated)
    double sigmoid(double v) => 1.0 / (1.0 + math.exp(-v));
    final bool applyActivation = !DetectionConfig.isOutputActivated;

    // Initialize cached score buffers
    if (_cachedMaxScores == null || _cachedMaxScores!.length != numDetections) {
      _cachedMaxScores = List<double>.filled(numDetections, 0.0);
      _cachedBestCls = List<int>.filled(numDetections, -1);
    }
    final List<double> cachedMaxScores = _cachedMaxScores!;
    final List<int> cachedBestCls = _cachedBestCls!;

    // Extract channel references for nested output
    final bool isNested = nestedOutput is List;
    dynamic ch0, ch1, ch2, ch3, ch4, ch5, ch6;
    if (isNested) {
      final dynamic chs = nestedOutput[0];
      ch0 = chs[0];
      ch1 = chs[1];
      ch2 = chs[2];
      ch3 = chs[3];
      ch4 = chs[4];
      ch5 = chs[5];
      ch6 = chs[6];
    }

    // First pass: collect candidates above threshold
    final List<int> candidateIdxs = [];

    // Diagnostic: track max raw and activated scores across all detections
    double diagMaxRaw = double.negativeInfinity;
    double diagMinRaw = double.infinity;
    double diagMaxActivated = 0.0;
    int diagMaxIdx = -1;

    for (int i = 0; i < numDetections; i++) {
      final double raw4 = isNested ? readRawFromChannel(ch4, i) : readVal(4, i);
      final double raw5 = isNested ? readRawFromChannel(ch5, i) : readVal(5, i);
      final double raw6 = isNested ? readRawFromChannel(ch6, i) : readVal(6, i);

      // Apply sigmoid only if model output is raw logits
      final double s0 = applyActivation ? sigmoid(raw4) : raw4;
      final double s1 = applyActivation ? sigmoid(raw5) : raw5;
      final double s2 = applyActivation ? sigmoid(raw6) : raw6;

      if (kDebugMode && i < 5) {
        debugPrint(
          '🔬 Detection[$i] Raw: ${raw4.toStringAsExponential(2)}, '
          '${raw5.toStringAsExponential(2)}, ${raw6.toStringAsExponential(2)} '
          '→ Activated: ${s0.toStringAsFixed(4)}, ${s1.toStringAsFixed(4)}, '
          '${s2.toStringAsFixed(4)} (applyActivation=$applyActivation)',
        );
      }

      double maxScore = s0;
      int clsNum = 0;
      if (s1 > maxScore) {
        maxScore = s1;
        clsNum = 1;
      }
      if (s2 > maxScore) {
        maxScore = s2;
        clsNum = 2;
      }

      cachedMaxScores[i] = maxScore;
      cachedBestCls[i] = clsNum;

      // Track diagnostics
      final double maxRawInThisDet = math.max(raw4, math.max(raw5, raw6));
      final double minRawInThisDet = math.min(raw4, math.min(raw5, raw6));
      if (maxRawInThisDet > diagMaxRaw) diagMaxRaw = maxRawInThisDet;
      if (minRawInThisDet < diagMinRaw) diagMinRaw = minRawInThisDet;
      if (maxScore > diagMaxActivated) {
        diagMaxActivated = maxScore;
        diagMaxIdx = i;
      }

      if (maxScore >= confThresh) candidateIdxs.add(i);
    }

    if (kDebugMode) {
      debugPrint(
        '📈 Diagnostic: Raw range [$diagMinRaw, $diagMaxRaw], '
        'Max activated=${diagMaxActivated.toStringAsFixed(4)} at idx=$diagMaxIdx, '
        'Threshold=$confThresh, Candidates=${candidateIdxs.length}',
      );
    }

    if (candidateIdxs.isEmpty) {
      if (kDebugMode) debugPrint('No candidates above threshold ($confThresh)');
      return [];
    }

    // Cap candidates to limit decoding work
    final int cap = math.max(DetectionConfig.maxDetections, 200);
    if (candidateIdxs.length > cap) {
      candidateIdxs.sort(
        (a, b) => cachedMaxScores[b].compareTo(cachedMaxScores[a]),
      );
      candidateIdxs.removeRange(cap, candidateIdxs.length);
      if (kDebugMode) {
        debugPrint('Capped candidates to top $cap (from $numDetections)');
      }
    }

    // Decode box coordinates for filtered candidates
    for (final i in candidateIdxs) {
      final double rawCx = isNested
          ? readRawFromChannel(ch0, i)
          : readVal(0, i);
      final double rawCy = isNested
          ? readRawFromChannel(ch1, i)
          : readVal(1, i);
      final double rawW = isNested ? readRawFromChannel(ch2, i) : readVal(2, i);
      final double rawH = isNested ? readRawFromChannel(ch3, i) : readVal(3, i);

      // YOLOv8/v11 outputs box coords directly in pixel space or normalized.
      // Auto-detect: if values > 1.0, they're pixels; otherwise normalized.
      final bool isPixelCoords = rawCx > 1.1 || rawCy > 1.1;

      final double xCenter = isPixelCoords ? rawCx : rawCx * inputW;
      final double yCenter = isPixelCoords ? rawCy : rawCy * inputH;
      final double width = isPixelCoords ? rawW : rawW * inputW;
      final double height = isPixelCoords ? rawH : rawH * inputH;

      final double x1 = xCenter - width / 2;
      final double y1 = yCenter - height / 2;
      final double x2 = xCenter + width / 2;
      final double y2 = yCenter + height / 2;

      if (kDebugMode) {
        lastPadBoxes.add(
          Rect.fromLTRB(
            x1.clamp(0.0, inputW.toDouble()),
            y1.clamp(0.0, inputH.toDouble()),
            x2.clamp(0.0, inputW.toDouble()),
            y2.clamp(0.0, inputH.toDouble()),
          ),
        );
        lastAltPadBoxes.add(
          Rect.fromLTRB(
            x1.clamp(0.0, inputW.toDouble()),
            y1.clamp(0.0, inputH.toDouble()),
            x2.clamp(0.0, inputW.toDouble()),
            y2.clamp(0.0, inputH.toDouble()),
          ),
        );
      }

      final double maxScore = cachedMaxScores[i];
      final int clsNum = cachedBestCls[i].clamp(0, labels.length - 1);

      results.add(
        Detection(
          box: Rect.fromLTRB(
            x1.clamp(0.0, inputW.toDouble()),
            y1.clamp(0.0, inputH.toDouble()),
            x2.clamp(0.0, inputW.toDouble()),
            y2.clamp(0.0, inputH.toDouble()),
          ),
          confidence: maxScore,
          classId: clsNum,
          label: (clsNum < labels.length) ? labels[clsNum] : 'class_$clsNum',
          inferenceTime: lastInferenceMs,
          letterboxScale: letterbox.scale,
          letterboxDx: letterbox.dx,
          letterboxDy: letterbox.dy,
        ),
      );
    }

    if (kDebugMode) debugPrint('Parsed ${results.length} detections');

    // Remap boxes to original image coordinates
    return results.map((det) => remapBox(det, letterbox)).toList();
  }

  /// Apply Non-Maximum Suppression to filter overlapping detections.
  List<Detection> nonMaxSuppression(List<Detection> detections) {
    if (detections.isEmpty) return [];

    final double threshold = DetectionConfig.iouThreshold;
    final int max = DetectionConfig.maxDetections;

    // Sort by confidence descending
    final List<int> idxs = List<int>.generate(detections.length, (i) => i);
    idxs.sort(
      (a, b) => detections[b].confidence.compareTo(detections[a].confidence),
    );

    final List<bool> suppressed = List<bool>.filled(detections.length, false);
    final List<Detection> results = [];

    for (int i = 0; i < idxs.length && results.length < max; i++) {
      final int idx = idxs[i];
      if (suppressed[idx]) continue;
      final Detection a = detections[idx];
      results.add(a);

      for (int j = i + 1; j < idxs.length; j++) {
        final int idxj = idxs[j];
        if (suppressed[idxj]) continue;
        final Detection b = detections[idxj];

        final double iou = _computeIoU(a.box, b.box);
        if (iou > threshold) suppressed[idxj] = true;
      }
    }

    return results;
  }

  double _computeIoU(Rect a, Rect b) {
    final double xx1 = math.max(a.left, b.left);
    final double yy1 = math.max(a.top, b.top);
    final double xx2 = math.min(a.right, b.right);
    final double yy2 = math.min(a.bottom, b.bottom);

    final double w = math.max(0.0, xx2 - xx1);
    final double h = math.max(0.0, yy2 - yy1);
    final double intersection = w * h;

    final double area1 = a.width * a.height;
    final double area2 = b.width * b.height;
    final double union = area1 + area2 - intersection;

    return union > 0 ? intersection / union : 0;
  }

  Detection remapBox(Detection det, LetterboxInfo letterbox) {
    final scale = det.letterboxScale;
    final dx = det.letterboxDx;
    final dy = det.letterboxDy;
    final origW = letterbox.srcWidth;
    final origH = letterbox.srcHeight;

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
}
