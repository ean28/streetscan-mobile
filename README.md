# Street Scan Mobile

Real-time pothole detection with road condition reporting and mapping mobile application.

For iOS and Android.

## Project Overview

Street Scan is a Flutter app for capturing and reporting potholes. Core features:

- Local session capture via camera + on-device detection (TFLite model using float32 quantization).
- Session review UI with per-entry image viewer.
- Map views (mini + fullscreen) using `flutter_map` and a centralized `MapTileLayer` wrapper that targets MapTiler tiles.
- Global marker fetching (Firestore) and optional heatmap overlay.
- Upload manager that batches local sessions and reports progress via local notifications.

## Camera & Detection (how the app captures sessions)

Quick guide for working on the capture and on-device detection flows. If you are changing capture, detection or saving behavior, read this first.

- Camera capture (file: `lib/screens/camera_screen.dart`)
	- Purpose: full-screen camera preview, start/stop video recording, GPS logging (1s), and save video + CSV GPS track to a folder.
	- Key functions: `_initializeCamera`, `_startRecording`, `_stopRecordingAndSave`, `_startLogging`, `_saveGpsCsv`.
	- Notes & tips:
		- The code currently requests microphone permission but the controller is created with `enableAudio: false`. If you don't need audio, remove the microphone permission; if you do, enable audio in the controller.
		- The app uses a default save folder (Android: `/storage/emulated/0/Android/media/...`) and allows picking a folder. On modern Android consider MediaStore or scoped storage instead of requesting `MANAGE_EXTERNAL_STORAGE`.
		- Prefer selecting the back-facing camera if available (`CameraLensDirection.back`) rather than always using the first camera exposed by the platform.
		- The GPS logger samples every second with `LocationAccuracy.bestForNavigation`; for battery savings consider a configurable interval and an accuracy threshold.
		- UI notes: move the `TextEditingController` for the folder field into State and reuse it across builds (avoids recreating controllers each build). Add a confirmation if the user navigates back while recording.

- On-device detection & snapshots (file: `lib/screens/detection_screen.dart`)
	- Purpose: stream camera frames into `PotholeDetectionPipeline`, paint bounding boxes with `DetectionPainter`, and take/save a still image (snapshot) when detections occur. Snapshots are stored under the session folder and a `PotholeEntry` is created for each detection.
	- Key functions: `_initializeCamera`, `_startImageStream`, `_maybeSnapshot`, `_snapshotPothole`, `_startSession`, `_endSession`.
	- Notes & tips:
		- Some camera plugins and devices do not support calling `takePicture()` while an image stream is active. To avoid CameraException, stop the image stream before taking a picture and restart it afterwards.
		- When scheduling snapshots from detection callbacks, capture a copy of the current detections and pass that copy into the snapshot routine so the persisted `PotholeEntry` matches the detection set that triggered the snapshot.
		- Use the snapshot queue (already implemented) but ensure it limits concurrency to avoid piling up heavy I/O when the device is busy.
		- Consider throttling overlay repaint frequency (for example, 10 Hz) to reduce UI work on slower devices.

## Uploads & Notifications

- `lib/core/services/notification_service.dart` centralizes the local notification initialization and tap handling. It creates a `FlutterLocalNotificationsPlugin` instance and routes payloads to the app navigator.
- `lib/screens/misc/uploadprogress.dart` and `lib/screens/upload_screen.dart` implement the upload UI. The Upload Manager (`lib/core/services/upload_manager.dart`) coordinates background batching and exposes a `progressStream` that the UI can listen to.

## Developer workflow

1. Install Flutter and required platforms (Android SDK / Xcode).
2. From project root run:

```powershell
flutter pub get
```

3. Run analyzer:

```powershell
flutter analyze
```

4. Launch on device or emulator:

```powershell
flutter run -d <device-id>
```

5. To build an APK for profiling / release:

```powershell
flutter build apk --profile
```