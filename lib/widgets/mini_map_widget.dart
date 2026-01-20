// lib/widgets/mini_map_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:street_scan/widgets/common/map/map_helpers.dart';
import 'package:street_scan/widgets/common/map/map_tile_layer.dart';
import 'package:street_scan/widgets/common/map/map_controls.dart';

import '../core/models/session_model.dart';
import '../core/services/proximity_service.dart';

class MiniMapWidget extends StatefulWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final List<SessionModel> sessions;
  final VoidCallback onFullScreenTap;
  final double height;
  final double? width;

  const MiniMapWidget({
    super.key,
    required this.mapController,
    required this.currentLocation,
    required this.sessions,
    required this.onFullScreenTap,
    required this.height,
    this.width,
  });

  @override
  State<MiniMapWidget> createState() => _MiniMapWidgetState();
}

class _MiniMapWidgetState extends State<MiniMapWidget> {
  // source: 0=local, 1=all, 2=global
  int _source = 0;
  bool showHeatmap = false;
  bool _loadingGlobal = false;
  final ValueNotifier<List<Marker>> _globalMarkers = ValueNotifier(const []);
  final ValueNotifier<List<Marker>> _localMarkers = ValueNotifier(const []);
  List<Marker>? _cachedAllMarkers;

  List<Marker> _buildLocalMarkers(List<SessionModel> sessions) {
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

  Future<void> _ensureGlobalMarkers() async {
    if (_globalMarkers.value.isNotEmpty) return;
    setState(() => _loadingGlobal = true);
    try {
      final fetched = await MapHelpers.fetchGlobalMarkers();
      _globalMarkers.value = fetched;
    } catch (e) {
      debugPrint('⚠️ Failed to load global potholes: $e');
    } finally {
      setState(() => _loadingGlobal = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // compute local markers once and cache in a ValueNotifier
    _localMarkers.value = _buildLocalMarkers(widget.sessions);
    // compute local markers once; display markers are computed reactively in build
  }

  @override
  void didUpdateWidget(covariant MiniMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      _localMarkers.value = _buildLocalMarkers(widget.sessions);
      // clear cachedAll so it will be recomputed if needed
      _cachedAllMarkers = null;
    }
  }

  @override
  void dispose() {
    _globalMarkers.dispose();
    _localMarkers.dispose();
    super.dispose();
  }

  // display markers are computed on-the-fly in build using ValueListenableBuilders

  @override
  Widget build(BuildContext context) {
    try {
      // display markers are computed and cached in _displayMarkers

      // Heatmap points (from local or global)
      final heatPoints = widget.sessions
          .expand((s) => s.entries)
          .map((e) => WeightedLatLng(LatLng(e.latitude, e.longitude), 0.5))
          .toList();

      return SizedBox(
        width: widget.width ?? double.infinity,
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: widget.mapController,
              options: MapOptions(
                initialCenter: widget.currentLocation,
                initialZoom: 16.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                const MapTileLayer(
                  apiKey: 'x3dDnoZnrBeQEatH0r2F',
                  mapId: 'streets',
                ),
                // Proximity radius circle (shows search radius around current location)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: widget.currentLocation,
                      color: Colors.blue.withOpacity(0.12),
                      borderColor: Colors.blue.withOpacity(0.6),
                      borderStrokeWidth: 1,
                      radius: ProximityService.instance.radiusMeters,
                      useRadiusInMeter: true,
                    ),
                  ],
                ),
                if (showHeatmap)
                  ValueListenableBuilder<List<Marker>>(
                    valueListenable: _globalMarkers,
                    builder: (context, gm, _) {
                      final globalHeat = gm
                          .map((m) => WeightedLatLng(m.point, 1.0))
                          .toList();
                      final data = _source == 2
                          ? globalHeat
                          : (_source == 1
                                ? [
                                    ...heatPoints,
                                    ...gm.map(
                                      (m) => WeightedLatLng(m.point, 0.75),
                                    ),
                                  ]
                                : heatPoints);
                      return HeatMapLayer(
                        heatMapDataSource: InMemoryHeatMapDataSource(
                          data: data,
                        ),
                        heatMapOptions: HeatMapOptions(radius: 20),
                      );
                    },
                  ),
                // Marker layer (computed reactively from local/global lists)
                ValueListenableBuilder<List<Marker>>(
                  valueListenable: _localMarkers,
                  builder: (context, localMarkers, _) {
                    return ValueListenableBuilder<List<Marker>>(
                      valueListenable: _globalMarkers,
                      builder: (context, gm, _) {
                        final List<Marker> markers = [
                          ...(_source != 2 ? localMarkers : <Marker>[]),
                          Marker(
                            point: widget.currentLocation,
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.navigation,
                              color: Colors.blue,
                              size: 28,
                            ),
                          ),
                          if (_source != 0) ...gm.cast<Marker>(),
                        ];
                        return MarkerLayer(markers: markers);
                      },
                    );
                  },
                ),
              ],
            ),
            // Source selector - top-left
            Positioned(
              top: 8,
              left: 8,
              child: MapControls(
                source: _source,
                onSourceChanged: (idx) async {
                  setState(() => _source = idx);
                  if (_source != 0) await _ensureGlobalMarkers();
                  if (_source == 1) {
                    _cachedAllMarkers ??= [
                      ..._localMarkers.value,
                      ..._globalMarkers.value,
                    ];
                  }
                },
                showSourceControl: true,
                showHeatmapControl: false,
                showFullScreenControl: false,
                loadingGlobal: _loadingGlobal,
              ),
            ),

            // Fullscreen button - top-right
            Positioned(
              top: 8,
              right: 8,
              child: MapControls(
                source: _source,
                onSourceChanged: null,
                showSourceControl: false,
                showHeatmapControl: false,
                showFullScreenControl: true,
                onFullScreen: widget.onFullScreenTap,
              ),
            ),

            // Heatmap toggle - bottom-left
            Positioned(
              bottom: 8,
              left: 8,
              child: MapControls(
                source: _source,
                onSourceChanged: null,
                showSourceControl: false,
                showHeatmapControl: true,
                showFullScreenControl: false,
                showHeatmapState: showHeatmap,
                onToggleHeatmap: () =>
                    setState(() => showHeatmap = !showHeatmap),
              ),
            ),
            if (_loadingGlobal)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      return const Center(
        child: Text('Map failed to load', style: TextStyle(color: Colors.red)),
      );
    }
  }
}
