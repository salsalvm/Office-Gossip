import 'package:dio/dio.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/base_remote_data_source.dart';
import '../../domain/entities/community_scope.dart';
import '../models/announcement_model.dart';
import '../models/community_member_model.dart';
import '../models/community_post_model.dart';

abstract interface class ICommunityRemoteDataSource {
  Future<List<CommunityPostModel>> loadFeed(CommunityScope scope);
  Future<List<CommunityMemberModel>> loadPeople();
  Future<List<AnnouncementModel>> loadAnnouncements();
  Future<void> createPost({required String body, required bool anonymous});
  Future<void> toggleLike(String postId);
  Future<void> editPost({required String postId, required String body});
  Future<void> deletePost(String postId);
  Future<void> archivePost({required String postId, required bool archived});
  Future<void> reportPost({required String postId, required String reason});
}

class CommunityRemoteDataSource extends BaseRemoteDataSource
    implements ICommunityRemoteDataSource {
  CommunityRemoteDataSource(this._dio);

  final Dio _dio;

  @override
  Future<List<CommunityPostModel>> loadFeed(CommunityScope scope) {
    return safeApiCall(() async {
      final response = await _dio.get<dynamic>(
        ApiEndpoints.communityFeed,
        queryParameters: {'scope': scope.name},
      );
      return mapList(response.data, CommunityPostModel.fromJson);
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
  Future<void> createPost({required String body, required bool anonymous}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.communityPosts,
        data: {'body': body, 'anonymous': anonymous},
      );
    });
  }

  @override
  Future<void> toggleLike(String postId) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(ApiEndpoints.communityPostLikes(postId));
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
}
