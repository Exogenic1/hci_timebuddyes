import 'package:flutter/material.dart';

class CalendarLeader extends StatelessWidget {
  const CalendarLeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.amber[100],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star, size: 16, color: Colors.amber),
          SizedBox(width: 8),
          Text('You are the group leader'),
        ],
      ),
    );
  }
}
