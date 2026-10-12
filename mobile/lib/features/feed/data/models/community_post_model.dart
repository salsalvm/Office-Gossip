import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_reaction.dart';

class PostPollModel extends PostPoll {
  const PostPollModel(
      {required super.options, required super.totalVotes, super.myVote});

  factory PostPollModel.fromJson(Map<String, dynamic> json) => PostPollModel(
        options: [
          for (final option in json['options'] as List<dynamic>? ?? const [])
            PollOption(
              id: (option as Map)['id'].toString(),
              label: option['label'] as String? ?? '',
              votes: option['votes'] as int? ?? 0,
            ),
        ],
        totalVotes: json['totalVotes'] as int? ?? 0,
        myVote: json['myVote'] as String?,
      );

  static Map<String, dynamic> toJson(PostPoll poll) => {
        'options': [
          for (final option in poll.options)
            {'id': option.id, 'label': option.label, 'votes': option.votes},
        ],
        'totalVotes': poll.totalVotes,
        'myVote': poll.myVote,
      };
}

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
    super.isPending,
    super.isPinned,
    super.saved,
    super.poll,
    super.reactions,
    super.myReaction,
    super.createdAt,
  });

  factory CommunityPostModel.fromJson(Map<String, dynamic> json) {
    final likes = json['likes'] as int? ?? 0;
    final liked = json['liked'] as bool? ?? false;
    // Older API responses only carry likes/liked; those count as ❤️.
    final hasReactions = json.containsKey('reactions');
    return CommunityPostModel(
        id: json['id'].toString(),
        person: json['person'] as String? ?? 'Member',
        role: json['role'] as String? ?? '',
        company: json['company'] as String? ?? '',
        time: json['time'] as String? ?? '',
        body: json['body'] as String? ?? '',
        likes: likes,
        comments: json['comments'] as int? ?? 0,
        anonymous: json['anonymous'] as bool? ?? false,
        liked: liked,
        isOwner: json['isOwner'] as bool? ?? false,
        isDeleted: json['isDeleted'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        isAdmin: json['isAdmin'] as bool? ?? false,
        isPending: json['isPending'] as bool? ?? false,
        isPinned: json['isPinned'] as bool? ?? false,
        saved: json['saved'] as bool? ?? false,
        poll: json['poll'] is Map
            ? PostPollModel.fromJson(
                Map<String, dynamic>.from(json['poll'] as Map))
            : null,
        reactions: hasReactions
            ? PostReaction.countsFromJson(json['reactions'])
            : likes > 0
                ? {PostReaction.love: likes}
                : const {},
        myReaction: hasReactions
            ? PostReaction.fromApi(json['myReaction'])
            : liked
                ? PostReaction.love
                : null,
        createdAt: json['createdAt'] as String?,
      );
  }

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
        'isPending': isPending,
        'isPinned': isPinned,
        'saved': saved,
        if (poll != null) 'poll': PostPollModel.toJson(poll!),
        'reactions': PostReaction.countsToJson(reactions),
        'myReaction': myReaction?.apiName,
        'createdAt': createdAt,
      };
}
