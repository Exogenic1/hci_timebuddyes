import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static const String _pushEnabledKey = 'push_notifications_enabled';
  static const String _taskReminderKey = 'task_reminder_notifications';
  static const String _groupMessageKey = 'group_message_notifications';
  static const String _taskUpdatesKey = 'task_updates_notifications';
  static const String _systemUpdatesKey = 'system_updates_notifications';

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseService _databaseService = DatabaseService();

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

    // Request permission for notifications
    await _requestPermission();
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
  Future<Map<String, bool>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      _pushEnabledKey: prefs.getBool(_pushEnabledKey) ?? false,
      _taskReminderKey: prefs.getBool(_taskReminderKey) ?? true,
      _groupMessageKey: prefs.getBool(_groupMessageKey) ?? true,
      _taskUpdatesKey: prefs.getBool(_taskUpdatesKey) ?? true,
      _systemUpdatesKey: prefs.getBool(_systemUpdatesKey) ?? true,
    };
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

  // Subscribe to topic (e.g., specific group)
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
  }

  // Send a test notification via FCM
  Future<void> sendTestNotification() async {
    try {
      // For testing purposes, we send a message to the device's own FCM token
      final token = await _firebaseMessaging.getToken();

      if (token == null) {
        debugPrint('Cannot send test notification: FCM token is null');
        return;
      }

      debugPrint('Test notification would be sent to token: $token');
      // In a real implementation, you would call your backend API here
      // to trigger a notification to this specific device token

      // Example placeholder:
      // await http.post(
      //   Uri.parse('https://your-backend-api.com/send-notification'),
      //   body: {
      //     'token': token,
      //     'title': 'Test Notification',
      //     'body': 'This is a test notification from Time Buddies'
      //   },
      // );

      // Since we can't actually send an FCM notification directly from client,
      // this is just a placeholder to show the intended functionality
    } catch (e) {
      debugPrint('Error sending test notification: $e');
      rethrow; // Allow the UI to handle the error
    }
  }
}
