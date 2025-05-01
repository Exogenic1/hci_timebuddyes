import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:time_buddies/screens/completed_task_screen.dart';
import 'package:time_buddies/screens/task_list.dart';
import 'package:time_buddies/screens/user_header.dart';
import 'package:time_buddies/screens/ratings_screen.dart';
import 'package:time_buddies/screens/performance_stats.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _currentPage = 0;
  final int _totalPages = 3;
  String? _selectedGroupId;
  List<String> _userGroups = [];
  bool _isLoadingGroups = true;
  bool _isLoadingTasks = false;
  List<Map<String, dynamic>> _incompleteTasks = [];

  @override
  void initState() {
    super.initState();
    _loadUserGroups();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserGroups() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _isLoadingGroups = false);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final groups = (userData['groups'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [];

      setState(() {
        _userGroups = groups;
        _selectedGroupId = groups.isNotEmpty ? groups.first : null;
        _isLoadingGroups = false;
      });

      // Load incomplete tasks if a group is selected
      if (_selectedGroupId != null) {
        _loadIncompleteTasks(user.uid);
      }
    } catch (e) {
      debugPrint('Error loading user groups: $e');
      setState(() => _isLoadingGroups = false);
    }
  }

  Future<void> _loadIncompleteTasks(String userId) async {
    if (_selectedGroupId == null) return;

    setState(() => _isLoadingTasks = true);

    try {
      // Check if user is a group leader
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(_selectedGroupId)
          .get();

      if (!groupDoc.exists) {
        setState(() => _isLoadingTasks = false);
        return;
      }

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final bool isLeader = groupData['leaderId'] == userId;

      // Query for incomplete tasks
      Query tasksQuery = FirebaseFirestore.instance
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId)
          .where('completed', isEqualTo: false);

      // If not a leader, only show tasks assigned to this user
      if (!isLeader) {
        tasksQuery = tasksQuery.where('assignedTo', isEqualTo: userId);
      }

      final taskDocs = await tasksQuery.get();

      // Get user names for assigned users
      final Set<String> userIds = {};
      for (var doc in taskDocs.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final assignedTo = data['assignedTo'] as String?;
        if (assignedTo != null) {
          userIds.add(assignedTo);
        }
      }

      // Fetch user names if there are any tasks
      Map<String, String> userNames = {};
      if (userIds.isNotEmpty) {
        final userDocs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: userIds.toList())
            .get();

        for (var doc in userDocs.docs) {
          userNames[doc.id] = (doc.data()['name'] as String?) ?? 'Unknown User';
        }
      }

      // Process tasks with user info
      final tasks = taskDocs.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final assignedTo = data['assignedTo'] as String?;
        final dueDate = data['dueDate'] as Timestamp;

        // Calculate if the task is overdue
        final bool isOverdue = dueDate.toDate().isBefore(DateTime.now());

        return {
          'id': doc.id,
          'title': data['title'] ?? 'Unnamed Task',
          'description': data['description'] ?? '',
          'dueDate': dueDate,
          'assignedTo': assignedTo,
          'assignedToName': assignedTo != null
              ? (userNames[assignedTo] ?? 'Unknown')
              : 'Unassigned',
          'isOverdue': isOverdue,
        };
      }).toList();

      // Sort tasks by due date (soonest first)
      tasks.sort((a, b) {
        final aDate = (a['dueDate'] as Timestamp).toDate();
        final bDate = (b['dueDate'] as Timestamp).toDate();
        return aDate.compareTo(bDate);
      });

      setState(() {
        _incompleteTasks = tasks;
        _isLoadingTasks = false;
      });
    } catch (e) {
      debugPrint('Error loading incomplete tasks: $e');
      setState(() => _isLoadingTasks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view tasks'));
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Your Tasks'),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UserHeader(),
          const SizedBox(height: 15),

          // Action Cards Carousel
          SizedBox(
            height: 100, // Fixed height for the carousel
            child: Stack(
              alignment: Alignment.center,
              children: [
                // PageView for scrolling cards
                PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: [
                    // Ratings Card
                    _buildActionCard(
                      context: context,
                      icon: Icons.star,
                      iconColor: Colors.amber[700]!,
                      title: 'View Ratings',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                RatingsScreen(userId: user.uid),
                          ),
                        );
                      },
                    ),
                    // Completed Tasks Card
                    _buildActionCard(
                      context: context,
                      icon: Icons.check_circle,
                      iconColor: Colors.green[700]!,
                      title: 'Completed Tasks',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CompletedTasksScreen(userId: user.uid),
                          ),
                        );
                      },
                    ),
                    // Performance Stats Card
                    _buildActionCard(
                      context: context,
                      icon: Icons.analytics,
                      iconColor: Colors.deepPurple,
                      title: 'Performance Stats',
                      onTap: () async {
                        // Get user name
                        final userDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get();
                        final userData =
                            userDoc.data() as Map<String, dynamic>?;
                        final userName = userData?['name'] as String? ?? 'User';

                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PerformanceStatsScreen(
                                userId: user.uid,
                                userName: userName,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),

                // Left arrow
                Positioned(
                  left: 0,
                  child: _currentPage > 0
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        )
                      : const SizedBox(width: 48), // Maintains symmetry
                ),

                // Right arrow
                Positioned(
                  right: 0,
                  child: _currentPage < _totalPages - 1
                      ? IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                        )
                      : const SizedBox(width: 48), // Maintains symmetry
                ),
              ],
            ),
          ),

          // Page indicator
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _totalPages,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ),

          // Group selector if there are multiple groups
          if (_userGroups.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildGroupSelector(),
            ),

          const SizedBox(height: 10),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              'Assigned Tasks',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),

          // Task list or loading/info indicator - showing only incomplete tasks
          Expanded(
            child: _isLoadingGroups
                ? const Center(child: CircularProgressIndicator())
                : _userGroups.isEmpty
                    ? const Center(
                        child: Text(
                          'Join or create a group to view tasks',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : _buildIncompleteTaskList(user.uid),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedGroupId,
            isExpanded: true,
            hint: const Text('Select a group'),
            items: _userGroups.map((groupId) {
              return DropdownMenuItem<String>(
                value: groupId,
                child: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Loading...');
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Text('Group $groupId');
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    return Text(data?['name'] ?? 'Unnamed Group');
                  },
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedGroupId = newValue;
                });
                _loadIncompleteTasks(user.uid);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIncompleteTaskList(String userId) {
    if (_isLoadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_incompleteTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No pending tasks',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'All caught up!',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _incompleteTasks.length,
      itemBuilder: (context, index) {
        final task = _incompleteTasks[index];
        final dueDate = (task['dueDate'] as Timestamp).toDate();
        final isOverdue = task['isOverdue'] as bool;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOverdue)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Overdue',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),

                if (task['description'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      task['description'],
                      style: TextStyle(color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 12),

                // Due date and assigned user
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14,
                        color: isOverdue ? Colors.red : Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${DateFormat('MMM d, y').format(dueDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.normal,
                        color: isOverdue ? Colors.red : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        task['assignedToName'],
                        style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Show remaining time until due
                if (!isOverdue)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildTimeRemainingIndicator(dueDate),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeRemainingIndicator(DateTime dueDate) {
    final now = DateTime.now();
    final difference = dueDate.difference(now);

    // Calculate percentage of time remaining (max 100%)
    double progress;
    String timeText;
    Color progressColor;

    if (difference.inDays > 7) {
      // More than a week remaining
      progress = 1.0;
      timeText = '${difference.inDays} days left';
      progressColor = Colors.green;
    } else if (difference.inDays > 0) {
      // Days remaining
      progress = difference.inDays / 7;
      timeText =
          '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} left';
      progressColor = difference.inDays > 3 ? Colors.green : Colors.orange;
    } else if (difference.inHours > 0) {
      // Hours remaining
      progress = difference.inHours / (24 * 7);
      timeText =
          '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} left';
      progressColor = Colors.orange;
    } else if (difference.inMinutes > 0) {
      // Minutes remaining
      progress = difference.inMinutes / (24 * 60 * 7);
      timeText =
          '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} left';
      progressColor = Colors.red;
    } else {
      // Due now
      progress = 0;
      timeText = 'Due now';
      progressColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeText,
          style: TextStyle(
            fontSize: 11,
            color: progressColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
