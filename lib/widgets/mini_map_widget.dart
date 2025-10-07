// lib/widgets/mini_map_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/models/session_model.dart';

class MiniMapWidget extends StatelessWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final List<SessionModel> sessions;
  final VoidCallback onFullScreenTap;
  final double height;
  final double? width;

  const MiniMapWidget({
    Key? key,
    required this.mapController,
    required this.currentLocation,
    required this.sessions,
    required this.onFullScreenTap,
    required this.height,
    this.width,
  }) : super(key: key);

  List<Marker> _buildPotholeMarkers() {
    final List<Marker> markers = [];
    for (final session in sessions) {
      for (final entry in session.entries) {
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

  @override
  Widget build(BuildContext context) {
    try {
      final potholeMarkers = _buildPotholeMarkers();
      // current location marker
      final currentMarker = Marker(
        point: currentLocation,
        width: 36,
        height: 36,
        child: Transform.rotate(
          angle: 0, // placeholder; later you can rotate based on heading
          child: const Icon(Icons.navigation, color: Colors.blue, size: 28),
        ),
      );
      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: currentLocation,
                initialZoom: 16.0,
                // disable interaction on the mini preview (button used for fullscreen)
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  // optional, helps some tile servers:
                  userAgentPackageName: 'com.gian.street_scan',
                ),
                MarkerLayer(
                  markers: [
                    ...potholeMarkers,
                    currentMarker,
                  ],
                ),
              ],
            ),
            // top-right full-screen button
            Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    backgroundColor: Colors.black54,
                  ),
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Full', style: TextStyle(fontSize: 12)),
                  onPressed: onFullScreenTap,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return Center(child: Text('Map failed to load', style: TextStyle(color: Colors.red)));
    }
  }
}
