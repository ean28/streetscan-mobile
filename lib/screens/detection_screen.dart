// lib/screens/detection_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:street_scan/core/services/detection_pipeline.dart';
import 'package:street_scan/widgets/common/settings/detscr_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../core/models/session_model.dart';
import '../core/models/pothole_entry.dart';
import '../core/services/local_storage_service.dart';
import '../core/services/pothole_detector.dart';
import '../core/utils/image_utils.dart';
import '../core/detection/detection.dart';
import '../core/detection/detection_painter.dart';
import 'session_review_screen.dart';
import '../widgets/common/back_button.dart';
import '../widgets/common/session_timer.dart';

class DetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DetectionScreen({super.key, required this.cameras});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  late PotholeDetectionPipeline _pipeline;
  CameraController? _cameraController;
  Timer? _sessionTimer;
  Timer? _gpsTimer;
  int _durationSeconds = 0;
  bool _detecting = false;
  SessionModel? _currentSession;
  final List<Map<String, double>> _gpsLog = [];
  DateTime? _lastSnapshotTime;

  InferenceBackend _selectedBackend = InferenceBackend.cpu;

  // new tracking variables
  List<Detection> _lastDetections = [];
  int _lastDetectionLatency = 0; 
  int _totalFrames = 0;
  int _totalLatencyMs = 0;
  int _lastInferenceMs = 0;
  String _deviceModel = "Unknown";
  bool _modelLoaded = false;

  OverlayMode _overlayMode = OverlayMode.sessionOnly;

  final _snapshotQueue = StreamController<void>.broadcast();

  @override
  void initState() {
    super.initState();
    _enterFullScreen();
    LocalStorageService.init();
    WakelockPlus.enable();
    _loadDeviceModel();
    _requestEssentialPermissions();
    _processSnapshotQueue();

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

      if (_detecting && detections.isNotEmpty) {
        _snapshotQueue.add(null); // trigger snapshot
      }
    },
    onModelLoaded: () {
      if (mounted) setState(() => _modelLoaded = true);
    },
    onDetectionMs: (detectionMs) {
      if (mounted) setState(() => _lastDetectionLatency = detectionMs);
    },
  );
  _pipeline.init();

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
  Future<void> _processSnapshotQueue() async {
    _snapshotQueue.stream.asyncMap((_) => _maybeSnapshot()).listen((_) {});
    }

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
                "Camera and Location permissions are required. Please enable them in Settings."),
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
      // await _initDetector();

      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFocusMode(FocusMode.auto);
      if(!mounted) return;
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
      final shouldProcessFrame = _detecting || _overlayMode == OverlayMode.alwaysOn;
      if (!shouldProcessFrame) return;

      _pipeline.addFrame(image); // send frame to iso pipeline
    });
  }

  Future<void> _maybeSnapshot({int minIntervalMs = 400, bool compress = true}) async {
    final now = DateTime.now();
    if (_lastSnapshotTime != null &&
        now.difference(_lastSnapshotTime!).inMilliseconds < minIntervalMs) {
      return;
    }
    _lastSnapshotTime = now;
    await _snapshotPothole(compress: compress);
  }

  Future<void> _snapshotPothole({bool compress = true}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_currentSession == null) await _startSession();

    try {
      final XFile file = await _cameraController!.takePicture();
      final now = DateTime.now();
      final baseName = 'StreetScan_${now.toIso8601String().replaceAll(":", "-")}.jpg';

      final sessionsDir = await LocalStorageService.sessionsDir();
      final sessionId = _currentSession!.id;
      final sessionFolder = Directory('$sessionsDir/$sessionId/images');
      if (!await sessionFolder.exists()) await sessionFolder.create(recursive: true);
      final destPath = '${sessionFolder.path}/$baseName';

      final File savedFile = compress
          ? await compressAndSave(File(file.path), destPath, maxDim: 1280, quality: 82)
          : await File(file.path).copy(destPath);

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);

      for (final detection in _lastDetections) {
        final entry = PotholeEntry(
          sessionId: sessionId,
          imagePath: savedFile.path,
          latitude: pos.latitude,
          longitude: pos.longitude,
          timestamp: DateTime.now(),
          confidence: detection.confidence,
          detectedClass: detection.label,
          deviceModel: _deviceModel,
          inferenceTime: PotholeDetector.instance.lastInferenceMs,
        );
        await LocalStorageService.addPotholeToSession(sessionId, entry);
        //pothole severity count
        _currentSession!.incrementSeverity(detection.label);
      }

      // Update session stats
      _currentSession!.totalFramesProcessed = _totalFrames;
      _currentSession!.averageLatency =
          _totalFrames > 0 ? _totalLatencyMs / _totalFrames : 0;
      _currentSession!.gpsTrack = _gpsLog.cast<Map<String, double>>();
      await LocalStorageService.saveSession(_currentSession!);

      if (kDebugMode) {
        debugPrint(
            'Saved pothole ${savedFile.path} at ${pos.latitude},${pos.longitude}');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Snapshot error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
      }
    }
  }

  // ---------------- GPS Logging ----------------
  Future<void> _startGpsLogging() async {
    _gpsTimer?.cancel();
    _gpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation);
        _gpsLog.add({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'acc': pos.accuracy,
          'ts': DateTime.now().millisecondsSinceEpoch.toDouble(), // keep time too
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
    _totalLatencyMs = 0;

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
        await LocalStorageService.deleteSession(_currentSession!.id,
            deleteFiles: false);
      }
      _currentSession = null;
      if (mounted) setState(() {});
      return;
    }

    // finalize session stats
    _currentSession!.totalFramesProcessed = _totalFrames;
    _currentSession!.averageLatency =
        _totalFrames > 0 ? _totalLatencyMs / _totalFrames : 0;
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
              child: const Text('Save for later')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Review now')),
        ],
      ),
    );

    if (res == true && _currentSession != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SessionReviewScreen(session: _currentSession!)),
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
    _snapshotQueue.close();
    _pipeline.dispose();
    PotholeDetector.instance.close();
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------------- UI Components ----------------
  bool get _shouldShowOverlay =>
      _overlayMode == OverlayMode.alwaysOn ||
      (_overlayMode == OverlayMode.sessionOnly && _detecting);

  Widget _gpsPreview() => Container(
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
              'Frames sent: $_totalFrames',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Pipeline Detection latency: ${_lastDetections.isNotEmpty ? _lastDetectionLatency : "-"} ms',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Model Inference Time: ${_lastDetections.isNotEmpty ? _lastInferenceMs : "-"} ms',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )
          ],
        ),
      );

  Widget _controls() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _modelLoaded
                ? (_detecting ? Colors.redAccent.withOpacity(0.8) : Colors.green.withOpacity(0.8))
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
    return Scaffold(
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: _cameraController!.value.previewSize!.height, 
                height: _cameraController!.value.previewSize!.width,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          if (_shouldShowOverlay && _lastDetections.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: DetectionPainter(
                  _lastDetections,
                  Size(
                    _cameraController!.value.previewSize!.width, 
                    _cameraController!.value.previewSize!.height),
                ),
              ),
            ),
          Positioned(top: 20, left: 0, right: 0, child: SessionTimer(durationSeconds: _durationSeconds)),
          Positioned(top: 10, left: 12, child: TopBackButton(onPressed: () => Navigator.pop(context))),
          Positioned(top: 10, right: 12, child: _settingsButton()),
          Positioned(bottom: 150, left: 20, right: 20, child: _gpsPreview()),
          Positioned(bottom: 40, left: 0, right: 0, child: _controls()),
        ],
      ),
    );
  }
}
