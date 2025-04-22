import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TaskList extends StatelessWidget {
  final String userId;

  const TaskList({super.key, required this.userId});

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
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('You do not have any tasks assigned'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final task = snapshot.data!.docs[index];
            final data = task.data() as Map<String, dynamic>;
            final title = data['title'];
            final description = data['description'];
            final isCompleted = data['completed'] ?? false;
            final isLocked = data['locked'] ?? false;
            final dueDate = (data['dueDate'] as Timestamp).toDate();
            final groupId = data['groupID'];

            // Determine status
            String status;
            Color statusColor;

            if (isCompleted) {
              final completedDate = data['completedAt'] != null
                  ? (data['completedAt'] as Timestamp).toDate()
                  : DateTime.now();

              if (completedDate.isAfter(dueDate)) {
                status = 'Late';
                statusColor = Colors.red;
              } else {
                status = 'Completed';
                statusColor = Colors.green;
              }
            } else {
              if (DateTime.now().isAfter(dueDate)) {
                status = 'Overdue';
                statusColor = Colors.red;
              } else {
                status = 'Pending';
                statusColor = Colors.orange;
              }
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 2,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (description?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                description,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 16,
                                    color: DateTime.now().isAfter(dueDate) &&
                                            !isCompleted
                                        ? Colors.red
                                        : Theme.of(context).primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Due: ${DateFormat('MMM d, y').format(dueDate)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DateTime.now().isAfter(dueDate) &&
                                            !isCompleted
                                        ? Colors.red
                                        : Colors.black87,
                                    fontWeight:
                                        DateTime.now().isAfter(dueDate) &&
                                                !isCompleted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Add group name display
                          FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('groups')
                                .doc(groupId)
                                .get(),
                            builder: (context, groupSnapshot) {
                              String groupName = 'Personal Task';

                              if (groupSnapshot.hasData &&
                                  groupSnapshot.data!.exists) {
                                final groupData = groupSnapshot.data!.data()
                                    as Map<String, dynamic>;
                                groupName =
                                    groupData['name'] ?? 'Unnamed Group';
                              }

                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.group,
                                        size: 16,
                                        color: Theme.of(context).primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Group: $groupName',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Add checkbox if task is not locked
                    if (!isLocked)
                      Padding(
                        padding:
                            const EdgeInsets.only(right: 16.0, bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Mark as complete:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            Checkbox(
                              value: isCompleted,
                              onChanged: (value) async {
                                if (value != null) {
                                  // Determine status
                                  String newStatus;
                                  if (value) {
                                    if (DateTime.now().isAfter(dueDate)) {
                                      newStatus = 'Late';
                                    } else {
                                      newStatus = 'Completed';
                                    }
                                  } else {
                                    if (DateTime.now().isAfter(dueDate)) {
                                      newStatus = 'Overdue';
                                    } else {
                                      newStatus = 'Pending';
                                    }
                                  }

                                  // Update task
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('tasks')
                                        .doc(task.id)
                                        .update({
                                      'completed': value,
                                      'completedAt': value
                                          ? FieldValue.serverTimestamp()
                                          : null,
                                      'status': newStatus,
                                      'locked': value, // Lock when completed
                                    });

                                    if (value == true) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Task marked as $newStatus'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Error updating task: $e'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
