import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:core_utils/core_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static Future<void> Function(String?)? _onNotificationClickAction;
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  static Color? _backgroundIconColor;

  static Future<void> init({
    required FirebaseOptions options,
    required Future<void> Function(String?) onClickAction,
    required Color? color,
  }) async {
    _backgroundIconColor = color;
    _onNotificationClickAction = onClickAction;

    AppLogs.debugLog("Initializing Firebase...");
    await Firebase.initializeApp(options: options);

    if (await Permission.notification.isDenied) {
      AppLogs.debugLog("Requesting notification permissions...");
      await Permission.notification.request();
    }

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings("app_icon");

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    _notificationsPlugin.cancelAll();
    AppLogs.debugLog("All previous notifications cleared.");

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (Platform.isAndroid) {
        AppLogs.debugLog(
            "Foreground Notification: ${message.notification?.title}");
        _showNotification(message, isForeGround: true);
      }
    });

    await _checkInitialMessage();
  }

  static Future<String?> getFCMToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = Platform.iOS ? await FirebaseMessaging.instance.getAPNSToken() : await FirebaseMessaging.instance.getToken();
      AppLogs.debugLog("FCM Token: $token");
      return token;
    } catch (e, stack) {
      AppLogs.debugLog("Error getting FCM token: $e\n$stack");
      return null;
    }
  }

  static void subscribeToTopics(List<String> topics) {
    for (String topic in topics) {
      FirebaseMessaging.instance.subscribeToTopic(topic).then((_) {
        AppLogs.debugLog("Subscribed to topic: $topic");
      });
    }
  }

  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    AppLogs.responseLog(
        "Background Notification: ${message.notification?.title}");
    _showNotification(message);
  }

  static Future<void> _checkInitialMessage() async {
    RemoteMessage? message =
        await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) {
      AppLogs.debugLog(
          "Initial notification received: ${message.notification?.title}");
      _handleMessageOpenedApp(message);
    }
  }

  static void _handleMessageOpenedApp(RemoteMessage message) {
    AppLogs.debugLog(
        "Notification clicked from app open: ${message.notification?.title}");
    if (message.data.containsKey('payload')) {
      _onNotificationClick(message.data['payload']);
    }
  }

  static Future<void> _showNotification(RemoteMessage message,
      {bool isForeGround = false}) async {
    final notification = message.notification;
    if (notification == null) return;

    if (notification.title != null && Platform.isAndroid && !isForeGround) {
      AppLogs.debugLog("Skipping Android Notification");
      return;
    }

    AppLogs.debugLog("Showing notification: ${notification.title}");

    _displayNotification(
      title: notification.title ?? "Notification",
      body: notification.body ?? "You have a new message.",
      imageUrl: message.notification?.android?.imageUrl,
    );
  }

  static Future<void> _onDidReceiveNotificationResponse(
      NotificationResponse response) async {
    AppLogs.debugLog("Notification clicked with payload: ${response.payload}");
    _onNotificationClick(response.payload);
  }

  static Future<void> _onNotificationClick(String? payload) async {
    if (_onNotificationClickAction != null) {
      AppLogs.debugLog(
          "Executing notification click action with payload: $payload");
      await _onNotificationClickAction!(payload);
    } else {
      AppLogs.debugLog("No action defined for notification click.");
    }
  }

  static Future<void> _displayNotification({
    int? id,
    String? title,
    String? body,
    String? imageUrl,
    bool autoCancel = false,
  }) async {
    BigPictureStyleInformation? bigPictureStyle;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final String largeIconPath =
          await _downloadAndSaveImage(imageUrl, 'largeIcon');
      bigPictureStyle = BigPictureStyleInformation(
        FilePathAndroidBitmap(largeIconPath),
        largeIcon: const DrawableResourceAndroidBitmap('app_icon'),
        contentTitle: title,
        summaryText: body,
      );
    }

    final androidDetails = AndroidNotificationDetails(
      '${Random().nextInt(1000)}',
      'App Notification',
      channelDescription: 'General Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      autoCancel: autoCancel,
      styleInformation: bigPictureStyle,
      icon: "app_icon",
      color: _backgroundIconColor,
    );

    final iosDetails = const DarwinNotificationDetails(
      threadIdentifier: '12345',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id ?? 12345,
      title ?? "App Notification",
      body ?? "You have a new notification.",
      notificationDetails,
    );

    AppLogs.debugLog("Notification displayed: $title");
  }

  static void cancelNotification({int? id}) {
    _notificationsPlugin.cancel(id ?? 12345);
    AppLogs.debugLog("Notification canceled: ID ${id ?? 12345}");
  }

  static Future<String> _downloadAndSaveImage(
      String url, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final response = await http.get(Uri.parse(url));
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);
    AppLogs.debugLog("Downloaded image for notification: $filePath");
    return filePath;
  }
}
