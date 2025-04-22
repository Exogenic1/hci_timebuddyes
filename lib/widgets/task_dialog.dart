import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:time_buddies/services/database_service.dart';

class TaskDialog extends StatefulWidget {
  final DatabaseService databaseService;
  final DateTime? initialDate;
  final Map<String, dynamic>? taskToEdit;
  final String? taskId;
  final String groupId;
  final String currentUserId;
  final List<Map<String, dynamic>> membersList; // Add this parameter

  const TaskDialog({
    super.key,
    required this.databaseService,
    this.initialDate,
    this.taskToEdit,
    this.taskId,
    required this.groupId,
    required this.currentUserId,
    this.membersList = const [], // Default to empty list
  });

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _status = 'In-Progress'; // Default status is now In-Progress
  String? _assignedToUserId;
  bool _isLoading = false;
  String _assignedToUserName = 'Select Member';
  List<Map<String, dynamic>> _members = [];

  // Changed to only two options
  final List<String> _statusOptions = ['In-Progress', 'Completed'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _members = List.from(widget.membersList);

    // If there's only one member in the group, auto-select them
    if (_members.length == 1) {
      _assignedToUserId = _members.first['userId'];
      _assignedToUserName = _members.first['name'];
    }

    if (widget.taskToEdit != null) {
      _titleController.text = widget.taskToEdit!['title'] ?? '';
      _descriptionController.text = widget.taskToEdit!['description'] ?? '';
      if (widget.taskToEdit!['dueDate'] != null) {
        _selectedDate = (widget.taskToEdit!['dueDate'] as Timestamp).toDate();
      }
      // Use the existing status or default to In-Progress
      _status = widget.taskToEdit!['status'] ?? 'In-Progress';
      _assignedToUserId = widget.taskToEdit!['assignedTo'];

      _loadAssignedUserDetails();
    }

    if (_members.isEmpty) {
      _loadGroupMembers();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // In _TaskDialogState
  Future<void> _loadGroupMembers() async {
    if (_isLoading || widget.groupId.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final membersList =
          await widget.databaseService.getGroupMembers(widget.groupId);

      if (mounted) {
        setState(() {
          _members = membersList;
          _isLoading = false;

          // Auto-select current user if they're in the group
          final currentUserInGroup = _members.firstWhere(
            (m) => m['userId'] == widget.currentUserId,
            orElse: () => {},
          );

          if (currentUserInGroup.isNotEmpty) {
            _assignedToUserId = widget.currentUserId;
            _assignedToUserName = currentUserInGroup['name'];
          }
          // Otherwise select first member if exists
          else if (_members.isNotEmpty) {
            _assignedToUserId = _members.first['userId'];
            _assignedToUserName = _members.first['name'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading group members: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading members: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadAssignedUserDetails() async {
    if (_assignedToUserId == null) return;

    // First check if the user is in the members list we already have
    final assignedMember = _members.firstWhere(
      (member) => member['userId'] == _assignedToUserId,
      orElse: () => {'userId': '', 'name': ''},
    );

    if (assignedMember['userId'].isNotEmpty) {
      setState(() {
        _assignedToUserName = assignedMember['name'];
      });
      return;
    }

    // If not found in list, fetch from Firestore
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_assignedToUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        if (userData != null && mounted) {
          setState(() {
            _assignedToUserName = userData['name'] ?? 'Unknown User';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading assigned user: $e');
    }
  }

  Future<void> _saveTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task title is required')),
      );
      return;
    }

    // Only validate assigned user if we have more than one member
    if (_members.length > 1 && _assignedToUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please assign the task to a member')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Make sure we have an assigned user, even if just one member
      final String assignedTo = _assignedToUserId ??
          (_members.isNotEmpty
              ? _members.first['userId']
              : widget.currentUserId);

      final taskData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'dueDate': Timestamp.fromDate(_selectedDate),
        'status': _status,
        'assignedTo': assignedTo,
        'groupID': widget.groupId,
        'createdBy': widget.currentUserId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.taskId != null) {
        // Update existing task
        await FirebaseFirestore.instance
            .collection('tasks')
            .doc(widget.taskId)
            .update(taskData);
      } else {
        // Create new task
        taskData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('tasks').add(taskData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  widget.taskId != null ? 'Task updated' : 'Task created')),
        );
      }
    } catch (e) {
      debugPrint('Error saving task: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.taskId != null ? 'Edit Task' : 'Add Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due Date'),
              subtitle: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                  );
                  if (pickedDate != null && mounted) {
                    setState(() => _selectedDate = pickedDate);
                  }
                },
              ),
            ),

            // Removed status dropdown - it will default to In-Progress
            // We'll keep it for editing existing tasks to allow toggling to Completed
            if (widget.taskToEdit != null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                value: _status,
                items: _statusOptions.map((status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _status = value);
                  }
                },
              ),
            ],

            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_members.isEmpty)
              const Text('No members available')
            else if (_members.length == 1)
              // For single member groups, just show who the task is assigned to
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Assigned To',
                  border: OutlineInputBorder(),
                ),
                child: Text(_assignedToUserName),
              )
            else
              // For multiple members, show the dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Assigned To', style: TextStyle(fontSize: 12)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _assignedToUserId,
                    hint: Text(_assignedToUserName),
                    items: _members.map((member) {
                      return DropdownMenuItem<String>(
                        value: member['userId'],
                        child: Text('${member['name']} (${member['email']})'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        final selectedMember = _members.firstWhere(
                          (m) => m['userId'] == value,
                          orElse: () =>
                              {'userId': value, 'name': 'Unknown User'},
                        );
                        setState(() {
                          _assignedToUserId = value;
                          _assignedToUserName = selectedMember['name'];
                        });
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveTask,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.taskId != null ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
