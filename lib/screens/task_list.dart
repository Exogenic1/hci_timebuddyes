import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/widgets/task_dialog.dart';
import 'package:time_buddies/services/task_service.dart';
import 'package:time_buddies/services/notifications_service.dart';

class TaskList extends StatefulWidget {
  final String userId;
  final String groupId;
  final bool
      showAll; // Whether to show all tasks or just those assigned to the user

  const TaskList({
    super.key,
    required this.userId,
    required this.groupId,
    this.showAll = false,
  });

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];
  bool _isGroupLeader = false;
  bool _showCompleted = true; // Show completed tasks by default
  late final DatabaseService _databaseService;
  late final TaskService _taskService;
  late final NotificationService _notificationService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _membersList = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _notificationService =
        Provider.of<NotificationService>(context, listen: false);
    _taskService = TaskService(
      databaseService: _databaseService,
      notificationService: _notificationService,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _checkIfGroupLeader();
    _loadGroupMembers();
  }

  @override
  void didUpdateWidget(TaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if the group ID changes
    if (oldWidget.groupId != widget.groupId) {
      _loadTasks();
      _checkIfGroupLeader();
      _loadGroupMembers();
    }
  }

  Future<void> _loadGroupMembers() async {
    // Return early if groupId is empty to prevent Firestore errors
    if (widget.groupId.isEmpty) {
      debugPrint('Warning: GroupId is empty when loading group members');
      setState(() {
        _membersList = [];
        _isLoading = false;
      });
      return;
    }

    try {
      final groupDoc =
          await _firestore.collection('groups').doc(widget.groupId).get();
      if (!groupDoc.exists) return;

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final members = groupData['members'] as List<dynamic>;

      final membersData = await Future.wait(
        members.map((memberId) async {
          try {
            // Skip if memberId is empty
            if (memberId == null || memberId.toString().isEmpty) {
              return null;
            }
            final userDoc =
                await _firestore.collection('users').doc(memberId).get();
            if (userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>;
              return {
                'id': memberId,
                'name': userData['name'] ?? 'Unknown User',
                'email': userData['email'] ?? '',
              };
            }
            return null;
          } catch (e) {
            debugPrint('Error loading member data: $e');
            return null;
          }
        }),
      );

      setState(() {
        _membersList = membersData.whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      debugPrint('Error loading group members: $e');
      setState(() {
        _membersList = [];
      });
    }
  }

  Future<void> _checkIfGroupLeader() async {
    // Return early if groupId is empty to prevent Firestore errors
    if (widget.groupId.isEmpty) {
      debugPrint('Warning: GroupId is empty when checking group leader');
      setState(() {
        _isGroupLeader = false;
        _isLoading = false;
      });
      return;
    }

    try {
      final groupDoc =
          await _firestore.collection('groups').doc(widget.groupId).get();
      if (!groupDoc.exists) {
        setState(() => _isGroupLeader = false);
        return;
      }

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final String groupLeaderId = groupData['leader'] ?? '';

      setState(() {
        _isGroupLeader = groupLeaderId == widget.userId;
      });
    } catch (e) {
      debugPrint('Error checking group leader: $e');
      setState(() => _isGroupLeader = false);
    }
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);

    // Return early if groupId is empty to prevent Firestore errors
    if (widget.groupId.isEmpty) {
      debugPrint('Warning: GroupId is empty when loading tasks');
      setState(() {
        _tasks = [];
        _isLoading = false;
      });
      return;
    }

    try {
      Query query = _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: widget.groupId);

      // If not showing all tasks, filter to just those assigned to current user
      if (!widget.showAll) {
        query = query.where('assignedTo', isEqualTo: widget.userId);
      }

      final taskDocs = await query.get();

      final tasks = taskDocs.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      // Sort tasks by due date
      tasks.sort((a, b) {
        final aDate = (a['dueDate'] as Timestamp).toDate();
        final bDate = (b['dueDate'] as Timestamp).toDate();
        return aDate.compareTo(bDate);
      });

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      setState(() {
        _tasks = [];
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _toggleTaskCompletion(String taskId, bool isCompleted) async {
    try {
      // Update task_service.dart to store completion date when a task is completed
      await _taskService.updateTaskCompletion(taskId, isCompleted);
      _loadTasks(); // Reload to get updated data

      if (isCompleted) {
        // Show rating dialog when task is completed
        _showRatingDialog(context, taskId);
      }
    } catch (e) {
      debugPrint('Error toggling task completion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await _taskService.deleteTask(taskId);
      _loadTasks(); // Reload to get updated data
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: ${e.toString()}')),
        );
      }
    }
  }

  void _showRatingDialog(BuildContext context, String taskId) async {
    // Only show rating dialog if we're the assigned user completing our own task
    final taskIndex = _tasks.indexWhere((task) => task['id'] == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    final assignedUserId = task['assignedTo'];

    // Only the assigned user should rate their own task when completing it
    if (assignedUserId != widget.userId) return;

    double rating = 3.0; // Default rating

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rate Your Task Performance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How would you rate your performance on this task?'),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      IconButton(
                        icon: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = i.toDouble();
                          });
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () {
              _submitRating(taskId, assignedUserId, rating);
              Navigator.of(context).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRating(
      String taskId, String userId, double rating) async {
    try {
      await _firestore.collection('ratings').add({
        'taskId': taskId,
        'userId': userId,
        'rating': rating,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted')),
        );
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Handle empty groupId scenario gracefully
    if (widget.groupId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No group selected',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Filter tasks based on completion status if needed
    final displayTasks = _showCompleted
        ? _tasks
        : _tasks.where((task) => !(task['completed'] ?? false)).toList();

    if (displayTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.showAll
                  ? 'No tasks in this group yet'
                  : 'No tasks assigned to you in this group',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (_isGroupLeader) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showAddTaskDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Create Task'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filter options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Show/hide completed tasks toggle
              Row(
                children: [
                  const Text('Show completed:'),
                  Switch(
                    value: _showCompleted,
                    onChanged: (value) {
                      setState(() {
                        _showCompleted = value;
                      });
                    },
                  ),
                ],
              ),

              // Add task button for group leaders
              if (_isGroupLeader)
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: () => _showAddTaskDialog(context),
                  tooltip: 'Add Task',
                ),
            ],
          ),
        ),

        // Task list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: displayTasks.length,
            itemBuilder: (context, index) {
              final task = displayTasks[index];
              final bool isCompleted = task['completed'] ?? false;
              final dueDate = (task['dueDate'] as Timestamp).toDate();
              final bool isOverdue =
                  !isCompleted && DateTime.now().isAfter(dueDate);
              final bool isAssignedToMe = task['assignedTo'] == widget.userId;
              final assigneeName = task['assignedToName'] ?? 'Unknown';

              // Show task status
              String statusText = isCompleted
                  ? 'Completed'
                  : isOverdue
                      ? 'Overdue'
                      : 'In Progress';
              Color statusColor = isCompleted
                  ? Colors.green
                  : isOverdue
                      ? Colors.red
                      : Colors.blue;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: isAssignedToMe
                          ? Checkbox(
                              value: isCompleted,
                              onChanged: (bool? value) {
                                if (value != null) {
                                  _toggleTaskCompletion(task['id'], value);
                                }
                              },
                            )
                          : Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: isCompleted ? Colors.green : Colors.grey,
                            ),
                      title: Text(
                        task['title'],
                        style: TextStyle(
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                          fontWeight: isOverdue && !isCompleted
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (task['description'] != null &&
                              task['description'].toString().isNotEmpty)
                            Text(task['description']),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Due: ${DateFormat('MMM d, y - h:mm a').format(dueDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isOverdue && !isCompleted
                                      ? Colors.red
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.person, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Assigned to: $assigneeName',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    if (_isGroupLeader)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Only show edit for non-completed tasks
                            if (!isCompleted)
                              IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue),
                                tooltip: 'Edit Task',
                                onPressed: () =>
                                    _showEditTaskDialog(context, task),
                              ),
                            // Leaders can rate tasks
                            if (isCompleted)
                              IconButton(
                                icon: const Icon(Icons.star_border,
                                    color: Colors.amber),
                                tooltip: 'Rate Task',
                                onPressed: () => _showLeaderRatingDialog(
                                    context, task['id'], task['assignedTo']),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Task',
                              onPressed: () => _deleteTask(task['id']),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TaskDialog(
        databaseService: _databaseService,
        initialDate: DateTime.now(),
        groupId: widget.groupId,
        currentUserId: widget.userId,
        membersList: _membersList,
      ),
    ).then((_) => _loadTasks());
  }

  void _showEditTaskDialog(BuildContext context, Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (context) => TaskDialog(
        databaseService: _databaseService,
        initialDate: (task['dueDate'] as Timestamp).toDate(),
        groupId: widget.groupId,
        currentUserId: widget.userId,
        taskToEdit: task,
        taskId: task['id'],
        membersList: _membersList,
      ),
    ).then((_) => _loadTasks());
  }

  void _showLeaderRatingDialog(
      BuildContext context, String taskId, String assigneeId) async {
    double rating = 3.0;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rate Member Performance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How well did this member perform this task?'),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      IconButton(
                        icon: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = i.toDouble();
                          });
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Rating is anonymous and will help improve team performance',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _submitRating(taskId, assigneeId, rating);
              Navigator.of(context).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
