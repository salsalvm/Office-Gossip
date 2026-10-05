import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../../../core/presentation/widgets/page_hero.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../notifications/domain/usecases/enable_push_notifications_usecase.dart';
import '../cubit/profile_cubit.dart';
import '../../../webpage/domain/webpage_type.dart';
import '../../../webpage/presentation/pages/webpage_page.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/verify_email_sheet.dart';

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

  Future<void> _verifyEmail(AppUser user) async {
    final verified = await showVerifyEmailSheet(context, user.email);
    if (!verified || !mounted) return;
    await context.read<ProfileCubit>().refresh();
    if (mounted) _snack('Email verified.');
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

    return Column(children: [
      Padding(
        padding: PageHero.headerPadding,
        child: _ProfileHeader(user: user, onEdit: () => _edit(user)),
      ),
      const SizedBox(height: PageHero.gap),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => context.read<ProfileCubit>().refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _StatsRow(stats: user.stats),
              if (user.bio?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _AboutCard(bio: user.bio!.trim()),
              ],
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
                  onTap: user.emailVerified ? null : () => _verifyEmail(user),
                  trailing: user.emailVerified
                      ? null
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF8D4D2)),
                          ),
                          child: const Text('Not verified · Verify',
                              style: TextStyle(
                                  color: Color(0xFFC2453D),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
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
                  onTap: user.company?.website == null
                      ? null
                      : () => openWebpage(context, WebpageType.company,
                          domain: user.company!.website!,
                          title: user.company!.name),
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
              const SizedBox(height: 18),
              const _SectionLabel('Support & legal'),
              _SettingsCard(children: [
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help center',
                  subtitle: 'FAQs and contact support',
                  onTap: () => openWebpage(context, WebpageType.help),
                ),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  subtitle: 'How we handle your data',
                  onTap: () => openWebpage(context, WebpageType.privacy),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms & conditions',
                  subtitle: 'Rules for using Office Gossip',
                  onTap: () => openWebpage(context, WebpageType.terms),
                ),
              ]),
              const SizedBox(height: 18),
              _SignOutCard(email: user.email, onTap: _confirmSignOut),
              if (user.createdAt != null) ...[
                const SizedBox(height: 14),
                Text('Member since ${_monthYear(user.createdAt!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: _muted)),
              ],
            ],
          ),
        ),
      ),
    ]);
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
    final overline = user.company?.name ??
        (user.pendingCompanyName != null
            ? '${user.pendingCompanyName} · pending'
            : 'Your space');
    return PageHero(
      tone: HeroTone.midnight,
      overline: overline,
      title: user.name.isEmpty ? 'Add your name' : user.name,
      subtitle: [
        role == null || role.isEmpty ? 'Add your role' : role,
        user.email,
      ].join('\n'),
      badge: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: .5), width: 2),
        ),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Text(initialsOf(user.name.isEmpty ? user.email : user.name),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: _accent)),
        ),
      ),
      action: IconButton.filledTonal(
        onPressed: onEdit,
        tooltip: 'Edit profile',
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: .18),
            foregroundColor: Colors.white),
        icon: const Icon(Icons.edit_outlined, size: 18),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.bio});
  final String bio;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ABOUT ME',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: _muted)),
          const SizedBox(height: 6),
          Text(bio, style: const TextStyle(height: 1.45)),
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
            borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(14),
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

class _SignOutCard extends StatelessWidget {
  const _SignOutCard({required this.email, required this.onTap});
  final String email;
  final VoidCallback onTap;

  static const _danger = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFF6D5D6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(11)),
                child:
                    const Icon(Icons.logout_rounded, size: 19, color: _danger),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sign out',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _danger)),
                      const SizedBox(height: 2),
                      Text('Signed in as $email',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _muted)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: _danger),
            ]),
          ),
        ),
      );
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
            borderRadius: BorderRadius.circular(14),
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
