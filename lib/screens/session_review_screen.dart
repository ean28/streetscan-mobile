// lib/screens/session_review_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../core/utils/app_env.dart';
import '../widgets/common/map/map_tile_layer.dart';
import 'package:street_scan/core/services/local_storage_service.dart';
import '../core/models/session_model.dart';
import '../core/models/pothole_entry.dart';
import '../core/utils/image_utils.dart' as image_utils;
import '../core/services/firebase_service.dart';
import '../core/services/upload_metadata_service.dart';

class SessionReviewScreen extends StatefulWidget {
  final SessionModel session;

  const SessionReviewScreen({super.key, required this.session});

  @override
  State<SessionReviewScreen> createState() => _SessionReviewScreenState();
}

class _SessionReviewScreenState extends State<SessionReviewScreen> {
  final MapController _mapController = MapController();
  late List<_PotholeWrapper> _potholes;

  String get severitySummary => (widget.session.potholeSeverityCounts ?? {})
      .entries
      .map((e) => "${e.key}: ${e.value}")
      .join(", ");

  @override
  void initState() {
    super.initState();
    _potholes = widget.session.entries
        .map((e) => _PotholeWrapper(entry: e, isSelected: false))
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bounds = _getBounds();
      if (bounds != null) {
        if ((bounds.north - bounds.south).abs() < 1e-6 &&
            (bounds.east - bounds.west).abs() < 1e-6) {
          _mapController.move(bounds.northEast, 16);
        } else {
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
          );
        }
      }
    });
  }

  /// Get bounds based on gpsTrack if available, else pothole entries
  LatLngBounds? _getBounds() {
    final track = widget.session.gpsTrack ?? [];

    if (track.isNotEmpty) {
      final first = track.first;
      final bounds = LatLngBounds(
        LatLng(first["lat"]!, first["lng"]!),
        LatLng(first["lat"]!, first["lng"]!),
      );
      for (final p in track.skip(1)) {
        bounds.extend(LatLng(p["lat"]!, p["lng"]!));
      }
      return bounds;
    }

    if (_potholes.isNotEmpty) {
      final first = _potholes.first.entry;
      final bounds = LatLngBounds(
        LatLng(first.latitude, first.longitude),
        LatLng(first.latitude, first.longitude),
      );
      for (final e in _potholes.skip(1)) {
        bounds.extend(LatLng(e.entry.latitude, e.entry.longitude));
      }
      return bounds;
    }

    return null;
  }

  bool get _anySelected => _potholes.any((p) => p.isSelected);

  void _toggleSelection(int index, bool? value) {
    setState(() {
      _potholes[index] = _potholes[index].copyWith(isSelected: value ?? false);
    });
  }

  void _deleteSelected() {
    setState(() {
      _potholes.removeWhere((p) => p.isSelected);
    });
  }

  void _deleteSingle(int index) {
    setState(() {
      _potholes.removeAt(index);
    });
  }

  void _discardChanges() {
    setState(() {
      _potholes = widget.session.entries
          .map((e) => _PotholeWrapper(entry: e, isSelected: false))
          .toList();
    });
  }

  Future<void> _confirmChanges() async {
    final remainingEntries = _potholes.map((p) => p.entry).toList();
    if (remainingEntries.isEmpty) {
      await LocalStorageService.deleteSession(widget.session.id);
      Navigator.pop(context, null);
    } else {
      final updatedSession = widget.session.copyWith(entries: remainingEntries);
      await LocalStorageService.saveSession(updatedSession);
      Navigator.pop(context, updatedSession);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gpsTrack = widget.session.gpsTrack ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Session Review"),
        actions: [
          if (_anySelected)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deleteSelected,
              tooltip: "Delete Selected",
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 250,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _potholes.isNotEmpty
                    ? LatLng(
                        _potholes.first.entry.latitude,
                        _potholes.first.entry.longitude,
                      )
                    : const LatLng(0, 0),
                initialZoom: 10,
              ),
              children: [
                MapTileLayer(
                  apiKey: AppEnv.mapTilerApiKey,
                  mapId: AppEnv.mapTilerMapId,
                ),
                if (gpsTrack.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          gpsTrack.first["lat"]!,
                          gpsTrack.first["lng"]!,
                        ),
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: 32,
                        ),
                      ),
                      Marker(
                        point: LatLng(
                          gpsTrack.last["lat"]!,
                          gpsTrack.last["lng"]!,
                        ),
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.stop,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                if (_potholes.isNotEmpty)
                  MarkerLayer(
                    markers: _potholes
                        .map(
                          (e) => Marker(
                            point: LatLng(e.entry.latitude, e.entry.longitude),
                            width: 36,
                            height: 36,
                            child: Icon(
                              Icons.location_on,
                              color: e.isSelected ? Colors.red : Colors.grey,
                              size: 30,
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
          const Divider(),
          //-----POTHOLE LABEL COUNT----//
          if (severitySummary.isNotEmpty ||
              widget.session.averageLatency != null ||
              widget.session.totalFramesProcessed != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (severitySummary.isNotEmpty)
                      Text(
                        "Severity Counts: $severitySummary",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    if (widget.session.averageLatency != null)
                      Text(
                        "Average Latency: ${widget.session.averageLatency!.toStringAsFixed(2)} ms",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    if (widget.session.totalFramesProcessed != null)
                      Text(
                        "Frames Processed: ${widget.session.totalFramesProcessed}",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: ListView.builder(
              itemCount: _potholes.length,
              itemBuilder: (context, i) {
                final pothole = _potholes[i];
                final loadImage = image_utils.loadImage(
                  pothole.entry.imagePath,
                  size: 60,
                );

                return _PotholeListTile(
                  index: i,
                  pothole: pothole,
                  loadImage: loadImage,
                  sessionPendingUpload: widget.session.pendingUpload,
                  onDelete: () => _deleteSingle(i),
                  onToggle: (v) => _toggleSelection(i, v),
                  onRetrySuccess: (newUrl) async {
                    // update local session entry
                    setState(() {
                      final updated = pothole.entry.copyWith(imageUrl: newUrl);
                      _potholes[i] = pothole.copyWith(entry: updated);
                    });
                    // persist session
                    final updatedSession = widget.session.copyWith(
                      entries: _potholes.map((p) => p.entry).toList(),
                    );
                    await LocalStorageService.saveSession(updatedSession);
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(221, 211, 52, 52),
              ),
              onPressed: _discardChanges,
              child: const Text("Discard Changes"),
            ),
            Divider(color: Colors.grey, thickness: 1, indent: 8, endIndent: 8),
            TextButton(
              onPressed: _confirmChanges,
              child: const Text("Confirm Changes"),
            ),
          ],
        ),
      ),
    );
  }
}

class _PotholeListTile extends StatefulWidget {
  final int index;
  final _PotholeWrapper pothole;
  final Widget loadImage;
  final bool sessionPendingUpload;
  final VoidCallback onDelete;
  final ValueChanged<bool?> onToggle;
  final ValueChanged<String> onRetrySuccess;

  const _PotholeListTile({
    required this.index,
    required this.pothole,
    required this.loadImage,
    required this.sessionPendingUpload,
    required this.onDelete,
    required this.onToggle,
    required this.onRetrySuccess,
  });

  @override
  State<_PotholeListTile> createState() => _PotholeListTileState();
}

class _PotholeListTileState extends State<_PotholeListTile> {
  bool _loading = false;

  Future<void> _retry() async {
    setState(() => _loading = true);
    try {
      final url = await FirebaseService().uploadSingleEntryImage(
        entryId: widget.pothole.entry.id,
        path: widget.pothole.entry.imagePath,
        sessionId: widget.pothole.entry.sessionId,
      );
      // clear metadata
      await UploadMetadataService.clearMetadata(widget.pothole.entry.id);
      widget.onRetrySuccess(url);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Retry succeeded')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retry failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pothole;
    final meta = UploadMetadataService.getMetadata(p.entry.id);
    final retryCount = (meta?['retryCount'] as int?) ?? 0;
    final lastError = meta?['lastError'] as String?;

    return Dismissible(
      key: ValueKey(p.entry.timestamp),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: ListTile(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("👉 Swipe left on a tile to delete it")),
        ),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: p.isSelected, onChanged: widget.onToggle),
            GestureDetector(
              onTap: () => _showImageViewer(context, p.entry.imagePath),
              child: widget.loadImage,
            ),
          ],
        ),
        title: Text(
          'Pothole ${widget.index + 1} @ ${p.entry.latitude.toStringAsFixed(5)}, ${p.entry.longitude.toStringAsFixed(5)}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Captured: ${p.entry.timestamp.toLocal().toString().split('.')[0]}',
            ),
            if (retryCount > 0)
              Text(
                'Retries: $retryCount',
                style: const TextStyle(color: Colors.red),
              ),
            if (lastError != null)
              Text(
                'Error: $lastError',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
          ],
        ),
        trailing: _loading
            ? const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(),
              )
            : (widget.sessionPendingUpload
                  ? const SizedBox(width: 36, height: 36)
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _retry,
                      tooltip: 'Retry upload for this entry',
                    )),
      ),
    );
  }

  void _showImageViewer(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(File(imagePath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

// Simple wrapper used by the review screen to track selection state alongside the entry
class _PotholeWrapper {
  final PotholeEntry entry;
  final bool isSelected;

  const _PotholeWrapper({required this.entry, required this.isSelected});

  _PotholeWrapper copyWith({PotholeEntry? entry, bool? isSelected}) {
    return _PotholeWrapper(
      entry: entry ?? this.entry,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
