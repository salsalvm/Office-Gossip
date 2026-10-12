import 'package:fpdart/fpdart.dart';

import '../../../../core/network/base_repository.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/block_entry.dart';
import '../../domain/entities/community_member.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/entities/post_reaction.dart';
import '../../domain/entities/topic.dart';
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
  ResultFuture<List<CommunityPost>> loadFeed(CommunityScope scope,
          {String? before,
          int? limit,
          bool trending = false,
          int? offset,
          String? tag,
          String? query}) =>
      handleRequest(() async {
        final posts = await _remoteDataSource.loadFeed(scope,
            before: before,
            limit: limit,
            trending: trending,
            offset: offset,
            tag: tag,
            query: query);
        if (before == null && !trending && tag == null && query == null) {
          await _localDataSource.saveFeed(scope, posts);
        }
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
  ResultFuture<bool> createPost(
      {required String body, required bool anonymous, List<String>? poll}) {
    return handleRequest(() => _remoteDataSource.createPost(
        body: body, anonymous: anonymous, poll: poll));
  }

  @override
  ResultFuture<PostPoll> votePoll(
          {required String postId, required String? optionId}) =>
      handleRequest(
          () => _remoteDataSource.votePoll(postId: postId, optionId: optionId));

  @override
  ResultVoid setSaved({required String postId, required bool saved}) =>
      handleRequest(() async {
        await _remoteDataSource.setSaved(postId: postId, saved: saved);
        return unit;
      });

  @override
  ResultFuture<List<CommunityPost>> loadSaved() =>
      handleRequest(_remoteDataSource.loadSaved);

  @override
  ResultVoid blockAuthor({required String postId, required BlockKind kind}) =>
      handleRequest(() async {
        await _remoteDataSource.blockAuthor(postId: postId, kind: kind);
        return unit;
      });

  @override
  ResultVoid blockMember({required String userId, required BlockKind kind}) =>
      handleRequest(() async {
        await _remoteDataSource.blockMember(userId: userId, kind: kind);
        return unit;
      });

  @override
  ResultVoid unblockMember(String userId) => handleRequest(() async {
        await _remoteDataSource.unblockMember(userId);
        return unit;
      });

  @override
  ResultFuture<List<BlockEntry>> loadBlocks() =>
      handleRequest(_remoteDataSource.loadBlocks);

  @override
  ResultVoid removeBlock(String blockId) => handleRequest(() async {
        await _remoteDataSource.removeBlock(blockId);
        return unit;
      });

  @override
  ResultFuture<List<Topic>> loadTopics(CommunityScope scope) =>
      handleRequest(() => _remoteDataSource.loadTopics(scope));

  @override
  ResultFuture<ReactionState> setReaction(
          {required String postId, required PostReaction? reaction}) =>
      handleRequest(() =>
          _remoteDataSource.setReaction(postId: postId, reaction: reaction));

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
