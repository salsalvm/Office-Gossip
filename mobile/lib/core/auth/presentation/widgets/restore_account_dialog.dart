import 'package:flutter/material.dart';

import '../../../presentation/tap_guard.dart';
import '../../domain/entities/deactivated_account.dart';

const _ink = Color(0xFF1F1D2B);
const _accent = Color(0xFF7357E8);
const _muted = Color(0xFF7B7888);
const _danger = Color(0xFFC2453D);

/// Offers to restore a deleted account. Resolves to true to restore.
Future<bool> showRestoreAccountDialog(
        BuildContext context, DeactivatedAccount account) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RestoreAccountDialog(account: account),
    ) ??
    false;

class _RestoreAccountDialog extends StatelessWidget {
  const _RestoreAccountDialog({required this.account});
  final DeactivatedAccount account;

  static String _date(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final canRestore = account.canRestore;
    final daysLeft = account.daysLeft;
    final purgeAfter = account.purgeAfter;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: canRestore
                  ? const Color(0xFFEFEBFF)
                  : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
                canRestore ? Icons.restore_rounded : Icons.block_rounded,
                color: canRestore ? _accent : _danger,
                size: 28),
          ),
          const SizedBox(height: 14),
          Text(canRestore ? 'Welcome back!' : 'Account deactivated',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 8),
          Text(
            canRestore
                ? 'Your account is scheduled for deletion${purgeAfter == null ? '' : ' on ${_date(purgeAfter)}'}'
                    '${daysLeft == null ? '' : ' — $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left'}. '
                    'Restore it to get your profile, posts and company membership back exactly as you left them.'
                : account.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.45, color: _muted),
          ),
          const SizedBox(height: 20),
          if (canRestore)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: TapGuard.wrap(() => Navigator.pop(context, true)),
                icon: const Icon(Icons.restore_rounded, size: 20),
                label: const Text('Restore my account',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: TapGuard.wrap(() => Navigator.pop(context, false)),
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: Text(canRestore ? 'Not now' : 'Close'),
          ),
        ]),
      ),
    );
  }
}
