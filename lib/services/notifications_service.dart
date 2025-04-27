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
    final defaultSettings = {
      _pushEnabledKey: true,
      _taskReminderKey: true,
      _groupMessageKey: true,
      _taskUpdatesKey: true,
      _systemUpdatesKey: true,
    };

    for (var entry in defaultSettings.entries) {
      if (!prefs.containsKey(entry.key)) {
        await prefs.setBool(entry.key, entry.value);
      }
    }

    if (!prefs.containsKey(_reminderTimeKey)) {
      await prefs.setInt(_reminderTimeKey, 24); // Default 24h before deadline
    }

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Initialize timezone for scheduled notifications
    tz.initializeTimeZones();
  }

  // Initialize notification service with user ID
  // Renamed from initialize to initializeForUser to avoid conflicts
  Future<void> initializeForUser(String userId) async {
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
    // Initialize Android notification channels for all types
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'deadline_reminders',
        'Deadline Reminders',
        description: 'Notifications for task deadlines',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'group_messages',
        'Group Messages',
        description: 'Notifications for group messages',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'task_updates',
        'Task Updates',
        description: 'Notifications for task updates',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'system_updates',
        'System Updates',
        description: 'Notifications for system updates',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'overdue_tasks',
        'Overdue Tasks',
        description: 'Notifications for overdue tasks',
        importance: Importance.high,
      ),
    ];

    // Create all channels
    for (final channel in channels) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
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

    final reminderTypes = {
      '24h': dueDate.subtract(const Duration(hours: 24)),
      '1h': dueDate.subtract(const Duration(hours: 1)),
    };

    final now = DateTime.now();

    for (var entry in reminderTypes.entries) {
      final reminderTime = entry.value;
      final reminderType = entry.key;

      if (reminderTime.isAfter(now)) {
        // Schedule local notification
        await _scheduleLocalReminder(
            taskId, title, description, reminderTime, dueDate, reminderType);

        // Store in Firestore
        await FirebaseFirestore.instance.collection('reminders').add({
          'taskId': taskId,
          'userId': assignedUserId,
          'title': title,
          'description': description,
          'dueDate': Timestamp.fromDate(dueDate),
          'reminderTime': Timestamp.fromDate(reminderTime),
          'reminderType': reminderType,
          'sent': false,
        });
      }
    }
  }

// Modified _scheduleLocalReminder to handle different notification types
  Future<void> _scheduleLocalReminder(
      String taskId,
      String title,
      String description,
      DateTime reminderTime,
      DateTime dueDate,
      String reminderType) async {
    final formattedDueDate = DateFormat('MMM d, y - h:mm a').format(dueDate);

    String notificationTitle;
    String notificationBody;

    if (reminderType == "24h") {
      notificationTitle = 'Task Due in 24 Hours: $title';
      notificationBody = 'Due: $formattedDueDate\n$description';
    } else {
      notificationTitle = 'Task Due in 1 Hour: $title';
      notificationBody = 'Final reminder! Due: $formattedDueDate\n$description';
    }

    final notificationId =
        reminderType == "24h" ? taskId.hashCode : taskId.hashCode + 100000;

    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    await sendTypedNotification(
      notificationId: notificationId,
      title: notificationTitle,
      body: notificationBody,
      type: NotificationType.taskReminder,
      payload: "$taskId:$reminderType",
      scheduledDate: scheduledDate,
    );
  }

  // Add sendTaskAssignmentNotification method
  Future<void> sendTaskAssignmentNotification(String taskId, String title,
      String description, DateTime dueDate, String assignedUserId) async {
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] && settings[_taskUpdatesKey])) {
      return; // Notifications disabled
    }

    try {
      // Send immediate notification about new task assignment
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'task_assignments',
        'Task Assignments',
        channelDescription: 'Notifications for new task assignments',
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
      final notificationTitle = 'New Task Assigned: $title';
      final notificationBody = 'Due: $formattedDueDate\n$description';

      await _localNotifications.show(
        taskId.hashCode + 200000, // Unique ID for assignment notifications
        notificationTitle,
        notificationBody,
        notificationDetails,
        payload: taskId,
      );

      // Store the notification in Firestore for tracking
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': assignedUserId,
        'taskId': taskId,
        'title': notificationTitle,
        'body': notificationBody,
        'type': 'assignment',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      // Also schedule the deadline reminders
      await scheduleTaskReminder(
          taskId, title, description, dueDate, assignedUserId);
    } catch (e) {
      debugPrint('Error sending task assignment notification: $e');
    }
  }

// Add methods for handling overdue tasks
  Future<void> _sendOverdueTaskNotification(String taskId, String title,
      String description, DateTime dueDate, String userId) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'overdue_tasks',
        'Overdue Tasks',
        channelDescription: 'Notifications for overdue tasks',
        importance: Importance.high,
        priority: Priority.high,
        color: Colors.red,
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
      final notificationTitle = 'OVERDUE TASK: $title';
      final notificationBody =
          'This task was due on $formattedDueDate and is now overdue.\n$description';

      // Generate a unique ID for overdue notifications
      final notificationId = taskId.hashCode + 300000;

      // Send the local notification
      await _localNotifications.show(
        notificationId,
        notificationTitle,
        notificationBody,
        notificationDetails,
        payload: taskId,
      );

      // Store the notification in Firestore
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'taskId': taskId,
        'title': notificationTitle,
        'body': notificationBody,
        'type': 'overdue',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('Error sending overdue notification: $e');
    }
  }

