// lib/screens/fullscreen_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import '../core/models/session_model.dart';
import '../widgets/common/map/map_helpers.dart';
import '../widgets/common/map/map_controls.dart';
import '../widgets/common/map/map_tile_layer.dart';
import '../core/services/proximity_service.dart';
import '../core/utils/app_env.dart';

class FullScreenMap extends StatefulWidget {
  final LatLng initialLocation;
  final List<SessionModel> sessions;

  const FullScreenMap({
    super.key,
    required this.initialLocation,
    this.sessions = const [],
  });

  @override
  State<FullScreenMap> createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<FullScreenMap> {
  final MapController _ctrl = MapController();
  int _source = 0; // 0=local,1=all,2=global
  bool showHeatmap = false;
  bool _loadingGlobal = false;
  final ValueNotifier<List<Marker>> _globalMarkers = ValueNotifier(const []);
  final ValueNotifier<List<Marker>> _localMarkers = ValueNotifier(const []);
  List<Marker>? _cachedAllMarkers;

  /// Use shared helpers
  List<Marker> _buildLocalMarkers(List<SessionModel> sessions) =>
      MapHelpers.buildLocalMarkers(sessions);

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
    _localMarkers.value = _buildLocalMarkers(widget.sessions);
    // display markers are computed reactively in build; no manual listeners
  }

  @override
  void didUpdateWidget(covariant FullScreenMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      _localMarkers.value = _buildLocalMarkers(widget.sessions);
      _cachedAllMarkers = null;
    }
  }

  @override
  void dispose() {
    _globalMarkers.dispose();
    _localMarkers.dispose();
    super.dispose();
  }

  // display markers are computed on-the-fly in build using nested ValueListenableBuilders

  @override
  Widget build(BuildContext context) {
    // markers are computed and cached in _displayMarkers

    // Heatmap points
    final heatPoints = widget.sessions
        .expand((s) => s.entries)
        .map((e) => WeightedLatLng(LatLng(e.latitude, e.longitude), 0.5))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Full Map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: widget.initialLocation,
              initialZoom: 16.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              MapTileLayer(
                apiKey: AppEnv.mapTilerApiKey,
                mapId: AppEnv.mapTilerMapId,
              ),
              // Proximity radius visualization
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: widget.initialLocation,
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
                      heatMapDataSource: InMemoryHeatMapDataSource(data: data),
                      heatMapOptions: HeatMapOptions(radius: 20),
                    );
                  },
                ),
              ValueListenableBuilder<List<Marker>>(
                valueListenable: _localMarkers,
                builder: (context, localMarkers, _) {
                  return ValueListenableBuilder<List<Marker>>(
                    valueListenable: _globalMarkers,
                    builder: (context, gm, _) {
                      final List<Marker> markers = [
                        ...(_source != 2 ? localMarkers : <Marker>[]),
                        Marker(
                          point: widget.initialLocation,
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
              onToggleHeatmap: () => setState(() => showHeatmap = !showHeatmap),
            ),
          ),
          if (_loadingGlobal)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          // heatmap toggle moved into MapControls
        ],
      ),
    );
  }
}
