import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:time_buddies/services/notifications_service.dart';
import 'package:time_buddies/services/task_service.dart';

class TaskDialog extends StatefulWidget {
  final DatabaseService databaseService;
  final DateTime initialDate;
  final String groupId;
  final String currentUserId;
  final Map<String, dynamic>? taskToEdit;
  final String? taskId;
  final List<Map<String, dynamic>> membersList;

  const TaskDialog({
    super.key,
    required this.databaseService,
    required this.initialDate,
    required this.groupId,
    required this.currentUserId,
    required this.membersList,
    this.taskToEdit,
    this.taskId,
  });

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String? _assignedUserId;
  String? _assignedUserName;
  bool _isLoading = false;
  late NotificationService _notificationService;
  late TaskService _taskService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notificationService =
        Provider.of<NotificationService>(context, listen: false);
    _taskService = TaskService(
      databaseService: widget.databaseService,
      notificationService: _notificationService,
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _selectedTime = TimeOfDay.now();

    // Initialize with current user as default if creating new task
    if (widget.taskToEdit == null) {
      _assignedUserId = widget.currentUserId;
      // Find current user in members list to get name
      final currentUser = widget.membersList.firstWhere(
        (member) => member['id'] == widget.currentUserId,
        orElse: () => {'id': widget.currentUserId, 'name': 'Myself'},
      );
      _assignedUserName = currentUser['name'];
    } else {
      // If editing an existing task, populate the form fields
      _titleController.text = widget.taskToEdit!['title'] ?? '';
      _descriptionController.text = widget.taskToEdit!['description'] ?? '';

      final dueDate = (widget.taskToEdit!['dueDate'] as Timestamp).toDate();
      _selectedDate = dueDate;
      _selectedTime = TimeOfDay(hour: dueDate.hour, minute: dueDate.minute);

      _assignedUserId = widget.taskToEdit!['assignedTo'] as String?;
      _assignedUserName = widget.taskToEdit!['assignedToName'] as String?;

      // If we have an assignedUserId but no name, fetch the name
      if (_assignedUserId != null && _assignedUserName == null) {
        _fetchUserName(_assignedUserId!);
      }
    }
  }

  Future<void> _fetchUserName(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists && mounted) {
        setState(() {
          _assignedUserName = userDoc.get('name') ?? 'Unknown User';
        });
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime && mounted) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _assignMember() async {
    // Get current user details
    final currentUser = widget.membersList.firstWhere(
      (member) => member['id'] == widget.currentUserId,
      orElse: () => {'id': widget.currentUserId, 'name': 'Myself', 'email': ''},
    );

    // Create a new list with current user first
    final allMembers = [
      currentUser,
      ...widget.membersList
          .where((member) => member['id'] != widget.currentUserId)
    ];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Member'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allMembers.length,
              itemBuilder: (context, index) {
                final member = allMembers[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      member['id'] == widget.currentUserId
                          ? Icons.person
                          : Icons.person_outline,
                    ),
                  ),
                  title: Text(member['name'] ?? 'Unknown User'),
                  subtitle: Text(member['email'] ?? ''),
                  selected: member['id'] == _assignedUserId,
                  onTap: () {
                    setState(() {
                      _assignedUserId = member['id'];
                      _assignedUserName = member['name'];
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_assignedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please assign a member to this task')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Combine date and time
      final dueDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      // Use the TaskService instead of direct Firestore operations
      if (widget.taskId != null) {
        // Update existing task
        await _taskService.updateTask(
          taskId: widget.taskId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          dueDate: dueDate,
          assignedTo: _assignedUserId!,
          assignedToName: _assignedUserName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task updated successfully')),
          );
        }
      } else {
        // Create new task
        await _taskService.createTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          dueDate: dueDate,
          assignedTo: _assignedUserId!,
          assignedToName: _assignedUserName,
          groupId: widget.groupId,
          createdBy: widget.currentUserId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task created successfully')),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error saving task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.taskId == null ? 'Create New Task' : 'Edit Task',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.task),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Due Date',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            DateFormat('MMM d, y').format(_selectedDate),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.access_time),
                          ),
                          child: Text(
                            _selectedTime.format(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _assignMember,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Assign To',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_add),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_assignedUserName ?? 'Select a member'),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveTask,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.taskId == null ? 'Create' : 'Update'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
