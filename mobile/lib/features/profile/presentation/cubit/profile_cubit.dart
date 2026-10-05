import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/domain/usecases/refresh_user_usecase.dart';
import '../../../../core/auth/domain/usecases/update_profile_usecase.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/usecase/usecase.dart';

enum ProfileStatus { idle, refreshing, saving, saved, failure }

class ProfileState extends Equatable {
  const ProfileState({this.status = ProfileStatus.idle, this.message});
  final ProfileStatus status;
  final String? message;

  @override
  List<Object?> get props => [status, message];
}

/// Loads and edits the signed-in member's profile, keeping [AuthBloc] in sync.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required RefreshUserUseCase refreshUser,
    required UpdateProfileUseCase updateProfile,
    required AuthBloc authBloc,
  })  : _refreshUser = refreshUser,
        _updateProfile = updateProfile,
        _authBloc = authBloc,
        super(const ProfileState());

  @override
  void emit(ProfileState state) {
    if (!isClosed) super.emit(state);
  }

  final RefreshUserUseCase _refreshUser;
  final UpdateProfileUseCase _updateProfile;
  final AuthBloc _authBloc;

  /// Returns the freshest user available: the API copy, or the cached one if offline.
  Future<AppUser?> refresh() async {
    emit(const ProfileState(status: ProfileStatus.refreshing));
    final result = await _refreshUser(const NoParams());
    return result.fold(
      (failure) {
        emit(ProfileState(
            status: ProfileStatus.failure, message: failure.message));
        return _authBloc.state.session?.user;
      },
      (user) {
        _authBloc.add(AuthUserUpdated(user));
        emit(const ProfileState());
        return user;
      },
    );
  }

  Future<bool> save({
    required String displayName,
    String? roleTitle,
    String? bio,
  }) async {
    emit(const ProfileState(status: ProfileStatus.saving));
    final result = await _updateProfile(UpdateProfileParams(
      displayName: displayName,
      roleTitle: roleTitle,
      bio: bio,
    ));
    return result.fold(
      (failure) {
        emit(ProfileState(
            status: ProfileStatus.failure, message: failure.message));
        return false;
      },
      (user) {
        _authBloc.add(AuthUserUpdated(user));
        emit(const ProfileState(
            status: ProfileStatus.saved, message: 'Profile updated.'));
        return true;
      },
    );
  }
}
