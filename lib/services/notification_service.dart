import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const scanChannelId = 'scan_progress';
  static const cloudChannelId = 'cloud_analysis';

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      await Permission.notification.request();

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // 扫描进度渠道 — 低重要性，静默显示在状态栏
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          scanChannelId,
          '扫描进度',
          description: '相册扫描进度',
          importance: Importance.low,
        ),
      );

      // 云端解析渠道 — 低重要性，后台可见进度条
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          cloudChannelId,
          '云端解析',
          description: '云端解析进度',
          importance: Importance.low,
        ),
      );
    }

    const androidSettings = AndroidInitializationSettings('ic_notification');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
    String channelId = scanChannelId,
    String channelName = '扫描进度',
  }) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelName,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      ongoing: true,
      autoCancel: false,
      icon: 'ic_notification',
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> showCompleted({
    required int id,
    required String title,
    required String body,
    String channelId = scanChannelId,
    String channelName = '扫描进度',
  }) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelName,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: false,
      ongoing: false,
      autoCancel: true,
      icon: 'ic_notification',
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}
