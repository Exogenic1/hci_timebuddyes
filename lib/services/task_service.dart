import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/services/notifications_service.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _databaseService;
  final NotificationService _notificationService;

  TaskService({
    required DatabaseService databaseService,
    required NotificationService notificationService,
  })  : _databaseService = databaseService,
        _notificationService = notificationService;

  /// Create a new task with automatic notification scheduling
  Future<String> createTask({
    required String title,
    required String description,
    required DateTime dueDate,
    required String assignedTo,
    required String groupId,
    required String createdBy,
    String? assignedToName,
    String? groupName,
  }) async {
    try {
      // Get group name if not provided
      String actualGroupName = groupName ?? 'your group';
      if (groupName == null) {
        try {
          final groupDoc =
              await _firestore.collection('groups').doc(groupId).get();
          if (groupDoc.exists && groupDoc.data() != null) {
            actualGroupName = groupDoc.data()!['name'] ?? 'your group';
          }
        } catch (e) {
          debugPrint('Error getting group name: $e');
        }
      }

      // Get assigned user's name if not provided
      String actualAssignedToName = assignedToName ?? 'Unknown User';
      if (assignedToName == null) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(assignedTo).get();
          if (userDoc.exists && userDoc.data() != null) {
            actualAssignedToName = userDoc.data()!['name'] ?? 'Unknown User';
          }
        } catch (e) {
          debugPrint('Error getting user name: $e');
        }
      }

      // Create task document
      final taskRef = _firestore.collection('tasks').doc();
      await taskRef.set({
        'title': title,
        'description': description,
        'dueDate': Timestamp.fromDate(dueDate),
        'assignedTo': assignedTo,
        'assignedToName': actualAssignedToName,
        'groupID': groupId,
        'completed': false,
        'locked': false,
        'isLate': false,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Schedule notifications in Firestore
      await _databaseService.scheduleTaskNotifications(
        taskRef.id,
        title,
        description,
        dueDate,
        assignedTo,
        groupId,
        actualGroupName,
      );

      // Schedule local notifications
      await _notificationService.scheduleTaskReminder(
        taskRef.id,
        title,
        description,
        dueDate,
        assignedTo,
      );

      // Send immediate notification about task assignment
      await _notificationService.sendTaskAssignmentNotification(
        taskRef.id,
        title,
        description,
        dueDate,
        assignedTo,
      );

      return taskRef.id;
    } catch (e) {
      debugPrint('Error creating task: $e');
      throw Exception('Failed to create task: $e');
    }
  }

  /// Update a task with automatic notification rescheduling
  Future<void> updateTask({
    required String taskId,
    String? title,
    String? description,
    DateTime? dueDate,
    String? assignedTo,
    String? assignedToName,
    String? groupId,
    bool? completed,
  }) async {
    try {
      // Get current task data
      final taskDoc = await _firestore.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) {
        throw Exception('Task not found');
      }

      final taskData = taskDoc.data()!;

      // Create update map with only changed fields
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (dueDate != null) updateData['dueDate'] = Timestamp.fromDate(dueDate);
      if (assignedTo != null) updateData['assignedTo'] = assignedTo;
      if (assignedToName != null) updateData['assignedToName'] = assignedToName;
      if (groupId != null) updateData['groupID'] = groupId;
      if (completed != null) {
        updateData['completed'] = completed;
        if (completed) {
          updateData['completedAt'] = FieldValue.serverTimestamp();
          updateData['locked'] = true; // Lock completed tasks
        } else {
          updateData['completedAt'] = null;
          updateData['locked'] = false;
        }
      }

      // Update task
      await taskDoc.reference.update(updateData);

      // If due date or assignee changed, update notifications
      final currentTitle = title ?? taskData['title'];
      final currentDescription = description ?? taskData['description'];
      final currentDueDate =
          dueDate ?? (taskData['dueDate'] as Timestamp).toDate();
      final currentAssignedTo = assignedTo ?? taskData['assignedTo'];
      final currentGroupId = groupId ?? taskData['groupID'];

      if (dueDate != null || assignedTo != null) {
        // Cancel existing task notifications
        await _firestore
            .collection('taskNotifications')
            .where('taskId', isEqualTo: taskId)
            .where('sent', isEqualTo: false)
            .get()
            .then((snapshot) {
          final batch = _firestore.batch();
          for (var doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          return batch.commit();
        });

        // Cancel local notifications
        await _notificationService.cancelTaskReminder(taskId);

        // Get group name
        String groupName = 'your group';
        try {
          final groupDoc =
              await _firestore.collection('groups').doc(currentGroupId).get();
          if (groupDoc.exists && groupDoc.data() != null) {
            groupName = groupDoc.data()!['name'] ?? 'your group';
          }
        } catch (e) {
          debugPrint('Error getting group name: $e');
        }

        // Reschedule notifications
        await _databaseService.scheduleTaskNotifications(
          taskId,
          currentTitle,
          currentDescription,
          currentDueDate,
          currentAssignedTo,
          currentGroupId,
          groupName,
        );

        await _notificationService.scheduleTaskReminder(
          taskId,
          currentTitle,
          currentDescription,
          currentDueDate,
          currentAssignedTo,
        );

        // If assignee changed, send immediate notification
        if (assignedTo != null && assignedTo != taskData['assignedTo']) {
          await _notificationService.sendTaskAssignmentNotification(
            taskId,
            currentTitle,
            currentDescription,
            currentDueDate,
            currentAssignedTo,
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating task: $e');
      throw Exception('Failed to update task: $e');
    }
  }

  /// Delete a task and clean up associated notifications
  Future<void> deleteTask(String taskId) async {
    try {
      // Delete task document
      await _firestore.collection('tasks').doc(taskId).delete();

      // Delete any pending notifications
      await _firestore
          .collection('taskNotifications')
          .where('taskId', isEqualTo: taskId)
          .get()
          .then((snapshot) {
        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        return batch.commit();
      });

      // Cancel local notifications
      await _notificationService.cancelTaskReminder(taskId);
    } catch (e) {
      debugPrint('Error deleting task: $e');
      throw Exception('Failed to delete task: $e');
    }
  }

  /// Mark a task as complete or incomplete
  Future<void> markTaskComplete(String taskId, bool isComplete) async {
    await updateTask(
      taskId: taskId,
      completed: isComplete,
    );
  }

  /// Get all tasks for a group
  Future<List<Map<String, dynamic>>> getGroupTasks(String groupId) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: groupId)
          .where('completed', isEqualTo: false)
          .get();

      return snapshot.docs
          .map((doc) => {
                ...doc.data(),
                'id': doc.id,
              })
          .toList();
    } catch (e) {
      debugPrint('Error fetching group tasks: $e');
      throw Exception('Failed to fetch group tasks: $e');
    }
  }

  /// Get tasks assigned to a specific user in a group
  Future<List<Map<String, dynamic>>> getUserTasksInGroup(
      String userId, String groupId) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: groupId)
          .where('assignedTo', isEqualTo: userId)
          .where('completed', isEqualTo: false)
          .get();

      return snapshot.docs
          .map((doc) => {
                ...doc.data(),
                'id': doc.id,
              })
          .toList();
    } catch (e) {
      debugPrint('Error fetching user tasks: $e');
      throw Exception('Failed to fetch user tasks: $e');
    }
  }
}
