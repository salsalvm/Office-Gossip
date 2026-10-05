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
}
