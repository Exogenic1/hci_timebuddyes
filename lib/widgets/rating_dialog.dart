import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RatingDialog extends StatefulWidget {
  final String taskId;
  final String userId;
  final String userName;
  final VoidCallback onRatingSubmitted;

  const RatingDialog({
    super.key,
    required this.taskId,
    required this.userId,
    required this.userName,
    required this.onRatingSubmitted,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  double _rating = 3.0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Check if this task has already been rated by this user
      final existingRatings = await _firestore
          .collection('ratings')
          .where('taskId', isEqualTo: widget.taskId)
          .where('ratedBy', isEqualTo: currentUser.uid)
          .get();

      if (existingRatings.docs.isNotEmpty) {
        // Update existing rating
        await _firestore
            .collection('ratings')
            .doc(existingRatings.docs.first.id)
            .update({
          'rating': _rating,
          'comment': _commentController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new rating
        await _firestore.collection('ratings').add({
          'taskId': widget.taskId,
          'userId': widget.userId, // The person being rated
          'ratedBy': currentUser.uid, // The person giving the rating
          'rating': _rating,
          'comment': _commentController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
          'isAnonymous': true, // Make ratings anonymous by default
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onRatingSubmitted();
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: ${e.toString()}')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.userName}\'s Work'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('How well did this member perform on this task?'),
          const SizedBox(height: 20),

          // Star rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  icon: Icon(
                    i <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () {
                    setState(() => _rating = i.toDouble());
                  },
                ),
            ],
          ),

          Text(
            'Rating: ${_rating.toStringAsFixed(1)}/5.0',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Optional comment field
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: 'Optional Comment',
              hintText: 'Add feedback (will remain anonymous)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 8),

          const Text(
            'Ratings are anonymous and help improve team performance',
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
          onPressed: _isSubmitting ? null : _submitRating,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