// Add methods for checking and sending pending reminders
  Future<void> checkAndSendPendingReminders() async {
    try {
      final now = DateTime.now();

      // Get reminders that should be sent
      final pendingRemindersQuery = await FirebaseFirestore.instance
          .collection('reminders')
          .where('reminderTime', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .where('sent', isEqualTo: false)
          .get();

      for (var doc in pendingRemindersQuery.docs) {
        final reminder = doc.data();
        final taskId = reminder['taskId'] as String;
        final userId = reminder['userId'] as String;
        final title = reminder['title'] as String;
        final description = reminder['description'] as String? ?? '';
        final dueDate = (reminder['dueDate'] as Timestamp).toDate();
        final reminderType = reminder['reminderType'] as String;

        // Send local notification
        await _sendReminderNotification(
            taskId, title, description, dueDate, reminderType);

        // Update reminder as sent
        await doc.reference.update({'sent': true});

        // Update task record
        if (reminderType == '24h') {
          await FirebaseFirestore.instance
              .collection('tasks')
              .doc(taskId)
              .update({'reminderSent24h': true});
        } else if (reminderType == '1h') {
          await FirebaseFirestore.instance
              .collection('tasks')
              .doc(taskId)
              .update({'reminderSent1h': true});
        }

        // Also store in notifications collection
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': userId,
          'taskId': taskId,
          'title': reminderType == '24h'
              ? 'Task Due in 24 Hours: $title'
              : 'Task Due in 1 Hour: $title',
          'body':
              'Due: ${DateFormat('MMM d, y - h:mm a').format(dueDate)}\n$description',
          'type': 'reminder_$reminderType',
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      debugPrint('Error checking and sending pending reminders: $e');
    }
  }

  Future<void> _sendReminderNotification(String taskId, String title,
      String description, DateTime dueDate, String reminderType) async {
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

    // Different notification messages based on reminder type
    String notificationTitle;
    String notificationBody;

    if (reminderType == "24h") {
      notificationTitle = 'Task Due in 24 Hours: $title';
      notificationBody = 'Due: $formattedDueDate\n$description';
    } else {
      notificationTitle = 'Task Due in 1 Hour: $title';
      notificationBody = 'Final reminder! Due: $formattedDueDate\n$description';
    }

    // Create a unique notification ID based on taskId and reminder type
    final notificationId = reminderType == "24h"
        ? taskId.hashCode
        : taskId.hashCode + 100000; // Offset for 1h notifications

    await _localNotifications.show(
      notificationId,
      notificationTitle,
      notificationBody,
      notificationDetails,
      payload: taskId,
    );
  }

  // Update task reminders when a task is modified
  Future<void> updateTaskReminder(String taskId, String title,
      String description, DateTime dueDate, String assignedUserId) async {
    // Cancel any existing reminders for this task
    await cancelTaskReminder(taskId);

    // Schedule new reminders (both 24h and 1h)
    await scheduleTaskReminder(
        taskId, title, description, dueDate, assignedUserId);
  }

// Cancel a specific task reminder - updated to cancel both notifications
  Future<void> cancelTaskReminder(String taskId) async {
    // Cancel both 24h and 1h local notifications
    await _localNotifications.cancel(taskId.hashCode); // 24h notification
    await _localNotifications
        .cancel(taskId.hashCode + 100000); // 1h notification

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
    // Determine notification type from message data
    final type = _getNotificationTypeFromMessage(message);

    await sendTypedNotification(
      notificationId: DateTime.now().millisecond,
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      type: type,
      payload: message.data['route'],
    );
  }

  NotificationType _getNotificationTypeFromMessage(RemoteMessage message) {
    final type = message.data['type'] ?? '';
    switch (type) {
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
    final settings = await getNotificationSettings();
    if (!(settings[_pushEnabledKey] && settings[type.storageKey])) {
      return;
    }

    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        type.channelId,
        type.channelName,
        channelDescription: type.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        color: color,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      if (scheduledDate != null) {
        await _localNotifications.zonedSchedule(
          notificationId,
          title,
          body,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      } else {
        await _localNotifications.show(
          notificationId,
          title,
          body,
          notificationDetails,
          payload: payload,
        );
      }
    } catch (e) {
      debugPrint('Error sending ${type.name} notification: $e');
    }
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

  Future<void> testDeadlineNotification() async {
    final notificationService = NotificationService();

    // Create a test task ID
    final testTaskId = 'test-task-${DateTime.now().millisecondsSinceEpoch}';

    // Test 24h notification (1 minute from now)
    final dueDate24h = DateTime.now().add(const Duration(seconds: 30));

    // Test 1h notification (30 seconds from now)
    final dueDate1h = DateTime.now().add(const Duration(seconds: 10));

    // Schedule test task reminders
    await notificationService.scheduleTaskReminder(
      testTaskId,
      'Test 24h Notification',
      'This is a test of the 24-hour notification',
      dueDate24h,
      'jDALtaiwMrUN5lbHVUUqZG3io9K2',
    );

    await notificationService.scheduleTaskReminder(
      "$testTaskId-1h",
      'Test 1h Notification',
      'This is a test of the 1-hour notification',
      dueDate1h,
      'jDALtaiwMrUN5lbHVUUqZG3io9K2',
    );
  }
}
