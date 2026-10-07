import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../feed/domain/entities/community_member.dart';
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

enum PeopleStatus { initial, loading, ready, failure }

class PeopleState extends Equatable {
  const PeopleState({
    this.status = PeopleStatus.initial,
    this.people = const [],
    this.offline = false,
    this.syncedAt,
    this.message,
  });
  final PeopleStatus status;
  final List<CommunityMember> people;

  /// The last refresh failed, so [people] is the cached copy from [syncedAt].
  final bool offline;
  final DateTime? syncedAt;
  final String? message;
  @override
  List<Object?> get props => [status, people, offline, syncedAt, message];
}

class PeopleBloc extends Bloc<PeopleEvent, PeopleState> {
  PeopleBloc(this._loadPeople) : super(const PeopleState()) {
    on<PeopleRequested>((event, emit) async {
      final cached = state.people.isEmpty ? _loadPeople.cached() : null;
      emit(PeopleState(
        status: PeopleStatus.loading,
        people: cached?.data ?? state.people,
        offline: state.offline,
        syncedAt: cached?.savedAt ?? state.syncedAt,
      ));
      final result = await _loadPeople(const NoParams());
      result.fold(
        (failure) => emit(state.people.isNotEmpty
            ? PeopleState(
                status: PeopleStatus.ready,
                people: state.people,
                offline: true,
                syncedAt: state.syncedAt,
              )
            : PeopleState(
                status: PeopleStatus.failure, message: failure.message)),
        (people) => emit(PeopleState(
          status: PeopleStatus.ready,
          people: people,
          syncedAt: DateTime.now(),
        )),
      );
    });
  }
  final LoadPeopleUseCase _loadPeople;
}
