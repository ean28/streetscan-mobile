import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  late GlobalKey<NavigatorState> _navigatorKey;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    // Check if app was launched from a notification
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        _initialPayload = details.notificationResponse?.payload;
      }
    } catch (_) {}

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload ?? '';
        if (payload == 'upload_home') {
          _navigatorKey.currentState?.pushNamed('/upload_home');
          return;
        }
        if (payload.startsWith('upload_progress')) {
          // open upload home where user can inspect active uploads
          _navigatorKey.currentState?.pushNamed('/upload_home');
          return;
        }
        // Other payloads
      },
    );
  }

  String? _initialPayload;
  String? get initialPayload => _initialPayload;

  Future<void> showNotification(
    String title,
    String body, {
    int id = 0,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'Upload Notifications',
      channelDescription: 'Notifications for upload progress',
      importance: Importance.max,
      priority: Priority.high,
      showProgress: true,
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // --- Proximity persistent notification support ---
  static const int _proximityNotifId = 1001;
  static const String _proximityChannelId = 'proximity_channel';

  Future<void> showOrUpdateProximityNotification(
    int count,
    double closestMeters,
  ) async {
    final title = count > 0 ? 'Nearby potholes: $count' : 'No nearby potholes';
    final body = count > 0
        ? 'Closest: ${closestMeters.toStringAsFixed(0)} m • Tap for details'
        : 'No potholes within range';

    final androidDetails = AndroidNotificationDetails(
      _proximityChannelId,
      'Proximity Alerts',
      channelDescription: 'Persistent proximity alerts for nearby potholes',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
    );
    final iosDetails = DarwinNotificationDetails(presentAlert: true);

    await _plugin.show(
      _proximityNotifId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'proximity',
    );
  }

  Future<void> cancelProximityNotification() async {
    try {
      await _plugin.cancel(_proximityNotifId);
    } catch (_) {}
  }
}
