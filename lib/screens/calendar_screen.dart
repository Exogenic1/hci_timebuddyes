import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/widgets/task_dialog.dart';
import 'package:time_buddies/widgets/confirmation_dialog.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<String> _userGroups = [];
  bool _isLoading = true;
  String? _selectedGroupId;
  Map<String, bool> _groupLeadership = {};
  Map<String, String> _groupNames = {};
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _groupsSubscription;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _setupAuthListener();
    _loadInitialData();
  }

  void _setupAuthListener() {
    _authSubscription = _auth.authStateChanges().listen((user) async {
      if (user != null && mounted) {
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        final validationService = DataValidationService();

        // Validate user data and groups
        await validationService.validateUserData(user.uid);
        await validationService.validateAllUserGroups(user.uid);

        // Load the groups data
        await _loadUserGroups();
      } else if (mounted) {
        setState(() {
          _userGroups = [];
          _selectedGroupId = null;
          _events = {};
          _groupLeadership = {};
          _groupNames = {};
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _loadInitialData() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _loadUserGroups();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserGroups() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    _groupsSubscription?.cancel(); // Cancel any existing subscription

    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Use a stream to keep groups updated in real-time
      _groupsSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((userDoc) async {
        if (!userDoc.exists) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }

        final userData = userDoc.data() as Map<String, dynamic>;
        final groups = (userData['groups'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            [];

        if (groups.isEmpty) {
          if (mounted) {
            setState(() {
              _userGroups = [];
              _selectedGroupId = null;
              _groupNames = {};
              _groupLeadership = {};
              _isLoading = false;
            });
          }
          return;
        }

        // Load group details in parallel
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
                (groupData['leaderId']?.toString() ?? '') == user.uid;
            validGroups.add(groupId);
          }
        }

        if (!mounted) return;
        setState(() {
          _userGroups = validGroups;
          _groupNames = newNamesMap;
          _groupLeadership = newLeadershipMap;
          // Preserve selected group if it still exists, otherwise select first
          _selectedGroupId = _userGroups.contains(_selectedGroupId)
              ? _selectedGroupId
              : (_userGroups.isNotEmpty ? _userGroups.first : null);
          _isLoading = false;
        });

        if (_selectedGroupId != null) {
          await _loadEvents();
        }
      });
    } catch (e) {
      debugPrint('Error loading groups: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: ${e.toString()}')),
        );
      }
    }
  }

  // In calendar_screen.dart - update the _loadEvents() method

  Future<void> _loadEvents() async {
    if (_selectedGroupId == null) return;
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final isLeader = _groupLeadership[_selectedGroupId] ?? false;
      Query query = _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId);

      // If not leader, only show tasks assigned to current user
      if (!isLeader) {
        query = query.where('assignedTo', isEqualTo: user.uid);
      }

      // Only show incomplete tasks in calendar view
      query = query.where('completed', isEqualTo: false);

      final querySnapshot = await query.get();

      final newEvents = <DateTime, List<Map<String, dynamic>>>{};
      for (var doc in querySnapshot.docs) {
        final task = doc.data();
        final dueDate =
            ((task as Map<String, dynamic>)['dueDate'] as Timestamp).toDate();
        final dateKey = DateTime(dueDate.year, dueDate.month, dueDate.day);

        // Check if the task is overdue but not completed
        final isLate =
            dueDate.isBefore(DateTime.now()) && !(task['completed'] ?? false);

        if (!newEvents.containsKey(dateKey)) {
          newEvents[dateKey] = [];
        }
        newEvents[dateKey]!.add({
          ...task,
          'id': doc.id,
          'isLate': isLate,
        });
      }

      if (mounted) {
        setState(() => _events = newEvents);
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _groupsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _addTask(DateTime selectedDate) async {
    if (_selectedGroupId == null) return;

    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to add tasks')),
        );
      }
      return;
    }

    // Check if user is leader
    if (!(_groupLeadership[_selectedGroupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can add tasks')),
        );
      }
      return;
    }

    try {
      // Get group members using the new method
      final membersList =
          await databaseService.getGroupMembers(_selectedGroupId!);

      if (membersList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No members found in this group')),
          );
        }
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => TaskDialog(
          databaseService: databaseService,
          initialDate: selectedDate,
          groupId: _selectedGroupId!,
          currentUserId: user.uid,
          membersList: membersList,
        ),
      );

      if (mounted) {
        await _loadEvents();
      }
    } catch (e) {
      debugPrint('Error adding task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding task: ${e.toString()}')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final isLeader = _selectedGroupId != null &&
        (_groupLeadership[_selectedGroupId] ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Calendar'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserGroups,
          )
        ],
      ),
      body: _auth.currentUser == null
          ? const Center(child: Text('Please sign in'))
          : SafeArea(
              child: Column(
                children: [
                  if (isLeader) _LeaderIndicator(),
                  GroupSelector(
                    isLoading: _isLoading,
                    userGroups: _userGroups,
                    selectedGroupId: _selectedGroupId,
                    groupNames: _groupNames,
                    groupLeadership: _groupLeadership,
                    onGroupChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() => _selectedGroupId = newValue);
                        _loadEvents();
                      }
                    },
                  ),
                  Expanded(
                    child: _selectedGroupId == null
                        ? const Center(child: Text('Select a group'))
                        : CalendarContent(
                            focusedDay: _focusedDay,
                            selectedDay: _selectedDay,
                            calendarFormat: _calendarFormat,
                            getEventsForDay: _getEventsForDay,
                            onDaySelected: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                              });
                            },
                            onFormatChanged: (format) {
                              setState(() {
                                _calendarFormat = format;
                              });
                            },
                            onPageChanged: (focusedDay) {
                              _focusedDay = focusedDay;
                            },
                            isLeader: isLeader,
                            onAddTask: () =>
                                _addTask(_selectedDay ?? DateTime.now()),
                            taskList: _selectedDay == null
                                ? null
                                : TaskList(
                                    selectedDay: _selectedDay!,
                                    events: _getEventsForDay(_selectedDay!),
                                    isLeader: isLeader,
                                    onAddTask: () => _addTask(_selectedDay!),
                                    onCompleteTask: _completeTask,
                                    onDeleteTask: _deleteTask,
                                    firestore: _firestore,
                                  ),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _selectedGroupId != null &&
              (_groupLeadership[_selectedGroupId] ?? false)
          ? FloatingActionButton(
              onPressed: () => _addTask(_selectedDay ?? DateTime.now()),
              tooltip: 'Add Task',
              child: const Icon(Icons.add),
            )
          : null,
      resizeToAvoidBottomInset: true,
    );
  }

  Future<void> _completeTask(String taskId, bool isComplete) async {
    if (_selectedGroupId == null) return;
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Get the task document first to check its details
      final taskDoc = await _firestore.collection('tasks').doc(taskId).get();
      final taskData = taskDoc.data() as Map<String, dynamic>;

      // Check if task is already locked (completed previously)
      if (taskData['locked'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This task is already completed and locked')),
        );
        return;
      }

      // Determine the status based on completion and due date
      final dueDate = (taskData['dueDate'] as Timestamp).toDate();
      String status;

      if (isComplete) {
        // If completing the task
        if (DateTime.now().isAfter(dueDate)) {
          status = 'Late';
        } else {
          status = 'Completed';
        }
      } else {
        // If marking as incomplete (should not happen if locked)
        status = 'Incomplete';
      }

      // Update the task with new status and lock if completed
      await _firestore.collection('tasks').doc(taskId).update({
        'completed': isComplete,
        'completedAt': isComplete ? FieldValue.serverTimestamp() : null,
        'status': status,
        'locked': isComplete, // Lock the task if it's being completed
      });

      await _loadEvents(); // Reload calendar events

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task marked as $status')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating task: ${e.toString()}')),
      );
    }
  }

  Future<void> _deleteTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const ConfirmationDialog(
        title: 'Delete Task',
        content: 'Are you sure you want to delete this task?',
      ),
    );

    if (confirmed != true) return;

    try {
      await _firestore.collection('tasks').doc(taskId).delete();
      _loadEvents();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting task: ${e.toString()}')),
      );
    }
  }
}

