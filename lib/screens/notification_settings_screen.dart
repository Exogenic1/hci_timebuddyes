import 'package:flutter/material.dart';
import 'package:time_buddies/services/notifications_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;

  // Notification settings
  bool _pushEnabled = false;
  bool _taskReminders = true;
  bool _groupMessages = true;
  bool _taskUpdates = true;
  bool _systemUpdates = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _notificationService.initializeSettings();
    final settings = await _notificationService.getNotificationSettings();

    setState(() {
      _pushEnabled = settings['push_notifications_enabled'] ?? false;
      _taskReminders = settings['task_reminder_notifications'] ?? true;
      _groupMessages = settings['group_message_notifications'] ?? true;
      _taskUpdates = settings['task_updates_notifications'] ?? true;
      _systemUpdates = settings['system_updates_notifications'] ?? true;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Enable or disable all notifications'),
                  value: _pushEnabled,
                  onChanged: (value) async {
                    final result = await _notificationService
                        .togglePushNotifications(value);
                    if (result != value && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Failed to change notification permission. Please update in device settings.'),
                        ),
                      );
                    }
                    setState(() {
                      _pushEnabled = result;
                    });
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Notification Types',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Task Reminders'),
                  subtitle: const Text(
                      'Get notified about upcoming tasks (24h and 1h before deadline)'),
                  value: _taskReminders && _pushEnabled,
                  onChanged: _pushEnabled
                      ? (value) async {
                          await _notificationService.toggleNotificationType(
                              'task_reminder_notifications', value);
                          setState(() {
                            _taskReminders = value;
                          });
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Group Messages'),
                  subtitle:
                      const Text('Get notified about new messages in groups'),
                  value: _groupMessages && _pushEnabled,
                  onChanged: _pushEnabled
                      ? (value) async {
                          await _notificationService.toggleNotificationType(
                              'group_message_notifications', value);
                          setState(() {
                            _groupMessages = value;
                          });
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Task Updates'),
                  subtitle: const Text('Get notified when tasks are updated'),
                  value: _taskUpdates && _pushEnabled,
                  onChanged: _pushEnabled
                      ? (value) async {
                          await _notificationService.toggleNotificationType(
                              'task_updates_notifications', value);
                          setState(() {
                            _taskUpdates = value;
                          });
                        }
                      : null,
                ),
                SwitchListTile(
                  title: const Text('App Updates'),
                  subtitle: const Text(
                      'Get notified about new app features and updates'),
                  value: _systemUpdates && _pushEnabled,
                  onChanged: _pushEnabled
                      ? (value) async {
                          await _notificationService.toggleNotificationType(
                              'system_updates_notifications', value);
                          setState(() {
                            _systemUpdates = value;
                          });
                        }
                      : null,
                ),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Note: You can also change notification settings in your device settings.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Task reminders will be sent 24 hours and 1 hour before a task deadline.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await _notificationService.sendTestNotification();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Test notification sent. You should receive it shortly.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('Error sending test notification: $e'),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Send Test Notification'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await _notificationService.testDeadlineNotification();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Test deadline notifications sent. You should receive them shortly.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('Error sending test notifications: $e'),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Test Deadline Notifications'),
                  ),
                ),
              ],
            ),
    );
  }
}
