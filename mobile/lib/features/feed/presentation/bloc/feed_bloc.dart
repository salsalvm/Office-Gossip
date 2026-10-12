import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/block_entry.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/entities/post_reaction.dart';
import '../../domain/entities/topic.dart';
import '../../domain/usecases/archive_post_usecase.dart';
import '../../domain/usecases/post_reaction_usecases.dart';
import '../../domain/usecases/block_usecases.dart';
import '../../domain/usecases/saved_posts_usecases.dart';
import '../../domain/usecases/vote_poll_usecase.dart';
import '../../domain/usecases/create_post_usecase.dart';
import '../../domain/usecases/delete_post_usecase.dart';
import '../../domain/usecases/edit_post_usecase.dart';
import '../../domain/usecases/load_announcements_usecase.dart';
import '../../domain/usecases/load_feed_usecase.dart';
import '../../domain/usecases/report_post_usecase.dart';

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

/// Quick ❤️: adds a love reaction, or removes whatever reaction the member left.
final class PostLikeRequested extends FeedEvent {
  const PostLikeRequested(this.postId);
  final String postId;
  @override
  List<Object?> get props => [postId];
}

/// Sets the member's reaction; null (or picking the current one) removes it.
final class PostReactionRequested extends FeedEvent {
  const PostReactionRequested({required this.postId, required this.reaction});
  final String postId;
  final PostReaction? reaction;
  @override
  List<Object?> get props => [postId, reaction];
}

/// Narrows the feed to a #[tag] and/or posts matching [query]; both empty shows everything.
final class FeedFilterChanged extends FeedEvent {
  const FeedFilterChanged({this.tag, this.query = ''});
  final String? tag;
  final String query;
  @override
  List<Object?> get props => [tag, query];
}

final class PostCreateRequested extends FeedEvent {
  const PostCreateRequested(
      {required this.body, required this.anonymous, this.poll});
  final String body;
  final bool anonymous;
  final List<String>? poll;
  @override
  List<Object?> get props => [body, anonymous, poll];
}

/// Votes for [optionId]; voting for the member's current choice takes it back.
final class PostVoteRequested extends FeedEvent {
  const PostVoteRequested({required this.postId, required this.optionId});
  final String postId;
  final String optionId;
  @override
  List<Object?> get props => [postId, optionId];
}

final class PostSaveRequested extends FeedEvent {
  const PostSaveRequested({required this.postId, required this.saved});
  final String postId;
  final bool saved;
  @override
  List<Object?> get props => [postId, saved];
}

