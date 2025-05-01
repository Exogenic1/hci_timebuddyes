import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:time_buddies/screens/performance_stats.dart';

class PerformanceButton extends StatelessWidget {
  final String userId;

  const PerformanceButton({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final userName = userData?['name'] as String? ?? 'User';

        return ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PerformanceStatsScreen(
                  userId: userId,
                  userName: userName,
                ),
              ),
            );
          },
          icon: const Icon(Icons.analytics, size: 18),
          label: const Text('View Performance'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        );
      },
    );
  }
}
