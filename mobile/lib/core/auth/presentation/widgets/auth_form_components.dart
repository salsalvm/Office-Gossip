import 'package:flutter/material.dart';

import '../../../presentation/widgets/office_gossip_mark.dart';

String normalizeAuthEmail(String value) {
  final input = value.trim();
  final markdownLink = RegExp(r'^\[([^\]]+)\]\(mailto:[^)]+\)$');
  return markdownLink.firstMatch(input)?.group(1)?.trim() ?? input;
}

bool isValidAuthEmail(String? value) {
  if (value == null) return false;
  final email = normalizeAuthEmail(value);
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child});
  final Widget child;

  /// Below this width the form fills the screen instead of sitting in a card.
  static const double _cardBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < _cardBreakpoint;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
                : const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: compact
                  ? child
                  : Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFEEEDEB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 32),
                        child: child,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const OfficeGossipMark(size: 40),
          const SizedBox(width: 10),
          const Text.rich(TextSpan(
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -1,
                  color: Color(0xFF292A30)),
              children: [
                TextSpan(text: 'office'),
                TextSpan(
                    text: 'gossip', style: TextStyle(color: Color(0xFF7357E8)))
              ])),
        ],
      );
}

Widget authOverline() => const Text('A KINDER WORKPLACE COMMUNITY',
    style: TextStyle(
        fontSize: 9,
        letterSpacing: .6,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8274CF)));

Widget authDivider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 17),
      child: Row(children: [
        Expanded(child: Divider(color: Color(0xFFEEEDEB))),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('or continue with email',
                style: TextStyle(fontSize: 10, color: Color(0xFFA1A1A8)))),
        Expanded(child: Divider(color: Color(0xFFEEEDEB)))
      ]),
    );

InputDecoration authInputDecoration(String label, IconData icon) =>
    InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF777880)),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE6E5E8))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE6E5E8))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF9688E5), width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );

enum AuthField { name, email, password, company }

class AuthValidators {
  AuthValidators._();

  static const int minPasswordLength = 8;

  static String? name(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your name';
    if (name.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your email';
    if (!isValidAuthEmail(value)) return 'Enter a valid email address';
    return null;
  }

  static String? loginPassword(String? value) =>
      value == null || value.isEmpty ? 'Enter your password' : null;

  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Create a password';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  static String? company(String? value) {
    final company = value?.trim() ?? '';
    if (company.isEmpty) return 'Enter your company name';
    if (company.length < 2) return 'Company name must be at least 2 characters';
    if (company.length > 100) {
      return 'Company name must be 100 characters or fewer';
    }
    return null;
  }

  /// Optional; mirrors the API, which strips the scheme and path before checking.
  static String? companyWebsite(String? value) {
    final domain = cleanCompanyDomain(value ?? '');
    if (domain.isEmpty) return null;
    final valid = RegExp(
            r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
        .hasMatch(domain);
    return valid && domain.length <= 253
        ? null
        : 'Enter a valid company website, like acme.com';
  }
}

String cleanCompanyDomain(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/.*$'), '')
    .toLowerCase();

/// Mirrors the API default for requested companies: "Acme Labs" → "acmelabs.com".
String defaultCompanyDomain(String name) {
  final slug = name.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return slug.isEmpty ? '' : '$slug.com';
}

/// Routes an API error to the form field it concerns; `null` means show it as a banner.
AuthField? authFieldForServerMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('invalid login credentials')) return null;
  if (lower.contains('already') && lower.contains('registered')) {
    return AuthField.email;
  }
  if (lower.contains('email')) return AuthField.email;
  if (lower.contains('password')) return AuthField.password;
  if (lower.contains('company')) return AuthField.company;
  if (lower.contains('name')) return AuthField.name;
  return null;
}

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.serverError,
    this.helperText,
    this.hintText,
    this.focusNode,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.obscure = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
  });

  /// Trailing widget inside the field, e.g. an inline action button.
  final Widget? suffix;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FormFieldValidator<String>? validator;

  /// Error returned by the API for this field; shown until the user edits it.
  final String? serverError;
  final String? helperText;

  /// Placeholder shown inside the empty field.
  final String? hintText;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool obscure;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        obscureText: _hidden,
        enableSuggestions: !widget.obscure,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        forceErrorText: widget.serverError,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        decoration: authInputDecoration(widget.label, widget.icon).copyWith(
          helperText: widget.helperText,
          hintText: widget.hintText,
          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFA1A1A8)),
          floatingLabelBehavior:
              widget.hintText == null ? null : FloatingLabelBehavior.always,
          helperMaxLines: 2,
          errorMaxLines: 2,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(_hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                )
              : widget.suffix == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: widget.suffix,
                    ),
          suffixIconConstraints: widget.suffix == null
              ? null
              : const BoxConstraints(minHeight: 32),
        ),
      );
}

class AuthMessageBanner extends StatelessWidget {
  const AuthMessageBanner(
      {super.key, required this.message, this.isError = true});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color =
        isError ? Theme.of(context).colorScheme.error : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, height: 1.4, color: color))),
      ]),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(45),
            backgroundColor: const Color(0xFF7357E8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label),
      );
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthBrand(),
          const SizedBox(height: 28),
          authOverline(),
          const SizedBox(height: 9),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 27,
                  height: 1.2,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF292A30))),
          const SizedBox(height: 7),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 13, height: 1.6, color: Color(0xFF888992))),
          const SizedBox(height: 23),
        ],
      );
}

class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onAction,
  });
  final String prompt;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Column(children: [
        const SizedBox(height: 12),
        Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(prompt,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF85868D))),
              GestureDetector(
                  onTap: onAction,
                  child: Text(actionLabel,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7357E8)))),
            ]),
        const SizedBox(height: 20),
        const Text(
            'By continuing, you agree to follow your company’s community guidelines.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 9, height: 1.5, color: Color(0xFFA1A1A8))),
      ]);
}
