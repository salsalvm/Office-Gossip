import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';
import '../../../../core/presentation/tap_guard.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  late final AuthBloc _authBloc = context.read<AuthBloc>();

  @override
  void initState() {
    super.initState();
    _authBloc.add(const AuthMessageCleared());
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
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
    _authBloc.add(AuthSignInRequested(
        email: normalizeAuthEmail(_email.text), password: _password.text));
  }

  Future<void> _openSignUp() async {
    await context.push('/sign-up');
    if (!mounted) return;
    _authBloc.add(const AuthMessageCleared());
  }

  Future<void> _openForgotPassword() async {
    await context.push('/forgot-password', extra: _email.text.trim());
    if (!mounted) return;
    _authBloc.add(const AuthMessageCleared());
  }

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
            return AuthFormCard(
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autovalidate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHeader(
                          title: 'Welcome back',
                          subtitle: 'Sign in to keep up with your community.'),
                      AuthTextField(
                        controller: _email,
                        label: 'Email address',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.email,
                          AutofillHints.username
                        ],
                        enabled: !submitting,
                        validator: AuthValidators.email,
                        serverError:
                            errorField == AuthField.email ? error : null,
                        onChanged: _clearServerError,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      AuthTextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !submitting,
                        validator: AuthValidators.loginPassword,
                        serverError:
                            errorField == AuthField.password ? error : null,
                        onChanged: _clearServerError,
                        onSubmitted: (_) => _submit(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF7357E8),
                                textStyle: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                            onPressed: TapGuard.wrap(submitting ? null : _openForgotPassword),
                            child: const Text('Forgot password?')),
                      ),
                      if (error != null && errorField == null) ...[
                        AuthMessageBanner(message: error),
                        const SizedBox(height: 12),
                      ],
                      AuthSubmitButton(
                          label: 'Sign in',
                          loading: submitting,
                          onPressed: TapGuard.wrap(_submit)),
                      AuthFooter(
                          prompt: 'New to Office Gossip? ',
                          actionLabel: 'Create an account',
                          onAction: submitting ? null : _openSignUp),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}
