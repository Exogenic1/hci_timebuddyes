import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/services/notifications_service.dart';
import 'package:time_buddies/services/task_service.dart';
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
  DatabaseService? _databaseService;
  DataValidationService? _validationService;
  TaskService? _taskService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store references to services in didChangeDependencies
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _validationService = DataValidationService();

    final notificationService =
        Provider.of<NotificationService>(context, listen: false);
    _taskService = TaskService(
      databaseService: _databaseService!,
      notificationService: notificationService,
    );
  }

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
        // Use stored references instead of getting from context
        await _validationService?.validateUserData(user.uid);
        await _validationService?.validateAllUserGroups(user.uid);
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
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserGroups() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    _groupsSubscription?.cancel();

    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
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

  Future<void> _loadEvents() async {
    if (_selectedGroupId == null) return;
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final isLeader = _groupLeadership[_selectedGroupId] ?? false;
      Query query = _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId);

      if (!isLeader) {
        query = query.where('assignedTo', isEqualTo: user.uid);
      }

      query = query.where('completed', isEqualTo: false);

      final querySnapshot = await query.get();

      // Get all unique user IDs from the tasks
      final userIds = querySnapshot.docs
          .map((doc) =>
              (doc.data() as Map<String, dynamic>)['assignedTo'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      // Fetch user names in a batch
      final userNames = <String, String>{};
      if (userIds.isNotEmpty) {
        final usersSnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: userIds)
            .get();

        for (var doc in usersSnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          userNames[doc.id] =
              data['name']?.toString() ?? 'Unknown'; // Safe access
        }
      }

      final newEvents = <DateTime, List<Map<String, dynamic>>>{};
      for (var doc in querySnapshot.docs) {
        final task = doc.data() as Map<String, dynamic>;
        final dueDate = task['dueDate'] is Timestamp
            ? (task['dueDate'] as Timestamp).toDate()
            : DateTime.now(); // Fallback
        final dateKey = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final isLate =
            dueDate.isBefore(DateTime.now()) && !(task['completed'] ?? false);
        final assignedTo = task['assignedTo']?.toString() ?? ''; // Safe access

        if (!newEvents.containsKey(dateKey)) {
          newEvents[dateKey] = [];
        }

        newEvents[dateKey]!.add({
          ...task,
          'id': doc.id,
          'isLate': isLate,
          'assignedToName': assignedTo.isNotEmpty
              ? userNames[assignedTo] ?? 'Unknown'
              : 'Unassigned',
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

  Future<void> _addTask(DateTime selectedDate) async {
    if (_selectedGroupId == null) return;

    // Use stored database service reference
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to add tasks')),
        );
      }
      return;
    }

    if (!(_groupLeadership[_selectedGroupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can add tasks')),
        );
      }
      return;
    }

    try {
      final membersList =
          await _databaseService?.getGroupMembers(_selectedGroupId!);

      if (membersList == null || membersList.isEmpty) {
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
          databaseService: _databaseService!,
          initialDate: selectedDate,
          groupId: _selectedGroupId!,
          currentUserId: user.uid,
          membersList: membersList,
        ),
      );

      if (mounted) {
        // Reload events after adding a task
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

  @override
  void dispose() {
    _authSubscription?.cancel();
    _groupsSubscription?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Future<void> _completeTask(String taskId, bool isComplete) async {
    try {
      // Use TaskService instead of direct Firestore operation
      await _taskService?.markTaskComplete(taskId, isComplete);

      // Reload events after completing a task
      await _loadEvents();

      // If marking as complete, show feedback
      if (isComplete && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task completed successfully!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      bool confirm = await showDialog(
            context: context,
            builder: (context) => const ConfirmationDialog(
              title: 'Delete Task',
              content: 'Are you sure you want to delete this task?',
            ),
          ) ??
          false;

      if (confirm) {
        // Use TaskService instead of direct Firestore operation
        await _taskService?.deleteTask(taskId);
        await _loadEvents();
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    if (_selectedGroupId == null) return;
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to edit tasks')),
        );
      }
      return;
    }

    if (!(_groupLeadership[_selectedGroupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can edit tasks')),
        );
      }
      return;
    }

    try {
      final membersList =
          await _databaseService?.getGroupMembers(_selectedGroupId!);

      if (membersList == null || membersList.isEmpty) {
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
          databaseService: _databaseService!,
          initialDate: (task['dueDate'] as Timestamp).toDate(),
          groupId: _selectedGroupId!,
          currentUserId: user.uid,
          membersList: membersList,
          taskToEdit: task,
          taskId: task['id'],
        ),
      );

      if (mounted) {
        // Reload events after editing a task
        await _loadEvents();
      }
    } catch (e) {
      debugPrint('Error editing task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error editing task: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Replace the existing AppBar in your build method with this:
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          if (_userGroups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGroupId,
                    onChanged: (value) {
                      if (value != null && value != _selectedGroupId) {
                        setState(() => _selectedGroupId = value);
                        _loadEvents();
                      }
                    },
                    items: _userGroups.map((groupId) {
                      return DropdownMenuItem<String>(
                        value: groupId,
                        child: Row(
                          children: [
                            Icon(
                              Icons.group,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _groupNames[groupId] ?? 'Unknown Group',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (_groupLeadership[groupId] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    dropdownColor: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 2,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userGroups.isEmpty
              ? const Center(
                  child: Text('Join or create a group to see your tasks'),
                )
              : Column(
                  children: [
                    TableCalendar(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) {
                        return isSameDay(_selectedDay, day);
                      },
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
                      eventLoader: _getEventsForDay,
                      calendarStyle: CalendarStyle(
                        markerDecoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    if (_selectedDay != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tasks for ${DateFormat('MMM d, yyyy').format(_selectedDay!)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (_groupLeadership[_selectedGroupId] == true)
                              ElevatedButton.icon(
                                onPressed: () => _addTask(_selectedDay!),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Task'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Expanded(
                        child: _getEventsForDay(_selectedDay!).isEmpty
                            ? const Center(
                                child: Text('No tasks for this day'),
                              )
                            : ListView.builder(
                                itemCount:
                                    _getEventsForDay(_selectedDay!).length,
                                itemBuilder: (context, index) {
                                  final task =
                                      _getEventsForDay(_selectedDay!)[index];
                                  final bool isCompleted =
                                      task['completed'] ?? false;
                                  final bool isLate = task['isLate'] ?? false;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 4.0,
                                    ),
                                    color: isCompleted
                                        ? Colors.green.shade100
                                        : isLate
                                            ? Colors.red.shade100
                                            : null,
                                    child: ListTile(
                                      title: Text(
                                        task['title'] ?? 'No Title',
                                        style: TextStyle(
                                          decoration: isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(task['description'] ??
                                              'No description'),
                                          const SizedBox(height: 4),
                                          // Show assigned user's name (future enhancement)
                                          Text(
                                            'Assigned to: ${task['assignedToName']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Complete/Uncomplete checkbox
                                          Checkbox(
                                            value: isCompleted,
                                            onChanged: (value) {
                                              if (value != null) {
                                                _completeTask(
                                                    task['id'], value);
                                              }
                                            },
                                          ),
                                          // Edit button (only for group leaders)
                                          if (_groupLeadership[
                                                  _selectedGroupId] ==
                                              true)
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              onPressed: () => _editTask(task),
                                            ),
                                          // Delete button (only for group leaders)
                                          if (_groupLeadership[
                                                  _selectedGroupId] ==
                                              true)
                                            IconButton(
                                              icon: const Icon(Icons.delete),
                                              onPressed: () =>
                                                  _deleteTask(task['id']),
                                            ),
                                        ],
                                      ),
                                      isThreeLine: true,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
