// lib/screens/upload_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/models/session_model.dart';
import '../core/services/firebase_service.dart';
import '../core/services/local_storage_service.dart';
import '../core/utils/image_utils.dart' as ImageUtils;

class UploadScreen extends StatefulWidget {
  final List<SessionModel> sessions;

  const UploadScreen({super.key, required this.sessions});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  // sessionId -> bool (include whole session)
  final Map<String, bool> _sessionSelected = {};

  // sessionId -> set of pothole ids included
  final Map<String, Set<String>> _potholeSelected = {};

  FlutterLocalNotificationsPlugin? _notificationsPlugin;

  @override
  void initState() {
    super.initState();
    // initialize session selections
    for (final s in widget.sessions) {
      _sessionSelected[s.id] = true;
      _potholeSelected[s.id] = s.entries.map((e) => e.id).toSet();
    }
    _initNotifications();
  }

  void _initNotifications() {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    _notificationsPlugin!.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  Future<void> _showNotification(String title, String body, {int id = 0}) async {
    const androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'Upload Notifications',
      channelDescription: 'Notifications for upload progress',
      importance: Importance.max,
      priority: Priority.high,
      showProgress: true,
    );
    const iosDetails = DarwinNotificationDetails();
    await _notificationsPlugin?.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  void _toggleSession(String sessionId, bool val) {
    setState(() {
      _sessionSelected[sessionId] = val;
      if (!val) {
        _potholeSelected[sessionId] = {};
      } else {
        final s = widget.sessions.firstWhere((x) => x.id == sessionId);
        _potholeSelected[sessionId] = s.entries.map((e) => e.id).toSet();
      }
    });
  }

  void _togglePothole(String sessionId, String potholeId, bool val) {
    setState(() {
      final set = _potholeSelected[sessionId] ?? <String>{};
      if (val) {
        set.add(potholeId);
      } else {
        set.remove(potholeId);
      }
      _potholeSelected[sessionId] = set;
    });
  }

  void _performUpload() {
    // prepare sessions
    final toUpload = <SessionModel>[];
    for (final s in widget.sessions) {
      if (_sessionSelected[s.id] != true) continue;
      final chosenIds = _potholeSelected[s.id] ?? <String>{};
      final chosen = s.entries.where((e) => chosenIds.contains(e.id)).toList();
      if (chosen.isNotEmpty) {
        toUpload.add(s.copyWith(entries: chosen));
      }
    }

    if (toUpload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sessions or potholes selected')),
      );
      return;
    }

    // Clear the screen immediately
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => UploadProgressScreen(toUpload: toUpload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Upload')),
      body: ListView(
        children: widget.sessions.map((s) {
          final selected = _sessionSelected[s.id] ?? false;
          return ExpansionTile(
            initiallyExpanded: true,
            title: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _toggleSession(s.id, v ?? false),
                ),
                Expanded(child: Text('Session: ${s.id} — ${s.count} potholes')),
              ],
            ),
            children: s.entries.map((p) {
              final potholeSelected = _potholeSelected[s.id]?.contains(p.id) ?? false;
              return ListTile(
                leading: ImageUtils.loadImage(p.imagePath, size: 52),
                title: Text(
                    'Pothole @ ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
                subtitle: Text(
                    'Captured: ${p.timestamp.toLocal().toString().split('.')[0]}'),
                trailing: Checkbox(
                  value: potholeSelected,
                  onChanged: selected
                      ? (v) => _togglePothole(s.id, p.id, v ?? false)
                      : null,
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _performUpload,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload Selected'),
          ),
        ),
      ),
    );
  }
}

class UploadProgressScreen extends StatefulWidget {
  final List<SessionModel> toUpload;

  const UploadProgressScreen({super.key, required this.toUpload});

  @override
  State<UploadProgressScreen> createState() => _UploadProgressScreenState();
}

class _UploadProgressScreenState extends State<UploadProgressScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  FlutterLocalNotificationsPlugin? _notificationsPlugin;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _startUpload();
  }

  void _initNotifications() {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    _notificationsPlugin!.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  Future<void> _showNotification(String title, String body, {int id = 0}) async {
    const androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'Upload Notifications',
      channelDescription: 'Notifications for upload progress',
      importance: Importance.max,
      priority: Priority.high,
      showProgress: true,
    );
    const iosDetails = DarwinNotificationDetails();
    await _notificationsPlugin?.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> _startUpload() async {
    for (int i = 0; i < widget.toUpload.length; i++) {
      final session = widget.toUpload[i];
      final notifId = i;

      try {
        await _showNotification('Uploading session ${session.id}', 'Uploading now...', id: notifId);

        await _firebaseService.uploadSession(session);

        await _showNotification('Session ${session.id} uploaded', 'Upload complete', id: notifId);
      } catch (e) {
        await _showNotification('Session ${session.id} failed', e.toString(), id: notifId);
      }
    }

    // All uploads done, pop back to previous screen
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uploading...')),
      body: const Center(
        child: Text('Your uploads are being processed. Check notifications for progress.'),
      ),
    );
  }
}