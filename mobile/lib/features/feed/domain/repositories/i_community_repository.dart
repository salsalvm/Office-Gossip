import '../../../../core/utils/type_def.dart';
import '../entities/community_member.dart';
import '../entities/community_post.dart';
import '../entities/community_scope.dart';

abstract interface class ICommunityRepository {
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope);
  ResultFuture<List<CommunityMember>> loadPeople();
  ResultVoid createPost({required String body, required bool anonymous});
  ResultVoid toggleLike(String postId);
}
