import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';

class GroupChatScreen extends StatefulWidget {
  final String chatId;
  final String groupName;
  final String currentUserId;
  final String currentUserName;
  final String groupLeaderId; // Now required

  const GroupChatScreen({
    super.key,
    required this.chatId,
    required this.groupName,
    required this.currentUserId,
    required this.currentUserName,
    required this.groupLeaderId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  late bool _isUserLeader;

  @override
  void initState() {
    super.initState();
    _isUserLeader = widget.currentUserId == widget.groupLeaderId;
    _setupNotifications();
  }

  void _setupNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.notification!.body ?? 'New message')),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle when app is opened from terminated state
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || !mounted) return;

    try {
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'text': _messageController.text.trim(),
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'timestamp': FieldValue.serverTimestamp(),
        'isFromLeader': _isUserLeader,
      });

      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': _messageController.text.trim(),
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.currentUserId,
      });

      if (mounted) {
        await _sendPushNotifications();
        _messageController.clear();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  Future<void> _sendPushNotifications() async {
    if (!mounted) return;

    try {
      final chatDoc =
          await _firestore.collection('chats').doc(widget.chatId).get();
      final members = List<String>.from(chatDoc['members'] ?? []);
      members.remove(widget.currentUserId);

      if (members.isEmpty) return;

      final usersSnapshot = await _firestore
          .collection('users')
          .where('uid', whereIn: members)
          .get();

      final tokens = <String>[];
      for (var doc in usersSnapshot.docs) {
        if (doc['fcmToken'] != null) {
          tokens.add(doc['fcmToken']);
        }
      }

      if (tokens.isEmpty) return;

      await _firestore.collection('notifications').add({
        'tokens': tokens,
        'title': widget.groupName,
        'body':
            '${widget.currentUserName}${_isUserLeader ? " (Leader)" : ""}: ${_messageController.text.trim()}',
        'chatId': widget.chatId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error sending notifications: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showManageGroupDialog() async {
    if (!_isUserLeader) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Add Members'),
              onTap: () {
                Navigator.pop(context);
                _showAddMembersDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text('Remove Members'),
              onTap: () {
                Navigator.pop(context);
                _showRemoveMembersDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Group'),
              onTap: () {
                Navigator.pop(context);
                _showRenameGroupDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMembersDialog() async {
    // This would typically fetch users not in the group
    // For now, it's a placeholder
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Members'),
        content: const Text('Feature coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRemoveMembersDialog() async {
    try {
      final chatDoc =
          await _firestore.collection('chats').doc(widget.chatId).get();
      final members = List<String>.from(chatDoc['members'] ?? []);

      if (members.isEmpty || members.length <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No members to remove')),
          );
        }
        return;
      }

      // Get member names
      final usersSnapshot = await _firestore
          .collection('users')
          .where('uid',
              whereIn:
                  members.where((id) => id != widget.currentUserId).toList())
          .get();

      final membersList = usersSnapshot.docs
          .map((doc) => {
                'uid': doc['uid'],
                'name': doc['name'] ?? 'Unknown User',
              })
          .toList();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Members'),
            content: SizedBox(
              width: double.maxFinite,
              child: membersList.isEmpty
                  ? const Text('No members to remove')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: membersList.length,
                      itemBuilder: (context, index) {
                        final member = membersList[index];
                        return ListTile(
                          title: Text(member['name'].toString()),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _removeMember(member['uid'].toString());
                            },
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load members: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      // Get current members
      final chatDoc =
          await _firestore.collection('chats').doc(widget.chatId).get();
      final members = List<String>.from(chatDoc['members'] ?? []);

      // Remove the member
      members.remove(userId);

      // Update the chat document
      await _firestore.collection('chats').doc(widget.chatId).update({
        'members': members,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error removing member: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove member: $e')),
        );
      }
    }
  }

  Future<void> _showRenameGroupDialog() async {
    final TextEditingController nameController = TextEditingController();
    nameController.text = widget.groupName;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _renameGroup(nameController.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameGroup(String newName) async {
    try {
      await _firestore.collection('chats').doc(widget.chatId).update({
        'name': newName,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group renamed successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error renaming group: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          if (_isUserLeader)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: _showManageGroupDialog,
              tooltip: 'Group Management',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isUserLeader)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.amber[100],
              child: const Row(
                children: [
                  Icon(Icons.star, size: 16, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('You are the group leader'),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: snapshot.data?.docs.length ?? 0,
                  itemBuilder: (context, index) {
                    final message = snapshot.data!.docs[index];
                    final data = message.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == widget.currentUserId;
                    final isFromLeader =
                        data['senderId'] == widget.groupLeaderId;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).primaryColor
                              : isFromLeader
                                  ? Colors.amber[100]
                                  : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    data['senderName'] ?? 'Unknown',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isMe ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  if (isFromLeader)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4.0),
                                      child: Icon(
                                        Icons.star,
                                        size: 14,
                                        color: isMe
                                            ? Colors.white70
                                            : Colors.amber,
                                      ),
                                    ),
                                ],
                              ),
                            Text(
                              data['text'],
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['timestamp'] != null
                                  ? DateFormat('HH:mm').format(
                                      (data['timestamp'] as Timestamp).toDate(),
                                    )
                                  : '--:--',
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
