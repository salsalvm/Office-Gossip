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
import '../../../../core/presentation/otp_notification.dart';
import '../widgets/company_picker_field.dart';

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
  final _company = TextEditingController();
  final _companyWebsite = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _companyFocus = FocusNode();
  final _companyWebsiteFocus = FocusNode();
  List<SignUpCompany> _companies = const [];
  bool _companiesLoading = false;
  String? _companiesError;
  SignUpCompany? _selectedCompany;
  bool _requestNewCompany = false;
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
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _companiesLoading = true;
      _companiesError = null;
    });
    try {
      final response =
          await _dio.get<List<dynamic>>(ApiEndpoints.publicCompanies);
      final companies = (response.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SignUpCompany.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        if (!companies.any((c) => c.id == _selectedCompany?.id)) {
          _selectedCompany = null;
        }
      });
    } on Object {
      if (mounted) {
        setState(() => _companiesError =
            'Could not load the company list. Tap refresh to try again.');
      }
    } finally {
      if (mounted) setState(() => _companiesLoading = false);
    }
  }

  void _setRequestNewCompany(bool value, {String prefill = ''}) {
    _clearServerError('');
    setState(() => _requestNewCompany = value);
    if (value) {
      if (prefill.isNotEmpty) _company.text = prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _companyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    OtpNotification.dismiss();
    _otp.dispose();
    _authBloc.add(const AuthMessageCleared());
    for (final controller in [
      _name,
      _email,
      _password,
      _company,
      _companyWebsite
    ]) {
      controller.dispose();
    }
    for (final node in [
      _emailFocus,
      _passwordFocus,
      _companyFocus,
      _companyWebsiteFocus
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
        companyId: _requestNewCompany ? null : _selectedCompany?.id,
        companyName: _requestNewCompany ? _company.text.trim() : null,
        companyWebsite:
            _requestNewCompany && _companyWebsite.text.trim().isNotEmpty
                ? _companyWebsite.text.trim()
                : null,
        verificationToken: _verificationToken));
  }

  Dio get _dio => sl<Dio>();

  String _errorText(Object error, String fallback) =>
      error is DioException ? AppException.fromDio(error).message : fallback;

  void _onEmailChanged(String value) {
    _clearServerError(value);
    if (_otpStage != _OtpStage.idle || _otpError != null) {
      _resendTimer?.cancel();
      OtpNotification.dismiss();
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
      final response = await _dio
          .post<Map<String, dynamic>>(ApiEndpoints.emailSendOtp, data: {
        'email': normalizeAuthEmail(_email.text),
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
      });
      if (!mounted) return;
      _otp.clear();
      setState(() => _otpStage = _OtpStage.sent);
      _startResendCooldown();
      final fallbackCode = response.data?['code'];
      if (fallbackCode is String) {
        final seconds = response.data?['expiresInSeconds'];
        OtpNotification.show(
          context,
          code: fallbackCode,
          expiresIn: Duration(seconds: seconds is num ? seconds.toInt() : 600),
          onUse: () => setState(() {
            _otp.text = fallbackCode;
            _otpError = null;
          }),
        );
      } else {
        OtpNotification.dismiss();
      }
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
      OtpNotification.dismiss();
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
                        onSubmitted: (_) => _requestNewCompany
                            ? _companyFocus.requestFocus()
                            : _emailFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      if (_requestNewCompany) ...[
                        AuthTextField(
                          controller: _company,
                          focusNode: _companyFocus,
                          label: 'Company name',
                          icon: Icons.business_outlined,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.organizationName],
                          enabled: !submitting,
                          validator: AuthValidators.company,
                          serverError: serverErrorFor(AuthField.company),
                          onChanged: (value) {
                            _clearServerError(value);
                            setState(() {});
                          },
                          onSubmitted: (_) =>
                              _companyWebsiteFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        AuthTextField(
                          controller: _companyWebsite,
                          focusNode: _companyWebsiteFocus,
                          label: 'Company website (optional)',
                          icon: Icons.language_outlined,
                          keyboardType: TextInputType.url,
                          autofillHints: const [AutofillHints.url],
                          helperText: _companyWebsite.text.trim().isNotEmpty
                              ? 'We’ll use this website for your company.'
                              : defaultCompanyDomain(_company.text).isNotEmpty
                                  ? 'Leave blank to use ${defaultCompanyDomain(_company.text)}.'
                                  : 'Leave blank and we’ll use your company name + .com.',
                          enabled: !submitting,
                          validator: AuthValidators.companyWebsite,
                          onChanged: (value) {
                            _clearServerError(value);
                            setState(() {});
                          },
                          onSubmitted: (_) => _emailFocus.requestFocus(),
                        ),
                        const SizedBox(height: 10),
                        const _CompanyRequestNote(),
                      ] else
                        CompanyPickerField(
                          companies: _companies,
                          selected: _selectedCompany,
                          loading: _companiesLoading,
                          loadError: _companiesError,
                          enabled: !submitting,
                          serverError: serverErrorFor(AuthField.company),
                          onRefresh: _loadCompanies,
                          onSelected: (company) {
                            _clearServerError('');
                            setState(() => _selectedCompany = company);
                          },
                          onNotListed: (query) =>
                              _setRequestNewCompany(true, prefill: query),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: submitting
                              ? null
                              : () =>
                                  _setRequestNewCompany(!_requestNewCompany),
                          child: Text(_requestNewCompany
                              ? '← Choose a listed company'
                              : 'My company isn’t listed'),
                        ),
                      ),
                      const SizedBox(height: 4),
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
                        suffix: AppConstants.emailOtpEnabled
                            ? _EmailVerifyAction(
                                stage: _otpStage,
                                emailVerified: _otpEmailVerified,
                                sending: _otpSending,
                                resendIn: _resendIn,
                                onSend: submitting ? null : _sendOtp,
                              )
                            : null,
                      ),
                      if (AppConstants.emailOtpEnabled) ...[
                        const SizedBox(height: 6),
                        _EmailVerification(
                          stage: _otpStage,
                          emailVerified: _otpEmailVerified,
                          email: normalizeAuthEmail(_email.text),
                          code: _otp,
                          checking: _otpChecking,
                          error: _otpError,
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
                        hintText:
                            'At least ${AuthValidators.minPasswordLength} characters',
                        enabled: !submitting,
                        validator: AuthValidators.newPassword,
                        serverError: serverErrorFor(AuthField.password),
                        textInputAction: TextInputAction.done,
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
                          label: _requestNewCompany
                              ? 'Request company & create account'
                              : 'Create account',
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

class _CompanyRequestNote extends StatelessWidget {
  const _CompanyRequestNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E0F3)),
        ),
        child: const Row(children: [
          Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF7357E8)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
                'We’ll send this company to the Office Gossip team for review.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6B6878))),
          ),
        ]),
      );
}

