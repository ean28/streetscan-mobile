import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Centralized TileLayer for MapTiler (used across the app).
class MapTileLayer extends StatelessWidget {
  final String apiKey;
  final String mapId;
  final double tileSize;

  const MapTileLayer({
    super.key,
    required this.apiKey,
    this.mapId = 'streets',
    this.tileSize = 512,
  });

  @override
  Widget build(BuildContext context) {
    final url =
        'https://api.maptiler.com/maps/$mapId/{z}/{x}/{y}.png?key=$apiKey';
    return TileLayer(
      urlTemplate: url,
      userAgentPackageName: 'com.gian.street_scan',
      additionalOptions: {
        'attribution': '© OpenStreetMap contributors © MapTiler',
      },
    );
  }
}
