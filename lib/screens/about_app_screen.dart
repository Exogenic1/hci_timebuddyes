import 'package:flutter/material.dart';
import 'package:time_buddies/services/app_info_service.dart';

class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  bool _isLoading = true;
  Map<String, String> _appInfo = {};

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    final appInfo = await AppInfoService.getAppInfo();
    setState(() {
      _appInfo = appInfo;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About App'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.access_time,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    _appInfo['appName'] ?? 'Time Buddies',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Version ${_appInfo['version']} (${_appInfo['buildNumber']})',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const ListTile(
                  title: Text(
                    'About Time Buddies',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Time Buddies is a collaborative task management app designed to help teams coordinate their work effectively. Organize tasks, communicate with team members, and track progress all in one place.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                const ListTile(
                  title: Text('Privacy Policy'),
                  subtitle: Text(
                    'The privacy policy makes sure that your data is secured, managed, and protected while using Time Buddies.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
                const ListTile(
                  title: Text('Terms of Service'),
                  subtitle: Text(
                    'By using Time Buddies, you agree to our terms of service which outline your rights and responsibilities as a user.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
                const SizedBox(height: 32),
                const Center(
                  child: Text(
                    '© 2025 Time Buddies',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}
