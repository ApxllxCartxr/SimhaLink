import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/utils/user_preferences.dart';

void main() {
  group('Group Cleanup Tests', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({});
      
      // Set up test data - create a group with one member
      await firestore.collection('groups').doc('test-group-123').set({
        'name': 'Test Group',
        'joinCode': 'ABC123',
        'memberIds': ['user123'],
        'createdBy': 'user123',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Add some messages to the group
      await firestore.collection('groups').doc('test-group-123')
          .collection('messages').doc('msg1').set({
        'senderId': 'user123',
        'message': 'Hello world',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // Add some locations to the group  
      await firestore.collection('groups').doc('test-group-123')
          .collection('locations').doc('loc1').set({
        'userId': 'user123',
        'latitude': 12.34,
        'longitude': 56.78,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    test('cleanupEmptyGroup should delete empty custom groups', () async {
      // Remove the last member from the group
      await firestore.collection('groups').doc('test-group-123').update({
        'memberIds': [],
      });
      
      // Call cleanup - this should delete the group and its sub-collections
      await UserPreferences.cleanupEmptyGroup('test-group-123');
      
      // Verify the group was deleted
      final groupDoc = await firestore.collection('groups').doc('test-group-123').get();
      expect(groupDoc.exists, false);
      
      // Verify sub-collections were deleted (messages)
      final messages = await firestore.collection('groups').doc('test-group-123')
          .collection('messages').get();
      expect(messages.docs.isEmpty, true);
      
      // Verify sub-collections were deleted (locations)
      final locations = await firestore.collection('groups').doc('test-group-123')
          .collection('locations').get();
      expect(locations.docs.isEmpty, true);
    });

    test('cleanupEmptyGroup should preserve special groups even when empty', () async {
      // Create an empty volunteers group
      await firestore.collection('groups').doc('volunteers').set({
        'name': 'Volunteers',
        'memberIds': [],
        'isSpecialGroup': true,
      });
      
      // Call cleanup on the volunteers group
      await UserPreferences.cleanupEmptyGroup('volunteers');
      
      // Verify the volunteers group was NOT deleted
      final groupDoc = await firestore.collection('groups').doc('volunteers').get();
      expect(groupDoc.exists, true);
    });

    test('cleanupEmptyGroup should not delete groups with members', () async {
      // Group already has members, should not be deleted
      await UserPreferences.cleanupEmptyGroup('test-group-123');
      
      // Verify the group still exists
      final groupDoc = await firestore.collection('groups').doc('test-group-123').get();
      expect(groupDoc.exists, true);
      
      // Verify sub-collections still exist
      final messages = await firestore.collection('groups').doc('test-group-123')
          .collection('messages').get();
      expect(messages.docs.isNotEmpty, true);
    });
  });
}
