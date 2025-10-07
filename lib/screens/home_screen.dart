// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:street_scan/screens/session_review_screen.dart';
import 'package:street_scan/screens/upload_screen.dart';
// import 'package:flutter/foundation.dart';

import '../core/services/roadmap_service.dart';
import '../core/services/local_storage_service.dart';
import '../core/models/session_model.dart';

import '../widgets/mini_map_widget.dart';
import '../widgets/session_tile.dart';
import 'fullscreen_map.dart';
import 'detection_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final RoadmapService _roadmapService = RoadmapService();
  final MapController _mapController = MapController();

  LatLng _currentLocation = const LatLng(0, 0);
  bool _loadingLocation = true;
  List<SessionModel> _sessions = [];

  @override
  void initState() {
    super.initState();
    LocalStorageService.init().then((_) => _loadSessions());
    WidgetsBinding.instance.addObserver(this);
    _getCurrentLocation();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSessions(); // reload sessions whenever app is resumed
    }
  }
  Future<void> _loadSessions() async {
    final list = LocalStorageService.getAllSessions();
    setState(() => _sessions = list.reversed.toList()); // latest first
  }

  Future<void> _getCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _loadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to get current location: $e');
      setState(() => _loadingLocation = false);
    }
  }

  void _openFullScreenMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => FullScreenMap(
          initialLocation: _currentLocation,
          sessions: _sessions,
        ),
      ),
    );
  }

  void _openUploadScreen() async {
    final pending = _sessions.where((s) => s.pendingUpload).toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No pending sessions')));
      return;
    }

    final success = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UploadScreen(sessions: pending),
      ),
    );

    if (success == true) {
      await _loadSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final miniHeight = MediaQuery.of(context).size.height / 3;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadSessions,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                "Street Scan",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Mini map
              _loadingLocation
                  ? const SizedBox(
                      height: 150, child: Center(child: CircularProgressIndicator()))
                  : MiniMapWidget(
                      mapController: _mapController,
                      currentLocation: _currentLocation,
                      sessions: _sessions,
                      height: miniHeight,
                      onFullScreenTap: _openFullScreenMap,
                    ),

              const SizedBox(height: 12),
              const Divider(),
              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openUploadScreen,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Upload Pending'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetectionScreen(cameras: widget.cameras),
                          ),
                        ).then((_) => _loadSessions());
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Start Detection'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Cached sessions
              const Padding(
                padding: EdgeInsets.all(8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Cached Sessions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),

              ..._sessions.map(
                (s) => SessionTile(
                  session: s,
                  onTap: ()  {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SessionReviewScreen(session: s),
                      ),
                    );
                  },
                  onDelete: () async {
                    await LocalStorageService.deleteSession(s.id);
                    _loadSessions();
                  },
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
