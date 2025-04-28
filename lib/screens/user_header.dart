import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:random_avatar/random_avatar.dart';

class UserHeader extends StatelessWidget {
  const UserHeader({super.key});

  Widget _buildAvatar(String? profilePictureUrl, bool isGoogleUser) {
    // For Google users, use their Google profile picture
    if (isGoogleUser) {
      final user = FirebaseAuth.instance.currentUser;
      final photoURL = user?.photoURL;

      if (photoURL != null && photoURL.isNotEmpty) {
        return CircleAvatar(
          radius: 25,
          backgroundColor: Colors.white.withOpacity(0.3),
          backgroundImage: CachedNetworkImageProvider(photoURL),
        );
      }
    }
    // For TimeBuddies Email users, use RandomAvatar
    else if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      // Use RandomAvatar for app users
      return ClipOval(
        child: SizedBox(
          height: 50,
          width: 50,
          child: RandomAvatar(
            profilePictureUrl,
            height: 50,
            width: 50,
          ),
        ),
      );
    }

    // Fallback for any user without an avatar
    return CircleAvatar(
      radius: 25,
      backgroundColor: Colors.white.withOpacity(0.3),
      child: const Icon(Icons.person, color: Colors.white, size: 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    // Check if user is signed in with Google
    final isGoogleUser = user.providerData
        .any((userInfo) => userInfo.providerId == 'google.com');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome Back!',
                style: TextStyle(
                  fontSize: 26,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 2.0,
                      color: Colors.black26,
                      offset: Offset(1.0, 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    debugPrint('User data error: ${snapshot.error}');
                  }
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final username =
                        data.containsKey('name') ? data['name'] : 'User';
                    return Text(
                      '@$username',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }

                  return Text(
                    '@User',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              String? profilePictureUrl;

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;

                if (data.containsKey('profilePicture')) {
                  profilePictureUrl = data['profilePicture'];
                }
              }

              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildAvatar(profilePictureUrl, isGoogleUser),
              );
            },
          ),
        ],
      ),
    );
  }
}
