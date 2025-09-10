import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/feed_post.dart';
import '../models/user_profile.dart';

class FeedService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'feed_posts';

  // Create a new feed post
  static Future<String?> createPost({
    required String content,
    required UserProfile user,
    String? parentPostId, // For replies
  }) async {
    try {
      // Check permissions
      if (!_canUserPost(user, isReply: parentPostId != null)) {
        throw Exception('User does not have permission to post');
      }

      // Get current location (only for original posts)
      Position? position;
      String? locationName;
      
      if (parentPostId == null) {
        position = await _getCurrentPosition();
        locationName = await _getLocationName(position);
      } else {
        // For replies, use parent post's location
        final parentDoc = await _firestore.collection(_collection).doc(parentPostId).get();
        if (parentDoc.exists) {
          final parentPost = FeedPost.fromMap(parentDoc.data()!);
          position = Position(
            latitude: parentPost.latitude,
            longitude: parentPost.longitude,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
          locationName = parentPost.locationName;
        }
      }

      if (position == null) {
        throw Exception('Could not determine location');
      }

      // Extract hashtags from content
      List<String> hashtags = extractHashtags(content);

      // Create post document
      final docRef = _firestore.collection(_collection).doc();
      final post = FeedPost(
        id: docRef.id,
        userId: user.uid,
        userName: user.displayName,
        userRole: user.role.toString(),
        content: content,
        hashtags: hashtags,
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: locationName,
        createdAt: DateTime.now(),
        parentPostId: parentPostId,
      );

      // Use batch to update post and parent reply count
      final batch = _firestore.batch();
      batch.set(docRef, post.toMap());

      // If this is a reply, increment parent's reply count
      if (parentPostId != null) {
        final parentRef = _firestore.collection(_collection).doc(parentPostId);
        batch.update(parentRef, {
          'replyCount': FieldValue.increment(1),
        });
      }

      await batch.commit();
      return docRef.id;
    } catch (e) {
      print('Error creating feed post: $e');
      return null;
    }
  }

  // Check if user can post
  static bool _canUserPost(UserProfile user, {bool isReply = false}) {
    if (isReply) {
      // Volunteers and organizers can reply to attendee posts
      return user.role == UserRole.volunteer || 
             user.role == UserRole.organizer ||
             user.role == UserRole.participant;
    } else {
      // Only attendees can create original posts
      return user.role == UserRole.participant;
    }
  }

  // Get posts visible to user (role-based)
  static Stream<List<FeedPost>> getPostsStreamForUser(UserProfile user) {
    print('🐛 FeedService: getPostsStreamForUser called for user: ${user.displayName} (${user.role})');
    
    Query query = _firestore
        .collection(_collection)
        .where('parentPostId', isNull: true) // Only original posts
        .orderBy('createdAt', descending: true);

    // Attendees see only attendee posts
    if (user.role == UserRole.participant) {
      print('🐛 FeedService: User is participant, filtering to participant posts only');
      query = query.where('userRole', isEqualTo: UserRole.participant.toString());
    } else {
      print('🐛 FeedService: User is ${user.role}, showing all attendee posts');
    }
    // Volunteers and organizers see all attendee posts (no additional filter needed)

    return query.snapshots().map((snapshot) {
      print('🐛 FeedService: Got snapshot with ${snapshot.docs.length} documents');
      final posts = snapshot.docs.map((doc) {
        try {
          return FeedPost.fromMap(doc.data() as Map<String, dynamic>);
        } catch (e) {
          print('🐛 FeedService: Error parsing post ${doc.id}: $e');
          return null;
        }
      }).where((post) => post != null).cast<FeedPost>().toList();
      print('🐛 FeedService: Successfully parsed ${posts.length} posts');
      return posts;
    });
  }

  // Get replies for a specific post
  static Stream<List<FeedPost>> getRepliesStream(String postId) {
    return _firestore
        .collection(_collection)
        .where('parentPostId', isEqualTo: postId)
        .orderBy('createdAt', descending: false) // Chronological order for replies
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FeedPost.fromMap(doc.data()))
            .toList());
  }

  // Get posts by hashtag (visible to user)
  static Stream<List<FeedPost>> getPostsByHashtagStreamForUser(String hashtag, UserProfile user) {
    Query query = _firestore
        .collection(_collection)
        .where('parentPostId', isNull: true) // Only original posts
        .where('hashtags', arrayContains: hashtag.toLowerCase())
        .orderBy('createdAt', descending: true);

    // Apply role-based filtering
    if (user.role == UserRole.participant) {
      query = query.where('userRole', isEqualTo: UserRole.participant.toString());
    }

    return query.snapshots().map((snapshot) => 
        snapshot.docs.map((doc) => FeedPost.fromMap(doc.data() as Map<String, dynamic>)).toList());
  }

  // Update existing post
  static Future<bool> updatePost({
    required String postId,
    required String newContent,
    required String userId,
  }) async {
    try {
      final docRef = _firestore.collection(_collection).doc(postId);
      final doc = await docRef.get();
      
      if (!doc.exists) return false;
      
      final post = FeedPost.fromMap(doc.data()!);
      
      // Check if user owns the post
      if (post.userId != userId) {
        throw Exception('User can only edit their own posts');
      }

      // Extract new hashtags
      List<String> hashtags = extractHashtags(newContent);

      await docRef.update({
        'content': newContent,
        'hashtags': hashtags,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isEdited': true,
      });

      return true;
    } catch (e) {
      print('Error updating feed post: $e');
      return false;
    }
  }

  // Delete post (and all its replies)
  static Future<bool> deletePost({
    required String postId,
    required String userId,
  }) async {
    try {
      final docRef = _firestore.collection(_collection).doc(postId);
      final doc = await docRef.get();
      
      if (!doc.exists) return false;
      
      final post = FeedPost.fromMap(doc.data()!);
      
      // Check if user owns the post
      if (post.userId != userId) {
        throw Exception('User can only delete their own posts');
      }

      final batch = _firestore.batch();

      // Delete the post
      batch.delete(docRef);

      // If it's an original post, delete all replies
      if (post.isOriginalPost) {
        final repliesSnapshot = await _firestore
            .collection(_collection)
            .where('parentPostId', isEqualTo: postId)
            .get();
        
        for (var replyDoc in repliesSnapshot.docs) {
          batch.delete(replyDoc.reference);
        }
      } else {
        // If it's a reply, decrement parent's reply count
        if (post.parentPostId != null) {
          final parentRef = _firestore.collection(_collection).doc(post.parentPostId!);
          batch.update(parentRef, {
            'replyCount': FieldValue.increment(-1),
          });
        }
      }

      await batch.commit();
      return true;
    } catch (e) {
      print('Error deleting feed post: $e');
      return false;
    }
  }

  // Get trending hashtags (from attendee posts only)
  static Future<List<String>> getTrendingHashtags({int limit = 10}) async {
    print('🐛 FeedService: getTrendingHashtags called');
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('parentPostId', isNull: true) // Only original posts
          .where('userRole', isEqualTo: UserRole.participant.toString()) // Only attendee posts
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      print('🐛 FeedService: Got ${snapshot.docs.length} documents for trending hashtags');
      Map<String, int> hashtagCount = {};
      
      for (var doc in snapshot.docs) {
        try {
          final post = FeedPost.fromMap(doc.data());
          for (String hashtag in post.hashtags) {
            hashtagCount[hashtag] = (hashtagCount[hashtag] ?? 0) + 1;
          }
        } catch (e) {
          print('🐛 FeedService: Error parsing document ${doc.id} for hashtags: $e');
        }
      }

      var sortedEntries = hashtagCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final result = sortedEntries
          .take(limit)
          .map((entry) => entry.key)
          .toList();
      
      print('🐛 FeedService: Returning ${result.length} trending hashtags: $result');
      return result;
    } catch (e) {
      print('🐛 FeedService: Error getting trending hashtags: $e');
      return [];
    }
  }

  // Helper: Extract hashtags from content
  static List<String> extractHashtags(String content) {
    final RegExp hashtagRegex = RegExp(r'#(\w+)');
    final matches = hashtagRegex.allMatches(content);
    return matches
        .map((match) => match.group(1)?.toLowerCase() ?? '')
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }

  // Helper: Get current position
  static Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition();
  }

  // Helper: Get location name from coordinates
  static Future<String?> _getLocationName(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.locality}, ${placemark.country}';
      }
    } catch (e) {
      print('Error getting location name: $e');
    }
    return null;
  }
}
