import 'post_reaction.dart';

class PollOption {
  const PollOption(
      {required this.id, required this.label, required this.votes});
  final String id;
  final String label;
  final int votes;
}

class PostPoll {
  const PostPoll(
      {required this.options, required this.totalVotes, this.myVote});
  final List<PollOption> options;
  final int totalVotes;

  /// The option the signed-in member voted for, or null before voting.
  final String? myVote;

  /// Whole-number share of the votes for [option], 0 when nobody voted yet.
  int percentFor(PollOption option) =>
      totalVotes == 0 ? 0 : (option.votes * 100 / totalVotes).round();
}

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
    this.isOwner = false,
    this.isDeleted = false,
    this.isArchived = false,
    this.isAdmin = false,
    this.isPending = false,
    this.isPinned = false,
    this.saved = false,
    this.poll,
    this.reactions = const {},
    this.myReaction,
    this.createdAt,
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

  /// The signed-in member wrote this post and may edit or delete it.
  final bool isOwner;

  /// Soft-deleted on the server; kept in the payload but never shown.
  final bool isDeleted;

  /// Hidden from everyone except the author.
  final bool isArchived;

  /// Published by the Office Gossip team.
  final bool isAdmin;

  /// Held until the author's company is approved; only the author sees it.
  final bool isPending;

  /// Pinned to Trending by an admin; only set on the Trending list.
  final bool isPinned;

  /// Bookmarked by the signed-in member (Profile › Saved posts).
  final bool saved;

  final PostPoll? poll;

  /// Reaction counts by kind; [likes] is their total.
  final Map<PostReaction, int> reactions;

  /// The signed-in member's reaction, or null; [liked] mirrors it.
  final PostReaction? myReaction;

  /// Up to three most-used reactions, most popular first.
  List<PostReaction> get topReactions {
    final used = reactions.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final entry in used.take(3)) entry.key];
  }

  /// This post with the member's reaction switched to [reaction] (null removes it), counts adjusted locally.
  CommunityPost withReaction(PostReaction? reaction) {
    final counts = Map<PostReaction, int>.of(reactions);
    final current = myReaction;
    if (current != null) {
      final left = (counts[current] ?? 0) - 1;
      if (left > 0) {
        counts[current] = left;
      } else {
        counts.remove(current);
      }
    }
    if (reaction != null) counts[reaction] = (counts[reaction] ?? 0) + 1;
    return withReactions(counts, reaction);
  }

  CommunityPost withReactions(
          Map<PostReaction, int> counts, PostReaction? mine) =>
      _copy(
        reactions: counts,
        myReaction: mine,
        likes: counts.values.fold<int>(0, (sum, count) => sum + count),
        liked: mine != null,
      );

  /// Server timestamp (ISO 8601); the cursor for loading older posts.
  final String? createdAt;

  CommunityPost copyWith({
    String? body,
    int? likes,
    bool? liked,
    bool? isDeleted,
    bool? isArchived,
    bool? saved,
    PostPoll? poll,
  }) =>
      _copy(
        body: body,
        likes: likes,
        liked: liked,
        isDeleted: isDeleted,
        isArchived: isArchived,
        saved: saved,
        poll: poll,
        reactions: reactions,
        myReaction: myReaction,
      );

  CommunityPost _copy({
    String? body,
    int? likes,
    bool? liked,
    bool? isDeleted,
    bool? isArchived,
    bool? saved,
    PostPoll? poll,
    required Map<PostReaction, int> reactions,
    required PostReaction? myReaction,
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
        isOwner: isOwner,
        isDeleted: isDeleted ?? this.isDeleted,
        isArchived: isArchived ?? this.isArchived,
        isAdmin: isAdmin,
        isPending: isPending,
        isPinned: isPinned,
        saved: saved ?? this.saved,
        poll: poll ?? this.poll,
        reactions: reactions,
        myReaction: myReaction,
        createdAt: createdAt,
      );
}
