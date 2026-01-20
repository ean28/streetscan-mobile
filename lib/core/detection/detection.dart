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
  });

  Rect remapToModelInput() {
    final double x1 = box.left * letterboxScale + letterboxDx;
    final double y1 = box.top * letterboxScale + letterboxDy;
    final double x2 = box.right * letterboxScale + letterboxDx;
    final double y2 = box.bottom * letterboxScale + letterboxDy;
    return Rect.fromLTRB(x1, y1, x2, y2);
  }

  Detection copyWith({
    Rect? box,
    double? confidence,
    int? classId,
    String? label,
    int? inferenceTime,
    double? letterboxScale,
    double? letterboxDx,
    double? letterboxDy,
  }) {
    return Detection(
      box: box ?? this.box,
      confidence: confidence ?? this.confidence,
      classId: classId ?? this.classId,
      label: label ?? this.label,
      inferenceTime: inferenceTime ?? this.inferenceTime,
      letterboxScale: letterboxScale ?? this.letterboxScale,
      letterboxDx: letterboxDx ?? this.letterboxDx,
      letterboxDy: letterboxDy ?? this.letterboxDy,
    );
  }
}
