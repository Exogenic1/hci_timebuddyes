import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _showMyRatings = true; // Toggle between ratings received vs. given
  double _averageRating = 0.0; // Store user's average rating
  int _totalRatings = 0; // Store total number of ratings

  @override
  void initState() {
    super.initState();
    _loadUserGroups();
    _loadUserRatingStats();
  }

  Future<void> _loadUserRatingStats() async {
    try {
      final userDoc =
          await _firestore.collection('users').doc(widget.userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _averageRating =
              (userData['averageRating'] as num?)?.toDouble() ?? 0.0;
          _totalRatings = (userData['totalRatings'] as int?) ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading user rating stats: $e');
    }
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
      // Get tasks for this group
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

      // Get ratings based on toggle state
      final Query<Map<String, dynamic>> ratingsQuery = _showMyRatings
          ? _firestore
              .collection('ratings')
              .where('taskId', whereIn: taskIds)
              .where('userId', isEqualTo: widget.userId)
          : _firestore.collection('ratings').where('taskId', whereIn: taskIds);

      final ratingDocs = await ratingsQuery.get();

      // Get task data to match with ratings
      final taskMap = {
        for (var doc in taskDocs.docs)
          doc.id: doc.data() as Map<String, dynamic>
      };

      // Build ratings list
      final ratings = <Map<String, dynamic>>[];
      for (var ratingDoc in ratingDocs.docs) {
        final ratingData = ratingDoc.data();
        final taskId = ratingData['taskId'];
        final taskData = taskMap[taskId];

        if (taskData != null) {
          // If we're showing ratings given by this user (not _showMyRatings),
          // we need to get the assignee's name
          String? assigneeName;
          if (!_showMyRatings) {
            try {
              final userDoc = await _firestore
                  .collection('users')
                  .doc(ratingData['userId'])
                  .get();
              if (userDoc.exists) {
                assigneeName = (userDoc.data() as Map<String, dynamic>)['name'];
              }
            } catch (e) {
              debugPrint('Error fetching user name: $e');
            }
          }

          ratings.add({
            'id': ratingDoc.id,
            'rating': ratingData['rating'],
            'timestamp': ratingData['timestamp'],
            'taskId': taskId,
            'taskTitle': taskData['title'],
            'taskDescription': taskData['description'],
            'dueDate': taskData['dueDate'],
            'assigneeName': assigneeName,
            'userId': ratingData['userId'],
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
          // User rating summary
          if (_totalRatings > 0)
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Performance Rating',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ...List.generate(5, (i) {
                                return Icon(
                                  i < _averageRating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: 20,
                                );
                              }),
                              const SizedBox(width: 8),
                              Text(
                                '${_averageRating.toStringAsFixed(1)} / 5.0',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_totalRatings ${_totalRatings == 1 ? 'Rating' : 'Ratings'}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Toggle between my ratings and ratings I gave
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showMyRatings = true;
                              });
                              _loadRatings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _showMyRatings
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  bottomLeft: Radius.circular(10),
                                ),
                              ),
                              child: Text(
                                'My Ratings',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _showMyRatings
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showMyRatings = false;
                              });
                              _loadRatings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_showMyRatings
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Ratings I Gave',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !_showMyRatings
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

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
              _showMyRatings
                  ? 'No ratings found for you in this group'
                  : 'You haven\'t rated any tasks in this group',
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
        final DateTime? timestamp = rating['timestamp'] != null
            ? (rating['timestamp'] as Timestamp).toDate()
            : null;

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

                // Show assignee name for ratings given to others
                if (!_showMyRatings && rating['assigneeName'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.person,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text(
                          'Assigned to: ${rating['assigneeName']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          _showMyRatings ? 'Your Rating: ' : 'Rating Given: ',
                          style: const TextStyle(
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
                    if (timestamp != null)
                      Text(
                        DateFormat('MMM d, y').format(timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
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
