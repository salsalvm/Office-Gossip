import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/usecases/archive_post_usecase.dart';
import '../../domain/usecases/create_post_usecase.dart';
import '../../domain/usecases/delete_post_usecase.dart';
import '../../domain/usecases/edit_post_usecase.dart';
import '../../domain/usecases/load_announcements_usecase.dart';
import '../../domain/usecases/load_feed_usecase.dart';
import '../../domain/usecases/report_post_usecase.dart';
import '../../domain/usecases/toggle_post_like_usecase.dart';

sealed class FeedEvent extends Equatable {
  const FeedEvent();
  @override
  List<Object?> get props => [];
}

/// Reloads the current scope's feed.
final class FeedRequested extends FeedEvent {
  const FeedRequested();
}

/// Appends the next page of older posts.
final class FeedMoreRequested extends FeedEvent {
  const FeedMoreRequested();
}

final class FeedScopeChanged extends FeedEvent {
  const FeedScopeChanged(this.scope);
  final CommunityScope scope;
  @override
  List<Object?> get props => [scope];
}

final class PostLikeRequested extends FeedEvent {
  const PostLikeRequested(this.postId);
  final String postId;
  @override
  List<Object?> get props => [postId];
}

final class PostCreateRequested extends FeedEvent {
  const PostCreateRequested({required this.body, required this.anonymous});
  final String body;
  final bool anonymous;
  @override
  List<Object?> get props => [body, anonymous];
}

final class PostEditRequested extends FeedEvent {
  const PostEditRequested({required this.postId, required this.body});
  final String postId;
  final String body;
  @override
  List<Object?> get props => [postId, body];
}

final class PostDeleteRequested extends FeedEvent {
  const PostDeleteRequested(this.postId);
  final String postId;
  @override
  List<Object?> get props => [postId];
}

final class PostArchiveRequested extends FeedEvent {
  const PostArchiveRequested({required this.postId, required this.archived});
  final String postId;
  final bool archived;
  @override
  List<Object?> get props => [postId, archived];
}

final class PostReportRequested extends FeedEvent {
  const PostReportRequested({required this.postId, required this.reason});
  final String postId;
  final String reason;
  @override
  List<Object?> get props => [postId, reason];
}

enum FeedStatus { initial, loading, ready, failure }

class FeedState extends Equatable {
  const FeedState({
    this.scope = CommunityScope.global,
    this.status = FeedStatus.initial,
    this.posts = const [],
    this.announcements = const [],
    this.offline = false,
    this.syncedAt,
    this.hasMore = false,
    this.loadingMore = false,
    this.message,
    this.messageId = 0,
  });

  final CommunityScope scope;
  final FeedStatus status;
  final List<CommunityPost> posts;
  final List<Announcement> announcements;

  /// The last refresh failed, so [posts] are the cached copy from [syncedAt].
  final bool offline;
  final DateTime? syncedAt;

  /// The server may have older posts than the ones loaded.
  final bool hasMore;
  final bool loadingMore;

  /// One-off snackbar text; [messageId] changes each time so repeats still show.
  final String? message;
  final int messageId;

  FeedState copyWith({
    CommunityScope? scope,
    FeedStatus? status,
    List<CommunityPost>? posts,
    List<Announcement>? announcements,
    bool? offline,
    DateTime? syncedAt,
    bool? hasMore,
    bool? loadingMore,
    String? message,
  }) =>
      FeedState(
        scope: scope ?? this.scope,
        status: status ?? this.status,
        posts: posts ?? this.posts,
        announcements: announcements ?? this.announcements,
        offline: offline ?? this.offline,
        syncedAt: syncedAt ?? this.syncedAt,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        message: message,
        messageId: message == null ? messageId : messageId + 1,
      );

