import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:time_buddies/main.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';

enum NotificationType {
  taskReminder,
  groupMessage,
  taskUpdate,
  systemUpdate,
  taskOverdue,
}

extension NotificationTypeExtension on NotificationType {
  String get storageKey {
    switch (this) {
      case NotificationType.taskReminder:
        return 'task_reminder_notifications';
      case NotificationType.groupMessage:
        return 'group_message_notifications';
      case NotificationType.taskUpdate:
        return 'task_updates_notifications';
      case NotificationType.systemUpdate:
        return 'system_updates_notifications';
      case NotificationType.taskOverdue:
        return 'task_overdue_notifications';
    }
  }

  String get channelId {
    switch (this) {
      case NotificationType.taskReminder:
        return 'deadline_reminders';
      case NotificationType.groupMessage:
        return 'group_messages';
      case NotificationType.taskUpdate:
        return 'task_updates';
      case NotificationType.systemUpdate:
        return 'system_updates';
      case NotificationType.taskOverdue:
        return 'overdue_tasks';
    }
  }

  String get channelName {
    switch (this) {
      case NotificationType.taskReminder:
        return 'Deadline Reminders';
      case NotificationType.groupMessage:
        return 'Group Messages';
      case NotificationType.taskUpdate:
        return 'Task Updates';
      case NotificationType.systemUpdate:
        return 'System Updates';
      case NotificationType.taskOverdue:
        return 'Overdue Tasks';
    }
  }

  String get channelDescription {
    switch (this) {
      case NotificationType.taskReminder:
        return 'Notifications for task deadlines';
      case NotificationType.groupMessage:
        return 'Notifications for group messages';
      case NotificationType.taskUpdate:
        return 'Notifications for task updates';
      case NotificationType.systemUpdate:
        return 'Notifications for system updates';
      case NotificationType.taskOverdue:
        return 'Notifications for overdue tasks';
    }
  }
}

class NotificationService {
  static const String _pushEnabledKey = 'push_notifications_enabled';
  static const String _reminderTimeKey = 'reminder_time_hours';

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseService _databaseService = DatabaseService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _notificationCountController = StreamController<int>.broadcast();
  Stream<int> get notificationCountStream =>
      _notificationCountController.stream;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
  }

  Future<void> initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultSettings = {
      _pushEnabledKey: true,
      ...NotificationType.values
          .asMap()
          .map((_, type) => MapEntry(type.storageKey, true)),
    };

    for (var entry in defaultSettings.entries) {
      if (!prefs.containsKey(entry.key)) {
        await prefs.setBool(entry.key, entry.value);
      }
    }

    if (!prefs.containsKey(_reminderTimeKey)) {
      await prefs.setInt(_reminderTimeKey, 24);
    }

    await _initializeLocalNotifications();
  }

  Future<void> initializeForUser(String userId) async {
    await initializeSettings();
    await _requestPermission();

    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _databaseService.updateFcmToken(userId, token);
    }

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _databaseService.updateFcmToken(userId, newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleRemoteMessage(message);
      _updateNotificationCount(userId);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data['route']);
    });

    _updateNotificationCount(userId);
    await processUpcomingReminders(userId);

    Timer.periodic(const Duration(minutes: 15), (_) {
      _checkDueTaskNotifications();
      _checkOverdueTasks();
    });
  }

  Future<void> _initializeLocalNotifications() async {
    const androidInitialization =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInitialization = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidInitialization,
        iOS: iosInitialization,
      ),
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );

    // Create all notification channels
    for (final type in NotificationType.values) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(AndroidNotificationChannel(
            type.channelId,
            type.channelName,
            description: type.channelDescription,
            importance: Importance.high,
          ));
    }
  }

  Future<void> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _pushEnabledKey,
      settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional,
    );
  }

  Future<void> scheduleTaskReminder(
    String taskId,
    String title,
    String description,
    DateTime dueDate,
    String assignedUserId,
  ) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] as bool &&
        settings[NotificationType.taskReminder.storageKey] as bool)) {
      return;
    }

    final reminderTimes = {
      '24h': dueDate.subtract(const Duration(hours: 24)),
      '1h': dueDate.subtract(const Duration(hours: 1)),
    };

    final now = DateTime.now();

    for (var entry in reminderTimes.entries) {
      final reminderTime = entry.value;
      if (reminderTime.isAfter(now)) {
        await _scheduleLocalReminder(
          taskId,
          title,
          description,
          reminderTime,
          dueDate,
          entry.key,
        );
      }
    }
  }

  Future<void> _scheduleLocalReminder(
    String taskId,
    String title,
    String description,
    DateTime reminderTime,
    DateTime dueDate,
    String reminderType,
  ) async {
    try {
      final manila = tz.getLocation('Asia/Manila');
      final scheduledDate = tz.TZDateTime.from(reminderTime, manila);
      final notificationId = _generateNotificationId(taskId, reminderType);

      await _localNotifications.zonedSchedule(
        notificationId,
        'Task Due in ${reminderType == "24h" ? "24 Hours" : "1 Hour"}: $title',
        'Due: ${DateFormat('MMM d, y - h:mm a').format(dueDate)}\n$description',
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationType.taskReminder.channelId,
            NotificationType.taskReminder.channelName,
            channelDescription:
                NotificationType.taskReminder.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: '$taskId|$reminderType',
      );
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  Future<void> sendTaskAssignmentNotification(
    String taskId,
    String title,
    String description,
    DateTime dueDate,
    String assignedUserId,
  ) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] as bool &&
        settings[NotificationType.taskUpdate.storageKey] as bool)) {
      return;
    }

    try {
      final formattedDueDate = DateFormat('MMM d, y - h:mm a').format(dueDate);
      await _localNotifications.show(
        taskId.hashCode + 200000,
        'New Task Assigned: $title',
        'Due: $formattedDueDate\n$description',
        NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationType.taskUpdate.channelId,
            NotificationType.taskUpdate.channelName,
            channelDescription: NotificationType.taskUpdate.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: taskId,
      );
    } catch (e) {
      debugPrint('Error sending task assignment notification: $e');
    }
  }

  Future<void> updateTaskReminder(
    String taskId,
    String title,
    String description,
    DateTime dueDate,
    String assignedUserId,
  ) async {
    await cancelTaskReminder(taskId);
    await scheduleTaskReminder(
        taskId, title, description, dueDate, assignedUserId);
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await _localNotifications.cancel(taskId.hashCode);
    await _localNotifications.cancel(taskId.hashCode + 100000);
  }

  Future<void> processUpcomingReminders(String userId) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] as bool &&
        settings[NotificationType.taskReminder.storageKey] as bool)) {
      return;
    }

    try {
      final now = DateTime.now();
      final tasksQuery = await FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .where('completed', isEqualTo: false)
          .get();

      for (var doc in tasksQuery.docs) {
        final task = doc.data();
        final dueDate = (task['dueDate'] as Timestamp).toDate();
        if (dueDate.isAfter(now)) {
          await scheduleTaskReminder(
            doc.id,
            task['title'] ?? 'Task Reminder',
            task['description'] ?? '',
            dueDate,
            userId,
          );
        }
      }
    } catch (e) {
      debugPrint('Error processing upcoming reminders: $e');
    }
  }

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      _pushEnabledKey: prefs.getBool(_pushEnabledKey) ?? false,
      ...NotificationType.values.asMap().map((_, type) =>
          MapEntry(type.storageKey, prefs.getBool(type.storageKey) ?? true)),
      _reminderTimeKey: prefs.getInt(_reminderTimeKey) ?? 24,
    };
  }

  Future<void> _updateNotificationCount(String userId) async {
    final count = await _databaseService.getUnreadNotificationCount(userId);
    _notificationCountController.add(count);
  }

  Future<void> _checkDueTaskNotifications() async {
    await _databaseService.processDueTaskNotifications();
  }

  Future<void> _checkOverdueTasks() async {
    await _databaseService.checkAndProcessOverdueTasks();
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    navigatorKey.currentState?.pushNamed('/task', arguments: payload);
  }

  // Made this method public to be accessible from NotificationProcessor
  // Add this method to NotificationService class
