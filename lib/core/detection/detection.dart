import 'dart:ui';

class Detection {
  final Rect box;           // Bounding box in original image coordinates
  final double confidence;  // Confidence score (0–1)
  final int classId;        // YOLO class index
  final String label;       // Human-readable label
  final int? inferenceTime; // Inference time in ms

  // Letterbox info for remapping
  final double letterboxScale; // Scale used to resize original -> model input
  final double letterboxDx;    // Horizontal padding (pixels)
  final double letterboxDy;    // Vertical padding (pixels)

  Detection({
    required this.box,
    required this.confidence,
    required this.classId,
    required this.label,
    this.inferenceTime,
    required this.letterboxScale,
    required this.letterboxDx,
    required this.letterboxDy,
  }) : assert(box.left >= 0 && box.top >= 0 && box.right >= 0 && box.bottom >= 0);

  /// Remap box back to model/padded input coordinates
  Rect remapToModelInput() {
    final double x1 = box.left * letterboxScale + letterboxDx;
    final double y1 = box.top * letterboxScale + letterboxDy;
    final double x2 = box.right * letterboxScale + letterboxDx;
    final double y2 = box.bottom * letterboxScale + letterboxDy;
    return Rect.fromLTRB(x1, y1, x2, y2);
  }
}