  @override
  List<Object?> get props => [
        scope,
        status,
        posts,
        announcements,
        offline,
        syncedAt,
        hasMore,
        loadingMore,
        message,
        messageId
      ];
}

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc({
    required LoadFeedUseCase loadFeed,
    required LoadAnnouncementsUseCase loadAnnouncements,
    required TogglePostLikeUseCase togglePostLike,
    required CreatePostUseCase createPost,
    required EditPostUseCase editPost,
    required DeletePostUseCase deletePost,
    required ReportPostUseCase reportPost,
    required ArchivePostUseCase archivePost,
    CommunityScope initialScope = CommunityScope.global,
  })  : _loadFeed = loadFeed,
        _loadAnnouncements = loadAnnouncements,
        _togglePostLike = togglePostLike,
        _createPost = createPost,
        _editPost = editPost,
        _deletePost = deletePost,
        _reportPost = reportPost,
        _archivePost = archivePost,
        super(FeedState(scope: initialScope)) {
    on<FeedRequested>(_onRequested);
    on<FeedMoreRequested>(_onMore);
    on<FeedScopeChanged>(_onScopeChanged);
    on<PostLikeRequested>(_onLike);
    // Repeat taps while a request is still running are dropped, so one tap = one post/edit/report.
    on<PostCreateRequested>(_onCreate, transformer: droppable());
    on<PostEditRequested>(_onEdit, transformer: droppable());
    on<PostDeleteRequested>(_onDelete, transformer: droppable());
    on<PostReportRequested>(_onReport, transformer: droppable());
    on<PostArchiveRequested>(_onArchive, transformer: droppable());
  }

  final LoadFeedUseCase _loadFeed;
  final LoadAnnouncementsUseCase _loadAnnouncements;
  final TogglePostLikeUseCase _togglePostLike;
  final CreatePostUseCase _createPost;
  final EditPostUseCase _editPost;
  final DeletePostUseCase _deletePost;
  final ReportPostUseCase _reportPost;
  final ArchivePostUseCase _archivePost;

  Future<void> _onRequested(
      FeedRequested event, Emitter<FeedState> emit) async {
    _emitCached(emit, state.scope, keepCurrent: true);
    await _load(emit);
  }

  /// Shows the last synced copy straight away (Instagram-style) while the
  /// network request runs; [keepCurrent] keeps posts already on screen.
  void _emitCached(Emitter<FeedState> emit, CommunityScope scope,
      {bool keepCurrent = false}) {
    final cachedPosts = _loadFeed.cached(scope);
    final cachedAnnouncements = _loadAnnouncements.cached();
    final posts = keepCurrent && state.posts.isNotEmpty
        ? state.posts
        : cachedPosts?.data ?? const <CommunityPost>[];
    emit(FeedState(
      scope: scope,
      status: FeedStatus.loading,
      posts: posts,
      announcements: state.announcements.isNotEmpty
          ? state.announcements
          : cachedAnnouncements?.data ?? const [],
      offline: state.offline,
      syncedAt: keepCurrent && state.posts.isNotEmpty
          ? state.syncedAt
          : cachedPosts?.savedAt,
      messageId: state.messageId,
    ));
  }

  Future<void> _onScopeChanged(
      FeedScopeChanged event, Emitter<FeedState> emit) async {
    if (event.scope == state.scope && state.status != FeedStatus.initial) {
      return;
    }
    _emitCached(emit, event.scope);
    await _load(emit);
  }

  Future<void> _load(Emitter<FeedState> emit) async {
    final scope = state.scope;
    final announcementsRequest = _loadAnnouncements(const NoParams());
    final result = await _loadFeed(scope);
    // Announcements are best-effort; a failure keeps whatever was shown before.
    (await announcementsRequest).fold(
      (_) {},
      (announcements) => emit(state.copyWith(announcements: announcements)),
    );
    if (scope != state.scope) return;
    result.fold(
      (failure) => emit(state.posts.isNotEmpty
          ? state.copyWith(status: FeedStatus.ready, offline: true)
          : state.copyWith(
              status: FeedStatus.failure, message: failure.message)),
      (posts) => emit(state.copyWith(
        status: FeedStatus.ready,
        posts: posts,
        offline: false,
        syncedAt: DateTime.now(),
        hasMore: posts.length >= LoadFeedUseCase.pageSize,
        loadingMore: false,
      )),
    );
  }

  Future<void> _onMore(FeedMoreRequested event, Emitter<FeedState> emit) async {
    final cursor = state.posts.isEmpty ? null : state.posts.last.createdAt;
    if (!state.hasMore ||
        state.loadingMore ||
        state.offline ||
        state.status != FeedStatus.ready ||
        cursor == null) {
      return;
    }
    final scope = state.scope;
    emit(state.copyWith(loadingMore: true));
    final result = await _loadFeed.olderThan(scope, cursor);
    if (scope != state.scope || state.status != FeedStatus.ready) return;
    result.fold(
      (failure) =>
          emit(state.copyWith(loadingMore: false, message: failure.message)),
      (page) {
        final known = {for (final post in state.posts) post.id};
        emit(state.copyWith(
          posts: [
            ...state.posts,
            ...page.where((post) => !known.contains(post.id)),
          ],
          hasMore: page.length >= LoadFeedUseCase.pageSize,
          loadingMore: false,
        ));
      },
    );
  }

  final Set<String> _likesInFlight = {};

  Future<void> _onLike(PostLikeRequested event, Emitter<FeedState> emit) async {
    if (!_likesInFlight.add(event.postId)) return;
    try {
      await _toggleLike(event, emit);
    } finally {
      _likesInFlight.remove(event.postId);
    }
  }

  Future<void> _toggleLike(
      PostLikeRequested event, Emitter<FeedState> emit) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final post in previous)
        post.id == event.postId ? _toggled(post) : post,
    ]));
    final result = await _togglePostLike(event.postId);
    result.fold(
      (failure) =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) {},
    );
  }

  Future<void> _onCreate(
      PostCreateRequested event, Emitter<FeedState> emit) async {
    final result = await _createPost(
        CreatePostParams(body: event.body, anonymous: event.anonymous));
    await result.fold(
      (failure) async => emit(state.copyWith(message: failure.message)),
      (_) async {
        emit(state.copyWith(message: 'Your post was shared.'));
        await _load(emit);
      },
    );
  }

  Future<void> _onEdit(PostEditRequested event, Emitter<FeedState> emit) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final post in previous)
        post.id == event.postId ? post.copyWith(body: event.body) : post,
    ]));
    final result =
        await _editPost(EditPostParams(postId: event.postId, body: event.body));
    result.fold(
      (failure) =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) => emit(state.copyWith(message: 'Post updated.')),
    );
  }

  Future<void> _onDelete(
      PostDeleteRequested event, Emitter<FeedState> emit) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final post in previous)
        post.id == event.postId ? post.copyWith(isDeleted: true) : post,
    ]));
    final result = await _deletePost(event.postId);
    result.fold(
      (failure) =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) => emit(state.copyWith(message: 'Post deleted.')),
    );
  }

  Future<void> _onArchive(
      PostArchiveRequested event, Emitter<FeedState> emit) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final post in previous)
        post.id == event.postId
            ? post.copyWith(isArchived: event.archived)
            : post,
    ]));
    final result = await _archivePost(
        ArchivePostParams(postId: event.postId, archived: event.archived));
    result.fold(
      (failure) =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) => emit(state.copyWith(
          message: event.archived
              ? 'Post archived. Only you can see it now.'
              : 'Post restored to the feed.')),
    );
  }

  Future<void> _onReport(
      PostReportRequested event, Emitter<FeedState> emit) async {
    final result = await _reportPost(
        ReportPostParams(postId: event.postId, reason: event.reason));
    result.fold(
      (failure) => emit(state.copyWith(message: failure.message)),
      (_) => emit(
          state.copyWith(message: 'Thanks — our team will review this post.')),
    );
  }

  static CommunityPost _toggled(CommunityPost post) => post.copyWith(
        likes: post.likes + (post.liked ? -1 : 1),
        liked: !post.liked,
      );
}
