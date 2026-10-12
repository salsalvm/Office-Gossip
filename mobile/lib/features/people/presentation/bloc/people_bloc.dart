import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../feed/domain/entities/block_entry.dart';
import '../../../feed/domain/entities/community_member.dart';
import '../../../feed/domain/usecases/block_usecases.dart';
import '../../../../core/usecase/usecase.dart';
import '../../domain/usecases/load_people_usecase.dart';

sealed class PeopleEvent extends Equatable {
  const PeopleEvent();
  @override
  List<Object?> get props => [];
}

final class PeopleRequested extends PeopleEvent {
  const PeopleRequested();
}

/// Blocks or mutes [member]; [kind] null unmutes / unblocks them.
final class PersonBlockRequested extends PeopleEvent {
  const PersonBlockRequested({required this.member, required this.kind});
  final CommunityMember member;
  final BlockKind? kind;
  @override
  List<Object?> get props => [member.id, kind];
}

enum PeopleStatus { initial, loading, ready, failure }

class PeopleState extends Equatable {
  const PeopleState({
    this.status = PeopleStatus.initial,
    this.people = const [],
    this.offline = false,
    this.syncedAt,
    this.message,
    this.notice,
    this.noticeId = 0,
  });
  final PeopleStatus status;
  final List<CommunityMember> people;

  /// The last refresh failed, so [people] is the cached copy from [syncedAt].
  final bool offline;
  final DateTime? syncedAt;
  final String? message;

  /// One-off snackbar text; [noticeId] changes each time so repeats still show.
  final String? notice;
  final int noticeId;

  PeopleState withNotice(String notice) => PeopleState(
        status: status,
        people: people,
        offline: offline,
        syncedAt: syncedAt,
        message: message,
        notice: notice,
        noticeId: noticeId + 1,
      );

  @override
  List<Object?> get props =>
      [status, people, offline, syncedAt, message, notice, noticeId];
}

class PeopleBloc extends Bloc<PeopleEvent, PeopleState> {
  PeopleBloc(this._loadPeople, this._setMemberBlock)
      : super(const PeopleState()) {
    on<PeopleRequested>((event, emit) async {
      final cached = state.people.isEmpty ? _loadPeople.cached() : null;
      emit(PeopleState(
        status: PeopleStatus.loading,
        people: cached?.data ?? state.people,
        offline: state.offline,
        syncedAt: cached?.savedAt ?? state.syncedAt,
        noticeId: state.noticeId,
      ));
      final result = await _loadPeople(const NoParams());
      result.fold(
        (failure) => emit(state.people.isNotEmpty
            ? PeopleState(
                status: PeopleStatus.ready,
                people: state.people,
                offline: true,
                syncedAt: state.syncedAt,
                noticeId: state.noticeId,
              )
            : PeopleState(
                status: PeopleStatus.failure,
                message: failure.message,
                noticeId: state.noticeId)),
        (people) => emit(PeopleState(
          status: PeopleStatus.ready,
          people: people,
          syncedAt: DateTime.now(),
          noticeId: state.noticeId,
        )),
      );
    });
    on<PersonBlockRequested>(_onBlock, transformer: droppable());
  }
  final LoadPeopleUseCase _loadPeople;
  final SetMemberBlockUseCase _setMemberBlock;

  Future<void> _onBlock(
      PersonBlockRequested event, Emitter<PeopleState> emit) async {
    final name = event.member.name;
    final result = await _setMemberBlock(
        SetMemberBlockParams(userId: event.member.id, kind: event.kind));
    result.fold(
      (failure) => emit(state.withNotice(failure.message)),
      (_) {
        emit(state.withNotice(switch (event.kind) {
          BlockKind.block => '$name blocked.',
          BlockKind.mute =>
            '$name muted. Their posts won’t show in your feeds.',
          null => '$name unmuted.',
        }));
        add(const PeopleRequested());
      },
    );
  }
}
