import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';

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
  late final AuthBloc _authBloc = context.read<AuthBloc>();

  @override
  void initState() {
    super.initState();
    _authBloc.add(const AuthMessageCleared());
  }

  @override
  void dispose() {
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
    _authBloc.add(AuthRegisterRequested(
        name: _name.text.trim(),
        email: normalizeAuthEmail(_email.text),
        password: _password.text,
        companyName: _company.text.trim()));
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
                        enabled: !submitting,
                        validator: AuthValidators.email,
                        serverError: serverErrorFor(AuthField.email),
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
