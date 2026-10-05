import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class ReportPostUseCase implements UseCase<Unit, ReportPostParams> {
  ReportPostUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(ReportPostParams params) =>
      repository.reportPost(postId: params.postId, reason: params.reason);
}

class ReportPostParams {
  const ReportPostParams({required this.postId, required this.reason});

  final String postId;
  final String reason;
}
