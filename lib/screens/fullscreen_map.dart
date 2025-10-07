// lib/screens/fullscreen_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/models/session_model.dart';

class FullScreenMap extends StatelessWidget {
  final LatLng initialLocation;
  final List<SessionModel> sessions;

  const FullScreenMap({
    super.key,
    required this.initialLocation,
    this.sessions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = MapController();

    // Collect all pothole markers
    final markers = <Marker>[];
    for (final s in sessions) {
      for (final p in s.entries) {
        markers.add(Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 36,
          height: 36,
          child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        ));
      }
    }

    // Add user location marker
    markers.add(Marker(
      point: initialLocation,
      width: 36,
      height: 36,
      child: const Icon(Icons.my_location, color: Colors.blue),
    ));

    // center map on user location or first marker
    final center = markers.isNotEmpty ? markers.first.point : initialLocation;

    return Scaffold(
      appBar: AppBar(title: const Text('Full Map')),
      body: FlutterMap(
        mapController: ctrl,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
