// lib/screens/detection_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:street_scan/core/services/detection_pipeline.dart';
import 'package:street_scan/core/services/config/detection_settings.dart';
import 'package:street_scan/widgets/common/settings/detscr_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:street_scan/core/services/inference_isolate.dart';

import '../core/models/session_model.dart';
import '../core/models/pothole_entry.dart';
import '../core/services/local_storage_service.dart';
import '../core/services/pothole_detector.dart';
import '../core/services/proximity_service.dart';
import '../core/detection/detection.dart';
import '../core/detection/detection_painter.dart';
import 'session_review_screen.dart';
import '../widgets/common/back_button.dart';
import '../widgets/common/session_timer.dart';

class LiveDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LiveDetectionScreen({super.key, required this.cameras});

  @override
  State<LiveDetectionScreen> createState() => _LiveDetectionScreenState();
}

// Top-level isolate entry: convert YUV420 planes to a resized JPEG written
// to `destPath`. Returns the destPath on success.
Future<String> _yuv420ToJpegAndSave(Map<String, dynamic> args) async {
  final Uint8List y = args['y'];
  final Uint8List u = args['u'];
  final Uint8List v = args['v'];
  final int width = args['width'];
  final int height = args['height'];
  final int yRowStride = args['yRowStride'];
  final int uvRowStride = args['uvRowStride'];
  final int uvPixelStride = args['uvPixelStride'];
  final String destPath = args['destPath'];
  final int quality = args['quality'] ?? 78;
  final int target = args['target'] ?? 320;

  // Create target image and sample from source with nearest-neighbor downscale.
  final img.Image out = img.Image(width: target, height: target);

  for (int ty = 0; ty < target; ty++) {
    final int srcY = ((ty * height) / target).floor();
    for (int tx = 0; tx < target; tx++) {
      final int srcX = ((tx * width) / target).floor();

      final int yIndex = srcY * yRowStride + srcX;
      final int uvIndex =
          (srcY >> 1) * uvRowStride + (srcX >> 1) * uvPixelStride;

      final int Y = y[yIndex] & 0xFF;
      final int U = u[uvIndex] & 0xFF;
      final int V = v[uvIndex] & 0xFF;

      int R = (Y + 1.370705 * (V - 128)).round();
      int G = (Y - 0.698001 * (V - 128) - 0.337633 * (U - 128)).round();
      int B = (Y + 1.732446 * (U - 128)).round();

      R = R.clamp(0, 255);
      G = G.clamp(0, 255);
      B = B.clamp(0, 255);

      out.setPixelRgba(tx, ty, R, G, B, 255);
    }
  }

  // Encode to JPEG and write atomically
  final jpg = img.encodeJpg(out, quality: quality);
  final file = File(destPath);
  await file.writeAsBytes(jpg, flush: true);
  return destPath;
}

class _LiveDetectionScreenState extends State<LiveDetectionScreen> {
  late PotholeDetectionPipeline _pipeline;
  CameraController? _cameraController;
  // Latest camera frame planes (cloned) for snapshotting from stream
  Uint8List? _latestY;
  Uint8List? _latestU;
  Uint8List? _latestV;
  int _latestImageWidth = 0;
  int _latestImageHeight = 0;
  int _latestYRowStride = 0;
  int _latestUvRowStride = 0;
  int _latestUvPixelStride = 0;
  bool _isSavingSnapshot = false;
  bool _pendingSaveRequested = false;
  String? _pendingSaveDest;
  bool _pendingSaveCompress = true;
  Timer? _sessionTimer;
  Timer? _gpsTimer;
  int _durationSeconds = 0;
  bool _detecting = false;
  SessionModel? _currentSession;
  final List<Map<String, double>> _gpsLog = [];
  DateTime? _lastSnapshotTime;

