import 'package:hive/hive.dart';

/// Simple box storing per-entry upload metadata like retry counts and last error.
class UploadMetadataService {
  static const String _boxName = 'upload_metadata_box';
  static bool _initialized = false;
  static Box<Map>? _box;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.openBox<Map>(_boxName);
    _box = Hive.box<Map>(_boxName);
    _initialized = true;
  }

  static Future<void> setMetadata(
    String entryId,
    Map<String, dynamic> data,
  ) async {
    await init();
    await _box!.put(entryId, data);
  }

  static Map<String, dynamic>? getMetadata(String entryId) {
    if (!_initialized) return null;
    final m = _box!.get(entryId);
    if (m == null) return null;
    return Map<String, dynamic>.from(m.cast<String, dynamic>());
  }

  static Future<void> incrementRetry(String entryId) async {
    await init();
    final existing = getMetadata(entryId) ?? {};
    final count = (existing['retryCount'] as int?) ?? 0;
    existing['retryCount'] = count + 1;
    await setMetadata(entryId, existing);
  }

  static Future<void> setLastError(String entryId, String error) async {
    await init();
    final existing = getMetadata(entryId) ?? {};
    existing['lastError'] = error;
    await setMetadata(entryId, existing);
  }

  static Future<void> clearMetadata(String entryId) async {
    await init();
    await _box!.delete(entryId);
  }

  static int failureCountForSession(List<String> entryIds) {
    if (!_initialized) return 0;
    int c = 0;
    for (final id in entryIds) {
      final m = getMetadata(id);
      if (m != null && (m['retryCount'] as int? ?? 0) > 0) c++;
    }
    return c;
  }
}
