import '../../domain/entities/community_member.dart';

class CommunityMemberModel extends CommunityMember {
  const CommunityMemberModel({
    required super.id,
    required super.name,
    required super.role,
    required super.team,
  });

  factory CommunityMemberModel.fromJson(Map<String, dynamic> json) =>
      CommunityMemberModel(
        id: json['id'].toString(),
        name: json['name'] as String? ?? 'Member',
        role: json['role'] as String? ?? '',
        team: json['team'] as String? ?? '',
      );
}
