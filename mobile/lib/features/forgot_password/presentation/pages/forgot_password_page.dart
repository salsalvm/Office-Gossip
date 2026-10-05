import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/auth/presentation/widgets/auth_form_components.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = ''});
  final String initialEmail;
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: AuthFormCard(
          child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthBrand(),
                    const SizedBox(height: 25),
                    Text('Reset your password',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Enter your email and we’ll send instructions if an account matches.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: authInputDecoration(
                            'Email address', Icons.mail_outline),
                        validator: (v) => !isValidAuthEmail(v)
                            ? 'Enter a valid email'
                            : null),
                    const SizedBox(height: 18),
                    BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (state.status ==
                                          AuthStatus.passwordResetSent &&
                                      state.message != null) ...[
                                    Text(state.message!,
                                        style: TextStyle(
                                            color: Colors.green.shade700)),
                                    const SizedBox(height: 12)
                                  ],
                                  if (state.message != null &&
                                      state.status !=
                                          AuthStatus.passwordResetSent &&
                                      state.status !=
                                          AuthStatus.submitting) ...[
                                    Text(state.message!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                    const SizedBox(height: 12)
                                  ],
                                  FilledButton(
                                      onPressed: state.status ==
                                              AuthStatus.submitting
                                          ? null
                                          : () {
                                              if (_formKey.currentState!
                                                  .validate())
                                                context.read<AuthBloc>().add(
                                                    AuthPasswordResetRequested(
                                                        email:
                                                            normalizeAuthEmail(
                                                                _email.text)));
                                            },
                                      style: FilledButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(50)),
                                      child: state.status ==
                                              AuthStatus.submitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Text(
                                              'Send reset instructions')),
                                ])),
                    TextButton(
                        onPressed: () => context.go('/sign-in'),
                        child: const Text('Back to sign in')),
                  ]))));
}
