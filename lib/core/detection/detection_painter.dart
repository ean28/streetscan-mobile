import 'package:flutter/material.dart';
import 'detection.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection>? detections;
  final Size imageSize;

  DetectionPainter(this.detections, this.imageSize) {
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
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final dx = (size.width - imageSize.width * scale) / 2;
    final dy = (size.height - imageSize.height * scale) / 2;

    for (final det in detections!) {
      final rect = Rect.fromLTRB(
        det.box.left * scale + dx,
        det.box.top * scale + dy,
        det.box.right * scale + dx,
        det.box.bottom * scale + dy,
      );

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
