import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/notifications_service.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DataValidationService _validationService = DataValidationService();

  // Add a new user
  // Add to database_service.dart
  Future<void> addUser({
    required String userID,
    required String name,
    required String email,
    String profilePicture = '',
    String? fcmToken,
  }) async {
    try {
      // Check if the user already exists
      final userDoc = await _firestore.collection('users').doc(userID).get();

      if (userDoc.exists) {
        // Update existing user
        final userData = userDoc.data() as Map<String, dynamic>;
        await _firestore.collection('users').doc(userID).update({
          'name': name,
          'email': email,
          'fcmToken': fcmToken ?? userData['fcmToken'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new user
        await _firestore.collection('users').doc(userID).set({
          'name': name,
          'email': email,
          'profilePicture': profilePicture,
          'fcmToken': fcmToken,
          'groups': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error adding/updating user: $e');
      rethrow;
    }
  }

  // Update FCM token
  Future<void> updateFcmToken(String userId, String? fcmToken) async {
    try {
      final userDoc = _firestore.collection('users').doc(userId);
      final docSnapshot = await userDoc.get();

      if (docSnapshot.exists) {
        await userDoc.update({
          'fcmToken': fcmToken,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create the document if it doesn't exist
        await userDoc.set({
          'fcmToken': fcmToken,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
      rethrow;
    }
  }

  // Check if user is a group leader
  Future<bool> isUserGroupLeader(String userId, String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return false;

      final data = groupDoc.data() as Map<String, dynamic>;
      return data['leaderId'] == userId;
    } catch (e) {
      debugPrint('Error checking leader status: $e');
      return false;
    }
  }

  // Get group members with details
  Future<List<Map<String, dynamic>>> getGroupMembersWithDetails(
      String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return [];

      final data = groupDoc.data() as Map<String, dynamic>;
      final membersList =
          List<Map<String, dynamic>>.from(data['members'] ?? []);

      return membersList;
    } catch (e) {
      debugPrint('Error fetching group members: $e');
      return [];
    }
  }

  // Get user's completed tasks
  Future<List<Map<String, dynamic>>> getUserCompletedTasks(
      String userId, String groupId) async {
    try {
      final tasksSnapshot = await _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: groupId)
          .where('assigneeId', isEqualTo: userId)
          .where('completed', isEqualTo: true)
          .get();

      return tasksSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();
    } catch (e) {
      debugPrint('Error fetching completed tasks: $e');
      return [];
    }
  }

  // Get group members
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    try {
      await _validationService.validateGroupData(groupId);

      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return [];

      final groupData = groupDoc.data();
      final members = groupData?['members'] ?? [];

      List<Map<String, dynamic>> membersList = [];

      if (members is List) {
        // First get all member IDs
        List<String> memberIds = [];
        for (var member in members) {
          if (member is String) {
            memberIds.add(member);
          } else if (member is Map) {
            final userId = member['userId'] ?? member['id'] ?? member['uid'];
            if (userId != null) memberIds.add(userId.toString());
          }
        }

        // Fetch all user documents in a single query
        if (memberIds.isNotEmpty) {
          final usersSnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: memberIds)
              .get();

          for (var doc in usersSnapshot.docs) {
            membersList.add({
              'userId': doc.id,
              'name': doc['name'] ?? 'Unknown User',
              'email': doc['email'] ?? '',
            });
          }
        }
      }

      return membersList;
    } catch (e) {
      debugPrint('Error getting group members: $e');
      return [];
    }
  }

  // Update user groups
  Future<void> updateUserGroups({
    required String userID,
    required List<String> groups,
  }) async {
    await _validationService.validateUserData(userID);

    final docRef = _firestore.collection('users').doc(userID);
    final doc = await docRef.get();

    if (!doc.exists) {
      await addUser(
          userID: userID, name: '', email: ''); // Create basic user first
    }

    await docRef.update({
      'groups': groups,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Create a new group
  Future<String> createGroup({
    required String name,
    required String description,
    required String createdBy,
  }) async {
    await _validationService.validateUserData(createdBy);

    DocumentReference groupRef = await _firestore.collection('groups').add({
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'leaderId': createdBy, // Set creator as leader
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'members': [createdBy], // Add the creator as the first member
      'tasks': [], // Initialize with an empty list of tasks
    });

    // Update the user's groups list
    final userDoc = await _firestore.collection('users').doc(createdBy).get();
    if (userDoc.exists) {
      List<String> currentGroups = List<String>.from(userDoc['groups'] ?? []);
      currentGroups.add(groupRef.id);
      await _firestore.collection('users').doc(createdBy).update({
        'groups': currentGroups,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return groupRef.id; // Return the group ID
  }

  // Update a task
  Future<void> updateTask({
    required String taskId,
    required String title,
    required String description,
    required String status,
    required DateTime dueDate,
    required String assignedTo,
  }) async {
    await _firestore.collection('tasks').doc(taskId).update({
      'title': title,
      'description': description,
      'status': status,
      'dueDate': dueDate,
      'assignedTo': assignedTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> manageTask({
    required String title,
    required String description,
    required String assignedTo,
    required DateTime dueDate,
    required String groupId, // Changed from groupID to groupId for consistency
    String? taskId,
    String? createdBy,
  }) async {
    final isUpdate = taskId != null;
    final batch = _firestore.batch();

    // Prepare task data
    final Map<String, dynamic> taskData = {
      'title': title,
      'groupId': groupId, // Consistent field name
      'description': description,
      'assignedTo': assignedTo,
      'dueDate': Timestamp.fromDate(dueDate),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!isUpdate) {
      taskData['status'] = 'Pending';
      taskData['completed'] = false;
      taskData['locked'] = false;
      taskData['createdAt'] = FieldValue.serverTimestamp();
      taskData['notificationScheduled'] = false;

      if (createdBy != null) {
        taskData['createdBy'] = createdBy;
      }
    }

    // Get or create task reference
    final DocumentReference taskRef = isUpdate
        ? _firestore.collection('tasks').doc(taskId)
        : _firestore.collection('tasks').doc();

    // Add or update task
    if (isUpdate) {
      taskData.removeWhere((_, value) => value == null);
      batch.update(taskRef, taskData);
    } else {
      batch.set(taskRef, taskData);
      batch.update(
        _firestore.collection('groups').doc(groupId),
        {
          'tasks': FieldValue.arrayUnion([taskRef.id]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();

    try {
      // Get group name for notification
      String groupName = "your group";
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (groupDoc.exists && groupDoc.data() != null) {
        groupName = groupDoc.data()!['name'] ?? 'your group';
      }

      // Send task assignment notification if new task
      if (!isUpdate) {
        await _firestore.collection('notifications').add({
          'recipientId': assignedTo,
          'type': 'task_assigned',
          'title': 'New Task Assigned',
          'message': 'You have been assigned a new task "$title" in $groupName',
          'taskId': taskRef.id,
          'groupId': groupId,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });

        await NotificationService().sendTaskAssignmentNotification(
          taskRef.id,
          title,
          description,
          dueDate,
          assignedTo,
        );
      }

      // Schedule reminder notifications
      if (dueDate.isAfter(DateTime.now())) {
        if (isUpdate) {
          await NotificationService().updateTaskReminder(
              taskRef.id, title, description, dueDate, assignedTo);
        } else {
          await NotificationService().scheduleTaskReminder(
              taskRef.id, title, description, dueDate, assignedTo);
        }
      }

      return taskRef.id;
    } catch (e) {
      debugPrint('Error in manageTask post-commit operations: $e');
      return taskRef.id;
    }
  }

// This replaces both addTask and addTaskWithNotification with a single method

  // Mark task as completed
  Future<void> markTaskAsCompleted(String taskId, bool isCompleted) async {
    await _firestore.collection('tasks').doc(taskId).update({
      'completed': isCompleted,
      'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> scheduleTaskNotifications(
      String taskId,
      String title,
      String description,
      DateTime dueDate,
      String assignedTo,
      String groupId,
      String groupName) async {
    final batch = _firestore.batch();

    // 24 hour reminder
    final reminder24h = dueDate.subtract(const Duration(hours: 24));
    if (reminder24h.isAfter(DateTime.now())) {
      final notificationRef = _firestore.collection('taskNotifications').doc();
      batch.set(notificationRef, {
        'taskId': taskId,
        'title': title,
        'message': 'Your task "$title" in $groupName is due in 24 hours',
        'assignedTo': assignedTo,
        'groupId': groupId,
        'groupName': groupName,
        'notificationTime': Timestamp.fromDate(reminder24h),
        'reminderType': '24h',
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 1 hour reminder
    final reminder1h = dueDate.subtract(const Duration(hours: 1));
    if (reminder1h.isAfter(DateTime.now())) {
      final notificationRef = _firestore.collection('taskNotifications').doc();
      batch.set(notificationRef, {
        'taskId': taskId,
        'title': title,
        'message': 'Your task "$title" in $groupName is due in 1 hour',
        'assignedTo': assignedTo,
        'groupId': groupId,
        'groupName': groupName,
        'notificationTime': Timestamp.fromDate(reminder1h),
        'reminderType': '1h',
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // Send a message to a group
  Future<void> sendMessage({
    required String senderID,
    required String groupID,
    required String content,
    required String type,
  }) async {
    await _firestore.collection('messages').add({
      'senderID': senderID,
      'groupID': groupID,
      'content': content,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'read': [],
    });
  }

  // Add a task rating
  Future<void> addTaskRating({
    required String taskId,
    required String groupId,
    required String ratedUserId,
    required int rating,
    required String comments,
    required String raterUserId,
  }) async {
    await _firestore.collection('taskRatings').add({
      'taskId': taskId,
      'groupId': groupId,
      'ratedUserId': ratedUserId, // Who is being rated
      'rating': rating, // 1-5 scale
      'comments': comments,
      'raterUserId': raterUserId, // Who is giving the rating
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Load user groups
  Future<void> loadUserGroups(String userId) async {
    try {
      await _validationService.validateUserData(userId);

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final groups = List<String>.from(userDoc['groups'] ?? []);

        // Validate each group
        for (String groupId in groups) {
          await _validationService.validateGroupData(groupId);
        }
      }
    } catch (e) {
      debugPrint('Error loading user groups: $e');
    }
  }

  // Get user group IDs
  Future<List<String>> getUserGroupIds(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return List<String>.from(userDoc['groups'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('Error getting user group IDs: $e');
      return [];
    }
  }

  // Verify group membership
  Future<void> verifyGroupMembership(String userId, String groupId) async {
    try {
      // Check if user is in group's members list
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (groupDoc.exists) {
        final members = groupDoc['members'] ?? [];
        bool isMember = members.any((member) {
          if (member is String) return member == userId;
          if (member is Map) return member['userId'] == userId;
          return false;
        });

        if (!isMember) {
          // Add user to group if not already a member
          await addGroupMember(
            groupId: groupId,
            userId: userId,
            role: 'member',
          );
        }
      }
    } catch (e) {
      debugPrint('Error verifying group membership: $e');
    }
  }

  // Add group member
  Future<void> addGroupMember({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([
        {
          'userId': userId,
          'role': role,
          'joinedAt': FieldValue.serverTimestamp(),
        }
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also update user's groups list
    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (userDoc.exists) {
      List<String> currentGroups = List<String>.from(userDoc['groups'] ?? []);
      if (!currentGroups.contains(groupId)) {
        currentGroups.add(groupId);
        await _firestore.collection('users').doc(userId).update({
          'groups': currentGroups,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // Remove group member
  Future<void> removeGroupMember(String groupId, String userId) async {
    try {
      // Get current members list
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final data = groupDoc.data() as Map<String, dynamic>;
      final members = data['members'] ?? [];

      // Create new members list without the user
      List newMembersList = [];
      if (members is List) {
        for (var member in members) {
          if (member is String) {
            if (member != userId) newMembersList.add(member);
          } else if (member is Map) {
            if (member['userId'] != userId) newMembersList.add(member);
          }
        }
      }

      // Update group
      await _firestore.collection('groups').doc(groupId).update({
        'members': newMembersList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update user's groups list
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        List<String> currentGroups = List<String>.from(userDoc['groups'] ?? []);
        currentGroups.remove(groupId);
        await _firestore.collection('users').doc(userId).update({
          'groups': currentGroups,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error removing group member: $e');
    }
  }

  // Get user's groups as stream
  Stream<QuerySnapshot> getUserGroupsStream(String userID) {
    return _firestore
        .collection('groups')
        .where('members', arrayContains: userID)
        .snapshots();
  }

  // Get tasks for a group as stream
  // In database_service.dart, modify your task fetching method
  Future<List<Map<String, dynamic>>> getGroupTasks(String groupId) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: groupId)
          .get();

      final tasks = snapshot.docs.map((doc) {
        final data = doc.data();
        final dueDate = (data['dueDate'] as Timestamp).toDate();
        final now = DateTime.now();
        final isLate = !(data['completed'] ?? false) && now.isAfter(dueDate);

        // Update if late (batched for efficiency)
        if (isLate && !(data['isLate'] ?? false)) {
          _firestore.collection('tasks').doc(doc.id).update({'isLate': true});
        }

        return {...data, 'id': doc.id, 'isLate': isLate};
      }).toList();

      return tasks;
    } catch (e) {
      debugPrint('Error getting group tasks: $e');
      return [];
    }
  }

  // Get messages for a group as stream
  Stream<QuerySnapshot> getGroupMessagesStream(String groupID) {
    return _firestore
        .collection('messages')
        .where('groupID', isEqualTo: groupID)
        .orderBy('timestamp')
        .snapshots();
  }

  // Get user data
  Future<DocumentSnapshot> getUserData(String userID) async {
    return await _firestore.collection('users').doc(userID).get();
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String userID,
    required String name,
  }) async {
    try {
      await _firestore.collection('users').doc(userID).update({
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      rethrow;
    }
  }

  // Get group data
  Future<DocumentSnapshot> getGroupData(String groupID) async {
    return await _firestore.collection('groups').doc(groupID).get();
  }

  // Delete a task
  Future<void> deleteTask(String taskId, String groupId) async {
    // 1. Delete reminders first
    await FirebaseFirestore.instance
        .collection('reminders')
        .where('taskId', isEqualTo: taskId)
        .get()
        .then((snapshot) {
      for (final doc in snapshot.docs) {
        doc.reference.delete();
      }
    });

    // 2. Remove from group's task list
    await FirebaseFirestore.instance.collection('groups').doc(groupId).update({
      'tasks': FieldValue.arrayRemove([taskId]),
    });

    // 3. Delete the task itself
    await FirebaseFirestore.instance.collection('tasks').doc(taskId).delete();
  }

  // Update group
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? leaderId,
  }) async {
    Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (leaderId != null) updates['leaderId'] = leaderId;

    await _firestore.collection('groups').doc(groupId).update(updates);
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId, String userId) async {
    await _firestore.collection('messages').doc(messageId).update({
      'read': FieldValue.arrayUnion([userId]),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingNotifications(
      String userId) async {
    try {
      final notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .orderBy('timestamp', descending: true)
          .get();

      return notificationsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();
    } catch (e) {
      debugPrint('Error getting pending notifications: $e');
      return [];
    }
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllNotificationsAsRead(String userId) async {
    final batch = _firestore.batch();
    final notificationsSnapshot = await _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    for (var doc in notificationsSnapshot.docs) {
      batch.update(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // Complete the checkAndProcessOverdueTasks method
  Future<void> checkAndProcessOverdueTasks() async {
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

// Process due task notifications
  Future<void> processDueTaskNotifications() async {
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
      debugPrint('Error processing due task notifications: $e');
    }
  }

// Get unread notification count for a user
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: userId)
          .where('read', isEqualTo: false)
          .count()
          .get();

      return querySnapshot.count;
    } catch (e) {
      debugPrint('Error getting unread notification count: $e');
      return 0;
    }
  }

// Get unread message count for a user
  Future<int> getUnreadMessagesCount(String userId) async {
    try {
      // Get all groups user is a member of
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final groups = List<String>.from(userDoc.data()?['groups'] ?? []);

      if (groups.isEmpty) return 0;

      int unreadCount = 0;

      // For each group, get unread messages
      for (var groupId in groups) {
        final messagesSnapshot = await _firestore
            .collection('messages')
            .where('groupID', isEqualTo: groupId)
            .where('read', arrayContains: userId)
            .get();

        unreadCount += messagesSnapshot.size;
      }

      return unreadCount;
    } catch (e) {
      debugPrint('Error getting unread messages count: $e');
      return 0;
    }
  }

// Listen for new notifications for a user
  Stream<QuerySnapshot> getUserNotificationsStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50) // Limit to avoid excessive reads
        .snapshots();
  }

// Create and send FCM notification
  Future<void> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get user's FCM token
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final fcmToken = userDoc.data()?['fcmToken'];

      if (fcmToken == null) {
        debugPrint('No FCM token found for user: $userId');
        return;
      }

      // Store notification in Firebase for FCM cloud functions to process
      await _firestore.collection('pushNotifications').add({
        'token': fcmToken,
        'title': title,
        'body': body,
        'data': data ?? {},
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'sent': false,
      });
    } catch (e) {
      debugPrint('Error sending push notification: $e');
    }
  }

// Update users' notification preferences
  Future<void> updateNotificationPreferences({
    required String userId,
    required Map<String, bool> preferences,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'notificationPreferences': preferences,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating notification preferences: $e');
    }
  }

// Get user's notification preferences
  Future<Map<String, bool>> getNotificationPreferences(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      if (data != null && data.containsKey('notificationPreferences')) {
        return Map<String, bool>.from(data['notificationPreferences']);
      }

      // Return default preferences if none exist
      return {
        'task_assigned': true,
        'task_reminder': true,
        'task_overdue': true,
        'group_messages': true,
        'rating_received': true,
      };
    } catch (e) {
      debugPrint('Error getting notification preferences: $e');
      return {
        'task_assigned': true,
        'task_reminder': true,
        'task_overdue': true,
        'group_messages': true,
        'rating_received': true,
      };
    }
  }

// Clear old notifications
  Future<void> cleanupOldNotifications() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final oldNotificationsSnapshot = await _firestore
          .collection('notifications')
          .where('timestamp', isLessThan: Timestamp.fromDate(thirtyDaysAgo))
          .limit(500) // Process in batches to avoid timeout
          .get();

      if (oldNotificationsSnapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (var doc in oldNotificationsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      // Recursively call if there are more to delete
      if (oldNotificationsSnapshot.docs.length == 500) {
        await cleanupOldNotifications();
      }
    } catch (e) {
      debugPrint('Error cleaning up old notifications: $e');
    }
  }
}
