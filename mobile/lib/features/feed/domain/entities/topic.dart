/// A popular #hashtag in recent posts, with how many posts used it.
class Topic {
  const Topic({required this.tag, required this.posts});

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        tag: json['tag'] as String? ?? '',
        posts: json['posts'] as int? ?? 0,
      );

  /// Lowercase, without the `#`.
  final String tag;
  final int posts;
}
