import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';

class NotificationService {
  // Storage keys
  static const String _pushEnabledKey = 'push_notifications_enabled';
  static const String _taskReminderKey = 'task_reminder_notifications';
  static const String _groupMessageKey = 'group_message_notifications';
  static const String _taskUpdatesKey = 'task_updates_notifications';
  static const String _systemUpdatesKey = 'system_updates_notifications';
  static const String _reminderTimeKey = 'reminder_time_hours';

  // Core services
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseService _databaseService = DatabaseService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Stream for notification badge count updates
  final _notificationCountController = StreamController<int>.broadcast();
  Stream<int> get notificationCountStream =>
      _notificationCountController.stream;

  // Initialize notification settings with defaults if not set
  Future<void> initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_pushEnabledKey)) {
      await prefs.setBool(_pushEnabledKey, true);
    }
    if (!prefs.containsKey(_taskReminderKey)) {
      await prefs.setBool(_taskReminderKey, true);
    }
    if (!prefs.containsKey(_groupMessageKey)) {
      await prefs.setBool(_groupMessageKey, true);
    }
    if (!prefs.containsKey(_taskUpdatesKey)) {
      await prefs.setBool(_taskUpdatesKey, true);
    }
    if (!prefs.containsKey(_systemUpdatesKey)) {
      await prefs.setBool(_systemUpdatesKey, true);
    }
    if (!prefs.containsKey(_reminderTimeKey)) {
      await prefs.setInt(
          _reminderTimeKey, 24); // Default 24 hours before deadline
    }

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Initialize timezone for scheduled notifications
    tz.initializeTimeZones();
  }

  // Initialize notification service with user ID
  Future<void> initialize(String userId) async {
    // Initialize base settings first
    await initializeSettings();

    // Request permission for notifications
    await _requestPermission();

    // Set up FCM token handling
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _databaseService.updateFcmToken(userId, token);
    }

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _databaseService.updateFcmToken(userId, newToken);
    });

    // Listen for FCM messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
      _updateNotificationCount(userId);
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data['route']);
    });

    // Update notification badge count initially
    _updateNotificationCount(userId);

    // Process user's upcoming task reminders
    await processUpcomingReminders(userId);

    // Set up periodic background task checks
    Timer.periodic(const Duration(minutes: 15), (_) {
      _checkDueTaskNotifications();
      _checkOverdueTasks();
    });
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        _handleNotificationTap(response.payload);
      },
    );
  }

  Future<void> _requestPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Update push enabled based on authorization status
    final prefs = await SharedPreferences.getInstance();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await prefs.setBool(_pushEnabledKey, true);
    } else {
      await prefs.setBool(_pushEnabledKey, false);
    }
  }

  // Toggle push notifications
  Future<bool> togglePushNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value) {
      // If turning on, request permission
      NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
    }

    await prefs.setBool(_pushEnabledKey, value);
    return value;
  }

  // Toggle specific notification types
  Future<void> toggleNotificationType(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // Get notification settings
  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      _pushEnabledKey: prefs.getBool(_pushEnabledKey) ?? false,
      _taskReminderKey: prefs.getBool(_taskReminderKey) ?? true,
      _groupMessageKey: prefs.getBool(_groupMessageKey) ?? true,
      _taskUpdatesKey: prefs.getBool(_taskUpdatesKey) ?? true,
      _systemUpdatesKey: prefs.getBool(_systemUpdatesKey) ?? true,
      _reminderTimeKey: prefs.getInt(_reminderTimeKey) ?? 24,
    };
  }

  // Set reminder time preference (hours before deadline)
  Future<void> setReminderTime(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderTimeKey, hours);
  }

  // Update FCM token for a user
  Future<void> updateFcmToken(String userId) async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _databaseService.updateFcmToken(userId, token);
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  // Schedule deadline notifications for a specific task
  Future<void> scheduleTaskReminder(String taskId, String title,
      String description, DateTime dueDate, String assignedUserId) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] && settings[_taskReminderKey])) {
      return; // Notifications disabled
    }

    final reminderHours = settings[_reminderTimeKey] ?? 24;
    final reminderTime = dueDate.subtract(Duration(hours: reminderHours));

    // Skip if reminder time is in the past
    if (reminderTime.isBefore(DateTime.now())) {
      return;
    }

    // For local notifications
    await _scheduleLocalReminder(
        taskId, title, description, reminderTime, dueDate);

    // Store the scheduled reminder in Firestore
    await FirebaseFirestore.instance.collection('reminders').add({
      'taskId': taskId,
      'userId': assignedUserId,
      'title': title,
      'description': description,
      'dueDate': Timestamp.fromDate(dueDate),
      'reminderTime': Timestamp.fromDate(reminderTime),
      'sent': false,
    });
  }

  Future<void> _scheduleLocalReminder(String taskId, String title,
      String description, DateTime reminderTime, DateTime dueDate) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'deadline_reminders',
      'Deadline Reminders',
      channelDescription: 'Notifications for task deadlines',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final formattedDueDate = DateFormat('MMM d, y - h:mm a').format(dueDate);

    // Convert reminderTime to TZDateTime
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    await _localNotifications.zonedSchedule(
      taskId.hashCode,
      'Upcoming Task: $title',
      'Due: $formattedDueDate\n$description',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: taskId,
    );
  }

  // Update task reminders when a task is modified
  Future<void> updateTaskReminder(String taskId, String title,
      String description, DateTime dueDate, String assignedUserId) async {
    // Cancel any existing reminders for this task
    await cancelTaskReminder(taskId);

    // Schedule new reminder
    await scheduleTaskReminder(
        taskId, title, description, dueDate, assignedUserId);
  }

  // Cancel a specific task reminder
  Future<void> cancelTaskReminder(String taskId) async {
    // Cancel local notification
    await _localNotifications.cancel(taskId.hashCode);

    // Update Firestore records
    final reminderQuery = await FirebaseFirestore.instance
        .collection('reminders')
        .where('taskId', isEqualTo: taskId)
        .get();

    for (var doc in reminderQuery.docs) {
      await doc.reference.delete();
    }
  }

  // Process all upcoming reminders for a user
  Future<void> processUpcomingReminders(String userId) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] && settings[_taskReminderKey])) {
      return; // Notifications disabled
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

        // Only schedule for future tasks
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

  // Handle notification tap
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;

    // Parse payload and navigate accordingly
    debugPrint('Notification tapped with payload: $payload');
    // Navigate based on payload - will be implemented by the navigator in main.dart
  }

  // Show notification from FCM message
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Default Notifications',
      channelDescription: 'Default notification channel',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      details,
      payload: message.data['route'],
    );
  }

  // Update notification badge count
  Future<void> _updateNotificationCount(String userId) async {
    final count = await _databaseService.getUnreadNotificationCount(userId);
    _notificationCountController.add(count);
  }

  // Check for due task notifications
  Future<void> _checkDueTaskNotifications() async {
    await _databaseService.processDueTaskNotifications();
  }

  // Check for overdue tasks
  Future<void> _checkOverdueTasks() async {
    await _databaseService.checkAndProcessOverdueTasks();
  }

  // Subscribe to topic (e.g., specific group)
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(
      String notificationId, String userId) async {
    await _databaseService.markNotificationAsRead(notificationId);
    _updateNotificationCount(userId);
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String userId) async {
    final notifications =
        await _databaseService.getPendingNotifications(userId);

    for (var notification in notifications) {
      await _databaseService.markNotificationAsRead(notification['id']);
    }

    _updateNotificationCount(userId);
  }

  // Send a test notification via FCM
  Future<void> sendTestNotification() async {
    try {
      // Show a local notification instead
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: 'For testing notifications',
        importance: Importance.high,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        0,
        'Test Notification',
        'This is a test notification from Time Buddies',
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error sending test notification: $e');
      rethrow; // Allow the UI to handle the error
    }
  }

  // Clean up resources
  void dispose() {
    _notificationCountController.close();
  }
}
