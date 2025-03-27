import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required')),
      );
      return;
    }

    try {
      await _firestore.collection('groups').add({
        'name': _groupNameController.text.trim(),
        'description': _groupDescriptionController.text.trim(),
        'createdBy': user.uid,
        'createdAt': DateTime.now(),
        'members': [user.uid],
        'tasks': [],
      });

      // Update user's groups list
      await _firestore.collection('users').doc(user.uid).update({
        'groups': FieldValue.arrayUnion([user.uid]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([user.uid]),
      });

      // Update user's groups list
      await _firestore.collection('users').doc(user.uid).update({
        'groups': FieldValue.arrayUnion([groupId]),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
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
                  .where('members', arrayContains: user.uid)
                  .snapshots(),
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
                          final group = snapshot.data!.docs[index];
                          return ListTile(
                            title: Text(group['name']),
                            subtitle: Text(group['description']),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () {
                              // Navigate to group details
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            // Chats Tab
            const Center(child: Text('Chats will appear here')),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Show dialog to join group by ID
            showDialog(
              context: context,
              builder: (context) {
                final TextEditingController groupIdController =
                    TextEditingController();
                return AlertDialog(
                  title: const Text('Join Group'),
                  content: TextField(
                    controller: groupIdController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Group ID',
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
