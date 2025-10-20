import 'package:flutter/material.dart';
import 'package:street_scan/core/services/notification_service.dart';
import 'package:street_scan/core/models/pothole_entry.dart';
import 'package:street_scan/core/models/session_model.dart';
import 'package:street_scan/core/services/firebase_service.dart';
import 'package:street_scan/core/utils/image_utils.dart' as image_utils;

class UploadProgressScreen extends StatefulWidget {
  final List<SessionModel> toUpload;

  const UploadProgressScreen({super.key, required this.toUpload});

  @override
  State<UploadProgressScreen> createState() => _UploadProgressScreenState();
}

class _UploadProgressScreenState extends State<UploadProgressScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  // Use central NotificationService
  final NotificationService _notificationService = NotificationService();

  // progress states
  int _uploaded = 0;
  int _failed = 0;
  int _total = 0;
  List<PotholeEntry> _uploadQueue = [];
  String _status = "Preparing uploads...";

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _startUpload();
  }

  void _initNotifications() {
    // NotificationService is initialized in main with navigatorKey
  }

  // Notifications are handled via NotificationService

  Future<void> _startUpload() async {
    _uploadQueue = widget.toUpload.expand((s) => s.entries).toList();
    _total = _uploadQueue.length;

    if (!mounted) return;
    setState(() => _status = "Uploading $_total potholes...");

    await _notificationService.showNotification(
      'Uploading',
      'Starting batch upload...',
      payload: 'upload_progress',
    );

    for (final session in widget.toUpload) {
      try {
        await _firebaseService.uploadSession(session, context: context);
        _uploaded += session.entries.length;
      } catch (_) {
        _failed += session.entries.length;
      }

      if (!mounted) return; // prevent updates after screen is gone
      setState(() {});
    }

    final message = "Uploaded $_uploaded / $_total • Failed: $_failed";

    await _notificationService.showNotification(
      'Upload Complete',
      message,
      payload: 'upload_progress',
    );

    if (!mounted) return;
    setState(() => _status = message);

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = _total == 0 ? 0.0 : _uploaded / _total;

    return Scaffold(
      appBar: AppBar(title: const Text('Uploading...')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(value: percent),
            const SizedBox(height: 12),
            Text(
              _status,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _uploadQueue.length,
                itemBuilder: (context, i) {
                  final entry = _uploadQueue[i];
                  final isDone = i < _uploaded;
                  final hasError =
                      i < _uploaded + _failed && !isDone && _failed > 0;

                  return ListTile(
                    leading: image_utils.loadImage(entry.imagePath, size: 48),
                    title: Text(
                      'Pothole ${entry.id.substring(0, 5)} @ ${entry.latitude.toStringAsFixed(4)}, ${entry.longitude.toStringAsFixed(4)}',
                    ),
                    trailing: Icon(
                      isDone
                          ? Icons.check_circle
                          : hasError
                          ? Icons.error
                          : Icons.cloud_upload,
                      color: isDone
                          ? Colors.green
                          : hasError
                          ? Colors.red
                          : Colors.grey,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
