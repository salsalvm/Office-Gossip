import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../notifications/domain/usecases/enable_push_notifications_usecase.dart';
import '../cubit/profile_cubit.dart';
import '../widgets/edit_profile_sheet.dart';

const _accent = Color(0xFF7357E8);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => sl<ProfileCubit>()..refresh(),
        child: const _ProfileView(),
      );
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();
  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  bool _enablingPush = false;
  bool _pushEnabled = false;

  Future<void> _enablePush() async {
    setState(() => _enablingPush = true);
    final result = await sl<EnablePushNotificationsUseCase>()(const NoParams());
    if (!mounted) return;
    setState(() => _enablingPush = false);
    result.fold(
      (failure) => _snack(failure.message),
      (_) {
        setState(() => _pushEnabled = true);
        _snack('Push notifications are enabled.');
      },
    );
  }

  Future<void> _edit(AppUser user) async {
    final saved = await showEditProfileSheet(context, user);
    if (saved && mounted) _snack('Profile updated.');
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<AuthBloc>().add(const AuthSignOutRequested());
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    final refreshing = context.select(
        (ProfileCubit cubit) => cubit.state.status == ProfileStatus.refreshing);

    if (user == null) {
      return Center(
        child: refreshing
            ? const CircularProgressIndicator()
            : OutlinedButton(
                onPressed: () => context.read<ProfileCubit>().refresh(),
                child: const Text('Load profile')),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ProfileCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ProfileHeader(user: user, onEdit: () => _edit(user)),
          const SizedBox(height: 14),
          _StatsRow(stats: user.stats),
          if (!user.canPost) ...[
            const SizedBox(height: 14),
            _PostingStatusCard(user: user, onEdit: () => _edit(user)),
          ],
          const SizedBox(height: 22),
          const _SectionLabel('Account'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.edit_outlined,
              title: 'Edit profile',
              subtitle: 'Name, role and bio',
              onTap: () => _edit(user),
            ),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Email',
              subtitle: user.email,
            ),
          ]),
          const SizedBox(height: 18),
          const _SectionLabel('Community'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.business_outlined,
              title: 'Company',
              subtitle: user.company?.name ??
                  user.pendingCompanyName ??
                  'Not a member of a company yet',
              trailing: _CompanyBadge(user: user),
            ),
          ]),
          const SizedBox(height: 18),
          const _SectionLabel('Preferences'),
          _SettingsCard(children: [
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Push notifications',
              subtitle: _pushEnabled
                  ? 'Enabled on this device'
                  : 'Get notified about community activity',
              trailing: _enablingPush
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _pushEnabled
                      ? const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF2E9E6A))
                      : null,
              onTap: _pushEnabled || _enablingPush ? null : _enablePush,
            ),
          ]),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _confirmSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: .35)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (user.createdAt != null) ...[
            const SizedBox(height: 14),
            Text('Member since ${_monthYear(user.createdAt!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ],
      ),
    );
  }

  static String _monthYear(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.toLocal().month - 1]} ${date.toLocal().year}';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.onEdit});
  final AppUser user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final role = user.roleTitle?.trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF644DD3), Color(0xFF9479EE)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: .5), width: 3),
            ),
            child: Text(user.initials,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: _accent)),
          ),
          const Spacer(),
          IconButton.filledTonal(
            onPressed: onEdit,
            tooltip: 'Edit profile',
            style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: .18),
                foregroundColor: Colors.white),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ]),
        const SizedBox(height: 14),
        Text(user.name.isEmpty ? 'Add your name' : user.name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(role == null || role.isEmpty ? 'Add your role' : role,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .85),
                fontWeight: FontWeight.w600)),
        if (user.bio?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(user.bio!.trim(),
              style: const TextStyle(color: Color(0xFFECE8FF), height: 1.4)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _HeaderChip(icon: Icons.mail_outline_rounded, label: user.email),
          if (user.company != null)
            _HeaderChip(icon: Icons.business_rounded, label: user.company!.name)
          else if (user.pendingCompanyName != null)
            _HeaderChip(
                icon: Icons.schedule_rounded,
                label: '${user.pendingCompanyName} · pending'),
        ]),
      ]),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .17),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border)),
        child: IntrinsicHeight(
          child: Row(children: [
            _Stat(value: stats.posts, label: 'Posts'),
            const VerticalDivider(width: 1, color: _border),
            _Stat(value: stats.reactions, label: 'Reactions'),
            const VerticalDivider(width: 1, color: _border),
            _Stat(value: stats.comments, label: 'Comments'),
          ]),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text('$value',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        ]),
      );
}

class _PostingStatusCard extends StatelessWidget {
  const _PostingStatusCard({required this.user, required this.onEdit});
  final AppUser user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final needsName =
        user.missingForPosting.contains(PostingRequirement.displayName);
    final pending = user.company == null && user.companyRequestPending;
    final message = needsName
        ? 'Add a display name so you can start posting.'
        : pending
            ? 'Your request to join “${user.pendingCompanyName}” is waiting for admin approval. You can post once it’s approved.'
            : 'Join your company community to start posting.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5E1A6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(pending ? Icons.schedule_rounded : Icons.info_outline_rounded,
            color: const Color(0xFFB07D00)),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Posting is not available yet',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(message,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: Color(0xFF6B5A2A))),
            if (needsName) ...[
              const SizedBox(height: 8),
              TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, foregroundColor: _accent),
                  child: const Text('Complete profile')),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _CompanyBadge extends StatelessWidget {
  const _CompanyBadge({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final (label, color) = user.company != null
        ? ('Active', const Color(0xFF2E9E6A))
        : user.companyRequestPending
            ? ('Pending', const Color(0xFFB07D00))
            : ('None', _muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: .8,
                fontWeight: FontWeight.w700,
                color: _muted)),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border)),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60, color: _border),
            children[i],
          ],
        ]),
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: const Color(0xFFF0EDFF),
              borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 19, color: _accent),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _muted)),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right_rounded, color: _muted)
                : null),
      );
}
