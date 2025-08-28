class GroupModel {
  final String id;
  final String name;
  final String leaderId;
  final List<String> memberIds;
  final String joinCode;
  final DateTime createdAt;

  GroupModel({
    required this.id,
    required this.name,
    required this.leaderId,
    required this.memberIds,
    required this.joinCode,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'leaderId': leaderId,
      'memberIds': memberIds,
      'joinCode': joinCode,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      leaderId: map['leaderId'] ?? '',
      memberIds: List<String>.from(map['memberIds'] ?? []),
      joinCode: map['joinCode'] ?? '',
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
