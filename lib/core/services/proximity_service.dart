import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'local_storage_service.dart';
import 'roadmap_service.dart';
import 'notification_service.dart';

class ProximityService {
  ProximityService._internal();
  static final ProximityService instance = ProximityService._internal();

  bool _running = false;
  bool get isRunning => _running;

  StreamSubscription<Position>? _posSub;
  Timer? _serverRefreshTimer;

  // Cached server-side potholes (map with lat/lng)
  List<Map<String, dynamic>> _serverPotholes = [];

  // Notifiers for UI (optional) and tests
  final ValueNotifier<int> nearbyCount = ValueNotifier<int>(0);
  // Split counts
  final ValueNotifier<int> localNearbyCount = ValueNotifier<int>(0);
  final ValueNotifier<int> serverNearbyCount = ValueNotifier<int>(0);
  final ValueNotifier<double?> closestDistanceMeters = ValueNotifier<double?>(
    null,
  );

  // Config
  double radiusMeters = 110.0;
  Duration serverRefreshInterval = const Duration(minutes: 2);

  Future<void> init() async {
    if (_running) return;

    // Initial server fetch
    try {
      _serverPotholes = await RoadmapService().getAllPotholesOnce();
      if (kDebugMode) {
        debugPrint(
          'Proximity: initial server potholes=${_serverPotholes.length}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Proximity: failed to fetch server potholes: $e');
      }
    }

    // Periodic refresh
    _serverRefreshTimer = Timer.periodic(serverRefreshInterval, (_) async {
      try {
        _serverPotholes = await RoadmapService().getAllPotholesOnce();
        if (kDebugMode) {
          debugPrint(
            'Proximity: periodic refresh server potholes=${_serverPotholes.length}',
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Proximity refresh failed: $e');
      }
    });

    // Start listening to location
    final locSettings = const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: locSettings)
        .listen(
          (pos) {
            _handlePosition(pos);
          },
          onError: (e) {
            if (kDebugMode) debugPrint('Proximity: position stream error: $e');
          },
        );

    _running = true;
  }

  Future<void> _handlePosition(Position pos) async {
    final lat = pos.latitude;
    final lng = pos.longitude;

    // Collect local entries
    final localSessions = LocalStorageService.getAllSessions();
    final List<Map<String, dynamic>> all = [];
    for (final s in localSessions) {
      for (final e in s.entries) {
        all.add({'lat': e.latitude, 'lng': e.longitude, 'source': 'local'});
      }
    }

    // Ensure we have server entries (try a fallback fetch if empty)
    if (_serverPotholes.isEmpty) {
      try {
        _serverPotholes = await RoadmapService().getAllPotholesOnce();
        if (kDebugMode) {
          debugPrint(
            'Proximity: fallback server potholes=${_serverPotholes.length}',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Proximity: fallback server fetch failed: $e');
        }
      }
    }

    // Normalize and add cached server entries
    for (final raw in _serverPotholes) {
      // support keys 'lat'/'latitude' and 'lng'/'longitude'
      final dynamic latRaw = raw['lat'] ?? raw['latitude'];
      final dynamic lngRaw = raw['lng'] ?? raw['longitude'];
      final double? plat = (latRaw is num)
          ? latRaw.toDouble()
          : (latRaw is String ? double.tryParse(latRaw) : null);
      final double? plng = (lngRaw is num)
          ? lngRaw.toDouble()
          : (lngRaw is String ? double.tryParse(lngRaw) : null);
      if (plat == null || plng == null) continue;
      all.add({'lat': plat, 'lng': plng, 'source': raw['source'] ?? 'server'});
    }

    int count = 0;
    int localCount = 0;
    int serverCount = 0;
    double? closest;
    for (final p in all) {
      final d = _haversineMeters(
        lat,
        lng,
        p['lat'] as double,
        p['lng'] as double,
      );
      if (closest == null || d < closest) closest = d;
      if (d <= radiusMeters) {
        count++;
        if ((p['source'] ?? 'server') == 'local') {
          localCount++;
        } else {
          serverCount++;
        }
      }
    }

    nearbyCount.value = count;
    localNearbyCount.value = localCount;
    serverNearbyCount.value = serverCount;
    closestDistanceMeters.value = closest;

    if (kDebugMode) {
      debugPrint(
        'Proximity: counts total=$count local=$localCount server=$serverCount closest=${closest?.toStringAsFixed(1)}',
      );
    }

    // Update persistent notification
    try {
      if (count > 0) {
        NotificationService().showOrUpdateProximityNotification(
          count,
          closest ?? 0.0,
        );
      } else {
        NotificationService().cancelProximityNotification();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Proximity: notification update failed: $e');
    }
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // m
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  Future<void> pause() async {
    _posSub?.pause();
  }

  Future<void> resume() async {
    _posSub?.resume();
  }

  Future<void> dispose() async {
    await _posSub?.cancel();
    _serverRefreshTimer?.cancel();
    nearbyCount.dispose();
    closestDistanceMeters.dispose();
    _running = false;
  }
}
