import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:street_scan/core/services/local_storage_service.dart';
import 'core/services/upload_metadata_service.dart';

import 'screens/main_screen.dart';
import 'screens/upload_home_screen.dart';
import 'package:provider/provider.dart';
import 'core/services/upload_manager.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';

// Global camera list
late final List<CameraDescription> cameras;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Optionally log to a service
  };

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await LocalStorageService.init();
  // Initialize upload metadata box
  await UploadMetadataService.init();
  await _requestPermissions();

  // Initialize Hive (local storage)
  await Hive.initFlutter();
  // Boxes will be opened by LocalStorageService at runtime
  // Load available cameras
  cameras = await availableCameras();
  // Initialize notifications with navigator key
  await NotificationService().init(navigatorKey);

  runApp(
    ChangeNotifierProvider(
      create: (_) => UploadManager(),
      child: MainApp(cameras: cameras, navigatorKey: navigatorKey),
    ),
  );
}

Future<void> _requestPermissions() async {
  final hasCamera = await Permission.camera.isGranted;
  final hasLoc = await Permission.locationWhenInUse.isGranted;
  final hasStorage = await Permission.storage.isGranted;
  if (!hasCamera || !hasLoc || !hasStorage) {
    await [
      Permission.camera,
      Permission.locationWhenInUse,
      Permission.storage,
    ].request();
  }
}

class MainApp extends StatefulWidget {
  final List<CameraDescription> cameras;
  final GlobalKey<NavigatorState> navigatorKey;
  const MainApp({super.key, required this.cameras, required this.navigatorKey});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    super.initState();
    // After first frame, check if app was launched via notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payload = NotificationService().initialPayload;
      if (payload == 'upload_home' ||
          (payload?.startsWith('upload_progress') ?? false)) {
        widget.navigatorKey.currentState?.pushNamed('/upload_home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      routes: {'/upload_home': (_) => const UploadHomeScreen()},
      title: 'Street Scan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(cameras: widget.cameras),
    );
  }
}
