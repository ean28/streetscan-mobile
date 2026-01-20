import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'detection.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection>? detections;
  final Size imageSize;

  final BoxFit fit;

  DetectionPainter(
    this.detections,
    this.imageSize, {
    this.fit = BoxFit.contain,
  }) {
    _initTextPainters();
  }

  final Paint boxPaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;

  final Paint textBgPaint = Paint()..color = Colors.black54;

  final TextStyle textStyle = const TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  final Map<String, TextPainter> _textPainters = {};

  void _initTextPainters() {
    if (detections == null) return;
    for (final det in detections!) {
      final key = '${det.label} ${(det.confidence * 100).toStringAsFixed(1)}%';
      if (!_textPainters.containsKey(key)) {
        final tp = TextPainter(
          text: TextSpan(text: key, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        _textPainters[key] = tp;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (detections == null || detections!.isEmpty) return;
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    if (kDebugMode) {
      debugPrint(
        'Painter.paint size=${size.width}x${size.height} imageSize=${imageSize.width}x${imageSize.height} fit=$fit scaleX=${scaleX.toStringAsFixed(3)} scaleY=${scaleY.toStringAsFixed(3)}',
      );
    }

    double scale;
    double dx = 0.0;
    double dy = 0.0;

    // Support non-uniform scaling (BoxFit.fill) so overlays match a stretched
    // CameraPreview which uses BoxFit.fill. For other fit modes fall back to
    // the existing uniform scaling logic.
    final bool nonUniform = fit == BoxFit.fill;
    if (nonUniform) {
      // dx/dy remain zero for fill (stretched to fill entire area)
      scale = 1.0; // not used for per-axis scaling
    } else {
      if (fit == BoxFit.cover) {
        scale = scaleX > scaleY ? scaleX : scaleY;
      } else {
        scale = scaleX < scaleY ? scaleX : scaleY;
      }

      dx = (size.width - imageSize.width * scale) / 2;
      dy = (size.height - imageSize.height * scale) / 2;
    }

    for (final det in detections!) {
      Rect rect;
      if (nonUniform) {
        rect = Rect.fromLTRB(
          det.box.left * scaleX,
          det.box.top * scaleY,
          det.box.right * scaleX,
          det.box.bottom * scaleY,
        );
      } else {
        rect = Rect.fromLTRB(
          det.box.left * scale + dx,
          det.box.top * scale + dy,
          det.box.right * scale + dx,
          det.box.bottom * scale + dy,
        );
      }

      if (kDebugMode) {
        debugPrint(
          'Painter mapping det.box=${det.box} -> rect=${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},${rect.right.toStringAsFixed(1)},${rect.bottom.toStringAsFixed(1)}',
        );
      }

      canvas.drawRect(rect, boxPaint);

      final key = '${det.label} ${(det.confidence * 100).toStringAsFixed(1)}%';
      final tp = _textPainters[key];

      if (tp != null) {
        final offset = Offset(
          rect.left,
          (rect.top - tp.height - 2).clamp(0.0, size.height - tp.height),
        );

        final bgRect = Rect.fromLTWH(
          offset.dx - 2,
          offset.dy - 1,
          tp.width + 4,
          tp.height + 2,
        );
        canvas.drawRect(bgRect, textBgPaint);

        tp.paint(canvas, offset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
