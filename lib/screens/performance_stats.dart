import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; // Ensure this import is present for FlBorderData

class PerformanceStatsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PerformanceStatsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<PerformanceStatsScreen> createState() => _PerformanceStatsScreenState();
}

class _PerformanceStatsScreenState extends State<PerformanceStatsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentRatings = [];
  String _timeFrame = 'all'; // 'all', 'month', 'week'
  List<String> _userGroups = [];
  Map<String, String> _groupNames = {};
  String? _selectedGroupId;

  // Performance metrics
  int _totalTasksCompleted = 0;
  int _tasksCompletedOnTime = 0;
  int _tasksCompletedLate = 0;
  double _onTimePercentage = 0;
  Map<int, int> _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  double _averageRating = 0;
  int _totalRatings = 0;

  @override
  void initState() {
    super.initState();
    _loadUserGroups();
  }

  Future<void> _loadUserGroups() async {
    setState(() => _isLoading = true);

    try {
      // Get user document to load groups
      final userDoc =
          await _firestore.collection('users').doc(widget.userId).get();

      if (!userDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final groups = (userData['groups'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [];

      if (groups.isEmpty) {
        setState(() {
          _userGroups = [];
          _selectedGroupId = null;
          _groupNames = {};
          _isLoading = false;
        });
        return;
      }

      // Load group details
      final groupsData = await Future.wait(
        groups.map((groupId) async {
          try {
            final groupDoc =
                await _firestore.collection('groups').doc(groupId).get();
            return {'id': groupId, 'data': groupDoc.data()};
          } catch (e) {
            debugPrint('Error loading group $groupId: $e');
            return null;
          }
        }),
      );

      final newNamesMap = <String, String>{};
      final validGroups = <String>[];

      for (final group in groupsData) {
        if (group != null && group['data'] != null) {
          final groupId = group['id'] as String;
          final groupData = group['data'] as Map<String, dynamic>;
          newNamesMap[groupId] =
              groupData['name']?.toString() ?? 'Unnamed Group';
          validGroups.add(groupId);
        }
      }

      setState(() {
        _userGroups = validGroups;
        _groupNames = newNamesMap;
        _selectedGroupId = _userGroups.isNotEmpty ? _userGroups.first : null;
        _isLoading = false;
      });

      if (_selectedGroupId != null) {
        _loadStats();
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadStats() async {
    if (_selectedGroupId == null) return;

    setState(() => _isLoading = true);

    try {
      // Define the date filter based on selected time frame
      DateTime? startDate;
      final now = DateTime.now();
      if (_timeFrame == 'week') {
        startDate = now.subtract(const Duration(days: 7));
      } else if (_timeFrame == 'month') {
        startDate = DateTime(now.year, now.month - 1, now.day);
      }

      // Query for tasks that the user completed
      Query tasksQuery = _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId)
          .where('assignedTo', isEqualTo: widget.userId)
          .where('completed', isEqualTo: true);

      if (startDate != null) {
        tasksQuery = tasksQuery.where('completionDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      final taskDocs = await tasksQuery.get();

      // Reset counters
      _totalTasksCompleted = taskDocs.docs.length;
      _tasksCompletedOnTime = 0;
      _tasksCompletedLate = 0;

      // Process task completion data
      final taskIds = <String>[];
      for (var doc in taskDocs.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dueDate = (data['dueDate'] as Timestamp).toDate();
        final completionDate = (data['completionDate'] as Timestamp?)?.toDate();

        if (completionDate != null) {
          if (completionDate.isBefore(dueDate) ||
              completionDate.isAtSameMomentAs(dueDate)) {
            _tasksCompletedOnTime++;
          } else {
            _tasksCompletedLate++;
          }
        }

        taskIds.add(doc.id);
      }

      // Calculate on-time percentage
      _onTimePercentage = _totalTasksCompleted > 0
          ? (_tasksCompletedOnTime / _totalTasksCompleted) * 100
          : 0;

      // Reset rating metrics
      _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      _totalRatings = 0;
      int ratingSum = 0;

      // Get ratings for these tasks
      if (taskIds.isNotEmpty) {
        // Filter by date if needed
        Query ratingsQuery = _firestore
            .collection('ratings')
            .where('userId', isEqualTo: widget.userId);

        if (taskIds.length <= 10) {
          // If we have 10 or fewer tasks, we can use whereIn
          ratingsQuery = ratingsQuery.where('taskId', whereIn: taskIds);
        }

        final ratingDocs = await ratingsQuery.get();
        _recentRatings = [];

        for (var doc in ratingDocs.docs) {
          final data = doc.data();
          final taskId = (data as Map<String, dynamic>)['taskId'] as String;

          // Skip if this rating is not for one of our tasks and we're using a larger query
          if (taskIds.length > 10 && !taskIds.contains(taskId)) {
            continue;
          }

          // Apply time filter if needed
          if (startDate != null) {
            final timestamp = data['timestamp'] as Timestamp?;
            if (timestamp == null || timestamp.toDate().isBefore(startDate)) {
              continue;
            }
          }

          final rating = (data['rating'] as num).toInt();
          _ratingDistribution[rating] = (_ratingDistribution[rating] ?? 0) + 1;
          ratingSum += rating;
          _totalRatings++;

          // Get task details for the recent ratings
          DocumentSnapshot? taskDoc;
          try {
            taskDoc = await _firestore.collection('tasks').doc(taskId).get();
          } catch (e) {
            debugPrint('Error loading task $taskId: $e');
          }

          if (taskDoc != null && taskDoc.exists) {
            final taskData = taskDoc.data() as Map<String, dynamic>?;
            _recentRatings.add({
              'id': doc.id,
              'rating': rating,
              'taskId': taskId,
              'timestamp': data['timestamp'],
              'ratedBy': data['ratedBy'],
              'taskTitle': taskData?['title'] ?? 'Unknown Task',
            });
          }
        }

        // Sort recent ratings by timestamp (newest first)
        _recentRatings.sort((a, b) {
          final aTime = a['timestamp'] as Timestamp?;
          final bTime = b['timestamp'] as Timestamp?;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        // Limit to most recent 5 ratings
        if (_recentRatings.length > 5) {
          _recentRatings = _recentRatings.sublist(0, 5);
        }
      }

      // Calculate average rating
      _averageRating = _totalRatings > 0 ? ratingSum / _totalRatings : 0;

      setState(() {
        _stats = {
          'tasksCompleted': _totalTasksCompleted,
          'onTimePercentage': _onTimePercentage,
          'averageRating': _averageRating,
          'totalRatings': _totalRatings,
        };
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading performance stats: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stats: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Stats'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userGroups.isEmpty
              ? const Center(
                  child: Text(
                      'No groups found. \nJoin a group to view performance stats.',
                      textAlign: TextAlign.center))
              : _buildStatsContent(),
    );
  }

  Widget _buildStatsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Group selector
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Group',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
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
                      if (newValue != null) {
                        setState(() => _selectedGroupId = newValue);
                        _loadStats();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Time frame selector
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Time Period',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'week', label: Text('Last Week')),
                      ButtonSegment(value: 'month', label: Text('Last Month')),
                      ButtonSegment(value: 'all', label: Text('All Time')),
                    ],
                    selected: {_timeFrame},
                    onSelectionChanged: (Set<String> selection) {
                      setState(() => _timeFrame = selection.first);
                      _loadStats();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Overview stats
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Performance Overview',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 20),

                  // Stats grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Tasks Completed',
                          '$_totalTasksCompleted',
                          Icons.task_alt,
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'On Time Completion',
                          '${_onTimePercentage.toStringAsFixed(1)}%',
                          Icons.timelapse,
                          _onTimePercentage >= 80
                              ? Colors.green
                              : _onTimePercentage >= 50
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Average Rating',
                          _totalRatings > 0
                              ? '${_averageRating.toStringAsFixed(1)} / 5.0'
                              : 'N/A',
                          Icons.star,
                          Colors.amber,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'Total Ratings',
                          '$_totalRatings',
                          Icons.reviews,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Task completion chart
          if (_totalTasksCompleted > 0)
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Task Completion',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: _buildCompletionPieChart(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendItem('On Time', Colors.green),
                        const SizedBox(width: 20),
                        _buildLegendItem('Late', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Rating distribution chart
          if (_totalRatings > 0)
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rating Distribution',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: _buildRatingBarChart(),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Recent ratings
          if (_recentRatings.isNotEmpty)
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent Ratings',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    ..._recentRatings.map((rating) => _buildRatingItem(rating)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompletionPieChart() {
    return PieChart(
      PieChartData(
        sectionsSpace: 0,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            color: Colors.green,
            value: _tasksCompletedOnTime.toDouble(),
            title: '$_tasksCompletedOnTime',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: Colors.red,
            value: _tasksCompletedLate.toDouble(),
            title: '$_tasksCompletedLate',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBarChart() {
    return BarChart(
      BarChartData(
        barGroups: [
          for (int i = 1; i <= 5; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _ratingDistribution[i]!.toDouble(),
                  color: _getRatingColor(i),
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                ),
              ],
            ),
        ],
        borderData: FlBorderData(show: false), // Ensure fl_chart is imported
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                String text = '${value.toInt()}★';
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(text, style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
      ),
    );
  }

  Color _getRatingColor(int rating) {
    const colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.lightGreen,
      Colors.green,
    ];
    return colors[rating - 1];
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildRatingItem(Map<String, dynamic> rating) {
    final timestamp = rating['timestamp'] as Timestamp?;
    final dateString = timestamp != null
        ? DateFormat('MMM d, yyyy').format(timestamp.toDate())
        : 'Unknown date';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${rating['rating']}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.amber,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rating['taskTitle'] ?? 'Unknown Task',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateString,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: List.generate(5, (index) {
              return Icon(
                index < (rating['rating'] as int)
                    ? Icons.star
                    : Icons.star_border,
                color: Colors.amber,
                size: 16,
              );
            }),
          ),
        ],
      ),
    );
  }
}
