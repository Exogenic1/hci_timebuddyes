import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/screens/login_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:time_buddies/services/app_info_service.dart';
import 'package:time_buddies/screens/notification_settings_screen.dart';
import 'package:time_buddies/screens/help_support_screen.dart';
import 'package:time_buddies/screens/about_app_screen.dart';
import 'package:time_buddies/services/auth_service.dart';
import 'package:time_buddies/services/database_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut(); // This will handle FCM token cleanup

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _navigateToNotificationSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationSettingsScreen(),
      ),
    );
  }

  void _navigateToHelpAndSupport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HelpSupportScreen(),
      ),
    );
  }

  void _navigateToAboutApp() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AboutAppScreen(),
      ),
    );
  }

  Future<void> _showChangeNameDialog(String currentName) async {
    _nameController.text = currentName;

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Name'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter your new name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (_nameController.text.trim().isNotEmpty) {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    try {
                      // Update name in Firestore
                      final databaseService =
                          Provider.of<DatabaseService>(context, listen: false);
                      await databaseService.updateUserProfile(
                        userID: user.uid,
                        name: _nameController.text.trim(),
                      );

                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Name updated successfully!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating name: $e'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name cannot be empty'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog() async {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user is signed in with Google
    final isGoogleUser = user.providerData
        .any((userInfo) => userInfo.providerId == 'google.com');

    if (isGoogleUser) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Google Account'),
          content: const Text(
              'Password management is handled by your Google account. Please use Google\'s account settings to change your password.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: Form(
            key: _passwordFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a new password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your new password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (_passwordFormKey.currentState!.validate()) {
                  try {
                    // Re-authenticate user
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null && user.email != null) {
                      final credential = EmailAuthProvider.credential(
                        email: user.email!,
                        password: _currentPasswordController.text,
                      );
                      await user.reauthenticateWithCredential(credential);

                      // Change password
                      await user.updatePassword(_newPasswordController.text);

                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password updated successfully!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } on FirebaseAuthException catch (e) {
                    Navigator.of(context).pop();
                    String errorMessage = 'Failed to change password';

                    if (e.code == 'wrong-password') {
                      errorMessage = 'Current password is incorrect';
                    } else if (e.code == 'weak-password') {
                      errorMessage = 'New password is too weak';
                    } else if (e.code == 'requires-recent-login') {
                      errorMessage =
                          'Please log out and log in again before changing your password';
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  } catch (e) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text('Change Password'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileAvatar(
      String userId, String? profilePictureUrl, bool isGoogleUser) {
    if (isGoogleUser &&
        profilePictureUrl != null &&
        profilePictureUrl.isNotEmpty) {
      // For Google users, use their Google profile picture
      return CircleAvatar(
        radius: 60,
        backgroundColor: Colors.grey[300],
        backgroundImage: CachedNetworkImageProvider(profilePictureUrl),
      );
    } else if (!isGoogleUser &&
        profilePictureUrl != null &&
        profilePictureUrl.isNotEmpty) {
      // For app users with a random avatar string
      if (profilePictureUrl.startsWith('https://')) {
        // Legacy users might still have URL-based profile pictures
        return CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey[300],
          backgroundImage: CachedNetworkImageProvider(profilePictureUrl),
        );
      } else {
        // Display random avatar for app users
        return SizedBox(
          height: 120,
          width: 120,
          child: RandomAvatar(
            profilePictureUrl,
            height: 120,
            width: 120,
          ),
        );
      }
    } else {
      // Fallback for users without a profile picture
      return CircleAvatar(
        radius: 60,
        backgroundColor: Colors.grey[300],
        child: const Icon(Icons.person, size: 60),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGoogleUser = user?.providerData
            .any((userInfo) => userInfo.providerId == 'google.com') ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to view your profile'))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading profile: ${snapshot.error}'));
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No profile data found'));
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>;
                final name = userData['name'] ?? 'User';
                final email = userData['email'] ?? user.email ?? '';
                final profilePictureUrl = userData['profilePicture'];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Profile Avatar - Now uses RandomAvatar for app users
                      _buildProfileAvatar(
                          user.uid, profilePictureUrl, isGoogleUser),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showChangeNameDialog(name),
                          ),
                        ],
                      ),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 30),
                      const Divider(),

                      // Settings List
                      ListTile(
                        leading: const Icon(Icons.lock),
                        title: const Text('Change Password'),
                        onTap: _showChangePasswordDialog,
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.notifications),
                        title: const Text('Notification Settings'),
                        onTap: _navigateToNotificationSettings,
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.help),
                        title: const Text('Help & Support'),
                        onTap: _navigateToHelpAndSupport,
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.info),
                        title: const Text('About App'),
                        subtitle: FutureBuilder<Map<String, String>>(
                          future: AppInfoService.getAppInfo(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Text(
                                  'Version ${snapshot.data!['version']}');
                            }
                            return const Text('Version info loading...');
                          },
                        ),
                        onTap: _navigateToAboutApp,
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Sign Out',
                            style: TextStyle(color: Colors.red)),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Sign Out'),
                              content: const Text(
                                  'Are you sure you want to sign out?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _signOut();
                                  },
                                  child: const Text('Sign Out',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
