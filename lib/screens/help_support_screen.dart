import 'package:flutter/material.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  ExpansionTile(
                    title: Text('How do I create a group?'),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          'To create a group, go to the Collaborate tab. Enter the group details and tap "Create Group".',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text('How do I invite members to my group?'),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          'Open your chat tab, tap on the copy link icon besides the group chat. You can share the invitation link with others.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text('How do I assign a task to a group member?'),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          'When creating or editing a task, tap on "Assign To" and select the group member from the dropdown list.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text('How do I change my password?'),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          'Go to the Profile tab, tap on "Change Password", enter your current password and your new password, then tap "Change Password".',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
