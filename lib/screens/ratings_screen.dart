import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class RatingsScreen extends StatefulWidget {
  final String userId;

  const RatingsScreen({
    super.key,
    required this.userId,
  });

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<String> _userGroups = [];
  String? _selectedGroupId;
  Map<String, String> _groupNames = {};
  List<Map<String, dynamic>> _ratings = [];

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
        _loadRatings();
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

  Future<void> _loadRatings() async {
    if (_selectedGroupId == null) return;

    setState(() => _isLoading = true);

    try {
      // First get tasks for this group
      final taskDocs = await _firestore
          .collection('tasks')
          .where('groupID', isEqualTo: _selectedGroupId)
          .get();

      if (taskDocs.docs.isEmpty) {
        setState(() {
          _ratings = [];
          _isLoading = false;
        });
        return;
      }

      // Get task IDs
      final taskIds = taskDocs.docs.map((doc) => doc.id).toList();

      // Get ratings for these tasks
      final ratingDocs = await _firestore
          .collection('ratings')
          .where('taskId', whereIn: taskIds)
          .get();

      // Get task data to match with ratings
      final taskMap = {
        for (var doc in taskDocs.docs)
          doc.id: doc.data() as Map<String, dynamic>
      };

      // Combine ratings with task data
      final ratings = <Map<String, dynamic>>[];
      for (var ratingDoc in ratingDocs.docs) {
        final ratingData = ratingDoc.data();
        final taskId = ratingData['taskId'];
        final taskData = taskMap[taskId];

        if (taskData != null) {
          ratings.add({
            'id': ratingDoc.id,
            'rating': ratingData['rating'],
            'timestamp': ratingData['timestamp'],
            'taskId': taskId,
            'taskTitle': taskData['title'],
            'taskDescription': taskData['description'],
            'dueDate': taskData['dueDate'],
            // Don't include user ID to keep ratings anonymous
          });
        }
      }

      setState(() {
        _ratings = ratings;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading ratings: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading ratings: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Ratings'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Group selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildGroupSelector(),
          ),

          // Ratings content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedGroupId == null
                    ? const Center(
                        child: Text('Select a group to view ratings'))
                    : _buildRatingsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    if (_userGroups.isEmpty) {
      return const Text('Join or create a group to view ratings');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                  _loadRatings();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingsList() {
    if (_ratings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No ratings found for this group',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _ratings.length,
      itemBuilder: (context, index) {
        final rating = _ratings[index];
        final starRating = (rating['rating'] as num).toDouble();
        final DateTime dueDate = (rating['dueDate'] as Timestamp).toDate();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rating['taskTitle'] ?? 'Unnamed Task',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Due: ${DateFormat('MMM d').format(dueDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
                if (rating['taskDescription'] != null &&
                    rating['taskDescription'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      rating['taskDescription'],
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Anonymous Rating: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    ...List.generate(5, (i) {
                      return Icon(
                        i < starRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 20,
                      );
                    }),
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
