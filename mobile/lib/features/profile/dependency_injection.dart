import '../../core/auth/domain/usecases/refresh_user_usecase.dart';
import '../../core/auth/domain/usecases/update_profile_usecase.dart';
import '../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../core/di/injection_container.dart';
import 'presentation/cubit/profile_cubit.dart';

void registerProfileFeature() {
  sl.registerFactory<ProfileCubit>(
    () => ProfileCubit(
      refreshUser: sl<RefreshUserUseCase>(),
      updateProfile: sl<UpdateProfileUseCase>(),
      authBloc: sl<AuthBloc>(),
    ),
  );
}
