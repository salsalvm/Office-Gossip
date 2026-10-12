import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_links.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../../../core/presentation/widgets/page_hero.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../feed/presentation/pages/blocked_members_page.dart';
import '../../../feed/presentation/pages/saved_posts_page.dart';
import '../../../notifications/domain/usecases/enable_push_notifications_usecase.dart';
import '../cubit/profile_cubit.dart';
import '../../../webpage/domain/webpage_type.dart';
import '../../../webpage/presentation/pages/webpage_page.dart';
import '../widgets/choose_company_sheet.dart';
import '../widgets/delete_account_sheet.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/verify_email_sheet.dart';
import '../../../../core/presentation/tap_guard.dart';

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
  bool _verifyNudgeShown = false;

  /// A one-off 15s reminder per visit instead of a permanent card.
  void _maybeNudgeVerify(AppUser user) {
    if (!AppConstants.emailOtpEnabled ||
        _verifyNudgeShown ||
        user.emailVerified) {
      return;
    }
    _verifyNudgeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 15),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          backgroundColor: const Color(0xFF2A2547),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(children: [
            const Icon(Icons.mark_email_unread_outlined,
                color: Color(0xFFCFC8FA), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Verify ${user.email} with a quick one-time code.',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
          action: SnackBarAction(
            label: 'Verify',
            textColor: const Color(0xFFCFC8FA),
            onPressed: TapGuard.wrap(() => _verifyEmail(user)),
          ),
        ));
    });
  }

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

  Future<void> _chooseCompany(AppUser user) async {
    final updated = await showChooseCompanySheet(context, user);
    if (updated == null || !mounted) return;
    _snack(updated.company != null
        ? 'You joined ${updated.company!.name}.'
        : updated.companyRequestPending
            ? 'Request sent. You can post once “${updated.pendingCompanyName}” is approved.'
            : 'Company updated.');
  }

  Future<void> _invite(String? companyName) async {
    final where = companyName == null ? '' : ' at $companyName';
    final text =
        'Join me$where on Office Gossip — a kinder corner of the internet for coworkers. Sign up here: ${AppLinks.webDomain}';
    try {
      await SharePlus.instance
          .share(ShareParams(text: text, subject: 'Join me on Office Gossip'));
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _snack('Invite link copied — paste it to your coworkers.');
    }
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
              onPressed:
                  TapGuard.wrap(() => Navigator.pop(dialogContext, false)),
              child: const Text('Cancel')),
          FilledButton(
              onPressed:
                  TapGuard.wrap(() => Navigator.pop(dialogContext, true)),
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

  Future<void> _deleteAccount(AppUser user) async {
    final deletion = await showDeleteAccountSheet(context, user.email);
    if (deletion == null || !mounted) return;
    final purge = deletion.purgeAfter;
    // The app-wide messenger keeps this visible on the sign-in screen.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      content: Text(purge == null
          ? 'Your account was deleted. Sign in again within ${deletion.graceDays} days to restore it.'
          : 'Your account was deleted and will be permanently erased on ${_dayMonthYear(purge)}. Sign in again before then to restore it.'),
    ));
    context.read<AuthBloc>().add(const AuthAccountDeleted());
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    final refreshing = context.select(
        (ProfileCubit cubit) => cubit.state.status == ProfileStatus.refreshing);

    if (user != null) _maybeNudgeVerify(user);
    if (user == null) {
      return Center(
        child: refreshing
            ? const CircularProgressIndicator()
            : OutlinedButton(
                onPressed:
                    TapGuard.wrap(() => context.read<ProfileCubit>().refresh()),
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
              const SizedBox(height: 12),
              Row(children: [
                _QuickAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Invite',
                    onTap: () => _invite(user.company?.name)),
                const SizedBox(width: 10),
                _QuickAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Help',
                    onTap: () => openWebpage(context, WebpageType.help)),
              ]),
              if (user.bio?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _AboutCard(bio: user.bio!.trim()),
              ],
              if (!user.canPost || !user.companyVerified) ...[
                const SizedBox(height: 14),
                _PostingStatusCard(
                    user: user,
                    onEdit: () => _edit(user),
                    onChooseCompany: () => _chooseCompany(user)),
              ],
              const SizedBox(height: 22),
              const _SectionLabel('Account'),
              _SettingsCard(children: [
                _SettingsTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Email',
                  subtitle: user.email,
                  onTap: TapGuard.wrap(
                      user.emailVerified || !AppConstants.emailOtpEnabled
                          ? null
                          : () => _verifyEmail(user)),
                  trailing: user.emailVerified
                      ? const _StatusTag('Verified',
                          color: Color(0xFF2E9E6A),
                          icon: Icons.verified_rounded)
                      : const _StatusTag(
                          AppConstants.emailOtpEnabled
                              ? 'Not verified · Verify'
                              : 'Not verified',
                          color: Color(0xFFC2453D)),
                ),
                _SettingsTile(
                  icon: Icons.business_outlined,
                  title: 'Company',
                  subtitle: user.company?.name ??
                      (user.pendingCompanyName != null
                          ? '${user.pendingCompanyName} · Waiting for approval'
                          : 'Not a member yet · Choose your company'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _CompanyBadge(user: user),
                    if (user.company == null)
                      const Icon(Icons.chevron_right_rounded, color: _muted),
                  ]),
                  onTap: TapGuard.wrap(user.company == null
                      ? () => _chooseCompany(user)
                      : user.company!.website == null
                          ? null
                          : () => openWebpage(context, WebpageType.company,
                              domain: user.company!.website!,
                              title: user.company!.name)),
                ),
              ]),
              const SizedBox(height: 18),
              const _SectionLabel('Your activity'),
              _SettingsCard(children: [
                _SettingsTile(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Saved posts',
                  subtitle: 'Posts you bookmarked to read later',
                  onTap: () => SavedPostsPage.open(context),
                ),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Blocked & muted',
                  subtitle: 'Manage who you’ve blocked or muted',
                  onTap: () => BlockedMembersPage.open(context),
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
                  onTap: TapGuard.wrap(
                      _pushEnabled || _enablingPush ? null : _enablePush),
                ),
              ]),
              const SizedBox(height: 18),
              const _SectionLabel('Support & legal'),
              _SettingsCard(children: [
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & contact',
                  subtitle: 'FAQs and get in touch with our team',
                  onTap: TapGuard.wrap(
                      () => openWebpage(context, WebpageType.help)),
                ),
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  subtitle: 'How we handle your data',
                  onTap: TapGuard.wrap(
                      () => openWebpage(context, WebpageType.privacy)),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms & conditions',
                  subtitle: 'Rules for using Office Gossip',
                  onTap: TapGuard.wrap(
                      () => openWebpage(context, WebpageType.terms)),
                ),
              ]),
              const SizedBox(height: 18),
              _SignOutCard(
                  email: user.email, onTap: TapGuard.wrap(_confirmSignOut)),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: TapGuard.wrap(() => _deleteAccount(user)),
                  style: TextButton.styleFrom(foregroundColor: _muted),
                  icon: const Icon(Icons.person_remove_outlined, size: 17),
                  label: const Text('Delete account',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
        ),
      ),
    ]);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthYear(DateTime date) =>
      '${_months[date.toLocal().month - 1]} ${date.toLocal().year}';

  static String _dayMonthYear(DateTime date) =>
      '${_months[date.toLocal().month - 1]} ${date.toLocal().day}, ${date.toLocal().year}';
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
        onPressed: TapGuard.wrap(onEdit),
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
  Widget build(BuildContext context) => Row(children: [
        _Stat(
            icon: Icons.chat_bubble_outline_rounded,
            value: stats.posts,
            label: 'Posts',
            tone: _accent),
        const SizedBox(width: 10),
        _Stat(
            icon: Icons.favorite_border_rounded,
            value: stats.reactions,
            label: 'Reactions',
            tone: const Color(0xFFE0517A)),
        const SizedBox(width: 10),
        _Stat(
            icon: Icons.forum_outlined,
            value: stats.comments,
            label: 'Comments',
            tone: const Color(0xFF2E9E6A)),
      ]);
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
  });
  final IconData icon;
  final int value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border)),
          child: Column(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: tone.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 16, color: tone),
            ),
            const SizedBox(height: 10),
            Text('$value',
                style: const TextStyle(
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF26242F))),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ]),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: const Color(0xFFF1EDFF),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: TapGuard.wrap(onTap),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(icon, size: 20, color: _accent),
                const SizedBox(height: 5),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accent)),
              ]),
            ),
          ),
        ),
      );
}

