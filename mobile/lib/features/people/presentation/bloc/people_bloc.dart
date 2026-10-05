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
  const PeopleState(
      {this.status = PeopleStatus.initial,
      this.people = const [],
      this.message});
  final PeopleStatus status;
  final List<CommunityMember> people;
  final String? message;
  @override
  List<Object?> get props => [status, people, message];
}

class PeopleBloc extends Bloc<PeopleEvent, PeopleState> {
  PeopleBloc(this._loadPeople) : super(const PeopleState()) {
    on<PeopleRequested>((event, emit) async {
      emit(const PeopleState(status: PeopleStatus.loading));
      final result = await _loadPeople(const NoParams());
      result.fold(
        (failure) => emit(PeopleState(
            status: PeopleStatus.failure, message: failure.message)),
        (people) =>
            emit(PeopleState(status: PeopleStatus.ready, people: people)),
      );
    });
  }
  final LoadPeopleUseCase _loadPeople;
}
