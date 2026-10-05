import '../../../../core/storage/cache_store.dart';
import '../../../../core/utils/cached.dart';
import '../../domain/entities/community_scope.dart';
import '../models/announcement_model.dart';
import '../models/community_member_model.dart';
import '../models/community_post_model.dart';

abstract interface class ICommunityLocalDataSource {
  Cached<List<CommunityPostModel>>? feed(CommunityScope scope);
  Future<void> saveFeed(CommunityScope scope, List<CommunityPostModel> posts);
  Cached<List<CommunityMemberModel>>? people();
  Future<void> savePeople(List<CommunityMemberModel> people);
  Cached<List<AnnouncementModel>>? announcements();
  Future<void> saveAnnouncements(List<AnnouncementModel> announcements);
}

class CommunityLocalDataSource implements ICommunityLocalDataSource {
  CommunityLocalDataSource(this._cache);

  final CacheStore _cache;

  static String _feedKey(CommunityScope scope) => 'feed_${scope.name}';
  static const _peopleKey = 'people';
  static const _announcementsKey = 'announcements';

  Cached<List<T>>? _readList<T>(
      String key, T Function(Map<String, dynamic>) fromJson) {
    final entry = _cache.read(key);
    final data = entry?.data;
    if (entry == null || data is! List) return null;
    try {
      return Cached(
        data.whereType<Map<String, dynamic>>().map(fromJson).toList(),
        entry.savedAt,
      );
    } on Object {
      return null;
    }
  }

  @override
  Cached<List<CommunityPostModel>>? feed(CommunityScope scope) =>
      _readList(_feedKey(scope), CommunityPostModel.fromJson);

  @override
  Future<void> saveFeed(CommunityScope scope, List<CommunityPostModel> posts) =>
      _cache.write(
          _feedKey(scope), posts.map((post) => post.toJson()).toList());

  @override
  Cached<List<CommunityMemberModel>>? people() =>
      _readList(_peopleKey, CommunityMemberModel.fromJson);

  @override
  Future<void> savePeople(List<CommunityMemberModel> people) => _cache.write(
      _peopleKey, people.map((person) => person.toJson()).toList());

  @override
  Cached<List<AnnouncementModel>>? announcements() =>
      _readList(_announcementsKey, AnnouncementModel.fromJson);

  @override
  Future<void> saveAnnouncements(List<AnnouncementModel> announcements) =>
      _cache.write(_announcementsKey,
          announcements.map((announcement) => announcement.toJson()).toList());
}
