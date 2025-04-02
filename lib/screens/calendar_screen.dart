import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/widgets/task_dialog.dart';
import 'package:time_buddies/widgets/confirmation_dialog.dart';

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
  List<String> _userGroups = [];
  bool _isLoading = true;
  bool _showGroupTasks = false;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _loadUserGroups();
  }

  Future<void> _loadUserGroups() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _userGroups = List<String>.from(userDoc.data()?['groups'] ?? []);
          if (_userGroups.isNotEmpty) {
            _selectedGroupId = _userGroups.first;
          }
          _isLoading = false;
        });
        _loadEvents();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: $e')),
        );
      }
    }
  }

  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      QuerySnapshot querySnapshot;
      if (_showGroupTasks && _selectedGroupId != null) {
        querySnapshot = await _firestore
            .collection('tasks')
            .where('groupID', isEqualTo: _selectedGroupId)
            .get();
      } else {
        querySnapshot = await _firestore
            .collection('tasks')
            .where('assignedTo', isEqualTo: user.uid)
            .get();
      }

      final Map<DateTime, List<Map<String, dynamic>>> newEvents = {};
      for (var doc in querySnapshot.docs) {
        final task = doc.data() as Map<String, dynamic>;
        final dueDate = (task['dueDate'] as Timestamp).toDate();
        final dateKey = DateTime(dueDate.year, dueDate.month, dueDate.day);

        if (!newEvents.containsKey(dateKey)) {
          newEvents[dateKey] = [];
        }
        newEvents[dateKey]!.add({...task, 'id': doc.id});
      }

      setState(() {
        _events = newEvents;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }

  Future<void> _addTask(DateTime selectedDate) async {
    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => TaskDialog(
        databaseService: databaseService,
        initialDate: selectedDate,
        groupId: _showGroupTasks ? _selectedGroupId : null,
      ),
    );
    _loadEvents();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted successfully')),
        );
      }
      _loadEvents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: $e')),
        );
      }
    }
  }

  Future<void> _editTask(Map<String, dynamic> taskData, String taskId) async {
    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => TaskDialog(
        databaseService: databaseService,
        taskToEdit: taskData,
        taskId: taskId,
        groupId: taskData['groupID'],
      ),
    );
    _loadEvents();
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Widget _buildGroupSelector() {
    if (_userGroups.isEmpty) return const SizedBox();

    return FutureBuilder<QuerySnapshot>(
      future: _firestore
          .collection('groups')
          .where(FieldPath.documentId, whereIn: _userGroups)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final groups = snapshot.data!.docs;
        if (groups.isEmpty) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Text('Group: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedGroupId,
                items: groups.map((group) {
                  return DropdownMenuItem<String>(
                    value: group.id,
                    child: Text(group['name']),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGroupId = newValue;
                    _loadEvents();
                  });
                },
              ),
              const SizedBox(width: 16),
              Switch(
                value: _showGroupTasks,
                onChanged: (value) {
                  setState(() {
                    _showGroupTasks = value;
                    _loadEvents();
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(_showGroupTasks ? 'Group Tasks' : 'My Tasks'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view calendar')),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          if (_userGroups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadEvents,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildGroupSelector(),
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
              markerDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              markerSize: 8,
              markerMargin: const EdgeInsets.symmetric(horizontal: 1),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selectedDay == null
                ? const Center(child: Text('No day selected'))
                : _buildTaskList(),
          ),
        ],
      ),
      floatingActionButton: _userGroups.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _addTask(_selectedDay ?? DateTime.now()),
              child: const Icon(Icons.add),
              tooltip: 'Add Task',
            )
          : null,
    );
  }

  Widget _buildTaskList() {
    final events = _getEventsForDay(_selectedDay!);
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_note, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No tasks for this day'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _addTask(_selectedDay!),
              child: const Text('Add Task'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final task = events[index];
        final taskId = task['id'];

        Color statusColor = Colors.grey;
        if (task['status'] == 'Pending') statusColor = Colors.orange;
        if (task['status'] == 'In Progress') statusColor = Colors.blue;
        if (task['status'] == 'Completed') statusColor = Colors.green;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(task['title']),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task['description'] != null &&
                    task['description'].isNotEmpty)
                  Text(task['description']),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Chip(
                      label: Text(
                        task['status'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: statusColor,
                    ),
                    if (_showGroupTasks &&
                        task['assignedTo'] !=
                            FirebaseAuth.instance.currentUser?.uid)
                      const SizedBox(width: 8),
                    if (_showGroupTasks &&
                        task['assignedTo'] !=
                            FirebaseAuth.instance.currentUser?.uid)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(task['assignedTo'])
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Chip(
                              label: Text(
                                snapshot.data!['name'] ?? 'Member',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: Colors.purple,
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editTask(task, taskId),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteTask(taskId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
