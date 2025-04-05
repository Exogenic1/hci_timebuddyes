import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
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
  List<String> _userGroups = [];
  bool _isLoading = true;
  bool _showGroupTasks = false;
  String? _selectedGroupId;
  Map<String, bool> _groupLeadership = {};
  Map<String, String> _groupNames = {};
  Map<String, String> _groupLeaders = {};

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
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        final groups = userData?['groups'] is List
            ? List<String>.from(userData!['groups'] ?? [])
            : [];

        final leadershipMap = <String, bool>{};
        final namesMap = <String, String>{};
        final leadersMap = <String, String>{};

        // Load group details in parallel
        final groupFutures = groups.map((groupId) async {
          try {
            final groupDoc =
                await _firestore.collection('groups').doc(groupId).get();
            if (groupDoc.exists) {
              final groupData = groupDoc.data() as Map<String, dynamic>?;
              final leaderId = groupData?['leaderId'] ?? '';
              leadershipMap[groupId] = leaderId == user.uid;
              namesMap[groupId] =
                  groupData?['name']?.toString() ?? 'Unnamed Group';
              leadersMap[groupId] = leaderId;
            }
          } catch (e) {
            debugPrint('Error loading group $groupId: $e');
          }
        });

        await Future.wait(groupFutures);

        if (!mounted) return;

        setState(() {
          _userGroups = groups.cast<String>();
          _groupLeadership = leadershipMap;
          _groupNames = namesMap;
          _groupLeaders = leadersMap;
          if (_userGroups.isNotEmpty) {
            _selectedGroupId = _userGroups.first;
          }
          if (_userGroups.isEmpty) {
            _showGroupTasks = false;
          }
          _isLoading = false;
        });
        _loadEvents();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

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

      if (!mounted) return;
      setState(() {
        _events = newEvents;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _addTask(DateTime selectedDate) async {
    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;

    if (_selectedGroupId == null || user == null) return;

    if (_showGroupTasks && !(_groupLeadership[_selectedGroupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can add tasks')),
        );
      }
      return;
    }

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

  Future<void> _deleteTask(String taskId, String? groupId) async {
    if (groupId != null && !(_groupLeadership[groupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can delete tasks')),
        );
      }
      return;
    }

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
          SnackBar(content: Text('Error deleting task: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _editTask(Map<String, dynamic> taskData, String taskId) async {
    final groupId = taskData['groupID'];
    if (groupId != null && !(_groupLeadership[groupId] ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only group leaders can edit tasks')),
        );
      }
      return;
    }

    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (context) => TaskDialog(
        databaseService: databaseService,
        taskToEdit: taskData,
        taskId: taskId,
        groupId: groupId,
      ),
    );
    _loadEvents();
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Widget _buildGroupSelector() {
    if (_userGroups.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Task View',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedGroupId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
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
                        setState(() {
                          _selectedGroupId = newValue;
                          _loadEvents();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: [
                      Text(
                        _showGroupTasks ? 'Group Tasks' : 'My Tasks',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Switch(
                        value: _showGroupTasks,
                        onChanged: (value) {
                          setState(() {
                            _showGroupTasks = value;
                            _loadEvents();
                          });
                        },
                        activeColor: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
              if (_showGroupTasks && _selectedGroupId != null)
                Text(
                  'You are ${_groupLeadership[_selectedGroupId] ?? false ? 'the leader' : 'a member'}',
                  style: TextStyle(
                    color: (_groupLeadership[_selectedGroupId] ?? false)
                        ? Colors.green
                        : Colors.blue,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your calendar...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        centerTitle: true,
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
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: TableCalendar(
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
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).primaryColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonTextStyle: TextStyle(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _selectedDay == null
                ? const Center(child: Text('Select a day to view tasks'))
                : _buildTaskList(),
          ),
        ],
      ),
      floatingActionButton: _userGroups.isNotEmpty &&
              (!_showGroupTasks ||
                  (_selectedGroupId != null &&
                      (_groupLeadership[_selectedGroupId] ?? false)))
          ? FloatingActionButton(
              onPressed: () => _addTask(_selectedDay ?? DateTime.now()),
              tooltip: 'Add Task',
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
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
            Icon(Icons.event_note, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No tasks for ${DateFormat('MMM d, y').format(_selectedDay!)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _addTask(_selectedDay!),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Add Task'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final task = events[index];
        final taskId = task['id'];
        final groupId = task['groupID'];
        final isLeader =
            groupId != null ? (_groupLeadership[groupId] ?? false) : true;
        final isAssignedToMe =
            task['assignedTo'] == FirebaseAuth.instance.currentUser?.uid;

        Color statusColor = Colors.grey;
        if (task['status'] == 'Pending') statusColor = Colors.orange;
        if (task['status'] == 'In Progress') statusColor = Colors.blue;
        if (task['status'] == 'Completed') statusColor = Colors.green;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        task['title'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isLeader || isAssignedToMe)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit,
                                color: Theme.of(context).primaryColor),
                            onPressed: () => _editTask(task, taskId),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteTask(taskId, groupId),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                  ],
                ),
                if (task['description'] != null &&
                    task['description'].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      task['description'],
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        task['status'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: statusColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    if (_showGroupTasks && !isAssignedToMe)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(task['assignedTo'])
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final userData =
                                snapshot.data!.data() as Map<String, dynamic>;
                            return Chip(
                              label: Text(
                                userData['name'] ?? 'Member',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: Colors.purple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    Chip(
                      label: Text(
                        DateFormat('MMM d, y')
                            .format((task['dueDate'] as Timestamp).toDate()),
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      backgroundColor:
                          Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
