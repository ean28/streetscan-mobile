// lib/screens/camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:street_scan/widgets/common/back_button.dart';
import 'package:street_scan/widgets/common/session_timer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/foundation.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  //------------- Config -----------------
  static const String kPackageName = 'com.gian.street_scan';
  String folderPath = '';
  ResolutionPreset selectedResolution = ResolutionPreset.high;

  //------------- State ------------------
  final List<String> _gpsLogs = [];
  final ScrollController _scrollController = ScrollController();
  CameraController? _cameraController;
  bool _isRecording = false;
  int _durationSeconds = 0;
  Timer? _gpsTimer;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  //------------- Methods ----------------
  @override
  void initState() {
    super.initState();
    _enterFullScreen();
    WakelockPlus.enable();
    _initEverything();
  }

  Future<void> _initEverything() async {
    // 1. Ask for essential permissions
    await _requestEssentialPermissions();

    // 2. Check if everything critical was granted
    final granted = await _checkAllPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permissions required. Please enable them in Settings.'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: openAppSettings, // from permission_handler
            ),
      ),
    );
      }
      return; // ⛔ Stop initialization
    }

    // 3. Continue with safe initialization
    await _initializeCamera();
    await _checkGpsPermission();
    folderPath = await _getSaveFolder();

    if (mounted) setState(() {});
  }

  Future<void> _enterFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras[0];
    await _cameraController?.dispose();

    _cameraController = CameraController(
      camera,
      selectedResolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (kDebugMode) debugPrint('Camera init error: $e');
    }
  }

  // Request permissions
  Future<void> _requestEssentialPermissions() async {
    final requested = await [
      Permission.camera,
      Permission.microphone, // 🎤 needed for video recording with audio
      Permission.locationWhenInUse,
      Permission.accessMediaLocation,
      if (Platform.isAndroid) Permission.manageExternalStorage else Permission.photosAddOnly,
      if (Platform.isAndroid) Permission.locationAlways,
    ].request();

    if (kDebugMode) debugPrint('Permission results: $requested');
  }

  // Check if all critical permissions are granted
  Future<bool> _checkAllPermissions() async {
    final camera = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted; // 🎤 check audio too
    final location = await Permission.locationWhenInUse.isGranted;

    final storage = Platform.isAndroid
        ? await Permission.manageExternalStorage.isGranted
        : await Permission.photosAddOnly.isGranted;

    return camera && mic && location && storage;
  }

  Future<void> _checkGpsPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission is required for GPS logging")),
      );
    }
  }
  // GPS Logging
  Future<void> _startLogging() async {
    _gpsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );

        if (pos.accuracy <= 40.0) {
          final logLine =
              '${DateTime.now().toIso8601String()}, ${pos.latitude}, ${pos.longitude}, ${pos.accuracy}';
          if (mounted) {
            setState(() => _gpsLogs.add(logLine));
          }
          if (kDebugMode) debugPrint(logLine);

          Future.delayed(const Duration(milliseconds: 50), () {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to get position: $e');
      }
    });
  }

  Future<void> _stopLogging() async {
    _gpsTimer?.cancel();
    _gpsTimer = null;
  }
  // File & Folder Handling
  Future<String> _getSaveFolder() async {
    String defaultFolder;
    if (Platform.isAndroid) {
      final root = '/storage/emulated/0/Android/media/$kPackageName';
      defaultFolder = '$root/StreetScan';
    } else {
      final base = await getApplicationDocumentsDirectory();
      defaultFolder = '${base.path}/StreetScan';
    }

    final folder = Directory(defaultFolder);
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder.path;
  }

  Future<void> pickSaveFolder(TextEditingController controller) async {
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        controller.text = selectedDirectory;
        folderPath = selectedDirectory;
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('pickSaveFolder error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot pick folder')));
      }
    }
  }

  Future<void> _saveGpsCsv(String baseName, String folder) async {
    final file = File('$folder/$baseName.csv');
    final content = ['timestamp,latitude,longitude,accuracy', ..._gpsLogs].join('\n');
    try {
      await file.writeAsString(content);
    } catch (e) {
      if (kDebugMode) debugPrint('Error writing CSV: $e');
    }
  }

  String _generateTimestampBaseName() {
    final now = DateTime.now();
    return 'StreetScan_${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (!await _checkAllPermissions()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera/Location/Storage permissions required')),
      );
      await _requestEssentialPermissions();
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized || _isRecording) return;

    try {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController!.startVideoRecording();
      await _startLogging();

      _elapsed = Duration.zero;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsed += const Duration(seconds: 1));
        }
      });

      setState(() => _isRecording = true);
    } catch (e) {
      if (kDebugMode) debugPrint('Start recording error: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecordingAndSave() async {
    if (_cameraController == null) return;
    try {
      await _stopLogging();
      _elapsedTimer?.cancel();
      _elapsedTimer = null;

      final baseName = _generateTimestampBaseName();
      final folder = folderPath.isNotEmpty ? folderPath : await _getSaveFolder();
      final videoPath = '$folder/$baseName.mp4';

      final XFile recorded = await _cameraController!.stopVideoRecording();
      await recorded.saveTo(videoPath);

      if (Platform.isAndroid) {
        await ImageGallerySaverPlus.saveFile(videoPath, isReturnPathOfIOS: false);
      }

      await _saveGpsCsv(baseName, folder);

      _gpsLogs.clear();
      setState(() {
        _isRecording = false;
        _elapsed = Duration.zero;
      });
      if (kDebugMode) debugPrint('Saved video: $videoPath and CSV to same folder');
    } catch (e) {
      if (kDebugMode) debugPrint('Stop recording error: $e');
      setState(() => _isRecording = false);
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _cameraController?.dispose();
    WakelockPlus.disable();
    _scrollController.dispose();
    super.dispose();
  }

  // Widget _backButton() {
  //   return Positioned(
  //     top: 10,
  //     left: 12,
  //     child: Container(
  //       padding: const EdgeInsets.all(4),
  //       decoration: BoxDecoration(
  //         color: Colors.black54,
  //         borderRadius: BorderRadius.circular(8),
  //       ),
  //       child: IconButton(
  //         icon: const Icon(Icons.arrow_back, color: Colors.white),
  //         onPressed: () async {
  //           Navigator.pop(context);
  //           await _cameraController?.dispose();
  //           WakelockPlus.disable();
  //           await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  //         },
  //       ),
  //     ),
  //   );
  // }

  Widget _settingsButton(TextEditingController customFolderController) {
    return Positioned(
      top: 10,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => StatefulBuilder(
                builder: (context, setStateDialog) => AlertDialog(
                  title: const Text('Settings'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Video Quality / Resolution'),
                        const SizedBox(height: 8),
                        DropdownButton<ResolutionPreset>(
                          value: selectedResolution,
                          items: ResolutionPreset.values.map((preset) {
                            return DropdownMenuItem(
                              value: preset,
                              child: Text(preset.name.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setStateDialog(() => selectedResolution = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Save Folder Path'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: customFolderController,
                          decoration: InputDecoration(
                            labelText: folderPath.isEmpty ? 'Default path in app media' : folderPath,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.folder_open),
                              onPressed: () async {
                                await pickSaveFolder(customFolderController);
                                setStateDialog(() {});
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('GPS Logging (Always On)'),
                            Switch(
                              value: _gpsTimer != null,
                              onChanged: (value) async {
                                if (value) {
                                  await _startLogging();
                                } else {
                                  await _stopLogging();
                                }
                                setStateDialog(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (customFolderController.text.isNotEmpty) {
                          folderPath = customFolderController.text;
                        }
                        await _initializeCamera();
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bottomControls() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 150,
            padding: const EdgeInsets.all(4),
            color: Colors.black54,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _gpsLogs.length,
              itemBuilder: (context, index) => Text(
                _gpsLogs[index],
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.8),
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                ),
                onPressed: () async {
                  if (_isRecording) {
                    await _stopRecordingAndSave();
                  } else {
                    await _startRecording();
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    key: ValueKey<bool>(_isRecording),
                    color: _isRecording ? Colors.redAccent : Colors.red,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(width: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                ),
                onPressed: () async {
                  if (!await _checkAllPermissions()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Storage permission required')),
                    );
                    await _requestEssentialPermissions();
                    return;
                  }
                  try {
                    final folderToOpen = folderPath.isNotEmpty ? folderPath : await _getSaveFolder();
                    await OpenFilex.open(folderToOpen);
                  } catch (e) {
                    if (kDebugMode) debugPrint('Failed to open folder: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open folder')));
                    }
                  }
                },
                child: const Icon(Icons.folder_open, color: Colors.white, size: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final customFolderController = TextEditingController(text: folderPath);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize!.height,
                height: _cameraController!.value.previewSize!.width,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          Positioned(top: 10, left: 12, child: TopBackButton(onPressed:() => Navigator.pop(context),)),
          Positioned(top: 20, left: 0, right: 0, child: SessionTimer(durationSeconds: _durationSeconds)),
          _settingsButton(customFolderController),
          _bottomControls(),
        ],
      ),
    );
  }
}
