import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:time_buddies/services/database_service.dart';

class NotificationsService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseService _databaseService = DatabaseService();

  // Callback variable (you can name this onMessageCallback if you prefer)
  late void Function(RemoteMessage message) onMessageCallback;

  Future<void> initialize({
    required void Function(RemoteMessage message) onMessageCallback,
  }) async {
    this.onMessageCallback = onMessageCallback;

    // Request permissions
    await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Get initial message
    RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      this.onMessageCallback(initialMessage);
    }

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      this.onMessageCallback(message);
    });

    // Background/opened app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      this.onMessageCallback(message);
    });

    // Token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _databaseService.updateFcmToken(user.uid, newToken);
      }
    });

    // Get initial token
    String? token = await _firebaseMessaging.getToken();
    if (token != null && FirebaseAuth.instance.currentUser != null) {
      _databaseService.updateFcmToken(
          FirebaseAuth.instance.currentUser!.uid, token);
    }
  }

  // Helper method to show notification when you have context
  static void showNotification({
    required RemoteMessage message,
    required BuildContext context,
    required void Function(String? chatId) onViewPressed,
  }) {
    if (message.notification != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.notification?.body ?? 'New message'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => onViewPressed(message.data['chatId']),
          ),
        ),
      );
    }
  }
}
