import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/announcement.dart';
import '../entities/block_entry.dart';
import '../entities/community_member.dart';
import '../entities/community_post.dart';
import '../entities/community_scope.dart';
import '../entities/post_reaction.dart';
import '../entities/topic.dart';

/// Network-first reads also refresh an on-device cache; the `cached*`
/// getters return that last good copy so screens can render instantly or
/// keep working offline.
abstract interface class ICommunityRepository {
  Cached<List<CommunityPost>>? cachedFeed(CommunityScope scope);
  Cached<List<CommunityMember>>? cachedPeople();
  Cached<List<Announcement>>? cachedAnnouncements();

  /// First page when [before] is null (also refreshes the cache unless
  /// filtered by [tag]/[query]), otherwise the page of posts older than [before].
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope,
      {String? before,
      int? limit,
      bool trending = false,
      int? offset,
      String? tag,
      String? query});
  ResultFuture<List<Topic>> loadTopics(CommunityScope scope);
  ResultFuture<List<CommunityMember>> loadPeople();
  ResultFuture<List<Announcement>> loadAnnouncements();

  /// Resolves to `true` when the post is held until the author's company is approved.
  ResultFuture<bool> createPost(
      {required String body, required bool anonymous, List<String>? poll});
  /// [reaction] null removes the member's reaction.
  ResultFuture<ReactionState> setReaction(
      {required String postId, required PostReaction? reaction});
  ResultVoid editPost({required String postId, required String body});
  ResultVoid deletePost(String postId);
  ResultVoid archivePost({required String postId, required bool archived});
  ResultVoid reportPost({required String postId, required String reason});

  /// [optionId] null takes the vote back. Resolves to the updated poll.
  ResultFuture<PostPoll> votePoll(
      {required String postId, required String? optionId});
  ResultVoid setSaved({required String postId, required bool saved});
  ResultFuture<List<CommunityPost>> loadSaved();

  /// Blocks or mutes a post's author; anonymous authors stay anonymous.
  ResultVoid blockAuthor({required String postId, required BlockKind kind});
  ResultVoid blockMember({required String userId, required BlockKind kind});
  ResultVoid unblockMember(String userId);
  ResultFuture<List<BlockEntry>> loadBlocks();
  ResultVoid removeBlock(String blockId);
}
