import 'dart:ui';

class Detection {
  final Rect box;
  final double confidence;
  final int classId;
  final String label;
  final int? inferenceTime;

  final double letterboxScale;
  final double letterboxDx;
  final double letterboxDy;

  Detection({
    required this.box,
    required this.confidence,
    required this.classId,
    required this.label,
    this.inferenceTime,
    required this.letterboxScale,
    required this.letterboxDx,
    required this.letterboxDy,
  }) : assert(
         box.left >= 0 && box.top >= 0 && box.right >= 0 && box.bottom >= 0,
       );

  Rect remapToModelInput() {
    final double x1 = box.left * letterboxScale + letterboxDx;
    final double y1 = box.top * letterboxScale + letterboxDy;
    final double x2 = box.right * letterboxScale + letterboxDx;
    final double y2 = box.bottom * letterboxScale + letterboxDy;
    return Rect.fromLTRB(x1, y1, x2, y2);
  }
}
