import 'dart:math';
import 'package:hive/hive.dart';

part 'pothole_entry.g.dart'; // Hive adapter

@HiveType(typeId: 1)
class PotholeEntry extends HiveObject {
  static final _rand = Random(); // static Random

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String imagePath; // non-nullable

  @HiveField(2)
  final double latitude;

  @HiveField(3)
  final double longitude;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final double? confidence; // Detection score

  @HiveField(6)
  final String? detectedClass; // label (e.g. "medium")

  @HiveField(7)
  final String sessionId;

  @HiveField(8)
  final String? deviceModel;

  @HiveField(9)
  final int? inferenceTime; // ms

  @HiveField(10)
  final String? imageUrl;

  PotholeEntry({
    String? id,
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.sessionId,
    this.confidence,
    this.detectedClass,
    this.deviceModel,
    this.inferenceTime,
    this.imageUrl,
  }) : id = id ?? _generateId();

  // Plain map helper (for API or JSON)
  Map<String, dynamic> toMap() => {
        'id': id,
        'imagePath': imagePath,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
        'detectedClass': detectedClass,
        'sessionId': sessionId,
        'deviceModel': deviceModel,
        'inferenceTime': inferenceTime,
        'imageUrl': imageUrl,
      };

  factory PotholeEntry.fromMap(Map<String, dynamic> m) => PotholeEntry(
        id: m['id'],
        imagePath: m['imagePath'],
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(m['timestamp']),
        confidence: (m['confidence'] as num?)?.toDouble(),
        detectedClass: m['detectedClass'],
        sessionId: m['sessionId'],
        deviceModel: m['deviceModel'],
        inferenceTime: m['inferenceTime'],
        imageUrl: m['imageUrl'],
      );

  static String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final randomPart =
        List.generate(4, (_) => chars[_rand.nextInt(chars.length)]).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$randomPart';
  }
  PotholeEntry copyWith({
    String? imagePath,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    double? confidence,
    String? detectedClass,
    String? sessionId,
    String? deviceModel,
    int? inferenceTime,
    String? imageUrl,
  }) {
    return PotholeEntry(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      confidence: confidence ?? this.confidence,
      detectedClass: detectedClass ?? this.detectedClass,
      sessionId: sessionId ?? this.sessionId,
      deviceModel: deviceModel ?? this.deviceModel,
      inferenceTime: inferenceTime ?? this.inferenceTime,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
