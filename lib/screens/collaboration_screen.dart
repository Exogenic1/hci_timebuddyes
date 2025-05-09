import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/screens/group_chat_screen.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/database_service.dart';

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_currentUser == null || !mounted) return;

    if (_groupNameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group name is required')),
        );
      }
      return;
    }

    try {
      // First check if a group with this name already exists
      final existingGroups = await _firestore
          .collection('groups')
          .where('createdBy', isEqualTo: _currentUser.uid)
          .where('name', isEqualTo: _groupNameController.text.trim())
          .get();

      if (existingGroups.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('You already have a group with this name')),
          );
        }
        return;
      }

      final groupRef = _firestore.collection('groups').doc();
      final groupId = groupRef.id;

      await groupRef.set({
        'id': groupId,
        'name': _groupNameController.text.trim(),
        'description': _groupDescriptionController.text.trim(),
        'leaderId': _currentUser.uid,
        'createdBy': _currentUser.uid,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
        'members': [
          {
            'userId': _currentUser.uid,
            'name': _currentUser.displayName ?? 'Group Leader',
            'email': _currentUser.email,
            'role': 'leader',
            'joinedAt': DateTime.now(),
          }
        ],
        'tasks': [],
      });

      await _firestore.collection('chats').doc(groupId).set({
        'groupId': groupId,
        'groupName': _groupNameController.text.trim(),
        'leaderId': _currentUser.uid,
        'members': [_currentUser.uid],
        'createdAt': DateTime.now(),
        'lastMessage': null,
        'lastMessageTime': null,
      });

      await _firestore.collection('users').doc(_currentUser.uid).update({
        'groups': FieldValue.arrayUnion([groupId]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group created successfully! ID: $groupId'),
            action: SnackBarAction(
              label: 'Copy ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: groupId));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Group ID copied to clipboard!')),
                  );
                }
              },
            ),
          ),
        );
        _groupNameController.clear();
        _groupDescriptionController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: ${e.toString()}')),
        );
      }
    }
  }

  // Update the _joinGroup method
  Future<void> _joinGroup(String groupId) async {
    if (_currentUser == null || !mounted || groupId.isEmpty) return;

    try {
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final validationService = DataValidationService();

      // Validate the group exists
      await validationService.validateGroupData(groupId);

      // Check if user is already in the group
      final userGroups =
          await databaseService.getUserGroupIds(_currentUser.uid);
      if (userGroups.contains(groupId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('You are already a member of this group')),
          );
        }
        return;
      }

      // Get user data
      final userDoc =
          await _firestore.collection('users').doc(_currentUser.uid).get();
      final userData = userDoc.data();
      final userName =
          userData?['name'] ?? _currentUser.displayName ?? 'Member';
      final userEmail = _currentUser.email ?? '';

      // Add user to group
      await _firestore.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([
          {
            'userId': _currentUser.uid,
            'name': userName,
            'email': userEmail,
            'role': 'member',
            'joinedAt': DateTime.now(),
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Add group to user's groups list
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'groups': FieldValue.arrayUnion([groupId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update chat members
      await _firestore.collection('chats').doc(groupId).update({
        'members': FieldValue.arrayUnion([_currentUser.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined group')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining group: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildGroupTile(DocumentSnapshot group) {
    final data = group.data() as Map<String, dynamic>?;
    if (data == null) return const SizedBox();

    final name = data['name'] as String? ?? 'Unnamed Group';
    final description = data['description'] as String? ?? 'No description';
    final leaderId = data['leaderId'] as String? ?? '';
    final isCurrentUserLeader = _currentUser?.uid == leaderId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                Chip(
                  label: Text(
                      '${(data['members'] as List?)?.length ?? 0} members'),
                  visualDensity: VisualDensity.compact,
                ),
                if (isCurrentUserLeader)
                  const Chip(
                    label: Text('Leader'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.orange,
                  ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'copy',
              child: Text('Copy Group ID'),
            ),
            const PopupMenuItem(
              value: 'chat',
              child: Text('Open Chat'),
            ),
          ],
          onSelected: (value) async {
            if (value == 'copy') {
              await Clipboard.setData(ClipboardData(text: group.id));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Group ID copied to clipboard!')),
                );
              }
            } else if (value == 'chat' && _currentUser != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatScreen(
                    chatId: group.id,
                    groupName: name,
                    currentUserId: _currentUser.uid,
                    currentUserName: _currentUser.displayName ?? 'User',
                    groupLeaderId: leaderId,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please sign in to view groups'));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Collaboration'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'Groups'),
              Tab(icon: Icon(Icons.chat), text: 'Chats'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Groups Tab
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('groups')
                  .where('members.userId', isEqualTo: _currentUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final groups = snapshot.data?.docs ?? [];

                return Column(
                  children: [
                    // Create Group Section
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _groupNameController,
                            decoration: const InputDecoration(
                              labelText: 'Group Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _groupDescriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description (Optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _createGroup,
                            child: const Text('Create Group'),
                          ),
                        ],
                      ),
                    ),
                    // Group List
                    Expanded(
                      child: ListView.builder(
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          return _buildGroupTile(groups[index]);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            // Chats Tab
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .where('members', arrayContains: _currentUser.uid)
                  .orderBy('lastMessageTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final chats = snapshot.data?.docs ?? [];
                if (chats.isEmpty) {
                  return const Center(child: Text('No chats available'));
                }

                return ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final chatData = chat.data() as Map<String, dynamic>? ?? {};

                    return FutureBuilder<DocumentSnapshot>(
                      future: _firestore
                          .collection('groups')
                          .doc(chatData['groupId'] as String?)
                          .get(),
                      builder: (context, groupSnapshot) {
                        if (!groupSnapshot.hasData) {
                          return const ListTile(title: Text('Loading...'));
                        }

                        final groupData = groupSnapshot.data!.data()
                                as Map<String, dynamic>? ??
                            {};
                        final groupName =
                            groupData['name'] as String? ?? 'Unknown Group';

                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.group)),
                          title: Text(groupName),
                          subtitle: Text(chatData['lastMessage'] as String? ??
                              'No messages yet'),
                          trailing: IconButton(
                            icon: const Icon(Icons.content_copy),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: chat.id));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Chat ID copied!')),
                                );
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupChatScreen(
                                  chatId: chat.id,
                                  groupName: groupName,
                                  currentUserId: _currentUser.uid,
                                  currentUserName: '',
                                  groupLeaderId:
                                      groupData['leaderId'] as String? ?? '',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                final groupIdController = TextEditingController();
                return AlertDialog(
                  title: const Text('Join Group'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: groupIdController,
                        decoration: const InputDecoration(
                          labelText: 'Enter Group ID',
                          hintText: 'Paste the group ID here',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          final clipboardData =
                              await Clipboard.getData('text/plain');
                          if (clipboardData != null) {
                            groupIdController.text = clipboardData.text ?? '';
                          }
                        },
                        child: const Text('Paste from clipboard'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (groupIdController.text.trim().isNotEmpty) {
                          _joinGroup(groupIdController.text.trim());
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Join'),
                    ),
                  ],
                );
              },
            );
          },
          child: const Icon(Icons.group_add),
        ),
      ),
    );
  }
}