final class PostAuthorBlockRequested extends FeedEvent {
  const PostAuthorBlockRequested({required this.postId, required this.kind});
  final String postId;
  final BlockKind kind;
  @override
  List<Object?> get props => [postId, kind];
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
    this.tag,
    this.query = '',
    this.topics = const [],
  });

  /// Active #hashtag filter (lowercase, no `#`).
  final String? tag;

  /// Active text search; empty when not searching.
  final String query;
  bool get filtered => tag != null || query.isNotEmpty;

  /// Popular hashtags in the current scope.
  final List<Topic> topics;

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
    List<Topic>? topics,
  }) =>
      FeedState(
        tag: tag,
        query: query,
        topics: topics ?? this.topics,
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
        messageId,
        tag,
        query,
        topics,
      ];
}

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc({
    required LoadFeedUseCase loadFeed,
    required LoadAnnouncementsUseCase loadAnnouncements,
    required SetPostReactionUseCase setReaction,
    required LoadTopicsUseCase loadTopics,
    required CreatePostUseCase createPost,
    required EditPostUseCase editPost,
    required DeletePostUseCase deletePost,
    required ReportPostUseCase reportPost,
    required ArchivePostUseCase archivePost,
    required VotePollUseCase votePoll,
    required SetPostSavedUseCase setPostSaved,
    required BlockAuthorUseCase blockAuthor,
    CommunityScope initialScope = CommunityScope.global,
    this.trending = false,
  })  : _votePoll = votePoll,
        _setPostSaved = setPostSaved,
        _blockAuthor = blockAuthor,
        _loadFeed = loadFeed,
        _loadAnnouncements = loadAnnouncements,
        _setReaction = setReaction,
        _loadTopics = loadTopics,
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
    on<PostReactionRequested>(_onReaction);
    on<FeedFilterChanged>(_onFilterChanged);
    // Repeat taps while a request is still running are dropped, so one tap = one post/edit/report.
    on<PostCreateRequested>(_onCreate, transformer: droppable());
    on<PostEditRequested>(_onEdit, transformer: droppable());
    on<PostDeleteRequested>(_onDelete, transformer: droppable());
    on<PostReportRequested>(_onReport, transformer: droppable());
    on<PostArchiveRequested>(_onArchive, transformer: droppable());
    on<PostVoteRequested>(_onVote, transformer: droppable());
    on<PostSaveRequested>(_onSave);
    on<PostAuthorBlockRequested>(_onBlockAuthor, transformer: droppable());
  }

  final VotePollUseCase _votePoll;
  final SetPostSavedUseCase _setPostSaved;
  final BlockAuthorUseCase _blockAuthor;

  /// Lists the server's Trending ranking instead of the latest posts.
  final bool trending;

  final LoadFeedUseCase _loadFeed;
  final LoadAnnouncementsUseCase _loadAnnouncements;
  final SetPostReactionUseCase _setReaction;
  final LoadTopicsUseCase _loadTopics;
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
    final cachedPosts =
        trending || state.filtered ? null : _loadFeed.cached(scope);
    final cachedAnnouncements = _loadAnnouncements.cached();
    final posts = keepCurrent && state.posts.isNotEmpty
        ? state.posts
        : cachedPosts?.data ?? const <CommunityPost>[];
    emit(FeedState(
      tag: state.tag,
      query: state.query,
      topics: scope == state.scope ? state.topics : const [],
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

  Future<void> _onFilterChanged(
      FeedFilterChanged event, Emitter<FeedState> emit) async {
    final query = event.query.trim();
    if (event.tag == state.tag && query == state.query) return;
    // Results replace the list only once they arrive; until then the loader shows.
    emit(FeedState(
      scope: state.scope,
      status: FeedStatus.loading,
      announcements: state.announcements,
      topics: state.topics,
      tag: event.tag,
      query: query,
      messageId: state.messageId,
    ));
    await _load(emit);
  }

  Future<void> _load(Emitter<FeedState> emit) async {
    final scope = state.scope;
    final tag = state.tag;
    final query = state.query;
    final announcementsRequest = _loadAnnouncements(const NoParams());
    final topicsRequest = trending ? null : _loadTopics(scope);
    final result = trending
        ? await _loadFeed.trending(scope)
        : state.filtered
            ? await _loadFeed.filtered(scope,
                tag: tag, query: query.isEmpty ? null : query)
            : await _loadFeed(scope);
    // Announcements and topics are best-effort; a failure keeps whatever was shown before.
    (await announcementsRequest).fold(
      (_) {},
      (announcements) => emit(state.copyWith(announcements: announcements)),
    );
    if (topicsRequest != null && scope == state.scope) {
      (await topicsRequest)
          .fold((_) {}, (topics) => emit(state.copyWith(topics: topics)));
    }
    if (scope != state.scope || tag != state.tag || query != state.query) {
      return;
    }
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
        hasMore: !trending && posts.length >= LoadFeedUseCase.pageSize,
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
    final tag = state.tag;
    final query = state.query;
    emit(state.copyWith(loadingMore: true));
    final result = state.filtered
        ? await _loadFeed.filtered(scope,
            tag: tag, query: query.isEmpty ? null : query, before: cursor)
        : await _loadFeed.olderThan(scope, cursor);
    if (scope != state.scope ||
        tag != state.tag ||
        query != state.query ||
        state.status != FeedStatus.ready) {
      return;
    }
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

  Future<void> _onLike(PostLikeRequested event, Emitter<FeedState> emit) {
    final post = _find(event.postId);
    if (post == null) return Future.value();
    return _react(event.postId,
        post.myReaction == null ? PostReaction.love : null, emit);
  }

  Future<void> _onReaction(
      PostReactionRequested event, Emitter<FeedState> emit) {
    final post = _find(event.postId);
    if (post == null) return Future.value();
    final reaction =
        event.reaction == post.myReaction ? null : event.reaction;
    return _react(event.postId, reaction, emit);
  }

  Future<void> _react(String postId, PostReaction? reaction,
      Emitter<FeedState> emit) async {
    if (!_likesInFlight.add(postId)) return;
    try {
      final previous = _find(postId);
      if (previous == null) return;
      _replace(emit, postId, (post) => post.withReaction(reaction));
      final result = await _setReaction(
          SetPostReactionParams(postId: postId, reaction: reaction));
      result.fold(
        (failure) {
          _replace(emit, postId, (_) => previous);
          emit(state.copyWith(message: failure.message));
        },
        (server) => _replace(emit, postId,
            (post) => post.withReactions(server.counts, server.mine)),
      );
    } finally {
      _likesInFlight.remove(postId);
    }
  }

  void _replace(Emitter<FeedState> emit, String postId,
      CommunityPost Function(CommunityPost post) update) {
    emit(state.copyWith(posts: [
      for (final post in state.posts) post.id == postId ? update(post) : post,
    ]));
  }

  Future<void> _onCreate(
      PostCreateRequested event, Emitter<FeedState> emit) async {
    final result = await _createPost(CreatePostParams(
        body: event.body, anonymous: event.anonymous, poll: event.poll));
    await result.fold(
      (failure) async => emit(state.copyWith(message: failure.message)),
      (held) async {
        emit(state.copyWith(
            message: held
                ? 'Your post is saved. It will be shared once your company is approved.'
                : 'Your post was shared.'));
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

  Future<void> _onVote(PostVoteRequested event, Emitter<FeedState> emit) async {
    final post = _find(event.postId);
    if (post?.poll == null) return;
    final optionId =
        post!.poll!.myVote == event.optionId ? null : event.optionId;
    final result = await _votePoll(
        VotePollParams(postId: event.postId, optionId: optionId));
    result.fold(
      (failure) => emit(state.copyWith(message: failure.message)),
      (poll) => emit(state.copyWith(posts: [
        for (final p in state.posts)
          p.id == event.postId ? p.copyWith(poll: poll) : p,
      ])),
    );
  }

  Future<void> _onSave(PostSaveRequested event, Emitter<FeedState> emit) async {
    List<CommunityPost> withSaved(bool saved) => [
          for (final p in state.posts)
            p.id == event.postId ? p.copyWith(saved: saved) : p,
        ];
    emit(state.copyWith(posts: withSaved(event.saved)));
    final result = await _setPostSaved(
        SetPostSavedParams(postId: event.postId, saved: event.saved));
    result.fold(
      (failure) => emit(state.copyWith(
          posts: withSaved(!event.saved), message: failure.message)),
      (_) => emit(state.copyWith(
          message: event.saved
              ? 'Saved. Find it under Profile › Saved posts.'
              : 'Removed from saved posts.')),
    );
  }

  /// Hides the post straight away, then reloads so the author's other posts
  /// drop out too (the client never learns who wrote an anonymous post).
  Future<void> _onBlockAuthor(
      PostAuthorBlockRequested event, Emitter<FeedState> emit) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final p in previous)
        if (p.id != event.postId) p,
    ]));
    final result = await _blockAuthor(
        BlockAuthorParams(postId: event.postId, kind: event.kind));
    await result.fold(
      (failure) async =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) async {
        emit(state.copyWith(
            message: event.kind == BlockKind.block
                ? 'Blocked. You won’t see each other’s posts.'
                : 'Muted. Their posts won’t show in your feeds.'));
        await _load(emit);
      },
    );
  }

  CommunityPost? _find(String postId) {
    for (final post in state.posts) {
      if (post.id == postId) return post;
    }
    return null;
  }
}
