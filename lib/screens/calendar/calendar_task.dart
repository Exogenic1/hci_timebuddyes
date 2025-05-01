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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCompleted
                ? BorderSide(color: statusColor.withOpacity(0.5), width: 1)
                : BorderSide.none,
          ),
          elevation: isCompleted ? 1 : 2,
          child: Column(
            children: [
              ListTile(
                leading: isAssignedToMe || isLeader
                    ? Checkbox(
                        value: isCompleted,
                        activeColor: statusColor,
                        onChanged: isLocked && !isLeader
                            ? null // Disable for locked tasks unless leader
                            : (bool? value) {
                                if (value != null) {
                                  onCompleteTask(task['id'], value);

                                  // If task is being marked as complete and is assigned to someone else,
                                  // prompt the leader to rate the task
                                  if (value && isLeader && !isAssignedToMe) {
                                    _promptToRateTask(context, task['id'],
                                        task['assignedTo']);
                                  }
                                }
                              },
                      )
                    : const Icon(Icons.lock, color: Colors.grey),
                title: Text(
                  task['title'],
                  style: TextStyle(
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    fontWeight: isLate && !isCompleted
                        ? FontWeight.bold
                        : FontWeight.normal,
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
                            color: isLate && !isCompleted
                                ? Colors.red
                                : Colors.black54,
                            fontWeight: isLate && !isCompleted
                                ? FontWeight.bold
                                : FontWeight.normal,
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
              Padding(
                padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Show rate button to everyone if task is completed and not assigned to them
                    if (isCompleted && task['assignedTo'] != currentUserId)
                      IconButton(
                        icon:
                            const Icon(Icons.star_border, color: Colors.amber),
                        tooltip: 'Rate Task',
                        onPressed: () => _showRatingDialog(
                            context, task['id'], task['assignedTo']),
                      ),
                    // Only show delete button to leaders
                    if (isLeader)
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

  // Method to prompt rating when a task is completed
  void _promptToRateTask(
      BuildContext context, String taskId, String assigneeId) {
    // Use a microtask to avoid showing dialog during build phase
    Future.microtask(() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rate This Completed Task?'),
          content: const Text(
              'Would you like to rate this member\'s performance on the task?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showRatingDialog(context, taskId, assigneeId);
              },
              child: const Text('Rate Now'),
            ),
          ],
        ),
      );
    });
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
                          size: 32,
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
            Text(
              'Rating: ${rating.toStringAsFixed(1)}/5.0',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
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
          ElevatedButton(
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
      // Check if this task has already been rated by this user
      final existingRatings = await firestore
          .collection('ratings')
          .where('taskId', isEqualTo: taskId)
          .where('ratedBy', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .get();

      if (existingRatings.docs.isNotEmpty) {
        // Update existing rating
        await firestore
            .collection('ratings')
            .doc(existingRatings.docs.first.id)
            .update({
          'rating': rating,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new rating
        await firestore.collection('ratings').add({
          'taskId': taskId,
          'userId': userId, // The person being rated
          'ratedBy': FirebaseAuth
              .instance.currentUser?.uid, // The person giving the rating
          'rating': rating,
          'timestamp': FieldValue.serverTimestamp(),
          'isAnonymous': true, // Make ratings anonymous by default
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: ${e.toString()}')),
        );
      }
    }
  }

  // Method to calculate and display user's performance stats
  Future<Map<String, dynamic>> getUserPerformanceStats(String userId) async {
    try {
      // Calculate stats
      final tasksQuery = await firestore
          .collection('tasks')
          .where('assignedTo', isEqualTo: userId)
          .get();

      final totalTasks = tasksQuery.docs.length;
      int completedTasks = 0;
      int completedOnTime = 0;
      int lateTasks = 0;

      for (final doc in tasksQuery.docs) {
        final taskData = doc.data();
        final bool isCompleted = taskData['completed'] ?? false;
        if (isCompleted) {
          completedTasks++;

          final dueDate = (taskData['dueDate'] as Timestamp).toDate();
          final completionDate = taskData['completionDate'] != null
              ? (taskData['completionDate'] as Timestamp).toDate()
              : DateTime.now();

          if (completionDate.isBefore(dueDate) ||
              completionDate.isAtSameMomentAs(dueDate)) {
            completedOnTime++;
          } else {
            lateTasks++;
          }
        }
      }

      // Calculate average rating
      final ratingsQuery = await firestore
          .collection('ratings')
          .where('userId', isEqualTo: userId)
          .get();

      double totalRating = 0;
      final ratingCount = ratingsQuery.docs.length;

      for (final doc in ratingsQuery.docs) {
        totalRating += (doc.data()['rating'] as num).toDouble();
      }

      final averageRating = ratingCount > 0 ? totalRating / ratingCount : 0.0;

      // Calculate completion rate
      final completionRate =
          totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0;

      // Calculate on-time completion rate
      final onTimeRate =
          completedTasks > 0 ? (completedOnTime / completedTasks) * 100 : 0.0;

      return {
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'completedOnTime': completedOnTime,
        'lateTasks': lateTasks,
        'averageRating': averageRating,
        'completionRate': completionRate,
        'onTimeRate': onTimeRate,
      };
    } catch (e) {
      debugPrint('Error getting user performance stats: $e');
      return {
        'error': e.toString(),
      };
    }
  }

  // Method to show performance stats
  void showPerformanceStats(
      BuildContext context, String userId, String userName) async {
    try {
      final stats = await getUserPerformanceStats(userId);

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Performance Stats: $userName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow('Total Tasks', '${stats['totalTasks']}'),
                _buildStatRow('Completed Tasks', '${stats['completedTasks']}'),
                _buildStatRow('Completion Rate',
                    '${stats['completionRate'].toStringAsFixed(1)}%'),
                _buildStatRow('On-time Completion',
                    '${stats['onTimeRate'].toStringAsFixed(1)}%'),
                _buildStatRow('Late Tasks', '${stats['lateTasks']}'),
                const SizedBox(height: 16),
                const Text('Average Rating:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      Icon(
                        i <= stats['averageRating']
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 24,
                      ),
                  ],
                ),
                Center(
                  child: Text(
                    '${stats['averageRating'].toStringAsFixed(1)}/5.0',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error showing performance stats: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Error loading performance stats: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
