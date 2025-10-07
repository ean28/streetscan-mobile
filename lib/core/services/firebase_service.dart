import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/pothole_entry.dart';
import '../models/session_model.dart';
import 'cloudinary_service.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _queueBoxName = 'upload_queue';
  late final Future<Box<SessionModel>> _queueBox;
  final CloudinaryService _cloudinaryService = CloudinaryService();

  FirebaseService() {
    // Open Hive box and start connectivity monitoring
    _queueBox = _openQueueBox();
    _monitorConnectivity();
  }

  Future<Box<SessionModel>> _openQueueBox() async {
    final box = await Hive.openBox<SessionModel>(_queueBoxName);
    await _uploadPendingSessions(); 
    return box;
  }

  // Connectivity listener
  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((status) async {
      if (status != ConnectivityResult.none) {
        await _uploadPendingSessions();
      }
    });
  }

  // Show feedback snackbar
  void _showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Queue a session for offline upload
  Future<void> queueSession(SessionModel session, BuildContext context) async {
    final box = await _queueBox;
    await box.put(session.id, session);
    _showSnackBar(context, "🟡 Session queued for upload: ${session.id}");
    await _uploadPendingSessions(context: context);
  }

  // Upload a single session (metadata + entries + images)
  Future<void> uploadSession(SessionModel session,
    {BuildContext? context}) async {
    final sessionRef = _db.collection('sessions').doc(session.id);

    try {
      // Upload session metadata
      await sessionRef.set({
        'id': session.id,
        'createdAt': session.createdAt.toIso8601String(),
        'durationSeconds': session.durationSeconds,
        'pendingUpload': false,
        'averageLatency': session.averageLatency,
        'totalFramesProcessed': session.totalFramesProcessed,
        'gpsTrack': session.gpsTrack,
        'potholeSeverityCounts': session.potholeSeverityCounts,
      });

      // Upload entries
      for (final entry in session.entries) {
        String? imageUrl;

        final entryRef = sessionRef.collection('entries').doc(entry.id);
        final existingEntry = await entryRef.get();

        // Delete old Cloudinary image if it exists
        // if (existingEntry.exists) {
        //   final oldUrl = existingEntry.data()?['imageUrl'] as String?;
        //   if (oldUrl != null && oldUrl.isNotEmpty) {
        //     await _cloudinaryService.deleteImage(oldUrl);
        //   }
        // }

        // Upload new image if present
        if (entry.imagePath != null && entry.imagePath.isNotEmpty) {
          imageUrl = await _cloudinaryService.uploadImage(
            entry.imagePath!,
            session.id,
          );
        }

        final entryWithUrl = entry.copyWith(imageUrl: imageUrl);

        // Save entry under session
        await entryRef.set(entryWithUrl.toMap());

        // Save entry globally
        await _db.collection('pothole_entries').doc(entry.id).set({
          ...entryWithUrl.toMap(),
          'sessionId': session.id,
        });
      }

      if (context != null) {
        _showSnackBar(context, "✅ Session uploaded: ${session.id}");
      }
    } catch (e) {
      if (context != null) {
        _showSnackBar(context, "❌ Failed to upload session: ${session.id}",
            isError: true);
      }
      rethrow;
    }
  }

  // Upload multiple sessions
  Future<void> uploadMultipleSessions(List<SessionModel> sessions,
    {BuildContext? context}) async {
    for (final session in sessions) {
      try {
        // Fetch existing entries for this session from Firestore
        final sessionRef = _db.collection('sessions').doc(session.id);
        final existingEntriesSnapshot = await sessionRef.collection('entries').get();

        // Map existing entryId -> imageUrl
        final existingImages = {
          for (var doc in existingEntriesSnapshot.docs)
            doc.id: (doc.data()['imageUrl'] as String?) ?? ''
        };

        // Delete old Cloudinary images if the entry is being overwritten
        // for (final entry in session.entries) {
        //   final oldUrl = existingImages[entry.id];
        //   if (oldUrl != null && oldUrl.isNotEmpty) {
        //     await _cloudinaryService.deleteImage(oldUrl);
        //   }
        // }

        // Now upload this session normally
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
      _showSnackBar(context, "✅ Batch upload finished for ${sessions.length} sessions");
    }
  }

  // Upload pending sessions in queue
  Future<void> _uploadPendingSessions({BuildContext? context}) async {
    try {
      final box = await _queueBox;
      if (box.isEmpty) return;

      final pendingSessions = box.values.toList();

      for (final session in pendingSessions) {
        try {
          await uploadSession(session, context: context);
          await box.delete(session.id);
        } catch (e) {
          if (context != null) {
            _showSnackBar(
              context,
              "❌ Failed to upload queued session: ${session.id}, will retry later",
              isError: true,
            );
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint("❌ Error uploading pending sessions: $e\n$st");
      }
    }
  }

  // Fetch all sessions
  Future<List<SessionModel>> fetchSessions() async {
    try {
      final snapshot = await _db.collection('sessions').get();
      return snapshot.docs
          .map((doc) => SessionModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Fetch pothole entries for a session
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
      return [];
    }
  }
}
