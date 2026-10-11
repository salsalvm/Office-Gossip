import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../error/failure.dart';
import '../../../usecase/usecase.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/deactivated_account.dart';
import '../../domain/entities/session.dart';
import '../../domain/usecases/account_lifecycle_usecases.dart';
import '../../domain/usecases/refresh_user_usecase.dart';
import '../../domain/usecases/register_account_usecase.dart';
import '../../domain/usecases/request_password_reset_usecase.dart';
import '../../domain/usecases/restore_session_usecase.dart';
import '../../domain/usecases/sign_in_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';

String _authErrorMessage(Failure failure) {
  final message = failure.message;
  if (message.toLowerCase().contains('email rate limit exceeded')) {
    return 'Email sending is temporarily rate-limited. Please wait before trying again.';
  }
  return message;
}

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

final class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

final class AuthRegisterRequested extends AuthEvent {
  const AuthRegisterRequested(
      {required this.name,
      required this.email,
      required this.password,
      this.companyId,
      this.companyName,
      this.companyWebsite,
      this.verificationToken});
  final String name;
  final String email;
  final String password;

  /// A listed company to join; otherwise [companyName] requests a new one.
  final String? companyId;
  final String? companyName;
  final String? companyWebsite;

  /// From verifying the email with a one-time code before sign-up.
  final String? verificationToken;
  @override
  List<Object?> get props => [
        name,
        email,
        password,
        companyId,
        companyName,
        companyWebsite,
        verificationToken
      ];
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Replaces the signed-in user after a profile refresh or edit.
final class AuthUserUpdated extends AuthEvent {
  const AuthUserUpdated(this.user);
  final AppUser user;
  @override
  List<Object?> get props => [user];
}

/// Re-fetches the signed-in user in the background (e.g. on app resume or a
/// company-approval push) so membership changes made by an admin show up.
final class AuthUserRefreshRequested extends AuthEvent {
  const AuthUserRefreshRequested();
}

/// Drops any stale error/info message, e.g. when an auth screen opens or a field is edited.
final class AuthMessageCleared extends AuthEvent {
  const AuthMessageCleared();
}

final class AuthPasswordResetRequested extends AuthEvent {
  const AuthPasswordResetRequested({required this.email});
  final String email;
  @override
  List<Object?> get props => [email];
}

/// Restores the account offered after [AuthStatus.accountDeactivated].
final class AuthRestoreAccountRequested extends AuthEvent {
  const AuthRestoreAccountRequested(
      {required this.email, required this.password});
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

/// The member chose not to restore their deleted account.
final class AuthRestoreDismissed extends AuthEvent {
  const AuthRestoreDismissed();
}

/// The account was deleted and its local session already cleared.
final class AuthAccountDeleted extends AuthEvent {
  const AuthAccountDeleted();
}

enum AuthStatus {
  checking,
  unauthenticated,
  authenticated,
  submitting,
  confirmationRequired,
  passwordResetSent,

  /// Valid credentials for a deleted account; see [AuthState.deactivatedAccount].
  accountDeactivated,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.checking,
    this.session,
    this.message,
    this.deactivatedAccount,
  });
  final AuthStatus status;
  final Session? session;
  final String? message;
  final DeactivatedAccount? deactivatedAccount;

  AuthState copyWith(
          {AuthStatus? status,
          Session? session,
          String? message,
          bool clearMessage = false}) =>
      AuthState(
          status: status ?? this.status,
          session: session ?? this.session,
          message: clearMessage ? null : message ?? this.message);

