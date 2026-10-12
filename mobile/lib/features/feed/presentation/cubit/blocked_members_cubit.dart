import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/block_entry.dart';
import '../../domain/usecases/block_usecases.dart';

enum BlockedMembersStatus { loading, ready, failure }

class BlockedMembersState extends Equatable {
  const BlockedMembersState({
    this.status = BlockedMembersStatus.loading,
    this.entries = const [],
    this.busyIds = const {},
    this.message,
    this.messageId = 0,
  });

  final BlockedMembersStatus status;
  final List<BlockEntry> entries;

  /// Entries whose unblock / unmute request is still running.
  final Set<String> busyIds;
  final String? message;
  final int messageId;

  BlockedMembersState copyWith({
    BlockedMembersStatus? status,
    List<BlockEntry>? entries,
    Set<String>? busyIds,
    String? message,
  }) =>
      BlockedMembersState(
        status: status ?? this.status,
        entries: entries ?? this.entries,
        busyIds: busyIds ?? this.busyIds,
        message: message,
        messageId: message == null ? messageId : messageId + 1,
      );

  @override
  List<Object?> get props => [status, entries, busyIds, message, messageId];
}

class BlockedMembersCubit extends Cubit<BlockedMembersState> {
  BlockedMembersCubit(this._loadBlocks, this._removeBlock)
      : super(const BlockedMembersState());

  final LoadBlocksUseCase _loadBlocks;
  final RemoveBlockUseCase _removeBlock;

  Future<void> load() async {
    emit(const BlockedMembersState());
    final result = await _loadBlocks(const NoParams());
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
          status: BlockedMembersStatus.failure, message: failure.message)),
      (entries) => emit(
          state.copyWith(status: BlockedMembersStatus.ready, entries: entries)),
    );
  }

  Future<void> remove(BlockEntry entry) async {
    if (state.busyIds.contains(entry.id)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, entry.id}));
    final result = await _removeBlock(entry.id);
    if (isClosed) return;
    final busy = {...state.busyIds}..remove(entry.id);
    result.fold(
      (failure) =>
          emit(state.copyWith(busyIds: busy, message: failure.message)),
      (_) => emit(state.copyWith(
          busyIds: busy,
          entries: [
            for (final e in state.entries)
              if (e.id != entry.id) e,
          ],
          message: entry.kind == BlockKind.block
              ? '${entry.label} unblocked.'
              : '${entry.label} unmuted.')),
    );
  }
}
