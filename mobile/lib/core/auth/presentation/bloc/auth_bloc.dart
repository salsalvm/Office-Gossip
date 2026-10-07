import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../error/failure.dart';
import '../../../usecase/usecase.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/session.dart';
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

enum AuthStatus {
  checking,
  unauthenticated,
  authenticated,
  submitting,
  confirmationRequired,
  passwordResetSent
}

class AuthState extends Equatable {
  const AuthState(
      {this.status = AuthStatus.checking, this.session, this.message});
  final AuthStatus status;
  final Session? session;
  final String? message;

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
  List<Object?> get props =>
      [status, session?.accessToken, session?.user, message];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required RestoreSessionUseCase restoreSession,
    required SignInUseCase signIn,
    required RegisterAccountUseCase registerAccount,
    required SignOutUseCase signOut,
    required RequestPasswordResetUseCase requestPasswordReset,
  })  : _restoreSession = restoreSession,
        _signIn = signIn,
        _registerAccount = registerAccount,
        _signOut = signOut,
        _requestPasswordReset = requestPasswordReset,
        super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthPasswordResetRequested>(_onPasswordReset);
    on<AuthMessageCleared>(_onMessageCleared);
    on<AuthUserUpdated>(_onUserUpdated);
  }

  final RestoreSessionUseCase _restoreSession;
  final SignInUseCase _signIn;
  final RegisterAccountUseCase _registerAccount;
  final SignOutUseCase _signOut;
  final RequestPasswordResetUseCase _requestPasswordReset;

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
    final result = await _signIn(
        SignInParams(email: event.email, password: event.password));
    result.fold(
      (failure) => emit(AuthState(
          status: AuthStatus.unauthenticated,
          message: _authErrorMessage(failure))),
      (session) =>
          emit(AuthState(status: AuthStatus.authenticated, session: session)),
    );
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

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    final session = state.session;
    if (session == null) return;
    emit(state.copyWith(session: session.copyWith(user: event.user)));
  }
}
