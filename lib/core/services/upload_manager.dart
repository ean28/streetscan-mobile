import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/session_model.dart';
import 'firebase_service.dart';
import 'local_storage_service.dart';
import 'notification_service.dart';

enum UploadStatus { pending, partial, uploaded }

class UploadProgress {
  final String sessionId;
  final int uploadedCount;
  final int totalCount;
  final bool isComplete;

  UploadProgress({
    required this.sessionId,
    required this.uploadedCount,
    required this.totalCount,
    this.isComplete = false,
  });
}

class UploadManager extends ChangeNotifier {
  UploadManager._internal() {
    _notificationService = NotificationService();
    _startBackgroundSync();
  }
  static final UploadManager _instance = UploadManager._internal();
  factory UploadManager() => _instance;

  late final NotificationService _notificationService;

  final Map<String, UploadStatus> _status = {};
  final Map<String, UploadProgress> _progress = {};
  final Set<String> _pausedSessions = {};
  final Set<String> _cancelledSessions = {};

  // Broadcast stream to report per-session progress as fraction 0.0..1.0
  final StreamController<Map<String, double>> _progressController =
      StreamController.broadcast();

  Stream<Map<String, double>> get progressStream => _progressController.stream;

  bool _isUploading = false;
  StreamSubscription? _connectivitySub;

  List<SessionModel> get localSessions => LocalStorageService.getAllSessions();

  UploadStatus statusFor(SessionModel s) =>
      _status[s.id] ??
      (s.pendingUpload ? UploadStatus.pending : UploadStatus.uploaded);

  UploadProgress? progressFor(String sessionId) => _progress[sessionId];

  Future<void> refreshRemote() async {
    final rem = await FirebaseService().fetchSessions();
    for (final r in rem) {
      _status[r.id] = UploadStatus.uploaded;
    }
    notifyListeners();
  }

  Future<void> enqueueAllPending() async {
    final pending = LocalStorageService.getAllSessions()
        .where((s) => s.pendingUpload)
        .toList();
    if (pending.isEmpty) return;
    await _uploadBatch(pending);
  }

  Future<void> _uploadBatch(List<SessionModel> sessions) async {
    if (_isUploading) return;
    _isUploading = true;

    int total = sessions.fold(0, (p, s) => p + s.entries.length);
    int uploaded = 0;

    for (final s in sessions) {
      if (_cancelledSessions.contains(s.id)) {
        _status[s.id] = UploadStatus.partial;
        continue;
      }

      // initialize progress
      _progress[s.id] = UploadProgress(
        sessionId: s.id,
        uploadedCount: 0,
        totalCount: s.entries.length,
      );
      notifyListeners();

      try {
        // Use firebase uploadSession with progress callback so we can emit per-entry progress
        await FirebaseService().uploadSession(
          s,
          onEntryUploaded: (sessionId, uploadedCount, totalCount) {
            // update internal progress
            _progress[sessionId] = UploadProgress(
              sessionId: sessionId,
              uploadedCount: uploadedCount,
              totalCount: totalCount,
              isComplete: uploadedCount >= totalCount,
            );
            // emit normalized progress map
            final fraction = totalCount > 0 ? uploadedCount / totalCount : 0.0;
            _progressController.add({sessionId: fraction});
            notifyListeners();
          },
          // allow uploadSession to check for cancellation via a simple predicate
          shouldCancel: () => _cancelledSessions.contains(s.id),
          shouldPause: () => _pausedSessions.contains(s.id),
        );
        uploaded += s.entries.length;
        _status[s.id] = UploadStatus.uploaded;
        _progress[s.id] = UploadProgress(
          sessionId: s.id,
          uploadedCount: s.entries.length,
          totalCount: s.entries.length,
          isComplete: true,
        );
      } catch (e) {
        // partial or failed
        _status[s.id] = UploadStatus.partial;
      }

      notifyListeners();
    }

    _isUploading = false;
    _notificationService.showNotification(
      'Uploads finished',
      'Uploaded: $uploaded / $total',
      payload: 'upload_progress',
    );
  }

  // Pause/resume/cancel APIs
  void pauseSession(String id) {
    _pausedSessions.add(id);
    notifyListeners();
  }

  void resumeSession(String id) {
    _pausedSessions.remove(id);
    notifyListeners();
  }

  void cancelSession(String id) {
    _cancelledSessions.add(id);
    notifyListeners();
  }

  // Query helpers for UI
  bool isPaused(String id) => _pausedSessions.contains(id);
  bool isCancelled(String id) => _cancelledSessions.contains(id);

  void _startBackgroundSync() {
    // placeholder for connectivity-based retries
  }

  /// Returns simple BarChartGroupData for the last N days (default 7)
  List<BarChartGroupData> analyticsBarGroups({int days = 7}) {
    // Build counts per day (0 = today, 1 = yesterday...)
    final now = DateTime.now();
    final counts = List<int>.filled(days, 0);
    for (final s in localSessions) {
      final diff = now.difference(s.createdAt).inDays;
      if (diff >= 0 && diff < days) counts[diff]++;
    }

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < days; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: counts[i].toDouble(),
              color: Colors.blue,
              width: 12,
            ),
          ],
        ),
      );
    }
    return groups;
  }

  void disposeManager() {
    _connectivitySub?.cancel();
    _progressController.close();
  }
}
