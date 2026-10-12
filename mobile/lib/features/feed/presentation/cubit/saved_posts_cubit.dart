import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/usecases/saved_posts_usecases.dart';
import '../../domain/usecases/vote_poll_usecase.dart';

enum SavedPostsStatus { loading, ready, failure }

class SavedPostsState extends Equatable {
  const SavedPostsState({
    this.status = SavedPostsStatus.loading,
    this.posts = const [],
    this.message,
    this.messageId = 0,
  });

  final SavedPostsStatus status;
  final List<CommunityPost> posts;

  /// One-off snackbar text; [messageId] changes each time so repeats still show.
  final String? message;
  final int messageId;

  SavedPostsState copyWith(
          {SavedPostsStatus? status,
          List<CommunityPost>? posts,
          String? message}) =>
      SavedPostsState(
        status: status ?? this.status,
        posts: posts ?? this.posts,
        message: message,
        messageId: message == null ? messageId : messageId + 1,
      );

  @override
  List<Object?> get props => [status, posts, message, messageId];
}

class SavedPostsCubit extends Cubit<SavedPostsState> {
  SavedPostsCubit(this._loadSaved, this._setSaved, this._votePoll)
      : super(const SavedPostsState());

  final LoadSavedPostsUseCase _loadSaved;
  final SetPostSavedUseCase _setSaved;
  final VotePollUseCase _votePoll;

  /// Clears the list first so stale posts never show next to the spinner.
  Future<void> load() async {
    emit(const SavedPostsState());
    final result = await _loadSaved(const NoParams());
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
          status: SavedPostsStatus.failure, message: failure.message)),
      (posts) => emit(state.copyWith(
          status: SavedPostsStatus.ready,
          posts: posts.where((post) => !post.isDeleted).toList())),
    );
  }

  Future<void> unsave(CommunityPost post) async {
    final previous = state.posts;
    emit(state.copyWith(posts: [
      for (final p in previous)
        if (p.id != post.id) p,
    ]));
    final result =
        await _setSaved(SetPostSavedParams(postId: post.id, saved: false));
    if (isClosed) return;
    result.fold(
      (failure) =>
          emit(state.copyWith(posts: previous, message: failure.message)),
      (_) => emit(state.copyWith(message: 'Removed from saved posts.')),
    );
  }

  Future<void> vote(CommunityPost post, String optionId) async {
    final current = post.poll?.myVote;
    final result = await _votePoll(VotePollParams(
        postId: post.id, optionId: current == optionId ? null : optionId));
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(message: failure.message)),
      (poll) => emit(state.copyWith(posts: [
        for (final p in state.posts)
          p.id == post.id ? p.copyWith(poll: poll) : p,
      ])),
    );
  }
}
