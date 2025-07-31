import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
    );

    await _createNotificationChannels();
    await _requestPermissions();
  }

  static Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel channelWithSound =
        AndroidNotificationChannel(
      'app_blocker_channel_with_sound',
      'App Blocker Milestones',
      description: 'Notifications for app blocking milestones with sound',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidNotificationChannel channelWithoutSound =
        AndroidNotificationChannel(
      'app_blocker_channel_no_sound',
      'App Blocker Countdown',
      description: 'Silent updates for app blocking countdown',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channelWithSound);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channelWithoutSound);
  }

  static Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    bool playSound = false,
    bool isAlertStyle = false,
    double? progress,
  }) async {
    try {
      final String channelId = playSound
          ? 'app_blocker_channel_with_sound'
          : 'app_blocker_channel_no_sound';

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        playSound ? 'App Blocker Milestones' : 'App Blocker Countdown',
        channelDescription: playSound
            ? 'Notifications for app blocking milestones with sound'
            : 'Silent updates for app blocking countdown',
        importance: playSound ? Importance.high : Importance.low,
        priority: playSound ? Priority.high : Priority.low,
        ongoing: !playSound && !isAlertStyle,
        autoCancel: playSound || isAlertStyle,
        playSound: playSound,
        enableVibration: playSound,
        showProgress: progress != null,
        maxProgress: 100,
        progress: progress != null ? (progress * 100).toInt() : 0,
        category: isAlertStyle ? AndroidNotificationCategory.alarm : null,
        visibility: NotificationVisibility.public,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('Cancelled notification: $id');
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    debugPrint('Cancelled all notifications');
  }
}