  @override
  List<Object?> get props => [
        status,
        session?.accessToken,
        session?.user,
        message,
        deactivatedAccount
      ];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required RestoreSessionUseCase restoreSession,
    required SignInUseCase signIn,
    required RegisterAccountUseCase registerAccount,
    required SignOutUseCase signOut,
    required RequestPasswordResetUseCase requestPasswordReset,
    required RestoreAccountUseCase restoreAccount,
    required RefreshUserUseCase refreshUser,
  })  : _restoreSession = restoreSession,
        _refreshUser = refreshUser,
        _signIn = signIn,
        _registerAccount = registerAccount,
        _signOut = signOut,
        _requestPasswordReset = requestPasswordReset,
        _restoreAccount = restoreAccount,
        super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthPasswordResetRequested>(_onPasswordReset);
    on<AuthMessageCleared>(_onMessageCleared);
    on<AuthUserUpdated>(_onUserUpdated);
    on<AuthUserRefreshRequested>(_onUserRefreshRequested);
    on<AuthRestoreAccountRequested>(_onRestoreAccount);
    on<AuthRestoreDismissed>(_onRestoreDismissed);
    on<AuthAccountDeleted>(
        (_, emit) => emit(const AuthState(status: AuthStatus.unauthenticated)));
  }

  final RestoreSessionUseCase _restoreSession;
  final SignInUseCase _signIn;
  final RegisterAccountUseCase _registerAccount;
  final SignOutUseCase _signOut;
  final RequestPasswordResetUseCase _requestPasswordReset;
  final RestoreAccountUseCase _restoreAccount;
  final RefreshUserUseCase _refreshUser;

  /// Sign-in and restore share outcomes: a session, a deleted account to
  /// offer restoring, or an error message.
  void _emitSignInResult(
      Either<Failure, Session> result, Emitter<AuthState> emit) {
    result.fold(
      (failure) => emit(failure is AccountDeactivatedFailure
          ? AuthState(
              status: AuthStatus.accountDeactivated,
              deactivatedAccount: failure.account)
          : AuthState(
              status: AuthStatus.unauthenticated,
              message: _authErrorMessage(failure))),
      (session) =>
          emit(AuthState(status: AuthStatus.authenticated, session: session)),
    );
  }

  Future<void> _onRestoreAccount(
      AuthRestoreAccountRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.submitting, clearMessage: true));
    _emitSignInResult(
        await _restoreAccount(
            SignInParams(email: event.email, password: event.password)),
        emit);
  }

  void _onRestoreDismissed(
      AuthRestoreDismissed event, Emitter<AuthState> emit) {
    final account = state.deactivatedAccount;
    emit(AuthState(
        status: AuthStatus.unauthenticated,
        message: account == null || !account.canRestore
            ? account?.message
            : 'Your account is still scheduled for deletion. Sign in again any time before then to restore it.'));
  }

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final result = await _restoreSession(const NoParams());
    result.fold(
      (_) => emit(const AuthState(status: AuthStatus.unauthenticated)),
      (session) => emit(AuthState(
          status: session == null
              ? AuthStatus.unauthenticated
              : AuthStatus.authenticated,
          session: session)),
    );
  }

  Future<void> _onSignIn(
      AuthSignInRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.submitting, clearMessage: true));
    _emitSignInResult(
        await _signIn(
            SignInParams(email: event.email, password: event.password)),
        emit);
  }

  Future<void> _onRegister(
      AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.submitting, clearMessage: true));
    final result = await _registerAccount(RegisterAccountParams(
        name: event.name,
        email: event.email,
        password: event.password,
        companyId: event.companyId,
        companyName: event.companyName,
        companyWebsite: event.companyWebsite,
        verificationToken: event.verificationToken));
    result.fold(
      (failure) => emit(AuthState(
          status: AuthStatus.unauthenticated,
          message: _authErrorMessage(failure))),
      (registration) {
        final session = registration.session;
        if (session != null) {
          emit(AuthState(status: AuthStatus.authenticated, session: session));
        } else {
          emit(const AuthState(
              status: AuthStatus.confirmationRequired,
              message:
                  'Account created. Check your email to confirm it, then sign in.'));
        }
      },
    );
  }

  Future<void> _onSignOut(
      AuthSignOutRequested event, Emitter<AuthState> emit) async {
    await _signOut(const NoParams());
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onPasswordReset(
      AuthPasswordResetRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.submitting, clearMessage: true));
    final result = await _requestPasswordReset(event.email);
    result.fold(
      (failure) => emit(AuthState(
          status: AuthStatus.unauthenticated,
          message: _authErrorMessage(failure))),
      (_) => emit(const AuthState(
          status: AuthStatus.passwordResetSent,
          message:
              'If an account exists for this email, reset instructions are on the way.')),
    );
  }

  void _onMessageCleared(AuthMessageCleared event, Emitter<AuthState> emit) {
    if (state.message == null || state.status == AuthStatus.submitting) return;
    emit(AuthState(
        status: state.status == AuthStatus.authenticated
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        session: state.session));
  }

  Future<void> _onUserRefreshRequested(
      AuthUserRefreshRequested event, Emitter<AuthState> emit) async {
    if (state.status != AuthStatus.authenticated) return;
    final result = await _refreshUser(const NoParams());
    final session = state.session;
    if (state.status != AuthStatus.authenticated || session == null) return;
    result.fold(
      (_) {},
      (user) => emit(state.copyWith(session: session.copyWith(user: user))),
    );
  }

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    final session = state.session;
    if (session == null) return;
    emit(state.copyWith(session: session.copyWith(user: event.user)));
  }
}
