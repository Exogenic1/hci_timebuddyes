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

  const TaskDialog({
    super.key,
    required this.databaseService,
    this.initialDate,
    this.groupId,
    this.taskToEdit,
    this.taskId,
  });

  @override
  TaskDialogState createState() => TaskDialogState();
}

class TaskDialogState extends State<TaskDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _status = 'Pending';
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    if (widget.taskToEdit != null) {
      _titleController.text = widget.taskToEdit!['title'] ?? '';
      _descriptionController.text = widget.taskToEdit!['description'] ?? '';
      _status = widget.taskToEdit!['status'] ?? 'Pending';
      _dueDate = (widget.taskToEdit!['dueDate'] as Timestamp).toDate();
    } else if (widget.initialDate != null) {
      _dueDate = widget.initialDate;
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
        );
      } else {
        // Create new task
        await widget.databaseService.addTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          assignedTo: user.uid,
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
