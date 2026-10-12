import 'package:dio/dio.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/base_remote_data_source.dart';
import '../../domain/entities/block_entry.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/entities/post_reaction.dart';
import '../../domain/entities/topic.dart';
import '../models/announcement_model.dart';
import '../models/community_member_model.dart';
import '../models/community_post_model.dart';

abstract interface class ICommunityRemoteDataSource {
  /// Newest first; pass [before] (a post's `createdAt`) for the next page.
  /// [trending] ranks posts by interactions and pages by [offset] instead of [before].
  /// [tag] keeps posts with that #hashtag; [query] searches post text.
  Future<List<CommunityPostModel>> loadFeed(CommunityScope scope,
      {String? before,
      int? limit,
      bool trending = false,
      int? offset,
      String? tag,
      String? query});
  Future<List<Topic>> loadTopics(CommunityScope scope);
  Future<List<CommunityMemberModel>> loadPeople();
  Future<List<AnnouncementModel>> loadAnnouncements();

  /// Returns `true` when the post is held until the author's company is approved.
  Future<bool> createPost(
      {required String body, required bool anonymous, List<String>? poll});
  /// [reaction] null removes the member's reaction. Returns the updated counts.
  Future<ReactionState> setReaction(
      {required String postId, required PostReaction? reaction});
  Future<void> editPost({required String postId, required String body});
  Future<void> deletePost(String postId);
  Future<void> archivePost({required String postId, required bool archived});
  Future<void> reportPost({required String postId, required String reason});

  /// [optionId] null takes the vote back. Returns the updated poll.
  Future<PostPollModel> votePoll(
      {required String postId, required String? optionId});
  Future<void> setSaved({required String postId, required bool saved});
  Future<List<CommunityPostModel>> loadSaved();
  Future<void> blockAuthor({required String postId, required BlockKind kind});
  Future<void> blockMember({required String userId, required BlockKind kind});
  Future<void> unblockMember(String userId);
  Future<List<BlockEntry>> loadBlocks();
  Future<void> removeBlock(String blockId);
}

class CommunityRemoteDataSource extends BaseRemoteDataSource
    implements ICommunityRemoteDataSource {
  CommunityRemoteDataSource(this._dio);

  final Dio _dio;

  @override
  Future<List<CommunityPostModel>> loadFeed(CommunityScope scope,
      {String? before,
      int? limit,
      bool trending = false,
      int? offset,
      String? tag,
      String? query}) {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(
        ApiEndpoints.communityFeed,
        queryParameters: {
          'scope': scope.name,
          if (limit != null) 'limit': limit,
          if (before != null) 'before': before,
          if (trending) 'sort': 'trending',
          if (offset != null) 'offset': offset,
          if (tag != null) 'tag': tag,
          if (query != null) 'q': query,
        },
      );
      return mapList(response.data, CommunityPostModel.fromJson);
    });
  }

  @override
  Future<List<Topic>> loadTopics(CommunityScope scope) {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(ApiEndpoints.communityTopics,
          queryParameters: {'scope': scope.name});
      return mapList(response.data, Topic.fromJson);
    });
  }

  @override
  Future<List<CommunityMemberModel>> loadPeople() {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(ApiEndpoints.communityPeople);
      return mapList(response.data, CommunityMemberModel.fromJson);
    });
  }

  @override
  Future<List<AnnouncementModel>> loadAnnouncements() {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(ApiEndpoints.announcements);
      return mapList(response.data, AnnouncementModel.fromJson);
    });
  }

  @override
  Future<bool> createPost(
      {required String body, required bool anonymous, List<String>? poll}) {
    return safeApiCall(() async {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.communityPosts,
        data: {
          'body': body,
          'anonymous': anonymous,
          if (poll != null) 'poll': poll,
        },
      );
      final data = response.data;
      return data is Map && data['pending'] == true;
    });
  }

  @override
  Future<ReactionState> setReaction(
      {required String postId, required PostReaction? reaction}) {
    return safeApiCall(() async {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.communityPostReactions(postId),
        data: {'reaction': reaction?.apiName},
      );
      final data = response.data as Map;
      return (
        counts: PostReaction.countsFromJson(data['reactions']),
        mine: PostReaction.fromApi(data['myReaction']),
      );
    });
  }

  @override
  Future<void> editPost({required String postId, required String body}) {
    return safeApiCall(() async {
      await _dio.patch<dynamic>(
        ApiEndpoints.communityPost(postId),
        data: {'body': body},
      );
    });
  }

  @override
  Future<void> deletePost(String postId) {
    return safeApiCall(() async {
      await _dio.delete<dynamic>(ApiEndpoints.communityPost(postId));
    });
  }

  @override
  Future<void> archivePost({required String postId, required bool archived}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPostArchive(postId),
        data: {'archived': archived},
      );
    });
  }

  @override
  Future<void> reportPost({required String postId, required String reason}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPostReport(postId),
        data: {'reason': reason},
      );
    });
  }

  @override
  Future<PostPollModel> votePoll(
      {required String postId, required String? optionId}) {
    return safeApiCall(() async {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.communityPostVote(postId),
        data: {'optionId': optionId},
      );
      final data = response.data as Map;
      return PostPollModel.fromJson(
          Map<String, dynamic>.from(data['poll'] as Map));
    });
  }

  @override
  Future<void> setSaved({required String postId, required bool saved}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPostSave(postId),
        data: {'saved': saved},
      );
    });
  }

  @override
  Future<List<CommunityPostModel>> loadSaved() {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(ApiEndpoints.meSaved);
      return mapList(response.data, CommunityPostModel.fromJson);
    });
  }

  @override
  Future<void> blockAuthor({required String postId, required BlockKind kind}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPostBlock(postId),
        data: {'kind': kind.name},
      );
    });
  }

  @override
  Future<void> blockMember({required String userId, required BlockKind kind}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPersonBlock(userId),
        data: {'kind': kind.name},
      );
    });
  }

  @override
  Future<void> unblockMember(String userId) {
    return safeApiCall(() async {
      await _dio.delete<dynamic>(ApiEndpoints.communityPersonBlock(userId));
    });
  }

  @override
  Future<List<BlockEntry>> loadBlocks() {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(ApiEndpoints.meBlocks);
      return mapList(response.data, BlockEntry.fromJson);
    });
  }

  @override
  Future<void> removeBlock(String blockId) {
    return safeApiCall(() async {
      await _dio.delete<dynamic>(ApiEndpoints.meBlock(blockId));
    });
  }
}
