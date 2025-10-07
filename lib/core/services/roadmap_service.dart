import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

      final docRef = _firestore.collection('roadmap_sessions').doc(sessionId).collection('potholes').doc();
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
    return _firestore.collection('roadmap_sessions').snapshots();
  }
}
