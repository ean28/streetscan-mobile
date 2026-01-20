import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';
import '../models/session_model.dart';
import 'local_storage_service.dart';

class RoadmapService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload a single image file and return download URL
  Future<String> uploadImage(File image, String remotePath) async {
    final ref = _storage.ref().child(remotePath);
    final uploadTask = ref.putFile(image);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// uploads images and writes Firestore documents.
  Future<void> confirmSessionUpload(SessionModel session) async {
    final sessionId = session.id;
    // batch for Firestore writes
    final batch = _firestore.batch();

    for (final entry in session.entries) {
      final file = File(entry.imagePath);
      // remote path: potholes/{sessionId}/{filename}
      final remotePath = 'potholes/$sessionId/${file.uri.pathSegments.last}';
      final url = await uploadImage(file, remotePath);

      final docRef = _firestore
          .collection('sessions')
          .doc(sessionId)
          .collection('potholes')
          .doc();
      batch.set(docRef, {
        'imageUrl': url,
        'latitude': entry.latitude,
        'longitude': entry.longitude,
        'timestamp': entry.timestamp.toIso8601String(),
      });
    }

    await batch.commit();
    // mark uploaded locally
    await LocalStorageService.markSessionUploaded(sessionId);
  }

  /// Stream sessions list (server-side sessions)
  Stream<QuerySnapshot> getSessions() {
    return _firestore.collection('sessions').snapshots();
  }

  /// Fetch all pothole documents once (flattened from subcollections).
  /// Returns list of maps containing `latitude` and `longitude` as doubles.
  Future<List<Map<String, dynamic>>> getAllPotholesOnce() async {
    try {
      final q = await _firestore.collectionGroup('potholes').get();
      final results = q.docs.map((d) {
        final data = d.data();
        final lat = (data['latitude'] is num)
            ? (data['latitude'] as num).toDouble()
            : (data['lat'] is num ? (data['lat'] as num).toDouble() : 0.0);
        final lng = (data['longitude'] is num)
            ? (data['longitude'] as num).toDouble()
            : (data['lng'] is num ? (data['lng'] as num).toDouble() : 0.0);
        return {'lat': lat, 'lng': lng, 'source': 'server'};
      }).toList();

      // Also merge global flat entries if available (some uploads write to 'pothole_entries')
      try {
        final global = await FirebaseService().fetchGlobalEntries();
        for (final e in global) {
          final lat = e.latitude;
          final lng = e.longitude;
          results.add({'lat': lat, 'lng': lng, 'source': 'server'});
        }
        if (kDebugMode) {
          debugPrint('Roadmap: merged global entries=${global.length}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Roadmap: fetchGlobalEntries failed: $e');
      }

      return results;
    } catch (e) {
      return [];
    }
  }
}
