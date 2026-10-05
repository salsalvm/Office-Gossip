import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_scope.dart';
import '../../domain/usecases/create_post_usecase.dart';
import '../../domain/usecases/load_feed_usecase.dart';
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

enum FeedStatus { initial, loading, ready, failure }

class FeedState extends Equatable {
  const FeedState({
    this.scope = CommunityScope.global,
    this.status = FeedStatus.initial,
    this.posts = const [],
    this.message,
    this.messageId = 0,
  });

  final CommunityScope scope;
  final FeedStatus status;
  final List<CommunityPost> posts;

  /// One-off snackbar text; [messageId] changes each time so repeats still show.
  final String? message;
  final int messageId;

  FeedState copyWith({
    CommunityScope? scope,
    FeedStatus? status,
    List<CommunityPost>? posts,
    String? message,
  }) =>
      FeedState(
        scope: scope ?? this.scope,
        status: status ?? this.status,
        posts: posts ?? this.posts,
        message: message,
        messageId: message == null ? messageId : messageId + 1,
      );

  @override
  List<Object?> get props => [scope, status, posts, message, messageId];
}

class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc({
    required LoadFeedUseCase loadFeed,
    required TogglePostLikeUseCase togglePostLike,
    required CreatePostUseCase createPost,
    CommunityScope initialScope = CommunityScope.global,
  })  : _loadFeed = loadFeed,
        _togglePostLike = togglePostLike,
        _createPost = createPost,
        super(FeedState(scope: initialScope)) {
    on<FeedRequested>(_onRequested);
    on<FeedScopeChanged>(_onScopeChanged);
    on<PostLikeRequested>(_onLike);
    on<PostCreateRequested>(_onCreate);
  }

  final LoadFeedUseCase _loadFeed;
  final TogglePostLikeUseCase _togglePostLike;
  final CreatePostUseCase _createPost;

  Future<void> _onRequested(
      FeedRequested event, Emitter<FeedState> emit) async {
    emit(state.copyWith(status: FeedStatus.loading));
    await _load(emit);
  }

  Future<void> _onScopeChanged(
      FeedScopeChanged event, Emitter<FeedState> emit) async {
    if (event.scope == state.scope && state.status != FeedStatus.initial) {
      return;
    }
    emit(state.copyWith(
        scope: event.scope, status: FeedStatus.loading, posts: const []));
    await _load(emit);
  }

  Future<void> _load(Emitter<FeedState> emit) async {
    final scope = state.scope;
    final result = await _loadFeed(scope);
    if (scope != state.scope) return;
    result.fold(
      (failure) => emit(
          state.copyWith(status: FeedStatus.failure, message: failure.message)),
      (posts) => emit(state.copyWith(status: FeedStatus.ready, posts: posts)),
    );
  }

  Future<void> _onLike(PostLikeRequested event, Emitter<FeedState> emit) async {
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

  static CommunityPost _toggled(CommunityPost post) => CommunityPost(
        id: post.id,
        person: post.person,
        role: post.role,
        company: post.company,
        time: post.time,
        body: post.body,
        likes: post.likes + (post.liked ? -1 : 1),
        comments: post.comments,
        anonymous: post.anonymous,
        liked: !post.liked,
        canReact: post.canReact,
      );
}
