import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/database_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    signInOption: SignInOption.standard,
  );
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Generate a random avatar URL for new users
  String generateRandomAvatar(String userId) {
    // Using userId as seed ensures the same user gets the same avatar
    return RandomAvatarString(userId);
  }

  // Sign in with Google
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      await _googleSignIn.signOut(); // Ensure clean sign-in
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // User cancelled sign-in

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await handleSuccessfulSignIn(
          context: context,
          user: userCredential.user!,
          googleUser: googleUser,
        );
      }
    } on FirebaseAuthException catch (e) {
      _handleAuthError(context, 'Google sign-in failed: ${e.message}');
    } catch (e) {
      _handleAuthError(context, 'Google sign-in failed. Please try again.');
    }
  }

  // Handle successful sign-in
  Future<void> handleSuccessfulSignIn({
    required BuildContext context,
    required User user,
    required GoogleSignInAccount googleUser,
  }) async {
    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);
    final validationService = DataValidationService();

    // Get FCM token
    String? fcmToken;
    try {
      fcmToken = await _firebaseMessaging.getToken();
      await _firebaseMessaging.subscribeToTopic('all_users');
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }

    // Validate and update user data
    await validationService.validateUserData(user.uid);
    await databaseService.addUser(
      userID: user.uid,
      name: googleUser.displayName ?? 'User',
      email: googleUser.email,
      profilePicture: googleUser.photoUrl ?? '',
      fcmToken: fcmToken,
    );

    // Validate all group memberships
    await validationService.validateAllUserGroups(user.uid);

    // Load user groups
    await databaseService.loadUserGroups(user.uid);

    // Safe navigation
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Clean up FCM token
      await _firebaseMessaging.deleteToken();
      await _firebaseMessaging.unsubscribeFromTopic('all_users');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }

    // Sign out from all providers
    await Future.wait([
      _googleSignIn.signOut(),
      _auth.signOut(),
    ]);
  }

  // Handle authentication errors
  void _handleAuthError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Sign in with email and password
  Future<User?> signInWithEmail(
      BuildContext context, String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Update FCM token
        String? fcmToken;
        try {
          fcmToken = await _firebaseMessaging.getToken();
          await _firebaseMessaging.subscribeToTopic('all_users');
        } catch (e) {
          debugPrint('Error getting FCM token: $e');
        }

        // Update user data with token
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        await databaseService.updateFcmToken(result.user!.uid, fcmToken);
      }

      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email Sign-In Error: $e');
      _handleAuthError(context, 'Sign-in failed: ${e.message}');
      return null;
    }
  }

  // Sign up with email and password
  Future<User?> signUpWithEmail(
      BuildContext context, String email, String password, String name) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Get FCM token
        String? fcmToken;
        try {
          fcmToken = await _firebaseMessaging.getToken();
          await _firebaseMessaging.subscribeToTopic('all_users');
        } catch (e) {
          debugPrint('Error getting FCM token: $e');
        }

        // Generate random avatar for the user
        final String randomAvatar = generateRandomAvatar(result.user!.uid);

        // Create user profile
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        await databaseService.addUser(
          userID: result.user!.uid,
          name: name,
          email: email,
          profilePicture: randomAvatar,
          fcmToken: fcmToken,
        );
      }

      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email Sign-Up Error: $e');
      _handleAuthError(context, 'Sign-up failed: ${e.message}');
      return null;
    }
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }
}
