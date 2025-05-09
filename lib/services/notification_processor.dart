import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:time_buddies/services/notifications_service.dart';

class NotificationProcessor {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService;
  Timer? _processingTimer;
  NotificationProcessor(this._notificationService);

  // Start periodic notification processing
  void startPeriodicProcessing() {
    // Process every 15 minutes
    _processingTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      processPendingNotifications();
      checkOverdueTasks();
    });

    // Also process immediately when started
    processPendingNotifications();
    checkOverdueTasks();
  }

  // Stop periodic processing
  void stopPeriodicProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  // Process pending notifications
  Future<void> processPendingNotifications() async {
    try {
      final now = DateTime.now();
      // Get notifications scheduled for before now that haven't been sent
      final notificationsSnapshot = await _firestore
          .collection('taskNotifications')
          .where('notificationTime',
              isLessThanOrEqualTo: Timestamp.fromDate(now))
          .where('sent', isEqualTo: false)
          .limit(100) // Process in batches
          .get();

      if (notificationsSnapshot.docs.isEmpty) return;

      debugPrint(
          'Processing ${notificationsSnapshot.size} due task notifications');
      final batch = _firestore.batch();

      for (var doc in notificationsSnapshot.docs) {
        final data = doc.data();
        final assignedTo = data['assignedTo'] ??
            data['assigneeId']; // Handle possible field name differences
        final taskId = data['taskId'];
        final taskTitle = data['title'];
        final message = data['message'];
        final groupId = data['groupId'] ?? '';

        // Create in-app notification
        final notificationRef = _firestore.collection('notifications').doc();
        batch.set(notificationRef, {
          'recipientId': assignedTo,
          'type':
              data['reminderType'] == '24h' ? 'task_reminder' : 'task_due_soon',
          'title': taskTitle,
          'message': message,
          'taskId': taskId,
          'groupId': groupId,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });

        // Mark notification as sent
        batch.update(doc.reference,
            {'sent': true, 'sentAt': FieldValue.serverTimestamp()});

        // Send push notification - use notificationId parameter name instead of id
        await _notificationService.showLocalNotification(
          notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: taskTitle,
          body: message,
          payload: 'task:$taskId',
        );

        // If we have FCM token, also send a push notification
        final userDoc =
            await _firestore.collection('users').doc(assignedTo).get();
        final fcmToken = userDoc.data()?['fcmToken'];

        if (fcmToken != null) {
          await _firestore.collection('pushNotifications').add({
            'token': fcmToken,
            'title': taskTitle,
            'body': message,
            'data': {
              'type': data['reminderType'] == '24h'
                  ? 'task_reminder'
                  : 'task_due_soon',
              'taskId': taskId,
              'groupId': groupId,
            },
            'userId': assignedTo,
            'createdAt': FieldValue.serverTimestamp(),
            'sent': false,
          });
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error processing pending notifications: $e');
    }
  }

  // Check for overdue tasks
  Future<void> checkOverdueTasks() async {
    try {
      final now = DateTime.now();
      final overdueTasks = await _firestore
          .collection('tasks')
          .where('completed', isEqualTo: false)
          .where('dueDate', isLessThan: Timestamp.fromDate(now))
          .where('isLate',
              isEqualTo: false) // Only get tasks not yet marked as late
          .limit(100) // Process in batches
          .get();

      if (overdueTasks.docs.isEmpty) return;

      debugPrint('Processing ${overdueTasks.size} overdue tasks');
      final batch = _firestore.batch();

      for (var doc in overdueTasks.docs) {
        final data = doc.data();
        final assignedTo = data['assignedTo'] ??
            data['assigneeId']; // Handle possible field name differences
        final taskId = doc.id;
        final taskTitle = data['title'] ?? 'Task';
        final groupId = data['groupID'] ?? '';

        // Get group name
        String groupName = 'your group';
        try {
          final groupDoc =
              await _firestore.collection('groups').doc(groupId).get();
          if (groupDoc.exists && groupDoc.data() != null) {
            groupName = groupDoc.data()!['name'] ?? 'your group';
          }
        } catch (e) {
          debugPrint('Error getting group name: $e');
        }

        // Mark task as late
        batch.update(doc.reference, {
          'isLate': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Create overdue notification
        final notificationRef = _firestore.collection('notifications').doc();
        final message = 'Your task "$taskTitle" in $groupName is now overdue';

        batch.set(notificationRef, {
          'recipientId': assignedTo,
          'type': 'task_overdue',
          'title': 'Task Overdue',
          'message': message,
          'taskId': taskId,
          'groupId': groupId,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });

        // Send local notification - use notificationId parameter name instead of id
        await _notificationService.showLocalNotification(
          notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Task Overdue',
          body: message,
          payload: 'task:$taskId',
        );

        // If we have FCM token, also send a push notification
        final userDoc =
            await _firestore.collection('users').doc(assignedTo).get();
        final fcmToken = userDoc.data()?['fcmToken'];

        if (fcmToken != null) {
          await _firestore.collection('pushNotifications').add({
            'token': fcmToken,
            'title': 'Task Overdue',
            'body': message,
            'data': {
              'type': 'task_overdue',
              'taskId': taskId,
              'groupId': groupId,
            },
            'userId': assignedTo,
            'createdAt': FieldValue.serverTimestamp(),
            'sent': false,
          });
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error checking overdue tasks: $e');
    }
  }
}
