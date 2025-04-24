import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:time_buddies/services/data_validation_service.dart';

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
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': fcmToken,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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

      final groupData = groupDoc.data() as Map<String, dynamic>?;
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

  // Add a task
  Future<String> addTask({
    required String title,
    required String description,
    required String assignedTo,
    String? groupId,
    required DateTime dueDate,
  }) async {
    // Determine initial status
    String status = 'Pending';

    final taskData = {
      'title': title,
      'description': description,
      'assigneeId': assignedTo,
      'status': status,
      'dueDate': dueDate,
      'completed': false,
      'locked': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (groupId != null) {
      taskData['groupID'] = groupId;
    }

    DocumentReference taskRef =
        await _firestore.collection('tasks').add(taskData);

    if (groupId != null) {
      await _firestore.collection('groups').doc(groupId).update({
        'tasks': FieldValue.arrayUnion([taskRef.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return taskRef.id;
  }

  // Mark task as completed
  Future<void> markTaskAsCompleted(String taskId, bool isCompleted) async {
    await _firestore.collection('tasks').doc(taskId).update({
      'completed': isCompleted,
      'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
  Stream<QuerySnapshot> getGroupTasksStream(String groupID) {
    return _firestore
        .collection('tasks')
        .where('groupID', isEqualTo: groupID)
        .orderBy('dueDate')
        .snapshots();
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
    // First remove task reference from group
    await _firestore.collection('groups').doc(groupId).update({
      'tasks': FieldValue.arrayRemove([taskId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Then delete the task document
    await _firestore.collection('tasks').doc(taskId).delete();
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
}