  // new tracking variables
  List<Detection> _lastDetections = [];
  int _lastDetectionLatency = 0;
  int _totalFrames = 0;
  int _totalFramesReceived = 0;
  int _totalLatencyMs = 0;
  int _lastInferenceMs = 0;
  String _deviceModel = "Unknown";
  bool _modelLoaded = false;
  ValueNotifier<ManagerStats>? _statsNotifier;
  late ValueNotifier<Map<String, int>> _frameStatsNotifier;

  OverlayMode _overlayMode = OverlayMode.sessionOnly;

  // Snapshot queue removed — snapshots will be triggered immediately on detection

  @override
  void initState() {
    super.initState();
    // Pause the global proximity service while live detection is active
    try {
      ProximityService.instance.pause();
    } catch (_) {}
    _enterFullScreen();
    LocalStorageService.init();
    WakelockPlus.enable();
    _loadDeviceModel();
    _requestEssentialPermissions();
    // no snapshot queue; snapshot immediately when detections occur
    _frameStatsNotifier = ValueNotifier<Map<String, int>>({
      'received': 0,
      'processed': 0,
    });

    //detection pipeline
    _pipeline = PotholeDetectionPipeline(
      snapshotEveryFrame: false,
      onDetection: (detections, detectionMs, inferenceMs) {
        if (!mounted) return;
        setState(() {
          _lastDetections = detections;
          _lastDetectionLatency = detectionMs;
          _totalFrames = _pipeline.totalFrames;
          _totalLatencyMs = _pipeline.totalDetectionMs;
          _lastInferenceMs = inferenceMs;
        });
        _frameStatsNotifier.value = {
          'received': _totalFramesReceived,
          'processed': _totalFrames,
        };

        if (_detecting && detections.isNotEmpty) {
          // Attempt to snapshot immediately (fire-and-forget).
          // Use configured snapshot interval to throttle saves.
          _maybeSnapshot(
            minIntervalMs: DetectionConfig.instance.snapshotIntervalMs,
          );
        }
      },
      onModelLoaded: () {
        if (mounted) {
          setState(() => _modelLoaded = true);
          // the pipeline creates the manager during init; read its stats notifier if available
          _statsNotifier = _pipeline.statsNotifier;
        }
      },
      onDetectionMs: (detectionMs) {
        if (mounted) setState(() => _lastDetectionLatency = detectionMs);
      },
    );
    _pipeline.init();

    // Listen for changes in processing interval and re-init pipeline when changed.
    DetectionConfig.instance.addListener(_onDetectionConfigChanged);
  }

  void _onDetectionConfigChanged() {
    // Apply new processing interval at runtime without restarting the pipeline.
    final ms = DetectionConfig.instance.processingIntervalMs;
    try {
      _pipeline.setProcessingIntervalMs(ms);
      // update local stats notifier reference in case it wasn't set earlier
      _statsNotifier ??= _pipeline.statsNotifier;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to set processing interval: $e');
    }
  }

