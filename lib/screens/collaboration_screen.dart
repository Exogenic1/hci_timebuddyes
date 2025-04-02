import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
// import 'package:time_buddies/widgets/role_badge.dart';
import 'package:time_buddies/screens/group_chat_screen.dart';
import 'package:share_plus/share_plus.dart';

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

  bool _hasUnreadMessages(String chatId) {
    // Implement your unread messages logic here
    return false;
  }

  void _openChatScreen(BuildContext context, String chatId, String groupName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatScreen(
          chatId: chatId,
          groupName: groupName,
          currentUserId: _currentUser?.uid ?? '',
        ),
      ),
    );
  }

  void _copyGroupId(String groupId) {
    Clipboard.setData(ClipboardData(text: groupId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group ID copied to clipboard')),
    );
  }

  void _shareGroupId(String groupId, String groupName) {
    Share.share(
      'Join my Time Buddies group "$groupName" using this ID: $groupId',
      subject: 'Join my Time Buddies group!',
    );
  }

  Future<void> _createGroup() async {
    if (_currentUser == null) return;

    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    try {
      // Create a new document reference to get the ID first
      final groupRef = _firestore.collection('groups').doc();

      // Create the group with the creator as leader
      await groupRef.set({
        'id': groupRef.id,
        'name': _groupNameController.text.trim(),
        'description': _groupDescriptionController.text.trim(),
        'createdBy': _currentUser.uid,
        'createdAt': DateTime.now(),
        'members': [
          {
            'userId': _currentUser.uid,
            'role': 'leader',
            'joinedAt': DateTime.now(),
          }
        ],
        'tasks': [],
        'chatId': groupRef.id, // Same ID for chat reference
      });

      // Update user's groups list
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'groups': FieldValue.arrayUnion([groupRef.id]),
      });

      // Create a corresponding chat document
      await _firestore.collection('chats').doc(groupRef.id).set({
        'groupId': groupRef.id,
        'groupName': _groupNameController.text.trim(),
        'createdAt': DateTime.now(),
        'createdBy': _currentUser.uid,
        'lastMessage': '',
        'lastMessageTime': DateTime.now(),
        'lastMessageSender': _currentUser.uid,
        'members': [_currentUser.uid],
      });

      if (mounted) {
        // Show a dialog with the group ID
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Group Created'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Your group was created successfully. Share this ID with friends to invite them:'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          groupRef.id,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copyGroupId(groupRef.id),
                        tooltip: 'Copy ID',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  _shareGroupId(groupRef.id, _groupNameController.text.trim());
                  Navigator.pop(context);
                },
                child: const Text('Share'),
              ),
            ],
          ),
        );

        _groupNameController.clear();
        _groupDescriptionController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: $e')),
        );
      }
    }
  }

  Future<void> _joinGroup(String groupId) async {
    if (_currentUser == null) return;

    try {
      // Check if the group exists
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Group not found. Please check the ID and try again')),
        );
        return;
      }

      // Check if user is already a member
      final groupData = groupDoc.data() as Map<String, dynamic>;
      final members =
          List<Map<String, dynamic>>.from(groupData['members'] ?? []);
      if (members.any((m) => m['userId'] == _currentUser.uid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You are already a member of this group')),
        );
        return;
      }

      // Add user as a member with default 'member' role
      await _firestore.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([
          {
            'userId': _currentUser.uid,
            'role': 'member',
            'joinedAt': FieldValue.serverTimestamp(),
          }
        ]),
      });

      // Update user's groups list
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'groups': FieldValue.arrayUnion([groupId]),
      });

      // Add user to chat members
      await _firestore.collection('chats').doc(groupId).update({
        'members': FieldValue.arrayUnion([_currentUser.uid]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined group successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining group: $e')),
        );
      }
    }
  }

  Widget _buildGroupTile(DocumentSnapshot group) {
    final data = group.data() as Map<String, dynamic>;
    final members = List<Map<String, dynamic>>.from(data['members'] ?? []);
    final isLeader = members
        .any((m) => m['userId'] == _currentUser?.uid && m['role'] == 'leader');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        children: [
          ListTile(
            title: Text(data['name']),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['description'] ?? 'No description'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    Chip(
                      label: Text('${members.length} members'),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (isLeader)
                      const Chip(
                        label: Text('Leader'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.orange,
                      ),
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              // Navigate to group details or chat
              _openChatScreen(context, data['chatId'], data['name']);
            },
          ),
          // Group ID section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Group ID: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    data['id'] ?? group.id,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copyGroupId(data['id'] ?? group.id),
                  tooltip: 'Copy ID',
                ),
                IconButton(
                  icon: const Icon(Icons.share, size: 20),
                  onPressed: () =>
                      _shareGroupId(data['id'] ?? group.id, data['name']),
                  tooltip: 'Share ID',
                ),
              ],
            ),
          ),
        ],
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
                  .where('members', arrayContains: {
                'userId': _currentUser.uid,
                'role': 'leader',
              }).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

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
                        itemCount: snapshot.data?.docs.length ?? 0,
                        itemBuilder: (context, index) {
                          return _buildGroupTile(snapshot.data!.docs[index]);
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
              builder: (context, chatSnapshot) {
                if (chatSnapshot.hasError) {
                  return Center(child: Text('Error: ${chatSnapshot.error}'));
                }

                if (chatSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (chatSnapshot.data?.docs.isEmpty ?? true) {
                  return const Center(child: Text('No chats available'));
                }

                return ListView.builder(
                  itemCount: chatSnapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final chatDoc = chatSnapshot.data!.docs[index];
                    final chatData = chatDoc.data() as Map<String, dynamic>;

                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.group)),
                      title: Text(chatData['groupName'] ?? 'Group Chat'),
                      subtitle: Text(
                        chatData['lastMessage']?.isNotEmpty ?? false
                            ? chatData['lastMessage']
                            : 'No messages yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(
                              (chatData['lastMessageTime'] as Timestamp)
                                  .toDate(),
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_hasUnreadMessages(chatDoc.id))
                            const CircleAvatar(
                              radius: 4,
                              backgroundColor: Colors.red,
                            ),
                        ],
                      ),
                      onTap: () => _openChatScreen(context, chatDoc.id,
                          chatData['groupName'] ?? 'Group'),
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
                  content: TextField(
                    controller: groupIdController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Group ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        _joinGroup(groupIdController.text.trim());
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
