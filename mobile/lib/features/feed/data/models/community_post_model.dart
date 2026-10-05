import '../../domain/entities/community_post.dart';

class CommunityPostModel extends CommunityPost {
  const CommunityPostModel({
    required super.id,
    required super.person,
    required super.role,
    required super.company,
    required super.time,
    required super.body,
    required super.likes,
    required super.comments,
    required super.anonymous,
    required super.liked,
    super.canReact,
  });

  factory CommunityPostModel.fromJson(Map<String, dynamic> json) =>
      CommunityPostModel(
        id: json['id'].toString(),
        person: json['person'] as String? ?? 'Member',
        role: json['role'] as String? ?? '',
        company: json['company'] as String? ?? '',
        time: json['time'] as String? ?? '',
        body: json['body'] as String? ?? '',
        likes: json['likes'] as int? ?? 0,
        comments: json['comments'] as int? ?? 0,
        anonymous: json['anonymous'] as bool? ?? false,
        liked: json['liked'] as bool? ?? false,
        canReact: json['canReact'] as bool? ?? true,
      );
}