/// Shown until the member can post to a verified company: what's done,
/// what's left, and the one next step.
class _PostingStatusCard extends StatelessWidget {
  const _PostingStatusCard({
    required this.user,
    required this.onEdit,
    required this.onChooseCompany,
  });
  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onChooseCompany;

  static const _amber = Color(0xFFB7791F);

  @override
  Widget build(BuildContext context) {
    final hasName = user.name.trim().isNotEmpty;
    final pending = user.company == null && user.companyRequestPending;
    final waiting = hasName && pending;
    final tone = waiting ? _amber : _accent;
    final softTone =
        waiting ? const Color(0xFFFFF6E0) : const Color(0xFFF1EDFF);
    final lineTone =
        waiting ? const Color(0xFFF3DFAB) : const Color(0xFFE2DAFC);
    final (icon, title, detail) = !hasName
        ? (
            Icons.edit_rounded,
            'Add your name to start posting',
            'Coworkers see your name and role on the posts you share.',
          )
        : pending
            ? (
                Icons.schedule_rounded,
                'Waiting for company approval',
                'You can post now. Posts stay visible only to you until “${user.pendingCompanyName}” is approved, then they’re shared in Global and your company community.',
              )
            : (
                Icons.business_rounded,
                'Join your company to start posting',
                'Pick your company so your posts reach your coworkers and the Global community.',
              );
    final steps = [
      _SetupStep('Display name', hasName ? user.name : 'Not added yet',
          hasName ? _StepState.done : _StepState.todo),
      _SetupStep(
          'Company',
          user.company?.name ??
              (pending
                  ? '${user.pendingCompanyName} · awaiting approval'
                  : 'Not chosen yet'),
          user.company != null
              ? _StepState.done
              : pending
                  ? _StepState.pending
                  : _StepState.todo),
    ];
    final done = steps.where((s) => s.state == _StepState.done).length;
    final progress = pending ? .75 : (done / 2).clamp(.06, 1.0);
    final actionLabel = !hasName
        ? 'Complete profile'
        : pending
            ? 'Check status'
            : 'Choose company';
    final onAction = TapGuard.wrap(!hasName ? onEdit : onChooseCompany);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [softTone, Colors.white],
          stops: const [0, .7],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: lineTone),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: tone.withValues(alpha: .35),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${waiting ? 'ALMOST THERE' : 'FINISH SETTING UP'} · $done/2',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                      color: tone)),
              const SizedBox(height: 3),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF26242F))),
              const SizedBox(height: 5),
              Text(detail,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.45, color: _muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: tone,
            backgroundColor: const Color(0xFFEBE8F3),
          ),
        ),
        const SizedBox(height: 12),
        for (final step in steps) ...[
          _SetupStepTile(step: step),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        waiting
            ? OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                    foregroundColor: tone,
                    side: BorderSide(color: lineTone),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11))),
                child: Text('$actionLabel  →',
                    style: const TextStyle(fontWeight: FontWeight.w700)))
            : FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11))),
                child: Text('$actionLabel  →',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

enum _StepState { done, pending, todo }

class _SetupStep {
  const _SetupStep(this.label, this.detail, this.state);
  final String label;
  final String detail;
  final _StepState state;
}

class _SetupStepTile extends StatelessWidget {
  const _SetupStepTile({required this.step});
  final _SetupStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, chip, fg, bg) = switch (step.state) {
      _StepState.done => (
          Icons.check_rounded,
          'Done',
          const Color(0xFF2E9E6A),
          const Color(0xFFE3F4EA)
        ),
      _StepState.pending => (
          Icons.schedule_rounded,
          'Pending',
          const Color(0xFFB7791F),
          const Color(0xFFFFF1CF)
        ),
      _StepState.todo => (
          Icons.radio_button_unchecked_rounded,
          'To do',
          const Color(0xFF9A98A6),
          const Color(0xFFF1F0F5)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEECF4)),
      ),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B2935))),
            Text(step.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text(chip,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
  }
}

class _CompanyBadge extends StatelessWidget {
  const _CompanyBadge({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => user.company != null
      ? const _StatusTag('Verified',
          color: Color(0xFF2E9E6A), icon: Icons.verified_rounded)
      : user.companyRequestPending
          ? const _StatusTag('Pending',
              color: Color(0xFFB07D00), icon: Icons.schedule_rounded)
          : const _StatusTag('None', color: _muted);
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.label, {required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
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
          onTap: TapGuard.wrap(onTap),
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
        onTap: TapGuard.wrap(onTap),
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
