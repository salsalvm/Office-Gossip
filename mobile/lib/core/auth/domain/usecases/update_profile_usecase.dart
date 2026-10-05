import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/app_user.dart';
import '../repositories/i_auth_repository.dart';

class UpdateProfileUseCase implements UseCase<AppUser, UpdateProfileParams> {
  UpdateProfileUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<AppUser> call(UpdateProfileParams params) =>
      repository.updateProfile(
        displayName: params.displayName,
        roleTitle: params.roleTitle,
        bio: params.bio,
      );
}

class UpdateProfileParams {
  const UpdateProfileParams({
    required this.displayName,
    this.roleTitle,
    this.bio,
  });

  final String displayName;
  final String? roleTitle;
  final String? bio;
}
