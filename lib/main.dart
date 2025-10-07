import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:street_scan/core/services/local_storage_service.dart';

import 'screens/main_screen.dart';
import 'firebase_options.dart';

// Global camera list
late final List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Optionally log to a service
  };

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await LocalStorageService.init();
  await _requestPermissions();

  // Initialize Hive (local storage)
  await Hive.initFlutter();
  // Boxes will be opened by LocalStorageService at runtime
  // Load available cameras
  cameras = await availableCameras();

  runApp(MainApp(cameras: cameras));
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

class MainApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MainApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Street Scan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          primary: Colors.blue,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(cameras: cameras),
    );
  }
}
