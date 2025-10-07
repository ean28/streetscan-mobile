import '../models/pothole_entry.dart';
import '../detection/detection.dart';
import 'package:geolocator/geolocator.dart';

extension DetectionToEntry on Detection {
  /// Converts a Detection to a PotholeEntry.
  /// Required: [imagePath], [position], [sessionId], [deviceModel].
  PotholeEntry toPotholeEntry({
    required String imagePath,
    required Position position,
    required String sessionId,
    required String deviceModel,
    DateTime? timestamp,
  }) {
    return PotholeEntry(
      imagePath: imagePath,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: timestamp ?? DateTime.now(),
      confidence: confidence,
      detectedClass: label,
      sessionId: sessionId,
      deviceModel: deviceModel,
      inferenceTime: inferenceTime,
    );
  }
}
