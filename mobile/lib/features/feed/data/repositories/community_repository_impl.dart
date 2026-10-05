import 'package:fpdart/fpdart.dart';

import '../../../../core/network/base_repository.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/community_member.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/repositories/i_community_repository.dart';
import '../datasources/community_local_datasource.dart';
import '../datasources/community_remote_datasource.dart';

class CommunityRepositoryImpl extends BaseRepository
    implements ICommunityRepository {
  CommunityRepositoryImpl(this._remoteDataSource, this._localDataSource);

  final ICommunityRemoteDataSource _remoteDataSource;
  final ICommunityLocalDataSource _localDataSource;

  @override
  Cached<List<CommunityPost>>? cachedFeed(CommunityScope scope) =>
      _localDataSource.feed(scope);

  @override
  Cached<List<CommunityMember>>? cachedPeople() => _localDataSource.people();

  @override
  Cached<List<Announcement>>? cachedAnnouncements() =>
      _localDataSource.announcements();

  @override
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope) =>
      handleRequest(() async {
        final posts = await _remoteDataSource.loadFeed(scope);
        await _localDataSource.saveFeed(scope, posts);
        return posts;
      });

  @override
  ResultFuture<List<CommunityMember>> loadPeople() => handleRequest(() async {
        final people = await _remoteDataSource.loadPeople();
        await _localDataSource.savePeople(people);
        return people;
      });

  @override
  ResultFuture<List<Announcement>> loadAnnouncements() =>
      handleRequest(() async {
        final announcements = await _remoteDataSource.loadAnnouncements();
        await _localDataSource.saveAnnouncements(announcements);
        return announcements;
      });

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

  @override
  ResultVoid editPost({required String postId, required String body}) {
    return handleRequest(() async {
      await _remoteDataSource.editPost(postId: postId, body: body);
      return unit;
    });
  }

  @override
  ResultVoid deletePost(String postId) {
    return handleRequest(() async {
      await _remoteDataSource.deletePost(postId);
      return unit;
    });
  }

  @override
  ResultVoid archivePost({required String postId, required bool archived}) {
    return handleRequest(() async {
      await _remoteDataSource.archivePost(postId: postId, archived: archived);
      return unit;
    });
  }

  @override
  ResultVoid reportPost({required String postId, required String reason}) {
    return handleRequest(() async {
      await _remoteDataSource.reportPost(postId: postId, reason: reason);
      return unit;
    });
  }
}
