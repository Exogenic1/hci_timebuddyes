import 'package:flutter/material.dart';

class CalendarGroup extends StatelessWidget {
  final bool isLoading;
  final List<String> userGroups;
  final String? selectedGroupId;
  final Map<String, String> groupNames;
  final Map<String, bool> groupLeadership;
  final Function(String?) onGroupChanged;

  const CalendarGroup({
    super.key,
    required this.isLoading,
    required this.userGroups,
    required this.selectedGroupId,
    required this.groupNames,
    required this.groupLeadership,
    required this.onGroupChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (userGroups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Join or create a group in the Collaborate tab'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
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
                value: selectedGroupId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                items: userGroups.map((groupId) {
                  return DropdownMenuItem<String>(
                    value: groupId,
                    child: Text(
                      groupNames[groupId] ?? 'Unnamed Group',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onGroupChanged,
              ),
              if (selectedGroupId != null &&
                  groupLeadership.containsKey(selectedGroupId))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    groupLeadership[selectedGroupId] == true
                        ? 'You are the leader'
                        : 'You are a member',
                    style: TextStyle(
                      color: groupLeadership[selectedGroupId] == true
                          ? Colors.green
                          : Colors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
