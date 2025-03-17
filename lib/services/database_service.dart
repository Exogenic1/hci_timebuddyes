import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Add a new user
  Future<void> addUser({
    required String userID,
    required String name,
    required String email,
    String? profilePicture,
  }) async {
    await _firestore.collection('users').doc(userID).set({
      'name': name,
      'email': email,
      'profilePicture':
          profilePicture ?? '', // Use an empty string if no picture is provided
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
      'groups': [], // Initialize with an empty list of groups
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

  // Add a task to a group
  Future<String> addTask({
    required String title,
    required String description,
    required String assignedTo,
    required String groupID,
    required String status,
    required DateTime dueDate,
  }) async {
    DocumentReference taskRef = await _firestore.collection('tasks').add({
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'groupID': groupID,
      'status': status,
      'dueDate': dueDate,
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
    });

    // Add the task ID to the group's tasks list
    await _firestore.collection('groups').doc(groupID).update({
      'tasks': FieldValue.arrayUnion([taskRef.id]),
    });

    return taskRef.id; // Return the task ID
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
