import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DataValidationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> validateUserData(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        await _firestore.collection('users').doc(userId).set({
          'groups': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error validating user data: $e');
    }
  }

  Future<void> validateGroupData(String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        // Remove this group reference from all users
        final users = await _firestore
            .collection('users')
            .where('groups', arrayContains: groupId)
            .get();

        final batch = _firestore.batch();
        for (var doc in users.docs) {
          batch.update(doc.reference, {
            'groups': FieldValue.arrayRemove([groupId]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error validating group data: $e');
    }
  }

  Future<void> validateAllUserGroups(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final groups = List<String>.from(userDoc['groups'] ?? []);
        for (String groupId in groups) {
          await validateGroupData(groupId);
        }
      }
    } catch (e) {
      debugPrint('Error validating user groups: $e');
    }
  }
}
