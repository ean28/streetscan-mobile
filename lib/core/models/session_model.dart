import 'dart:math';
import 'package:hive/hive.dart';
import 'pothole_entry.dart';

part 'session_model.g.dart';

@HiveType(typeId: 0)
class SessionModel extends HiveObject {
  static final _rand = Random();

  @HiveField(0)
  final String id;

  @HiveField(1)
  DateTime createdAt;

  @HiveField(2)
  int durationSeconds;

  @HiveField(3)
  List<PotholeEntry> entries;

  @HiveField(4)
  bool pendingUpload;

  // 🔥 new fields
  @HiveField(5)
  double? averageLatency; // ms

  @HiveField(6)
  int? totalFramesProcessed;

  @HiveField(7)
  List<Map<String, double>>? gpsTrack; 
  // each item = {"lat": 13.42, "lng": 123.34}

  @HiveField(8)
  Map<String, int>? potholeSeverityCounts = {}; 
  // {"minor": 12, "major": 3}

  SessionModel({
    String? id,
    required this.createdAt,
    this.durationSeconds = 0,
    List<PotholeEntry>? entries,
    this.pendingUpload = true,
    this.averageLatency,
    this.totalFramesProcessed,
    List<Map<String, double>>? gpsTrack,
    Map<String, int>? potholeSeverityCounts,
  })  : id = id ?? _generateId(),
        entries = entries ?? [],
        gpsTrack = gpsTrack ?? [],
        potholeSeverityCounts = potholeSeverityCounts ?? {};

  static String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final randomPart =
        List.generate(4, (_) => chars[_rand.nextInt(chars.length)]).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$randomPart';
  }

  int get count => entries.length;

  Map<String, int> get countsByClass {
    final counts = <String, int>{};
    for (final e in entries) {
      if (e.detectedClass != null) {
        counts[e.detectedClass!] = (counts[e.detectedClass!] ?? 0) + 1;
      }
    }
    return counts;
  }

  double get computedAverageConfidence {
    final scores = entries
        .where((e) => e.confidence != null)
        .map((e) => e.confidence!)
        .toList();
    if (scores.isEmpty) return 0.0;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  SessionModel copyWith({
    String? id,
    DateTime? createdAt,
    int? durationSeconds,
    List<PotholeEntry>? entries,
    bool? pendingUpload,
    double? averageLatency,
    int? totalFramesProcessed,
    List<Map<String, double>>? gpsTrack,
    Map<String, int>? potholeSeverityCounts,
  }) {
    return SessionModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      entries: entries ?? List<PotholeEntry>.from(this.entries),
      pendingUpload: pendingUpload ?? this.pendingUpload,
      averageLatency: averageLatency ?? this.averageLatency,
      totalFramesProcessed: totalFramesProcessed ?? this.totalFramesProcessed,
      gpsTrack: gpsTrack ?? List<Map<String, double>>.from(this.gpsTrack ?? []),
      potholeSeverityCounts: potholeSeverityCounts ??
          Map<String, int>.from(this.potholeSeverityCounts ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'entries': entries.map((e) => e.toMap()).toList(),
        'pendingUpload': pendingUpload,
        'averageLatency': averageLatency,
        'totalFramesProcessed': totalFramesProcessed,
        'gpsTrack': gpsTrack,
        'potholeSeverityCounts': potholeSeverityCounts,
      };

  factory SessionModel.fromMap(Map<String, dynamic> m) => SessionModel(
        id: m['id'],
        createdAt: DateTime.parse(m['createdAt']),
        durationSeconds: m['durationSeconds'] ?? 0,
        entries: (m['entries'] as List<dynamic>? ?? [])
            .map((e) => PotholeEntry.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        pendingUpload: m['pendingUpload'] ?? true,
        averageLatency: (m['averageLatency'] as num?)?.toDouble() ?? 0.0,
        totalFramesProcessed: m['totalFramesProcessed'] ?? 0,
        gpsTrack: (m['gpsTrack'] as List<dynamic>? ?? [])
            .map((e) => Map<String, double>.from(e))
            .toList(),
        potholeSeverityCounts:
            Map<String, int>.from(m['potholeSeverityCounts'] ?? {}),
      );

  void incrementSeverity(String label) {
    potholeSeverityCounts?[label] = (potholeSeverityCounts?[label] ?? 0) + 1;
    save(); // persist change
  }
}
