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
    super.isOwner,
    super.isDeleted,
    super.isArchived,
    super.isAdmin,
    super.createdAt,
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
        isOwner: json['isOwner'] as bool? ?? false,
        isDeleted: json['isDeleted'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        isAdmin: json['isAdmin'] as bool? ?? false,
        createdAt: json['createdAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'person': person,
        'role': role,
        'company': company,
        'time': time,
        'body': body,
        'likes': likes,
        'comments': comments,
        'anonymous': anonymous,
        'liked': liked,
        'isOwner': isOwner,
        'isDeleted': isDeleted,
        'isArchived': isArchived,
        'isAdmin': isAdmin,
        'createdAt': createdAt,
      };
}
