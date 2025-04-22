import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:time_buddies/services/data_validation_service.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Add a new user
  Future<void> addUser({
    required String userID,
    required String name,
    required String email,
    String? profilePicture,
    String? fcmToken,
  }) async {
    final validationService = DataValidationService();
    await validationService.validateUserData(userID);

    await _firestore.collection('users').doc(userID).set({
      'name': name,
      'email': email,
      'profilePicture': profilePicture ?? '',
      'fcmToken': fcmToken,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'groups': FieldValue.arrayUnion([]),
    }, SetOptions(merge: true));
  }

// Add this new method
  Future<void> updateFcmToken(String userID, String? fcmToken) async {
    await _firestore.collection('users').doc(userID).update({
      'fcmToken': fcmToken,
      'updatedAt': DateTime.now(),
    });
  }
// Add these methods to database_service.dart

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

// Method to get user's completed tasks
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

  // Add this method to your DatabaseService class
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    try {
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

  Future<void> updateUserGroups({
    required String userID,
    required List<String> groups,
  }) async {
    final docRef = _firestore.collection('users').doc(userID);
    final doc = await docRef.get();

    if (!doc.exists) {
      await addUser(
          userID: userID, name: '', email: ''); // Create basic user first
    }

    await docRef.update({
      'groups': groups,
      'updatedAt': DateTime.now(),
    });
  }

  // Create a new group
  Future<String> createGroup({
    required String name,
    required String description,
    required String createdBy,
  }) async {
    DocumentReference groupRef = await _firestore.collection('groups').add({
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'createdAt': DateTime.now(),
      'members': [createdBy], // Add the creator as the first member
      'tasks': [], // Initialize with an empty list of tasks
    });
    return groupRef.id; // Return the group ID
  }

  Future<void> updateTask({
    required String taskId,
    required String title,
    required String description,
    required String status,
    required DateTime dueDate,
    required String assignedTo,
  }) async {
    await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
      'title': title,
      'description': description,
      'status': status,
      'dueDate': dueDate,
      'assignedTo': assignedTo,
      'updatedAt': DateTime.now(),
    });
  }

  // Add a task to a group
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
      'assignedTo': assignedTo,
      'status': status,
      'dueDate': dueDate,
      'completed': false,
      'locked': false,
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
    };

    if (groupId != null) {
      taskData['groupID'] = groupId;
    }

    DocumentReference taskRef =
        await _firestore.collection('tasks').add(taskData);

    if (groupId != null) {
      await _firestore.collection('groups').doc(groupId).update({
        'tasks': FieldValue.arrayUnion([taskRef.id]),
      });
    }

    return taskRef.id;
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
      'timestamp': DateTime.now(),
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
      'raterUserId':
          raterUserId, // Who is giving the rating (anonymous to others)
      'createdAt': DateTime.now(),
    });
  }

  // Add these new methods to DatabaseService
  Future<void> loadUserGroups(String userId) async {
    try {
      final validationService = DataValidationService();
      await validationService.validateUserData(userId);

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final groups = List<String>.from(userDoc['groups'] ?? []);

        // Validate each group
        for (String groupId in groups) {
          await validationService.validateGroupData(groupId);
        }
      }
    } catch (e) {
      debugPrint('Error loading user groups: $e');
    }
  }

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

// In the groups collection
  // In database_service.dart
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
          'joinedAt': DateTime.now(),
        }
      ]),
      'updatedAt': DateTime.now(),
    });
  }

  // Get all groups for a user
  Stream<QuerySnapshot> getUserGroups(String userID) {
    return _firestore
        .collection('groups')
        .where('members', arrayContains: userID)
        .snapshots();
  }

  // Get all tasks for a group
  Stream<QuerySnapshot> getGroupTasks(String groupID) {
    return _firestore
        .collection('tasks')
        .where('groupID', isEqualTo: groupID)
        .snapshots();
  }

  // Get all messages for a group
  Stream<QuerySnapshot> getGroupMessages(String groupID) {
    return _firestore
        .collection('messages')
        .where('groupID', isEqualTo: groupID)
        .orderBy('timestamp')
        .snapshots();
  }

  // Get user data by ID
  Future<DocumentSnapshot> getUserData(String userID) async {
    return await _firestore.collection('users').doc(userID).get();
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String userID,
    String? name,
    String? profilePicture,
  }) async {
    Map<String, dynamic> updates = {
      'updatedAt': DateTime.now(),
    };

    if (name != null) updates['name'] = name;
    if (profilePicture != null) updates['profilePicture'] = profilePicture;

    await _firestore.collection('users').doc(userID).update(updates);
  }
}
