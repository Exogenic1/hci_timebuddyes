import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/screens/login_screen.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/screens/collaboration_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const CalendarScreen(),
    const CollaborationScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Fixed type for better spacing
        elevation: 8.0, // Adds shadow
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.blue, // Blue background
        selectedItemColor: Colors.white, // White for selected item
        unselectedItemColor: Colors.white
            .withOpacity(0.7), // Slightly transparent white for unselected
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'Collaborate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _status = 'Pending';
  DateTime? _dueDate;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // You can fetch additional user data here if needed
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _showTaskInputDialog() async {
    _titleController.clear();
    _descriptionController.clear();
    _status = 'Pending';
    _dueDate = null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add New Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(hintText: 'Task title'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descriptionController,
                      decoration:
                          const InputDecoration(hintText: 'Description'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _status,
                      items: ['Pending', 'In Progress', 'Completed']
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _status = value!;
                        });
                      },
                      decoration: const InputDecoration(hintText: 'Status'),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      title: Text(_dueDate == null
                          ? 'Select due date'
                          : 'Due: ${_dueDate!.toLocal().toString().split(' ')[0]}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDueDate(context),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    if (_titleController.text.trim().isNotEmpty &&
                        _dueDate != null) {
                      try {
                        final databaseService = Provider.of<DatabaseService>(
                            context,
                            listen: false);
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        // Get user's first group (you might want to implement group selection)
                        final groups = await _firestore
                            .collection('groups')
                            .where('members', arrayContains: user.uid)
                            .limit(1)
                            .get();

                        if (groups.docs.isNotEmpty) {
                          final groupId = groups.docs.first.id;
                          await databaseService.addTask(
                            title: _titleController.text.trim(),
                            description: _descriptionController.text.trim(),
                            assignedTo: user.uid,
                            groupID: groupId,
                            status: _status,
                            dueDate: _dueDate!,
                          );
                          _titleController.clear();
                          _descriptionController.clear();
                          if (!mounted) return;
                          Navigator.pop(context);
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('You need to be in a group first')),
                          );
                        }
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding task: $e')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Title and due date are required')),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: $e')),
        );
      }
    }
  }

  // Future<List<String>> _getUserGroups(String userId) async {
  //   try {
  //     final groups = await _firestore
  //         .collection('groups')
  //         .where('members', arrayContains: userId)
  //         .get();
  //     return groups.docs.map((doc) => doc.id).toList();
  //   } catch (e) {
  //     debugPrint('Error fetching user groups: $e');
  //     return [];
  //   }
  // }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view tasks'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section (unchanged)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.blueAccent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome Back!',
                      style: TextStyle(
                        fontSize: 26,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final username = snapshot.data!['name'] ?? 'User';
                          return Text(
                            '@$username',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white70,
                            ),
                          );
                        }
                        return const Text(
                          '@User',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                // Profile picture (unchanged)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    String? photoUrl;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      photoUrl = snapshot.data!['profilePicture'];
                    }
                    return CircleAvatar(
                      radius: 25,
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl) as ImageProvider
                          : const AssetImage('assets/user_icon.png'),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tasks Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              'Your Tasks',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),

          // Simplified Tasks List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tasks')
                  .where('assignedTo', isEqualTo: user.uid)
                  .orderBy('dueDate', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('You do not have any tasks yet'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showTaskInputDialog,
                          child: const Text('Add your first task'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final task = snapshot.data!.docs[index];
                    final taskId = task.id;
                    final data = task.data() as Map<String, dynamic>;
                    final title = data['title'];
                    final description = data['description'];
                    final status = data['status'];
                    final dueDate = (data['dueDate'] as Timestamp).toDate();

                    Color statusColor = Colors.grey;
                    if (status == 'Pending') statusColor = Colors.orange;
                    if (status == 'In Progress') statusColor = Colors.blue;
                    if (status == 'Completed') statusColor = Colors.green;

                    return Dismissible(
                      key: Key(taskId),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) => _deleteTask(taskId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 4,
                          color: Colors.white,
                          child: ListTile(
                            title: Text(title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (description.isNotEmpty) Text(description),
                                const SizedBox(height: 4),
                                Text(
                                  'Due: ${dueDate.toLocal().toString().split(' ')[0]}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Chip(
                              label: Text(status,
                                  style: const TextStyle(color: Colors.white)),
                              backgroundColor: statusColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showTaskInputDialog,
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  Widget _buildHoverableTile(
      BuildContext context, IconData icon, String text, Color color) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        tileColor: Colors.blue.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () {
          Navigator.pop(context);
        },
        hoverColor: Colors.blue.shade300,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ElevatedButton(
            style: ButtonStyle(
              overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return Colors.blue.shade100;
                }
                return null;
              }),
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHoverableTile(
                            context, Icons.add, "Add Plan", Colors.blueAccent),
                        _buildHoverableTile(
                            context, Icons.edit, "Modify Plan", Colors.green),
                        _buildHoverableTile(
                            context, Icons.delete, "Delete Plan", Colors.red),
                        _buildHoverableTile(
                            context, Icons.settings, "Settings", Colors.grey),
                      ],
                    ),
                  );
                },
              );
            },
            child: const Text('Open Calendar Options'),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Log Out"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error logging out: $e')),
                  );
                }
              },
              child: const Text("Log Out", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view profile'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(
                  leading: Icon(Icons.person),
                  title: Text('My Account'),
                  subtitle: Text('Error loading profile'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final username = userData?['name'] ?? 'User';
              final email = userData?['email'] ?? user.email ?? 'No email';

              return Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: userData?['profilePicture'] != null &&
                            userData!['profilePicture'].isNotEmpty
                        ? NetworkImage(userData['profilePicture'])
                            as ImageProvider
                        : const AssetImage('assets/user_icon.png'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('My Account'),
            subtitle: const Text('Make changes to your account'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _showDialog(
                context, "My Account", "Edit your account details here."),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('Manage your language settings'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () =>
                _showDialog(context, "Language", "Change the app language."),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log Out'),
            subtitle: const Text('Further secure your account'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _confirmLogout(context),
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _showDialog(
                context, "Help & Support", "Contact support for assistance."),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About App'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () =>
                _showDialog(context, "About App", "TimeBuddies - Version 1.0"),
          ),
        ],
      ),
    );
  }
}
