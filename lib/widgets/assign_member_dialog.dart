// assign_member_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AssignMemberDialog extends StatefulWidget {
  final String groupId;
  final String currentUserId;

  const AssignMemberDialog({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  State<AssignMemberDialog> createState() => _AssignMemberDialogState();
}

class _AssignMemberDialogState extends State<AssignMemberDialog> {
  String? _selectedMemberId;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroupMembers();
  }

  // In assign_member_dialog.dart
  Future<void> _loadGroupMembers() async {
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      final membersData = groupDoc['members'];
      final members = <Map<String, dynamic>>[];

      if (membersData is List) {
        for (var member in membersData) {
          if (member is String) {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(member)
                .get();
            members.add({
              'id': member,
              'name': userDoc['name'],
              'email': userDoc['email'],
            });
          } else if (member is Map) {
            final memberId = member['userId'] ?? member['id'];
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(memberId)
                .get();
            members.add({
              'id': memberId,
              'name': userDoc['name'] ?? member['name'],
              'email': userDoc['email'] ?? member['email'],
            });
          }
        }
      }

      setState(() {
        _members = members;
        _isLoading = false;
        if (_members.any((m) => m['id'] == widget.currentUserId)) {
          _selectedMemberId = widget.currentUserId;
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading members: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Task To'),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
              ? const Text('No members in this group')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedMemberId,
                      items: _members.map((member) {
                        return DropdownMenuItem<String>(
                          value: member['id'],
                          child: Text('${member['name']} (${member['email']})'),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedMemberId = newValue;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Select Member',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedMemberId == null
              ? null
              : () => Navigator.pop(context, _selectedMemberId),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
