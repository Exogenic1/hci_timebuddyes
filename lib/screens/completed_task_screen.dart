import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:time_buddies/widgets/rating_dialog.dart';

class CompletedTasksScreen extends StatefulWidget {
  final String userId;

  const CompletedTasksScreen({
    super.key,
    required this.userId,
  });

  @override
  State<CompletedTasksScreen> createState() => _CompletedTasksScreenState();
}

class _CompletedTasksScreenState extends State<CompletedTasksScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<String> _userGroups = [];
  String? _selectedGroupId;
  Map<String, String> _groupNames = {};
  Map<String, bool> _groupLeadership = {};
  List<Map<String, dynamic>> _tasks = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserGroups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserGroups() async {
    setState(() => _isLoading = true);

    try {
      // Get user document to load groups
      final userDoc =
          await _firestore.collection('users').doc(widget.userId).get();

      if (!userDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final groups = (userData['groups'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [];

      if (groups.isEmpty) {
        setState(() {
          _userGroups = [];
          _selectedGroupId = null;
          _groupNames = {};
          _isLoading = false;
        });
        return;
      }

      // Load group details
      final groupsData = await Future.wait(
        groups.map((groupId) async {
          try {
            final groupDoc =
                await _firestore.collection('groups').doc(groupId).get();
            return {'id': groupId, 'data': groupDoc.data()};
          } catch (e) {
            debugPrint('Error loading group $groupId: $e');
            return null;
          }
        }),
      );

      final newNamesMap = <String, String>{};
      final newLeadershipMap = <String, bool>{};
      final validGroups = <String>[];

      for (final group in groupsData) {
        if (group != null && group['data'] != null) {
          final groupId = group['id'] as String;
          final groupData = group['data'] as Map<String, dynamic>;
          newNamesMap[groupId] =
              groupData['name']?.toString() ?? 'Unnamed Group';
          newLeadershipMap[groupId] =
              (groupData['leaderId']?.toString() ?? '') == widget.userId;
          validGroups.add(groupId);
        }
      }

      setState(() {
        _userGroups = validGroups;
        _groupNames = newNamesMap;
        _groupLeadership = newLeadershipMap;
        _selectedGroupId = _userGroups.isNotEmpty ? _userGroups.first : null;
        _isLoading = false;
      });

      if (_selectedGroupId != null) {
        _loadCompletedTasks();
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadCompletedTasks() async {
    if (_selectedGroupId == null) return;

    setState(() => _isLoading = true);

    try {
      final isLeader = _groupLeadership[_selectedGroupId] ?? false;
      Query query = _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId)
          .where('completed', isEqualTo: true);

      if (!isLeader) {
        // If not a leader, only show tasks assigned to the current user
        query = query.where('assignedTo', isEqualTo: widget.userId);
      }

      final taskDocs = await query.get();

      // Get task IDs
      final taskIds = taskDocs.docs.map((doc) => doc.id).toList();

      // Get ratings for these tasks
      Map<String, List<Map<String, dynamic>>> taskRatings = {};

      if (taskIds.isNotEmpty) {
        final ratingDocs = await _firestore
            .collection('ratings')
            .where('taskId', whereIn: taskIds)
            .get();

        // Group ratings by task ID
        for (var doc in ratingDocs.docs) {
          final data = doc.data();
          final taskId = data['taskId'] as String;

          if (!taskRatings.containsKey(taskId)) {
            taskRatings[taskId] = [];
          }

          taskRatings[taskId]!.add({
            'id': doc.id,
            'rating': data['rating'],
            'timestamp': data['timestamp'],
            'ratedBy': data['ratedBy'],
            'isAnonymous': data['isAnonymous'] ?? true,
          });
        }
      }

      // Get user names for assigned users
      final userIds = taskDocs.docs
          .map((doc) =>
              (doc.data() as Map<String, dynamic>)['assignedTo'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, String> userNames = {};

      if (userIds.isNotEmpty) {
        final userDocs = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: userIds)
            .get();

        for (var doc in userDocs.docs) {
          userNames[doc.id] = (doc.data()['name'] as String?) ?? 'Unknown User';
        }
      }

      // Process tasks with ratings and user info
      final tasks = taskDocs.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        final assignedTo = data['assignedTo'] as String?;

        // Get completion data
        final completionDate = data['completionDate'] as Timestamp?;
        final dueDate = data['dueDate'] as Timestamp;

        // Calculate if the task is late or overdue
        bool isLate = false;
        bool isOverdue = false;

        if (completionDate != null) {
          // Late: completed after due date
          isLate = completionDate.toDate().isAfter(dueDate.toDate());

          // Overdue: completed significantly after due date (7+ days)
          final daysDifference =
              completionDate.toDate().difference(dueDate.toDate()).inDays;
          isOverdue = daysDifference >= 7;
        }

        // Check if current user has already rated this task
        final ratings = taskRatings[id] ?? [];
        final bool hasRated =
            isLeader && ratings.any((r) => r['ratedBy'] == widget.userId);

        // Calculate average rating if available
        double? averageRating;
        if (ratings.isNotEmpty) {
          final sum = ratings.fold<double>(
              0, (sum, item) => sum + (item['rating'] as num).toDouble());
          averageRating = sum / ratings.length;
        }

        return {
          'id': id,
          'title': data['title'] ?? 'Unnamed Task',
          'description': data['description'] ?? '',
          'dueDate': data['dueDate'] as Timestamp,
          'completionDate': data['completionDate'] as Timestamp?,
          'assignedTo': assignedTo,
          'assignedToName': data['assignedToName'] ?? 'Unknown User',
          'isLate': isLate,
          'isOverdue': isOverdue,
          'hasRated': hasRated,
          'ratings': ratings,
          'averageRating': averageRating,
        };
      }).toList();

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading completed tasks: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: ${e.toString()}')),
        );
      }
    }
  }

  void _showRatingDialog(BuildContext context, Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (context) => RatingDialog(
        taskId: task['id'],
        userId: task['assignedTo'],
        userName: task['assignedToName'],
        onRatingSubmitted: () {
          _loadCompletedTasks(); // Reload tasks after rating
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completed Tasks'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overdue'),
            Tab(text: 'Late'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Group selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildGroupSelector(),
          ),

          // Tasks content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedGroupId == null
                    ? const Center(child: Text('Select a group to view tasks'))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTasksList(taskType: 'overdue'),
                          _buildTasksList(taskType: 'late'),
                          _buildTasksList(taskType: 'completed'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    if (_userGroups.isEmpty) {
      return const Text('Join or create a group to view tasks');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Group',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedGroupId,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              items: _userGroups.map((groupId) {
                return DropdownMenuItem<String>(
                  value: groupId,
                  child: Text(
                    _groupNames[groupId] ?? 'Unnamed Group',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() => _selectedGroupId = newValue);
                  _loadCompletedTasks();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList({required String taskType}) {
    // Filter tasks based on the tab
    final filteredTasks = _tasks.where((task) {
      if (taskType == 'overdue') {
        return task['isOverdue'] == true;
      } else if (taskType == 'late') {
        return task['isLate'] == true && task['isOverdue'] == false;
      } else {
        // Regular completed tasks (not late or overdue)
        return task['isLate'] != true && task['isOverdue'] != true;
      }
    }).toList();

    if (filteredTasks.isEmpty) {
      IconData iconData;
      String message;

      switch (taskType) {
        case 'overdue':
          iconData = Icons.assignment_late;
          message = 'No overdue tasks found';
          break;
        case 'late':
          iconData = Icons.timer_off;
          message = 'No late tasks found';
          break;
        default:
          iconData = Icons.assignment_turned_in;
          message = 'No completed tasks found';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredTasks.length,
      itemBuilder: (context, index) {
        final task = filteredTasks[index];
        final completionDate = task['completionDate'] != null
            ? (task['completionDate'] as Timestamp).toDate()
            : null;
        final dueDate = (task['dueDate'] as Timestamp).toDate();
        final hasRating = task['averageRating'] != null;
        final isLeader = _groupLeadership[_selectedGroupId] ?? false;

        // Calculate completion status color and label
        Color statusColor;
        String statusLabel;

        if (task['isOverdue']) {
          statusColor = Colors.red[700]!;
          statusLabel = 'Severely Overdue';
        } else if (task['isLate']) {
          statusColor = Colors.orange[700]!;
          statusLabel = 'Completed Late';
        } else {
          statusColor = Colors.green[700]!;
          statusLabel = 'On Time';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),

                if (task['description'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      task['description'],
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),

                const SizedBox(height: 8),

                // Due date and completion date
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${DateFormat('MMM d, y').format(dueDate)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Completed: ${completionDate != null ? DateFormat('MMM d, y').format(completionDate) : 'Unknown'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Assigned user
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Assigned to: ${task['assignedToName']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Rating section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Show rating if available
                    if (hasRating)
                      Row(
                        children: [
                          const Text(
                            'Rating: ',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          ...List.generate(5, (i) {
                            return Icon(
                              i < (task['averageRating'] ?? 0)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 18,
                            );
                          }),
                          const SizedBox(width: 4),
                          Text(
                            '(${task['averageRating']?.toStringAsFixed(1) ?? '0.0'})',
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 12),
                          ),
                        ],
                      ),

                    // Rate button (only for leaders and unrated tasks assigned to others)
                    if (isLeader &&
                        !task['hasRated'] &&
                        task['assignedTo'] != widget.userId)
                      ElevatedButton.icon(
                        onPressed: () => _showRatingDialog(context, task),
                        icon: const Icon(Icons.star, size: 16),
                        label: const Text('Rate Task'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