/// Compact action shown inside the email field: Verify → Resend → ✓ Verified.
class _EmailVerifyAction extends StatelessWidget {
  const _EmailVerifyAction({
    required this.stage,
    required this.emailVerified,
    required this.sending,
    required this.resendIn,
    required this.onSend,
  });
  final _OtpStage stage;
  final bool emailVerified;
  final bool sending;
  final int resendIn;
  final VoidCallback? onSend;

  static const _green = Color(0xFF2E9E6A);

  @override
  Widget build(BuildContext context) {
    if (stage == _OtpStage.verified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F6EE),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_rounded, color: _green, size: 15),
          const SizedBox(width: 4),
          Text(emailVerified ? 'Verified' : 'Accepted',
              style: const TextStyle(
                  color: _green, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
    }

    final coolingDown = stage == _OtpStage.sent && resendIn > 0;
    final label = sending
        ? 'Sending…'
        : stage == _OtpStage.sent
            ? (coolingDown ? 'Resend ${resendIn}s' : 'Resend')
            : 'Verify';
    return SizedBox(
      height: 32,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFEFEBFF),
          foregroundColor: const Color(0xFF5B45D1),
          disabledBackgroundColor: const Color(0xFFF3F2F6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        onPressed: sending || coolingDown ? null : onSend,
        child: Text(label),
      ),
    );
  }
}

class _EmailVerification extends StatelessWidget {
  const _EmailVerification({
    required this.stage,
    required this.emailVerified,
    required this.email,
    required this.code,
    required this.checking,
    required this.error,
    required this.onConfirm,
    required this.onChangeEmail,
    required this.onCodeChanged,
  });
  final _OtpStage stage;
  final bool emailVerified;
  final String email;
  final TextEditingController code;
  final bool checking;
  final String? error;
  final VoidCallback? onConfirm;
  final VoidCallback? onChangeEmail;
  final VoidCallback onCodeChanged;

  static const _accent = Color(0xFF7357E8);
  static const _green = Color(0xFF2E9E6A);
  static const _red = Color(0xFFC2453D);
  static const _hintStyle = TextStyle(fontSize: 12, color: Color(0xFF85868D));

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
      return Row(children: [
        Expanded(
          child: Text(
              emailVerified
                  ? 'Email verified.'
                  : 'Code accepted — you can verify your email later from Profile.',
              style: _hintStyle.copyWith(color: _green)),
        ),
        TextButton(
          onPressed: onChangeEmail,
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12)),
          child: const Text('Use a different email'),
        ),
      ]);
    }

    if (stage == _OtpStage.idle) {
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: errorText ??
            const Text(
                'We’ll email you a one-time code to confirm it’s really you.',
                style: _hintStyle),
      );
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
      ]),
    );
  }
}
