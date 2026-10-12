import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/block_entry.dart';
import '../repositories/i_community_repository.dart';

/// Blocks or mutes a post's author without revealing an anonymous author.
class BlockAuthorUseCase implements UseCase<Unit, BlockAuthorParams> {
  BlockAuthorUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(BlockAuthorParams params) =>
      repository.blockAuthor(postId: params.postId, kind: params.kind);
}

class BlockAuthorParams {
  const BlockAuthorParams({required this.postId, required this.kind});

  final String postId;
  final BlockKind kind;
}

/// Blocks or mutes a member from People; [kind] null undoes it.
class SetMemberBlockUseCase implements UseCase<Unit, SetMemberBlockParams> {
  SetMemberBlockUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(SetMemberBlockParams params) => params.kind == null
      ? repository.unblockMember(params.userId)
      : repository.blockMember(userId: params.userId, kind: params.kind!);
}

class SetMemberBlockParams {
  const SetMemberBlockParams({required this.userId, required this.kind});

  final String userId;
  final BlockKind? kind;
}

class LoadBlocksUseCase implements UseCase<List<BlockEntry>, NoParams> {
  LoadBlocksUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<BlockEntry>> call(NoParams params) =>
      repository.loadBlocks();
}

class RemoveBlockUseCase implements UseCase<Unit, String> {
  RemoveBlockUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(String blockId) => repository.removeBlock(blockId);
}
