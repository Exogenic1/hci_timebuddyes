import 'package:cloud_firestore/cloud_firestore.dart';

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
    await _firestore.collection('users').doc(userID).set({
      'name': name,
      'email': email,
      'profilePicture': profilePicture ?? '',
      'fcmToken': fcmToken,
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
      'groups': [],
    }, SetOptions(merge: true)); // Use merge to not overwrite existing data
  }

// Add this new method
  Future<void> updateFcmToken(String userID, String? fcmToken) async {
    await _firestore.collection('users').doc(userID).update({
      'fcmToken': fcmToken,
      'updatedAt': DateTime.now(),
    });
  }

  // Update user's groups
  Future<void> updateUserGroups({
    required String userID,
    required List<String> groups,
  }) async {
    await _firestore.collection('users').doc(userID).update({
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
    required String status,
    required DateTime dueDate,
  }) async {
    final taskData = {
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'status': status,
      'dueDate': dueDate,
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

// In the groups collection
  Future<void> addGroupMember({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([
        {
          'userId': userId,
          'role': role, // e.g., 'admin', 'member', 'leader'
          'joinedAt': DateTime.now(),
        }
      ]),
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
