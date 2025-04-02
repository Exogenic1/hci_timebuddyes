import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:time_buddies/widgets/task_dialog.dart';

class TaskList extends StatelessWidget {
  final String userId;

  const TaskList({super.key, required this.userId});

  Future<void> _deleteTask(BuildContext context, String taskId) async {
    try {
      await FirebaseFirestore.instance.collection('tasks').doc(taskId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting task: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .orderBy('dueDate', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.assignment_outlined,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('You do not have any tasks yet'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => TaskDialog(
                      databaseService:
                          Provider.of<DatabaseService>(context, listen: false),
                    ),
                  ),
                  child: const Text('Add your first task'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final task = snapshot.data!.docs[index];
            final taskId = task.id;
            final data = task.data() as Map<String, dynamic>;
            final title = data['title'];
            final description = data['description'];
            final status = data['status'];
            final dueDate = (data['dueDate'] as Timestamp).toDate();

            Color statusColor = Colors.grey;
            if (status == 'Pending') statusColor = Colors.orange;
            if (status == 'In Progress') statusColor = Colors.blue;
            if (status == 'Completed') statusColor = Colors.green;

            return Dismissible(
              key: Key(taskId),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (direction) => _deleteTask(context, taskId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 4,
                  color: Colors.white,
                  child: ListTile(
                    title: Text(title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (description.isNotEmpty) Text(description),
                        const SizedBox(height: 4),
                        Text(
                          'Due: ${dueDate.toLocal().toString().split(' ')[0]}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(status,
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: statusColor,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
