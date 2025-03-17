import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/database_service.dart'; // Import DatabaseService

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    signInOption: SignInOption.standard, // Always show account picker
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Google
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      // Ensure the user is signed out of Google before showing the account picker
      await _googleSignIn.signOut();

      // Prompt the user to select a Google account
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // User canceled account selection

      // Get Google authentication details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in with the credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        // Add user to Firestore if they don't already exist
        final databaseService =
            Provider.of<DatabaseService>(context, listen: false);
        await databaseService.addUser(
          userID: userCredential.user!.uid,
          name: googleUser.displayName ?? 'User',
          email: googleUser.email,
          profilePicture: googleUser.photoUrl ?? '',
        );

        // Navigate to the home screen
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      print('Google Sign-In Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: ${e.message}'),
        ),
      );
    } catch (e) {
      print('Unexpected Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google sign-in failed. Please try again.'),
        ),
      );
    }
  }

  // Sign in with email and password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('Email Sign-In Error: $e');
      return null;
    }
  }

  // Sign up with email and password
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('Email Sign-Up Error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut(); // Sign out from Google
    await _auth.signOut(); // Sign out from Firebase
  }

  // Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }
}
