import 'package:fpdart/fpdart.dart';

import '../../../../core/network/base_repository.dart';
import '../../../../core/utils/type_def.dart';
import '../../domain/entities/community_member.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/repositories/i_community_repository.dart';
import '../datasources/community_remote_datasource.dart';

class CommunityRepositoryImpl extends BaseRepository
    implements ICommunityRepository {
  CommunityRepositoryImpl(this._remoteDataSource);

  final ICommunityRemoteDataSource _remoteDataSource;

  @override
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope) =>
      handleRequest(() => _remoteDataSource.loadFeed(scope));

  @override
  ResultFuture<List<CommunityMember>> loadPeople() =>
      handleRequest(_remoteDataSource.loadPeople);

  @override
  ResultVoid createPost({required String body, required bool anonymous}) {
    return handleRequest(() async {
      await _remoteDataSource.createPost(body: body, anonymous: anonymous);
      return unit;
    });
  }

  @override
  ResultVoid toggleLike(String postId) {
    return handleRequest(() async {
      await _remoteDataSource.toggleLike(postId);
      return unit;
    });
  }
}
