class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.person,
    required this.role,
    required this.company,
    required this.time,
    required this.body,
    required this.likes,
    required this.comments,
    required this.anonymous,
    required this.liked,
    this.canReact = true,
    this.isOwner = false,
    this.isDeleted = false,
    this.isArchived = false,
    this.isAdmin = false,
  });

  final String id;
  final String person;
  final String role;
  final String company;
  final String time;
  final String body;
  final int likes;
  final int comments;
  final bool anonymous;
  final bool liked;

  /// Members can only react to posts from their own company.
  final bool canReact;

  /// The signed-in member wrote this post and may edit or delete it.
  final bool isOwner;

  /// Soft-deleted on the server; kept in the payload but never shown.
  final bool isDeleted;

  /// Hidden from everyone except the author.
  final bool isArchived;

  /// Published by the Office Gossip team.
  final bool isAdmin;

  CommunityPost copyWith({
    String? body,
    int? likes,
    bool? liked,
    bool? isDeleted,
    bool? isArchived,
  }) =>
      CommunityPost(
        id: id,
        person: person,
        role: role,
        company: company,
        time: time,
        body: body ?? this.body,
        likes: likes ?? this.likes,
        comments: comments,
        anonymous: anonymous,
        liked: liked ?? this.liked,
        canReact: canReact,
        isOwner: isOwner,
        isDeleted: isDeleted ?? this.isDeleted,
        isArchived: isArchived ?? this.isArchived,
        isAdmin: isAdmin,
      );
}
