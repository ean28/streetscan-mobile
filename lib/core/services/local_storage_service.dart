import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/session_model.dart';
import '../models/pothole_entry.dart';

/// LocalStorageService: Hive-backed session storage and filesystem helpers.
class LocalStorageService {
  static const String _boxName = 'sessions_box';
  static bool _initialized = false;
  static Box<SessionModel>? _box;

  /// Compact the Hive box in the background to keep storage fast and small
  static Future<void> compactBox() async {
    await init();
    await _box?.compact();
  }

  /// Export all sessions as serializable maps (safe for isolates)
  static Future<List<Map<String, dynamic>>> exportSessions() async {
    await init();
    final sessions = _box?.values.toList() ?? [];

    return sessions.map((s) => {
      'id': s.id,
      'createdAt': s.createdAt.toIso8601String(),
      'durationSeconds': s.durationSeconds,
      'pendingUpload': s.pendingUpload,
      'averageLatency': s.averageLatency,
      'totalFramesProcessed': s.totalFramesProcessed,
      'gpsTrack': s.gpsTrack,
      'potholeSeverityCounts': s.potholeSeverityCounts,
      'entries': s.entries.map((e) => {
        'sessionId': e.sessionId,
        'latitude': e.latitude,
        'longitude': e.longitude,
        'timestamp': e.timestamp.toIso8601String(),
        'imagePath': e.imagePath,
        'confidence': e.confidence,
        'detectedClass': e.detectedClass,
        'deviceModel': e.deviceModel,
        'inferenceTime': e.inferenceTime,
      }).toList(),
    }).toList();
  }

  /// Initialize Hive, register adapters, open boxes.
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SessionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PotholeEntryAdapter());
    }

    _box = await Hive.openBox<SessionModel>(_boxName);
    _initialized = true;
  }

  /// Returns the session directory on device for storing images.
  static Future<String> sessionsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final sessions = Directory('${dir.path}/sessions');
    if (!await sessions.exists()) {
      await sessions.create(recursive: true);
    }
    return sessions.path;
  }

  static Future<void> saveSession(SessionModel session) async {
    await init();
    await _box!.put(session.id, session);
  }

  /// Get all sessions
  static List<SessionModel> getAllSessions() {
    if (!_initialized) return const [];
    return List.unmodifiable(_box!.values.toList());
  }

  /// Get single session
  static SessionModel? getSession(String id) {
    if (!_initialized) return null;
    return _box!.get(id);
  }

  /// Delete session and optional files
  static Future<void> deleteSession(String id, {bool deleteFiles = true}) async {
    final session = getSession(id);
    if (session != null) {
      if (deleteFiles) {
        try {
          final base = await sessionsDir();
          final dir = Directory('$base/$id');
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }
      await _box!.delete(id);
    }
  }

  static Future<void> addPotholeToSession(String sessionId, PotholeEntry entry) async {
    await init();
    final session = _box!.get(sessionId);
    if (session != null) {
      session.entries = [...session.entries, entry];
      await session.save();
    } else {
      // create session fallback
      final s = SessionModel(
        id: sessionId,
        createdAt: DateTime.now(),
        entries: [entry],
        durationSeconds: 0,
        pendingUpload: true,
        averageLatency: 0,
        totalFramesProcessed: 1,
        gpsTrack: [],
        potholeSeverityCounts: {},
      );
      await saveSession(s);
    }
  }

  static Future<void> markSessionUploaded(String sessionId) async {
    await init();
    final s = _box!.get(sessionId);
    if (s != null) {
      s.pendingUpload = false;
      await s.save();
    }
  }
}
