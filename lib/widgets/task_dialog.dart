import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:intl/intl.dart';

class TaskDialog extends StatefulWidget {
  final DatabaseService databaseService;
  final DateTime? initialDate;
  final String? groupId;
  final Map<String, dynamic>? taskToEdit;
  final String? taskId;
  final String? assignedTo; // New parameter for assigned user

  const TaskDialog({
    super.key,
    required this.databaseService,
    this.initialDate,
    this.groupId,
    this.taskToEdit,
    this.taskId,
    this.assignedTo,
  });

  @override
  TaskDialogState createState() => TaskDialogState();
}

class TaskDialogState extends State<TaskDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _status = 'Pending';
  DateTime? _dueDate;
  String? _assignedTo;
  List<Map<String, dynamic>> _groupMembers = [];
  bool _isLoadingMembers = false;

  // In initState, modify how we get the assignedTo value:
  @override
  void initState() {
    super.initState();
    if (widget.taskToEdit != null) {
      _titleController.text = widget.taskToEdit!['title'] ?? '';
      _descriptionController.text = widget.taskToEdit!['description'] ?? '';
      _status = widget.taskToEdit!['status'] ?? 'Pending';
      _dueDate = (widget.taskToEdit!['dueDate'] as Timestamp).toDate();

      // Handle both String and Map cases for assignedTo
      final assignedTo = widget.taskToEdit!['assignedTo'];
      if (assignedTo is String) {
        _assignedTo = assignedTo;
      } else if (assignedTo is Map) {
        _assignedTo = assignedTo['id'] ?? assignedTo['uid'];
      }
    } else if (widget.initialDate != null) {
      _dueDate = widget.initialDate;
    }

    _assignedTo = widget.assignedTo ??
        _assignedTo ??
        FirebaseAuth.instance.currentUser?.uid;

    if (widget.groupId != null) {
      _loadGroupMembers();
    }
  }

  Future<void> _loadGroupMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        // Ensure we're getting a List<String> for members
        final memberIds = List<String>.from(groupDoc.get('members') ?? []);
        final members = <Map<String, dynamic>>[];

        for (var memberId in memberIds) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(memberId)
              .get();
          if (userDoc.exists) {
            members.add({
              'id': memberId,
              'name': userDoc.get('name') ?? 'Unknown',
              'email': userDoc.get('email') ?? '',
            });
          }
        }

        setState(() {
          _groupMembers = members;
          if (widget.taskToEdit == null &&
              _assignedTo == null &&
              members.any(
                  (m) => m['id'] == FirebaseAuth.instance.currentUser?.uid)) {
            _assignedTo = FirebaseAuth.instance.currentUser?.uid;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading members: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _handleTaskSubmission() async {
    if (_titleController.text.trim().isEmpty || _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and due date are required')),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (widget.taskId != null && widget.taskToEdit != null) {
        // Update existing task
        await widget.databaseService.updateTask(
          taskId: widget.taskId!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          dueDate: _dueDate!,
          assignedTo: _assignedTo ?? '',
        );
      } else {
        // Create new task
        await widget.databaseService.addTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          assignedTo: _assignedTo ?? user.uid,
          groupId: widget.groupId,
          status: _status,
          dueDate: _dueDate!,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Widget _buildMemberDropdown() {
    if (_isLoadingMembers) {
      return const CircularProgressIndicator();
    }

    if (_groupMembers.isEmpty) {
      return const Text('No members available');
    }

    return DropdownButtonFormField<String>(
      value: _assignedTo,
      items: _groupMembers.map((member) {
        return DropdownMenuItem<String>(
          value: member['id'],
          child: Text('${member['name']} (${member['email']})'),
        );
      }).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _assignedTo = newValue;
        });
      },
      decoration: const InputDecoration(
        labelText: 'Assign To',
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.taskId != null ? 'Edit Task' : 'Add New Task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
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
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.groupId != null) ...[
              _buildMemberDropdown(),
              const SizedBox(height: 16),
            ],
            ListTile(
              title: Text(
                _dueDate == null
                    ? 'Select due date'
                    : 'Due: ${DateFormat.yMd().format(_dueDate!)}',
              ),
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
          onPressed: _handleTaskSubmission,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