// EXTRACTED WIDGETS

class _LeaderIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.amber[100],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star, size: 16, color: Colors.amber),
          SizedBox(width: 8),
          Text('You are the group leader'),
        ],
      ),
    );
  }
}

class GroupSelector extends StatelessWidget {
  final bool isLoading;
  final List<String> userGroups;
  final String? selectedGroupId;
  final Map<String, String> groupNames;
  final Map<String, bool> groupLeadership;
  final Function(String?) onGroupChanged;

  const GroupSelector({
    Key? key,
    required this.isLoading,
    required this.userGroups,
    required this.selectedGroupId,
    required this.groupNames,
    required this.groupLeadership,
    required this.onGroupChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userGroups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Join or create a group in the Collaborate tab'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
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
                value: selectedGroupId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                items: userGroups.map((groupId) {
                  return DropdownMenuItem<String>(
                    value: groupId,
                    child: Text(
                      groupNames[groupId] ?? 'Unnamed Group',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onGroupChanged,
              ),
              if (selectedGroupId != null &&
                  groupLeadership.containsKey(selectedGroupId))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    groupLeadership[selectedGroupId] == true
                        ? 'You are the leader'
                        : 'You are a member',
                    style: TextStyle(
                      color: groupLeadership[selectedGroupId] == true
                          ? Colors.green
                          : Colors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CalendarContent extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final List<Map<String, dynamic>> Function(DateTime) getEventsForDay;
  final Function(DateTime, DateTime) onDaySelected;
  final Function(CalendarFormat) onFormatChanged;
  final Function(DateTime) onPageChanged;
  final bool isLeader;
  final VoidCallback onAddTask;
  final Widget? taskList;

  const CalendarContent({
    Key? key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.getEventsForDay,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onPageChanged,
    required this.isLeader,
    required this.onAddTask,
    required this.taskList,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        mediaQuery.viewInsets.bottom;

    return LayoutBuilder(builder: (context, constraints) {
      // Calculate maximum height for calendar based on available space
      double maxCalendarHeight = isKeyboardOpen
          ? constraints.maxHeight * 0.6
          : constraints.maxHeight * 0.7;

      // Ensure maxHeight is never smaller than minHeight
      maxCalendarHeight = maxCalendarHeight.clamp(200, double.infinity);

      return Column(
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxCalendarHeight,
                minHeight: 200,
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: focusedDay,
                  calendarFormat: isKeyboardOpen
                      ? CalendarFormat
                          .week // Force week view when keyboard is open
                      : calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                  onDaySelected: onDaySelected,
                  onFormatChanged: onFormatChanged,
                  onPageChanged: onPageChanged,
                  eventLoader: getEventsForDay,
                  calendarStyle: CalendarStyle(
                    markerDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    markerSize: 8,
                    markerMargin: const EdgeInsets.symmetric(horizontal: 1),
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible:
                        !isKeyboardOpen, // Hide format button when keyboard is open
                    titleCentered: true,
                    formatButtonDecoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).primaryColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    formatButtonTextStyle:
                        TextStyle(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
            ),
          ),
          // Flexible task list that can scroll and resize
          Expanded(
            child: taskList ??
                const Center(child: Text('Select a date to view tasks')),
          ),
        ],
      );
    });
  }
}

class TaskList extends StatelessWidget {
  final DateTime selectedDay;
  final List<Map<String, dynamic>> events;
  final bool isLeader;
  final VoidCallback onAddTask;
  final Function(String, bool) onCompleteTask;
  final Function(String) onDeleteTask;
  final FirebaseFirestore firestore;

  const TaskList({
    super.key,
    required this.selectedDay,
    required this.events,
    required this.isLeader,
    required this.onAddTask,
    required this.onCompleteTask,
    required this.onDeleteTask,
    required this.firestore,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isLeader = this.isLeader;

    // Filter tasks for members - only show their assigned tasks
    final visibleTasks = isLeader
        ? events
        : events.where((task) => task['assignedTo'] == currentUserId).toList();

    if (visibleTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_note, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  isLeader
                      ? 'No tasks for ${DateFormat('MMM d, y').format(selectedDay)}'
                      : 'No tasks assigned to you for ${DateFormat('MMM d, y').format(selectedDay)}',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                if (isLeader) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onAddTask,
                    child: const Text('Add Task'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: visibleTasks.length,
      itemBuilder: (context, index) {
        final task = visibleTasks[index];
        final bool isCompleted = task['completed'] ?? false;
        final bool isLocked = task['locked'] ?? false;
        final bool isLate = task['isLate'] ?? false;
        final isAssignedToMe = task['assignedTo'] == currentUserId;
        final dueDate = (task['dueDate'] as Timestamp).toDate();

        // Determine status display
        String statusText = 'Incomplete';
        Color statusColor = Colors.orange;

        if (isCompleted) {
          statusText = DateTime.now().isAfter(dueDate) ? 'Late' : 'Completed';
          statusColor = statusText == 'Late' ? Colors.red : Colors.green;
        } else if (isLate) {
          statusText = 'Overdue';
          statusColor = Colors.red;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              ListTile(
                leading: isAssignedToMe || isLeader
                    ? Checkbox(
                        value: isCompleted,
                        onChanged: isLocked
                            ? null // Disable checkbox if task is locked
                            : (bool? value) {
                                if (value != null) {
                                  onCompleteTask(task['id'], value);
                                }
                              },
                      )
                    : const Icon(Icons.lock, color: Colors.grey),
                title: Text(
                  task['title'],
                  style: TextStyle(
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task['description'] ?? ''),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Due: ${DateFormat('MMM d, y').format(dueDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isLate ? Colors.red : Colors.black54,
                            fontWeight:
                                isLate ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    FutureBuilder<DocumentSnapshot>(
                      future: firestore
                          .collection('users')
                          .doc(task['assignedTo'])
                          .get(),
                      builder: (context, snapshot) {
                        // Handle loading state
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Text('Loading assignee...');
                        }

                        // Handle error or non-existent document
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Text('Assignee: Unknown',
                              style: TextStyle(fontStyle: FontStyle.italic));
                        }

                        // Safely get the name with fallbacks
                        final assigneeName =
                            snapshot.data!.get('name')?.toString() ?? 'Unknown';
                        return Text(
                          'Assigned to: $assigneeName',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        );
                      },
                    ),
                  ],
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              if (isLeader)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Add rating button
                      IconButton(
                        icon:
                            const Icon(Icons.star_border, color: Colors.amber),
                        tooltip: 'Rate Task',
                        onPressed: () => _showRatingDialog(
                            context, task['id'], task['assignedTo']),
                      ),
                      // Delete button
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Delete Task',
                        onPressed: () => onDeleteTask(task['id']),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Method to show the rating dialog
  void _showRatingDialog(
      BuildContext context, String taskId, String assigneeId) async {
    double rating = 3.0; // Default rating

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
              _submitRating(context, taskId, assigneeId, rating);
              Navigator.of(context).pop();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // Method to submit the rating
  Future<void> _submitRating(
      BuildContext context, String taskId, String userId, double rating) async {
    try {
      // Add rating to the ratings collection
      await firestore.collection('ratings').add({
        'taskId': taskId,
        'userId': userId,
        'rating': rating,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update the user's average rating
      final userRatings = await firestore
          .collection('ratings')
          .where('userId', isEqualTo: userId)
          .get();

      if (userRatings.docs.isNotEmpty) {
        double totalRating = 0;
        for (var doc in userRatings.docs) {
          totalRating += (doc.data()['rating'] as num).toDouble();
        }

        final averageRating = totalRating / userRatings.docs.length;

        await firestore.collection('users').doc(userId).update({
          'averageRating': averageRating,
          'totalRatings': userRatings.docs.length,
        });
      }

      // Check if context is still mounted before showing snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted anonymously')),
        );
      }
    } catch (e) {
      // Also check here
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: ${e.toString()}')),
        );
      }
    }
  }
}