  Future<void> _loadDeviceModel() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        if (!mounted) return;
        setState(() {
          _deviceModel = "${info.manufacturer} ${info.model}";
        });
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        if (!mounted) return;
        setState(() {
          _deviceModel = "${info.name} (${info.model})";
        });
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint("Device model load error: $e\n$st");
    }
  }

  // snapshot queue removed; immediate snapshots are triggered directly

  Future<void> _enterFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _requestEssentialPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
      Permission.microphone,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      if (statuses.values.any((s) => s.isPermanentlyDenied)) {
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Permissions Required"),
            content: const Text(
              "Camera and Location permissions are required. Please enable them in Settings.",
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(c);
                  await openAppSettings();
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
        );
      }
    }

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.locationWhenInUse]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      await _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras[0];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await _cameraController!.initialize();

      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFocusMode(FocusMode.auto);
      if (!mounted) return;
      setState(() {});
      _startImageStream();
    } catch (e, st) {
      if (kDebugMode) debugPrint('Camera init error: $e\n$st');
    }
  }

  void _startImageStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint('Camera controller is null or not initialized!');
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      _totalFramesReceived++;
      _frameStatsNotifier.value = {
        'received': _totalFramesReceived,
        'processed': _totalFrames,
      };
      final shouldProcessFrame =
          _detecting || _overlayMode == OverlayMode.alwaysOn;
      if (!shouldProcessFrame) return;

      // Clone and store the latest frame planes only when a save is requested.
      // Cloning every frame is costly; snapshot requests are rare so we avoid
      // copying per-frame unless `_pendingSaveRequested` is true.
      if (_pendingSaveRequested) {
        try {
          _latestImageWidth = image.width;
          _latestImageHeight = image.height;
          final p0 = image.planes[0];
          final p1 = image.planes[1];
          final p2 = image.planes[2];
          _latestYRowStride = p0.bytesPerRow;
          _latestUvRowStride = p1.bytesPerRow;
          _latestUvPixelStride = p1.bytesPerPixel ?? 1;
          _latestY = Uint8List.fromList(p0.bytes);
          _latestU = Uint8List.fromList(p1.bytes);
          _latestV = Uint8List.fromList(p2.bytes);
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to clone camera frame: $e');
        }

        // After cloning the requested frame, attempt to process the pending save.
        // This allows snapshot requests to wait for the next available frame
        // without cloning every incoming frame.
        _processPendingSave();
      }

      _pipeline.addFrame(image); // send frame to iso pipeline
    });
  }

  Future<void> _maybeSnapshot({
    int minIntervalMs = 0,
    bool compress = true,
  }) async {
    final now = DateTime.now();
    if (_lastSnapshotTime != null &&
        now.difference(_lastSnapshotTime!).inMilliseconds < minIntervalMs) {
      return;
    }
    _lastSnapshotTime = now;
    await _snapshotPothole(compress: compress);
  }

  Future<void> _snapshotPothole({bool compress = true}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_currentSession == null) await _startSession();

    final now = DateTime.now();
    final baseName =
        'StreetScan_${now.toIso8601String().replaceAll(":", "-")}.jpg';
    final sessionsDir = await LocalStorageService.sessionsDir();
    final sessionId = _currentSession!.id;
    final sessionFolder = Directory('$sessionsDir/$sessionId/images');
    if (!await sessionFolder.exists()) {
      await sessionFolder.create(recursive: true);
    }
    final destPath = '${sessionFolder.path}/$baseName';

    _pendingSaveRequested = true;
    _pendingSaveDest = destPath;
    _pendingSaveCompress = compress;
    // Start processing if not currently running
    _processPendingSave();
  }

  Future<void> _processPendingSave() async {
    if (!_pendingSaveRequested) return;
    if (_isSavingSnapshot) return;

    // Ensure we have a frame to process. If there's no cloned frame yet,
    // return and let the image stream callback perform the clone and call
    // `_processPendingSave()` once it has data. This avoids cancelling the
    // pending save prematurely and removes the need to clone every frame.
    if (_latestY == null || _latestU == null || _latestV == null) {
      return;
    }

    _isSavingSnapshot = true;
    _pendingSaveRequested = false;

    // Local copies of the latest frame data
    final y = Uint8List.fromList(_latestY!);
    final u = Uint8List.fromList(_latestU!);
    final v = Uint8List.fromList(_latestV!);
    final width = _latestImageWidth;
    final height = _latestImageHeight;
    final yRow = _latestYRowStride;
    final uvRow = _latestUvRowStride;
    final uvPix = _latestUvPixelStride;
    final dest =
        _pendingSaveDest ??
        '${await LocalStorageService.sessionsDir()}/_unknown.jpg';
    final quality = _pendingSaveCompress ? 78 : 90;

    String? savedPath;
    try {
      final args = {
        'y': y,
        'u': u,
        'v': v,
        'width': width,
        'height': height,
        'yRowStride': yRow,
        'uvRowStride': uvRow,
        'uvPixelStride': uvPix,
        'destPath': dest,
        'quality': quality,
        'target': 320,
      };

      savedPath = await compute(_yuv420ToJpegAndSave, args);
    } catch (e) {
      if (kDebugMode) debugPrint('Background save failed: $e');
    }

    if (savedPath != null) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        );

        for (final detection in _lastDetections) {
          final entry = PotholeEntry(
            sessionId: _currentSession!.id,
            imagePath: savedPath,
            latitude: pos.latitude,
            longitude: pos.longitude,
            timestamp: DateTime.now(),
            confidence: detection.confidence,
            detectedClass: detection.label,
            deviceModel: _deviceModel,
            inferenceTime: PotholeDetector.instance.lastInferenceMs,
          );
          // Update in-memory session
          _currentSession!.entries = [..._currentSession!.entries, entry];
          // Update severity counts in-memory
          _currentSession!.potholeSeverityCounts?[detection.label] =
              (_currentSession!.potholeSeverityCounts?[detection.label] ?? 0) +
              1;
        }

        // Update session metadata and persist once
        _currentSession!.totalFramesProcessed = _totalFrames;
        _currentSession!.averageLatency = _totalFrames > 0
            ? _totalLatencyMs / _totalFrames
            : 0;
        _currentSession!.gpsTrack = _gpsLog.cast<Map<String, double>>();
        await LocalStorageService.saveSession(_currentSession!);

        if (kDebugMode) debugPrint('Saved pothole $savedPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved pothole: ${savedPath.split('/').last}'),
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Post-save processing failed: $e');
      }
    }

    _isSavingSnapshot = false;

    // If another save was requested while we processed, handle it now.
    if (_pendingSaveRequested) {
      _processPendingSave();
    }
  }

  // ---------------- GPS Logging ----------------
  Future<void> _startGpsLogging() async {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        );
        _gpsLog.add({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'acc': pos.accuracy,
          'ts': DateTime.now().millisecondsSinceEpoch
              .toDouble(), // keep time too
        });
      } catch (e) {
        if (kDebugMode) debugPrint('GPS log error: $e');
      }
    });
  }

  Future<void> _stopGpsLogging() async {
    _gpsTimer?.cancel();
    _gpsTimer = null;
  }

  Future<void> _startSession() async {
    final hasCamera = await Permission.camera.isGranted;
    final hasLoc = await Permission.locationWhenInUse.isGranted;
    if (!hasCamera || !hasLoc) {
      await [Permission.camera, Permission.locationWhenInUse].request();
    }

    _currentSession = SessionModel(
      createdAt: DateTime.now(),
      durationSeconds: 0,
      entries: [],
      pendingUpload: true,
    );
    await LocalStorageService.saveSession(_currentSession!);

    _durationSeconds = 0;
    _totalFrames = 0;
    _totalFramesReceived = 0;
    _totalLatencyMs = 0;
    _frameStatsNotifier.value = {'received': 0, 'processed': 0};

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      if (_currentSession != null) {
        _currentSession!.durationSeconds = _durationSeconds;
        LocalStorageService.saveSession(_currentSession!);
      }
      if (mounted) setState(() {});
    });

    await _startGpsLogging();
    if (mounted) setState(() => _detecting = true);
  }

  Future<void> _endSession() async {
    _sessionTimer?.cancel();
    await _stopGpsLogging();
    if (mounted) {
      setState(() {
        _detecting = false;
        _durationSeconds = 0;
      });
    }

    if (_currentSession == null || _currentSession!.count == 0) {
      if (_currentSession != null) {
        await LocalStorageService.deleteSession(
          _currentSession!.id,
          deleteFiles: false,
        );
      }
      _currentSession = null;
      if (mounted) setState(() {});
      return;
    }

    // finalize session stats
    _currentSession!.totalFramesProcessed = _totalFrames;
    _currentSession!.averageLatency = _totalFrames > 0
        ? _totalLatencyMs / _totalFrames
        : 0;
    _currentSession!.gpsTrack = _gpsLog.cast<Map<String, double>>();
    await LocalStorageService.saveSession(_currentSession!);

    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Session finished'),
        content: const Text('Review now or save for later?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Save for later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Review now'),
          ),
        ],
      ),
    );

    if (res == true && _currentSession != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionReviewScreen(session: _currentSession!),
        ),
      );
    }

    _currentSession = null;
    setState(() {});
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _gpsTimer?.cancel();
    _cameraController?.dispose();
    // snapshot queue removed; nothing to close
    _pipeline.dispose();
    DetectionConfig.instance.removeListener(_onDetectionConfigChanged);
    PotholeDetector.instance.close();
    // Resume the global proximity service when leaving live detection
    try {
      ProximityService.instance.resume();
    } catch (_) {}
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------------- UI Components ----------------
  bool get _shouldShowOverlay =>
      _overlayMode == OverlayMode.alwaysOn ||
      (_overlayMode == OverlayMode.sessionOnly && _detecting);

  Widget _gpsPreview() => ValueListenableBuilder<Map<String, int>>(
    valueListenable: _frameStatsNotifier,
    builder: (context, stats, child) => Container(
      height: 120,
      color: Colors.black54,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _currentSession == null
                ? 'No session'
                : 'Session ${_currentSession!.id} - ${_currentSession!.count} potholes detected.',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Frames received: ${stats['received']}, Processed: ${stats['processed']}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            'Pipeline Detection latency: ${_lastDetections.isNotEmpty ? _lastDetectionLatency : "-"} ms',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            'Model Inference Time: ${_lastDetections.isNotEmpty ? _lastInferenceMs : "-"} ms',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _controls() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _modelLoaded
                ? (_detecting
                      ? Colors.redAccent.withAlpha((0.8 * 255).round())
                      : Colors.green.withAlpha((0.8 * 255).round()))
                : Colors.grey, // greyed out if model not loaded
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(32),
          ),
          onPressed: _modelLoaded
              ? () {
                  if (_detecting) {
                    _endSession();
                  } else {
                    _startSession();
                  }
                }
              : null, // disable button
          child: Icon(
            _detecting ? Icons.stop : Icons.play_arrow,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 8),
        if (!_modelLoaded)
          const Text(
            'Model not loaded yet',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
      ],
    ),
  );

  Widget _settingsButton() => DetectionScreenSettings(
    isDetectionActive: _detecting,
    onToggleDetection: () {
      if (_detecting) {
        _endSession();
      } else {
        _startSession();
      }
    },
    onOpenSettings: () {},
    onOverlayModeChanged: (mode) {
      setState(() {
        _overlayMode = mode;
      });
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Use preview size directly as requested (no rotation logic)
    final previewSize = _cameraController!.value.previewSize!;

    // If the stream is portrait (height > width), use it as is.
    // If it's landscape but displayed portrait, we might need to swap for the container size
    // but the user insists "logic of rotation doesnt exist".
    // We will trust the previewSize matches the visual aspect ratio or the FittedBox handles it.
    // However, CameraPreview widget usually expects the child to match the aspect ratio.

    // We will use the previewSize for the painter to map detections correctly.

    return Scaffold(
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.center,
              child: SizedBox(
                width: previewSize.width,
                height: previewSize.height,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          // Inference debug overlay (shows frames sent/processed/dropped etc.)
          // if (_statsNotifier != null)
          //   Positioned(
          //     top: 12,
          //     left: 12,
          //     child: /* InferenceOverlay removed */ null,
          //   ),
          if (_shouldShowOverlay && _lastDetections.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: DetectionPainter(
                  _lastDetections, // No rotation
                  previewSize,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: SessionTimer(durationSeconds: _durationSeconds),
          ),
          Positioned(
            top: 10,
            left: 12,
            child: TopBackButton(onPressed: () => Navigator.pop(context)),
          ),
          Positioned(top: 10, right: 12, child: _settingsButton()),
          Positioned(bottom: 150, left: 20, right: 20, child: _gpsPreview()),
          Positioned(bottom: 40, left: 0, right: 0, child: _controls()),
        ],
      ),
    );
  }
}
