import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_endpoints.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _company = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _companyFocus = FocusNode();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  final _otp = TextEditingController();
  _OtpStage _otpStage = _OtpStage.idle;
  bool _otpSending = false;
  bool _otpChecking = false;
  String? _otpError;
  String? _verificationToken;
  bool _otpEmailVerified = true;
  int _resendIn = 0;
  Timer? _resendTimer;
  late final AuthBloc _authBloc = context.read<AuthBloc>();

  @override
  void initState() {
    super.initState();
    _authBloc.add(const AuthMessageCleared());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otp.dispose();
    _authBloc.add(const AuthMessageCleared());
    for (final controller in [
      _name,
      _email,
      _password,
      _confirmPassword,
      _company
    ]) {
      controller.dispose();
    }
    for (final node in [
      _emailFocus,
      _passwordFocus,
      _confirmPasswordFocus,
      _companyFocus
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  void _clearServerError(String _) {
    if (_authBloc.state.message != null) {
      _authBloc.add(const AuthMessageCleared());
    }
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    if (AppConstants.emailOtpEnabled &&
        (_otpStage != _OtpStage.verified || _verificationToken == null)) {
      setState(
          () => _otpError = 'Verify your email before creating your account.');
      return;
    }
    _authBloc.add(AuthRegisterRequested(
        name: _name.text.trim(),
        email: normalizeAuthEmail(_email.text),
        password: _password.text,
        companyName: _company.text.trim(),
        verificationToken: _verificationToken));
  }

  Dio get _dio => sl<Dio>();

  String _errorText(Object error, String fallback) =>
      error is DioException ? AppException.fromDio(error).message : fallback;

  void _onEmailChanged(String value) {
    _clearServerError(value);
    if (_otpStage != _OtpStage.idle || _otpError != null) {
      _resendTimer?.cancel();
      setState(() {
        _otpStage = _OtpStage.idle;
        _verificationToken = null;
        _otpError = null;
        _resendIn = 0;
        _otp.clear();
      });
    }
  }

  Future<void> _sendOtp() async {
    final emailError = AuthValidators.email(_email.text);
    if (emailError != null) {
      setState(() => _otpError = emailError);
      return;
    }
    setState(() {
      _otpSending = true;
      _otpError = null;
    });
    try {
      await _dio.post<dynamic>(ApiEndpoints.emailSendOtp,
          data: {'email': normalizeAuthEmail(_email.text)});
      if (!mounted) return;
      _otp.clear();
      setState(() => _otpStage = _OtpStage.sent);
      _startResendCooldown();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _otpError =
            _errorText(error, 'Could not send the code. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _resendIn = 0;
            if (_otpStage == _OtpStage.sent) {
              _otpStage = _OtpStage.idle;
              _otpError = null;
              _otp.clear();
            }
          });
        }
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _confirmOtp() async {
    if (_otp.text.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _otpChecking = true;
      _otpError = null;
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.emailVerifyOtp,
          data: {'email': normalizeAuthEmail(_email.text), 'code': _otp.text});
      final token = response.data?['verificationToken'] as String?;
      final emailVerified = response.data?['emailVerified'] != false;
      if (!mounted) return;
      if (token == null) throw StateError('missing token');
      _resendTimer?.cancel();
      setState(() {
        _verificationToken = token;
        _otpEmailVerified = emailVerified;
        _otpStage = _OtpStage.verified;
      });
      _passwordFocus.requestFocus();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _otpError =
            _errorText(error, 'That code is invalid or has expired.'));
      }
    } finally {
      if (mounted) setState(() => _otpChecking = false);
    }
  }

  void _backToSignIn() =>
      context.canPop() ? context.pop() : context.go('/sign-in');

  @override
  Widget build(BuildContext context) => Scaffold(
        body: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (previous, current) =>
              current.status == AuthStatus.authenticated &&
              previous.status != AuthStatus.authenticated,
          listener: (_, __) => TextInput.finishAutofillContext(),
          builder: (context, state) {
            final submitting = state.status == AuthStatus.submitting;
            final error = state.status == AuthStatus.unauthenticated
                ? state.message
                : null;
            final errorField =
                error == null ? null : authFieldForServerMessage(error);
            final info = state.status == AuthStatus.confirmationRequired
                ? state.message
                : null;
            String? serverErrorFor(AuthField field) =>
                errorField == field ? error : null;

            return AuthFormCard(
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autovalidate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHeader(
                          title: 'Create your account',
                          subtitle:
                              'Join your company community and start connecting.'),
                      AuthTextField(
                        controller: _name,
                        label: 'Full name',
                        icon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        enabled: !submitting,
                        validator: AuthValidators.name,
                        serverError: serverErrorFor(AuthField.name),
                        onChanged: _clearServerError,
                        onSubmitted: (_) => _emailFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthTextField(
                        controller: _email,
                        focusNode: _emailFocus,
                        label: 'Email address',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        enabled: !submitting && _otpStage != _OtpStage.verified,
                        validator: AuthValidators.email,
                        serverError: serverErrorFor(AuthField.email),
                        onChanged: _onEmailChanged,
                        onSubmitted: (_) => AppConstants.emailOtpEnabled
                            ? _sendOtp()
                            : _passwordFocus.requestFocus(),
                      ),
                      if (AppConstants.emailOtpEnabled) ...[
                        const SizedBox(height: 10),
                        _EmailVerification(
                          stage: _otpStage,
                          emailVerified: _otpEmailVerified,
                          email: normalizeAuthEmail(_email.text),
                          code: _otp,
                          sending: _otpSending,
                          checking: _otpChecking,
                          resendIn: _resendIn,
                          error: _otpError,
                          onSend: submitting ? null : _sendOtp,
                          onConfirm: submitting ? null : _confirmOtp,
                          onChangeEmail: submitting
                              ? null
                              : () {
                                  _onEmailChanged(_email.text);
                                  _emailFocus.requestFocus();
                                },
                          onCodeChanged: () => setState(() {}),
                        ),
                      ],
                      const SizedBox(height: 14),
                      AuthTextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        helperText:
                            'At least ${AuthValidators.minPasswordLength} characters with a letter and a number.',
                        enabled: !submitting,
                        validator: AuthValidators.newPassword,
                        serverError: serverErrorFor(AuthField.password),
                        onChanged: _clearServerError,
                        onSubmitted: (_) =>
                            _confirmPasswordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthTextField(
                        controller: _confirmPassword,
                        focusNode: _confirmPasswordFocus,
                        label: 'Confirm password',
                        icon: Icons.lock_outline,
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        enabled: !submitting,
                        validator: AuthValidators.confirmPassword(
                            () => _password.text),
                        onChanged: _clearServerError,
                        onSubmitted: (_) => _companyFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthTextField(
                        controller: _company,
                        focusNode: _companyFocus,
                        label: 'Company name',
                        icon: Icons.business_outlined,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.organizationName],
                        helperText:
                            'If it is not listed yet, we’ll request it for review.',
                        enabled: !submitting,
                        validator: AuthValidators.company,
                        serverError: serverErrorFor(AuthField.company),
                        onChanged: _clearServerError,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 18),
                      if (error != null && errorField == null) ...[
                        AuthMessageBanner(message: error),
                        const SizedBox(height: 12),
                      ],
                      if (info != null) ...[
                        AuthMessageBanner(message: info, isError: false),
                        const SizedBox(height: 12),
                      ],
                      AuthSubmitButton(
                          label: 'Create account',
                          loading: submitting,
                          onPressed: _submit),
                      AuthFooter(
                          prompt: 'Already have an account? ',
                          actionLabel: 'Sign in',
                          onAction: submitting ? null : _backToSignIn),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

enum _OtpStage { idle, sent, verified }

class _EmailVerification extends StatelessWidget {
  const _EmailVerification({
    required this.stage,
    required this.emailVerified,
    required this.email,
    required this.code,
    required this.sending,
    required this.checking,
    required this.resendIn,
    required this.error,
    required this.onSend,
    required this.onConfirm,
    required this.onChangeEmail,
    required this.onCodeChanged,
  });
  final _OtpStage stage;
  final bool emailVerified;
  final String email;
  final TextEditingController code;
  final bool sending;
  final bool checking;
  final int resendIn;
  final String? error;
  final VoidCallback? onSend;
  final VoidCallback? onConfirm;
  final VoidCallback? onChangeEmail;
  final VoidCallback onCodeChanged;

  static const _accent = Color(0xFF7357E8);
  static const _green = Color(0xFF2E9E6A);
  static const _red = Color(0xFFC2453D);

  @override
  Widget build(BuildContext context) {
    final errorText = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!,
                style: const TextStyle(color: _red, fontSize: 12.5)),
          );

    if (stage == _OtpStage.verified) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F6EE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.verified_rounded, color: _green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                emailVerified
                    ? 'Email verified'
                    : 'Code accepted · verify later in Profile',
                style: const TextStyle(
                    color: _green, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          TextButton(onPressed: onChangeEmail, child: const Text('Change')),
        ]),
      );
    }

    if (stage == _OtpStage.idle) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 46,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF5B45D1),
                backgroundColor: const Color(0xFFEFEBFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.mark_email_read_outlined, size: 20),
            label: Text(sending ? 'Sending code…' : 'Verify email',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        if (errorText != null) errorText,
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E0F3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Enter the code sent to '),
            TextSpan(
                text: email,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF1F1D2B))),
          ]),
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6878)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => onCodeChanged(),
              onSubmitted: (_) => onConfirm?.call(),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: InputDecoration(
                hintText: '••••••',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE4E0F3))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: checking || code.text.length != 6 ? null : onConfirm,
              child: checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        if (errorText != null) errorText,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: resendIn > 0 || sending ? null : onSend,
            child: Text(
                resendIn > 0 ? 'Resend code in ${resendIn}s' : 'Resend code'),
          ),
        ),
      ]),
    );
  }
}
