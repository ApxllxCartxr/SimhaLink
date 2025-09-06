class FeedPost {
  final String id;
  final String userId;
  final String userName;
  final String userRole;
  final String content;
  final List<String> hashtags;
  final double latitude;
  final double longitude;
  final String? locationName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isEdited;
  final String? parentPostId; // For replies
  final int replyCount; // Cache reply count
  final Map<String, dynamic>? metadata;

  const FeedPost({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.content,
    required this.hashtags,
    required this.latitude,
    required this.longitude,
    this.locationName,
    required this.createdAt,
    this.updatedAt,
    this.isEdited = false,
    this.parentPostId,
    this.replyCount = 0,
    this.metadata,
  });

  bool get isReply => parentPostId != null;
  bool get isOriginalPost => parentPostId == null;

  factory FeedPost.fromMap(Map<String, dynamic> map) {
    return FeedPost(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userRole: map['userRole'] ?? '',
      content: map['content'] ?? '',
      hashtags: List<String>.from(map['hashtags'] ?? []),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      locationName: map['locationName'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt']) 
          : null,
      isEdited: map['isEdited'] ?? false,
      parentPostId: map['parentPostId'],
      replyCount: map['replyCount'] ?? 0,
      metadata: map['metadata'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'content': content,
      'hashtags': hashtags,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'isEdited': isEdited,
      'parentPostId': parentPostId,
      'replyCount': replyCount,
      'metadata': metadata,
    };
  }

  FeedPost copyWith({
    String? content,
    List<String>? hashtags,
    DateTime? updatedAt,
    bool? isEdited,
    int? replyCount,
    Map<String, dynamic>? metadata,
  }) {
    return FeedPost(
      id: id,
      userId: userId,
      userName: userName,
      userRole: userRole,
      content: content ?? this.content,
      hashtags: hashtags ?? this.hashtags,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEdited: isEdited ?? this.isEdited,
      parentPostId: parentPostId,
      replyCount: replyCount ?? this.replyCount,
      metadata: metadata ?? this.metadata,
    );
  }
}