// Add this method to the NotificationService class
// Keep the existing named parameter version
  Future<void> showLocalNotification({
    required int notificationId,
    required String title,
    required String body,
    String? payload,
    NotificationType type = NotificationType.systemUpdate,
  }) async {
    try {
      await _localNotifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            type.channelId,
            type.channelName,
            channelDescription: type.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

// Add this method to handle RemoteMessage
  Future<void> showLocalNotificationFromMessage(RemoteMessage message) async {
    final type = _getNotificationTypeFromMessage(message);
    await showLocalNotification(
      notificationId: message.data['id'] != null
          ? int.parse(message.data['id'])
          : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      payload: message.data['route'],
      type: type,
    );
  }

  Future<void> _handleRemoteMessage(RemoteMessage message) async {
    final type = _getNotificationTypeFromMessage(message);
    await sendTypedNotification(
      notificationId:
          message.data['id'] != null ? int.parse(message.data['id']) : 0,
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      type: type,
      payload: message.data['route'],
    );
  }

  NotificationType _getNotificationTypeFromMessage(RemoteMessage message) {
    switch (message.data['type'] ?? '') {
      case 'task_reminder':
        return NotificationType.taskReminder;
      case 'group_message':
        return NotificationType.groupMessage;
      case 'task_update':
        return NotificationType.taskUpdate;
      case 'system_update':
        return NotificationType.systemUpdate;
      case 'task_overdue':
        return NotificationType.taskOverdue;
      default:
        return NotificationType.systemUpdate;
    }
  }

  Future<void> sendTypedNotification({
    required int notificationId,
    required String title,
    required String body,
    required NotificationType type,
    String? payload,
    Color? color,
    tz.TZDateTime? scheduledDate,
  }) async {
    final validId = notificationId % 2147483647;
    final settings = await getNotificationSettings();

    if (!(settings[_pushEnabledKey] as bool &&
        settings[type.storageKey] as bool)) {
      return;
    }

    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          type.channelId,
          type.channelName,
          channelDescription: type.channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          color: color,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      if (scheduledDate != null) {
        await _localNotifications.zonedSchedule(
          validId,
          title,
          body,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } else {
        await _localNotifications.show(validId, title, body, details,
            payload: payload);
      }
    } catch (e) {
      debugPrint('Error sending ${type.name} notification: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
  }

  int _generateNotificationId(String taskId, String reminderType) {
    return reminderType == "24h" ? taskId.hashCode : taskId.hashCode + 1000000;
  }

  // Add these methods to the NotificationService class

  Future<bool> togglePushNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (enabled) {
      // Request permission if turning on
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      await prefs.setBool(_pushEnabledKey, authorized);
      return authorized;
    } else {
      // Just save the preference if turning off
      await prefs.setBool(_pushEnabledKey, false);
      return false;
    }
  }

  Future<void> toggleNotificationType(String typeKey, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(typeKey, enabled);
  }

  Future<void> sendTestNotification() async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] as bool)) {
      throw Exception('Push notifications are disabled');
    }

    return showLocalNotification(
      notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Test Notification',
      body: 'This is a test notification from TimeBuddies',
      payload: 'test',
    );
  }
}
