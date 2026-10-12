/// A post's reaction counts plus the signed-in member's own reaction.
typedef ReactionState = ({Map<PostReaction, int> counts, PostReaction? mine});

/// The emoji reactions a member can leave on a post (one per member).
enum PostReaction {
  love('love', '❤️', 'Love'),
  laugh('laugh', '😂', 'Haha'),
  fire('fire', '🔥', 'Fire'),
  clap('clap', '👏', 'Applause'),
  wow('wow', '😮', 'Wow');

  const PostReaction(this.apiName, this.emoji, this.label);

  /// Wire name used by the API.
  final String apiName;
  final String emoji;
  final String label;

  static PostReaction? fromApi(Object? value) {
    for (final reaction in values) {
      if (reaction.apiName == value) return reaction;
    }
    return null;
  }

  /// Parses `{ "love": 3, "laugh": 1 }`, ignoring unknown kinds.
  static Map<PostReaction, int> countsFromJson(Object? json) {
    if (json is! Map) return const {};
    return {
      for (final entry in json.entries)
        if (fromApi(entry.key) != null && entry.value is int && (entry.value as int) > 0)
          fromApi(entry.key)!: entry.value as int,
    };
  }

  static Map<String, int> countsToJson(Map<PostReaction, int> counts) =>
      {for (final entry in counts.entries) entry.key.apiName: entry.value};
}
