import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/data_validation_service.dart';
import 'package:time_buddies/services/database_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    signInOption: SignInOption.standard,
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Google
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        // Get FCM token
        String? fcmToken;
        try {
          fcmToken = await _firebaseMessaging.getToken();
          await _firebaseMessaging.subscribeToTopic('all_users');
        } catch (e) {
          debugPrint('Error getting FCM token: $e');
        }

        // Update user data and groups
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        await databaseService.addUser(
          userID: userCredential.user!.uid,
          name: googleUser.displayName ?? 'User',
          email: googleUser.email,
          profilePicture: googleUser.photoUrl ?? '',
          fcmToken: fcmToken,
        );

        // Load user groups
        await databaseService.loadUserGroups(userCredential.user!.uid);

        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    } on FirebaseAuthException catch (e) {
      _handleAuthError(context, 'Google sign-in failed: ${e.message}');
    } catch (e) {
      _handleAuthError(context, 'Google sign-in failed. Please try again.');
    }
  }

  // Add this to your AuthService class
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

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

// Add this to your signOut method
  Future<void> signOut() async {
    try {
      await _firebaseMessaging.deleteToken();
      await _firebaseMessaging.unsubscribeFromTopic('all_users');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }

    await Future.wait([
      _googleSignIn.signOut(),
      _auth.signOut(),
    ]);
  }

  Future<void> _handleSuccessfulSignIn({
    required BuildContext context,
    required User user,
    required GoogleSignInAccount googleUser,
  }) async {
    final databaseService =
        Provider.of<DatabaseService>(context, listen: false);

    await databaseService.addUser(
      userID: user.uid,
      name: googleUser.displayName ?? 'User',
      email: googleUser.email,
      profilePicture: googleUser.photoUrl ?? '',
    );

    // Safe navigation using NavigatorState
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _handleAuthError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Sign in with email and password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email Sign-In Error: $e');
      return null;
    }
  }

  // Sign up with email and password
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email Sign-Up Error: $e');
      return null;
    }
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }
}
