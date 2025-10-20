// Shared helpers for map widgets
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:street_scan/core/models/session_model.dart';
// pothole_entry import not required here

class MapHelpers {
  /// Fetch global pothole markers from Firestore collection `pothole_entries`.
  static Future<List<Marker>> fetchGlobalMarkers() async {
    final query = await FirebaseFirestore.instance
        .collection('pothole_entries')
        .get();
    return query.docs.map((doc) {
      final data = doc.data();
      final double lat = (data['latitude'] as num).toDouble();
      final double lng = (data['longitude'] as num).toDouble();
      return Marker(
        point: LatLng(lat, lng),
        width: 24,
        height: 24,
        child: const Icon(Icons.location_on, color: Colors.orange, size: 22),
      );
    }).toList();
  }

  /// Build markers from local sessions' entries.
  static List<Marker> buildLocalMarkers(List<SessionModel> sessions) {
    final List<Marker> markers = [];
    for (final s in sessions) {
      for (final entry in s.entries) {
        markers.add(
          Marker(
            point: LatLng(entry.latitude, entry.longitude),
            width: 20,
            height: 20,
            child: const Icon(Icons.location_on, color: Colors.red, size: 20),
          ),
        );
      }
    }
    return markers;
  }
}
