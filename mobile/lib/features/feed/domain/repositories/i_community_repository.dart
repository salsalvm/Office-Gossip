import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/announcement.dart';
import '../entities/community_member.dart';
import '../entities/community_post.dart';
import '../entities/community_scope.dart';

/// Network-first reads also refresh an on-device cache; the `cached*`
/// getters return that last good copy so screens can render instantly or
/// keep working offline.
abstract interface class ICommunityRepository {
  Cached<List<CommunityPost>>? cachedFeed(CommunityScope scope);
  Cached<List<CommunityMember>>? cachedPeople();
  Cached<List<Announcement>>? cachedAnnouncements();

  /// First page when [before] is null (also refreshes the cache), otherwise
  /// the page of posts older than [before].
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope,
      {String? before, int? limit});
  ResultFuture<List<CommunityMember>> loadPeople();
  ResultFuture<List<Announcement>> loadAnnouncements();
  ResultVoid createPost({required String body, required bool anonymous});
  ResultVoid toggleLike(String postId);
  ResultVoid editPost({required String postId, required String body});
  ResultVoid deletePost(String postId);
  ResultVoid archivePost({required String postId, required bool archived});
  ResultVoid reportPost({required String postId, required String reason});
}
