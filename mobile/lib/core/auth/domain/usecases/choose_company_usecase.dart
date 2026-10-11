import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/app_user.dart';
import '../repositories/i_auth_repository.dart';

class ChooseCompanyUseCase implements UseCase<AppUser, ChooseCompanyParams> {
  ChooseCompanyUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<AppUser> call(ChooseCompanyParams params) =>
      repository.chooseCompany(
        companyId: params.companyId,
        companyName: params.companyName,
        companyWebsite: params.companyWebsite,
      );
}

/// Either [companyId] (a listed company) or [companyName] (a new request).
class ChooseCompanyParams {
  const ChooseCompanyParams.join(String this.companyId)
      : companyName = null,
        companyWebsite = null;

  const ChooseCompanyParams.request(String this.companyName,
      {this.companyWebsite})
      : companyId = null;

  final String? companyId;
  final String? companyName;
  final String? companyWebsite;
}
