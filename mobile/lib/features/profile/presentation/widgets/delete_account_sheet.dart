import 'package:flutter/material.dart';

import '../../../../core/auth/domain/entities/deactivated_account.dart';
import '../../../../core/auth/domain/usecases/account_lifecycle_usecases.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/tap_guard.dart';
import '../../../../core/usecase/usecase.dart';

const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _danger = Color(0xFFD0453F);
const _border = Color(0xFFECEAF2);

const _reasons = [
  'I don’t use Office Gossip anymore',
  'I have privacy concerns',
  'I changed jobs',
  'Too many notifications',
  'Something else',
];

/// Confirms with the member's password and deletes the account.
/// Resolves to the deletion details, or null if cancelled.
Future<AccountDeletion?> showDeleteAccountSheet(
        BuildContext context, String email) =>
    showModalBottomSheet<AccountDeletion>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: _DeleteAccountForm(email: email),
      ),
    );

class _DeleteAccountForm extends StatefulWidget {
  const _DeleteAccountForm({required this.email});
  final String email;

  @override
  State<_DeleteAccountForm> createState() => _DeleteAccountFormState();
}

class _DeleteAccountFormState extends State<_DeleteAccountForm> {
  final _password = TextEditingController();
  String? _reason;
  bool _acknowledged = false;
  bool _obscure = true;
  bool _deleting = false;
  String? _error;
  int _graceDays = 30;

  @override
  void initState() {
    super.initState();
    sl<GetAccountGraceDaysUseCase>()(const NoParams()).then((result) {
      if (mounted)
        result.fold((_) {}, (days) => setState(() => _graceDays = days));
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_deleting && _acknowledged && _password.text.isNotEmpty;

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await sl<DeleteAccountUseCase>()(
        DeleteAccountParams(password: _password.text, reason: _reason));
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _deleting = false;
        _error = failure.message;
      }),
      (deletion) => Navigator.pop(context, deletion),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.person_remove_outlined,
                    color: _danger, size: 27),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Delete your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 6),
            Text('Signed in as ${widget.email}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(height: 16),
            _Consequences(graceDays: _graceDays),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscure,
              enabled: !_deleting,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Confirm it’s you',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _error,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Why are you leaving? (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                for (final reason in _reasons)
                  DropdownMenuItem(value: reason, child: Text(reason)),
              ],
              onChanged:
                  _deleting ? null : (value) => setState(() => _reason = value),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: _deleting
                  ? null
                  : (value) => setState(() => _acknowledged = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: _danger,
              title: Text(
                  'I understand my account will be permanently deleted after $_graceDays days unless I sign in again to restore it.',
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.4, color: _muted)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: TapGuard.wrap(_canSubmit ? _delete : null),
                child: _deleting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Delete account',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            TextButton(
              onPressed: TapGuard.wrap(
                  _deleting ? null : () => Navigator.pop(context)),
              style: TextButton.styleFrom(foregroundColor: _muted),
              child: const Text('Keep my account'),
            ),
          ],
        ),
      );
}

class _Consequences extends StatelessWidget {
  const _Consequences({required this.graceDays});
  final int graceDays;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9FD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(children: [
          const _Point(
              icon: Icons.visibility_off_outlined,
              title: 'Right away',
              text:
                  'Your profile, posts and comments are hidden and you’re signed out on every device.'),
          const SizedBox(height: 10),
          _Point(
              icon: Icons.restore_rounded,
              title: 'For $graceDays days',
              text:
                  'Change your mind? Sign in again and choose Restore account.'),
          const SizedBox(height: 10),
          const _Point(
              icon: Icons.delete_forever_outlined,
              title: 'After that',
              text:
                  'Your profile, posts, comments, reactions and followers are permanently erased.'),
        ]),
      );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$title  ',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _ink)),
              TextSpan(text: text),
            ]),
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: _muted),
          ),
        ),
      ]);
}
