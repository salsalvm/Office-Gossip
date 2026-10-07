import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/di/injection_container.dart';
import '../cubit/profile_cubit.dart';
import 'edit_profile_sheet.dart';
import '../../../../core/presentation/tap_guard.dart';

/// Re-fetches the profile and, if something the API requires for posting is
/// missing, explains what to fix. Resolves to `true` only when posting can proceed.
Future<bool> ensureCanPost(BuildContext context) async {
  final cubit = sl<ProfileCubit>();
  final user = await cubit.refresh();
  await cubit.close();
  if (!context.mounted || user == null) return false;
  if (user.canPost) return true;

  final action = await showModalBottomSheet<_GateAction>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _PostingRequirementsSheet(user: user),
  );
  if (!context.mounted) return false;

  switch (action) {
    case _GateAction.editProfile:
      final saved = await showEditProfileSheet(context, user);
      if (!saved || !context.mounted) return false;
      return ensureCanPost(context);
    case _GateAction.openProfile:
      context.go('/profile');
      return false;
    case null:
      return false;
  }
}

enum _GateAction { editProfile, openProfile }

class _PostingRequirementsSheet extends StatelessWidget {
  const _PostingRequirementsSheet({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final missing = user.missingForPosting;
    final needsName = missing.contains(PostingRequirement.displayName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Finish setting up to post',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Your company community needs these before you can share.',
              style: TextStyle(fontSize: 12, color: Color(0xFF888992))),
          const SizedBox(height: 18),
          _RequirementTile(
            done: !needsName,
            title: 'Display name',
            subtitle: needsName ? 'Add the name coworkers will see' : user.name,
          ),
          _RequirementTile(
            done: user.company != null,
            title: 'Active company membership',
            subtitle: user.company?.name ??
                (user.pendingCompanyName != null
                    ? '“${user.pendingCompanyName}” is waiting for admin approval'
                    : 'Join your company to see and share posts'),
            pending: user.company == null && user.companyRequestPending,
          ),
          const SizedBox(height: 18),
          if (needsName)
            FilledButton(
                onPressed: TapGuard.wrap(() =>
                    Navigator.pop(context, _GateAction.editProfile)),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(45),
                    backgroundColor: const Color(0xFF7357E8)),
                child: const Text('Complete profile'))
          else
            FilledButton(
                onPressed: TapGuard.wrap(() =>
                    Navigator.pop(context, _GateAction.openProfile)),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(45),
                    backgroundColor: const Color(0xFF7357E8)),
                child: const Text('View profile')),
          TextButton(
              onPressed: TapGuard.wrap(() => Navigator.pop(context)),
              child: const Text('Not now')),
        ],
      ),
    );
  }
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.done,
    required this.title,
    required this.subtitle,
    this.pending = false,
  });
  final bool done;
  final bool pending;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = done
        ? (Icons.check_circle_rounded, const Color(0xFF2E9E6A))
        : pending
            ? (Icons.schedule_rounded, const Color(0xFFE0A100))
            : (Icons.radio_button_unchecked_rounded, const Color(0xFFB4B2BD));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}
