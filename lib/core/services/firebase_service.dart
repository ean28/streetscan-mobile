import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/pothole_entry.dart';
import 'upload_metadata_service.dart';
import '../models/session_model.dart';
import 'cloudinary_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal() {
    _queueBox = _openQueueBox();
    _monitorConnectivity();
  }

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _queueBoxName = 'upload_queue';
  late final Future<Box<SessionModel>> _queueBox;
  final CloudinaryService _cloudinaryService = CloudinaryService();

  bool _isUploading = false;

  Future<Box<SessionModel>> _openQueueBox() async {
    final box = await Hive.openBox<SessionModel>(_queueBoxName);
    await _uploadPendingSessions();
    return box;
  }

  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((dynamic status) async {
      ConnectivityResult current;
      if (status is List &&
          status.isNotEmpty &&
          status.first is ConnectivityResult) {
        current = status.first as ConnectivityResult;
      } else if (status is ConnectivityResult) {
        current = status;
      } else {
        // Unknown payload; conservatively assume connected.
        current = ConnectivityResult.mobile;
      }

      if (current != ConnectivityResult.none) {
        await _uploadPendingSessions();
      }
    });
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> uploadSession(
    SessionModel session, {
    BuildContext? context,
    void Function(String sessionId, int uploadedCount, int totalCount)?
    onEntryUploaded,
    bool Function()? shouldCancel,
    bool Function()? shouldPause,
  }) async {
    final sessionRef = _db.collection('sessions').doc(session.id);

    try {
      final sessionData = {
        'id': session.id,
        'createdAt': session.createdAt.toIso8601String(),
        'durationSeconds': session.durationSeconds,
        'pendingUpload': false,
        'averageLatency': session.averageLatency,
        'totalFramesProcessed': session.totalFramesProcessed,
        'gpsTrack': session.gpsTrack,
        'potholeSeverityCounts': session.potholeSeverityCounts,
      };

      final batch = _db.batch();

      batch.set(sessionRef, sessionData);

      int uploadedCount = 0;
      int skippedCount = 0;
      final totalCount = session.entries.length;

      for (final entry in session.entries) {
        if (shouldCancel?.call() ?? false) break;

        while (shouldPause?.call() ?? false) {
          await Future.delayed(const Duration(milliseconds: 300));
        }

        String? imageUrl = entry.imageUrl;

        // Only upload if image hasn't been uploaded before
        if (entry.imagePath.isNotEmpty &&
            (entry.imageUrl == null || entry.imageUrl!.isEmpty)) {
          final uploadedUrl = await _cloudinaryService.uploadImage(
            entry.imagePath,
            session.id,
          );

          if (uploadedUrl == null) {
            continue;
          } else {
            imageUrl = uploadedUrl;
            uploadedCount++;
          }
        } else {
          skippedCount++;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Skipped duplicate: ${entry.imagePath.split('/').last}',
                ),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        final entryWithUrl = entry.copyWith(imageUrl: imageUrl);
        final entryMap = entryWithUrl.toMap();

        final entryRef = sessionRef.collection('entries').doc(entry.id);
        batch.set(entryRef, entryMap);

        final globalRef = _db.collection('pothole_entries').doc(entry.id);
        batch.set(globalRef, {...entryMap, 'sessionId': session.id});

        try {
          onEntryUploaded?.call(
            session.id,
            uploadedCount + skippedCount,
            totalCount,
          );
        } catch (_) {}
      }

      await batch.commit();

      if (context != null) {
        final message =
            "Session ${session.id} upload complete:\n"
            "✅ Uploaded: $uploadedCount\n"
            "⚠️ Skipped (duplicates): $skippedCount";

        _showSnackBar(context, message, isError: false);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint("❌ Upload error for ${session.id}: $e\n$st");
      if (context != null) {
        _showSnackBar(
          context,
          "❌ Failed to upload session: ${session.id}",
          isError: true,
        );
      }
      rethrow;
    }
  }

  Future<void> uploadMultipleSessions(
    List<SessionModel> sessions, {
    BuildContext? context,
  }) async {
    for (final session in sessions) {
      try {
        await uploadSession(session, context: context);
      } catch (e) {
        if (context != null) {
          _showSnackBar(
            context,
            "❌ Failed to upload session: ${session.id}, will retry later",
            isError: true,
          );
        }
      }
    }

    if (context != null) {
      _showSnackBar(
        context,
        "✅ Batch upload finished for ${sessions.length} sessions",
      );
    }
  }

  Future<void> _uploadPendingSessions({BuildContext? context}) async {
    if (_isUploading) return;
    _isUploading = true;

    try {
      final box = await _queueBox;
      if (box.isEmpty) return;

      final pendingSessions = box.values.toList();

      for (final session in pendingSessions) {
        try {
          await uploadSession(session, context: context);
          await box.delete(session.id);
        } catch (_) {
          if (context != null) {
            _showSnackBar(
              context,
              "⚠️ Retrying later: ${session.id}",
              isError: true,
            );
          }
        }
      }

      if (box.length > 100) await box.compact();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint("❌ Error uploading pending sessions: $e\n$st");
      }
    } finally {
      _isUploading = false;
    }
  }

  Future<List<SessionModel>> fetchSessions() async {
    try {
      final snapshot = await _db.collection('sessions').get();
      return snapshot.docs
          .map((doc) => SessionModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint("⚠️ fetchSessions error: $e");
      return [];
    }
  }

  Future<List<PotholeEntry>> fetchEntriesForSession(String sessionId) async {
    try {
      final snapshot = await _db
          .collection('sessions')
          .doc(sessionId)
          .collection('entries')
          .get();
      return snapshot.docs
          .map((doc) => PotholeEntry.fromMap(doc.data()))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint("⚠️ fetchEntries error: $e");
      return [];
    }
  }

  Future<List<PotholeEntry>> fetchGlobalEntries() async {
    try {
      final snapshot = await _db.collection('pothole_entries').get();
      return snapshot.docs
          .map((doc) => PotholeEntry.fromMap(doc.data()))
          .toList();
    } catch (e, st) {
      if (kDebugMode) debugPrint("⚠️ fetchGlobalEntries error: $e\n$st");
      return [];
    }
  }

  Future<String> _uploadImageWithRetries(
    String path,
    String sessionId,
    String entryId, {
    String? existingUrl, // pass current imageUrl
  }) async {
    if (existingUrl != null && existingUrl.isNotEmpty) {
      if (kDebugMode) debugPrint('✅ Skipping upload, already uploaded: $path');
      return existingUrl;
    }

    int attempt = 0;
    while (true) {
      try {
        final url = await _cloudinaryService.uploadImage(path, sessionId);
        if (url == null) throw Exception('Cloudinary returned null URL');

        // On success, store in metadata
        try {
          await UploadMetadataService.clearMetadata(entryId);
        } catch (_) {}

        if (kDebugMode) debugPrint('⚡ Uploaded image: $path');
        return url;
      } catch (e) {
        attempt++;
        try {
          await UploadMetadataService.incrementRetry(entryId);
        } catch (_) {}

        if (attempt >= 3) {
          try {
            await UploadMetadataService.setLastError(entryId, e.toString());
          } catch (_) {}
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
      }
    }
  }

  Future<String> uploadSingleEntryImage({
    required String entryId,
    required String path,
    required String sessionId,
  }) async {
    return await _uploadImageWithRetries(path, sessionId, entryId);
  }
}
