import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CalendarTask extends StatelessWidget {
  final DateTime selectedDay;
  final List<Map<String, dynamic>> events;
  final bool isLeader;
  final VoidCallback onAddTask;
  final Function(String, bool) onCompleteTask;
  final Function(String) onDeleteTask;
  final FirebaseFirestore firestore;

  const CalendarTask({
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

    // If leader, show all tasks; otherwise, only show tasks assigned to current user
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
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: visibleTasks.length,
      itemBuilder: (context, index) {
        final task = visibleTasks[index];
        final bool isCompleted = task['completed'] ?? false;
        final bool isLocked = task['locked'] ?? false;
        final bool isLate = task['isLate'] ?? false;
        final isAssignedToMe = task['assignedTo'] == currentUserId;
        final dueDate = (task['dueDate'] as Timestamp).toDate();
        final assigneeName =
            task['assignedToName'] ?? 'Unknown'; // Use stored name

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
                            ? null
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
                        const Icon(Icons.calendar_today, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Due: ${DateFormat('MMM d, y - h:mm a').format(dueDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isLate ? Colors.red : Colors.black54,
                            fontWeight:
                                isLate ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    // Display the stored assignee name
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Assigned to: $assigneeName',
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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
                      IconButton(
                        icon:
                            const Icon(Icons.star_border, color: Colors.amber),
                        tooltip: 'Rate Task',
                        onPressed: () => _showRatingDialog(
                            context, task['id'], task['assignedTo']),
                      ),
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

  void _showRatingDialog(
      BuildContext context, String taskId, String assigneeId) async {
    double rating = 3.0;

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

  Future<void> _submitRating(
      BuildContext context, String taskId, String userId, double rating) async {
    try {
      await firestore.collection('ratings').add({
        'taskId': taskId,
        'userId': userId,
        'rating': rating,
        'timestamp': FieldValue.serverTimestamp(),
      });

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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted anonymously')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: ${e.toString()}')),
        );
      }
    }
  }
}
