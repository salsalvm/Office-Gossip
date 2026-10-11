import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/domain/entities/app_user.dart';
import '../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_links.dart';
import '../../core/presentation/tap_guard.dart';
import '../../core/presentation/widgets/initials_avatar.dart';
import '../../core/presentation/widgets/office_gossip_mark.dart';
import '../../features/profile/presentation/widgets/choose_company_sheet.dart';
import '../../features/profile/presentation/widgets/edit_profile_sheet.dart';
import '../../features/profile/presentation/widgets/verify_email_sheet.dart';
import '../../features/webpage/domain/webpage_type.dart';
import '../../features/webpage/presentation/pages/webpage_page.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);
const _danger = Color(0xFFE5484D);

/// Opened from the app-bar logo: who you are, what's left to set up,
/// navigation and the account actions members reach for most.
class MemberDrawer extends StatelessWidget {
  const MemberDrawer({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<(IconData icon, IconData selectedIcon, String label)> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _profileIndex = 3;

  /// Closes the drawer first so sheets and pages open on top of the app.
  void _then(BuildContext context, void Function() action) {
    Navigator.pop(context);
    action();
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final authBloc = context.read<AuthBloc>();
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
              style: FilledButton.styleFrom(backgroundColor: _danger),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) authBloc.add(const AuthSignOutRequested());
  }

  Future<void> _invite(BuildContext context, String? companyName) async {
    final messenger = ScaffoldMessenger.of(context);
    final where = companyName == null ? '' : ' at $companyName';
    final text =
        'Join me$where on Office Gossip — a kinder corner of the internet for coworkers. Sign up here: ${AppLinks.webDomain}';
    try {
      await SharePlus.instance
          .share(ShareParams(text: text, subject: 'Join me on Office Gossip'));
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(const SnackBar(
          content: Text('Invite link copied — paste it to your coworkers.')));
    }
  }

  Future<void> _verifyEmail(BuildContext context, AppUser user) async {
    final authBloc = context.read<AuthBloc>();
    final verified = await showVerifyEmailSheet(context, user.email);
    if (verified) authBloc.add(const AuthUserRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    // Sheets need a context that outlives the drawer.
    final appContext = Navigator.of(context, rootNavigator: true).context;

    return Drawer(
      backgroundColor: const Color(0xFFF8F7FC),
      width: 304,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            const _Brand(),
            const SizedBox(height: 14),
            if (user != null) ...[
              _ProfileCard(
                user: user,
                onTap: () => _then(context, () => onSelected(_profileIndex)),
              ),
              if (_setupSteps(user).isNotEmpty) ...[
                const SizedBox(height: 10),
                _SetupCard(
                  steps: _setupSteps(user),
                  onStep: (step) => _then(context, () {
                    switch (step) {
                      case _Setup.name:
                        showEditProfileSheet(appContext, user);
                      case _Setup.company:
                        showChooseCompanySheet(appContext, user);
                      case _Setup.email:
                        _verifyEmail(appContext, user);
                    }
                  }),
                ),
              ],
            ],
            const SizedBox(height: 16),
            const _Label('Browse'),
            _Group(children: [
              for (var i = 0; i < destinations.length; i++)
                _Item(
                  icon: i == currentIndex
                      ? destinations[i].$2
                      : destinations[i].$1,
                  title: destinations[i].$3,
                  selected: i == currentIndex,
                  onTap: () => _then(context, () => onSelected(i)),
                ),
            ]),
            if (user != null) ...[
              const SizedBox(height: 16),
              const _Label('Your account'),
              _Group(children: [
                _Item(
                  icon: Icons.edit_outlined,
                  title: 'Edit profile',
                  subtitle: 'Name, role and bio',
                  onTap: () => _then(
                      context, () => showEditProfileSheet(appContext, user)),
                ),
                _Item(
                  icon: Icons.business_outlined,
                  title: 'Company',
                  subtitle: user.company?.name ??
                      (user.pendingCompanyName != null
                          ? '${user.pendingCompanyName} · awaiting approval'
                          : 'Choose your company'),
                  onTap: user.company != null
                      ? () => _then(context, () => onSelected(_profileIndex))
                      : () => _then(context,
                          () => showChooseCompanySheet(appContext, user)),
                ),
                _Item(
                  icon: Icons.person_add_alt_1_outlined,
                  title: 'Invite coworkers',
                  subtitle: 'Share Office Gossip with your team',
                  onTap: () => _then(
                      context, () => _invite(appContext, user.company?.name)),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            const _Label('Support'),
            _Group(children: [
              _Item(
                icon: Icons.help_outline_rounded,
                title: 'Help & contact',
                onTap: () => _then(
                    context, () => openWebpage(appContext, WebpageType.help)),
              ),
              _Item(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                onTap: () => _then(context,
                    () => openWebpage(appContext, WebpageType.privacy)),
              ),
              _Item(
                icon: Icons.description_outlined,
                title: 'Terms & conditions',
                onTap: () => _then(
                    context, () => openWebpage(appContext, WebpageType.terms)),
              ),
            ]),
            if (user != null) ...[
              const SizedBox(height: 16),
              _Group(children: [
                _Item(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle: user.email,
                  danger: true,
                  onTap: () =>
                      _then(context, () => _confirmSignOut(appContext)),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            const Text('A kinder corner of the internet ✿',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
    );
  }

  static List<_Setup> _setupSteps(AppUser user) => [
        if (user.name.trim().isEmpty) _Setup.name,
        if (user.company == null) _Setup.company,
        if (AppConstants.emailOtpEnabled && !user.emailVerified) _Setup.email,
      ];
}

enum _Setup { name, company, email }

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          const OfficeGossipMark(size: 34),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'office'),
                TextSpan(text: 'gossip', style: TextStyle(color: _accent)),
              ]),
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                  color: _ink),
            ),
          ),
          IconButton(
            onPressed: TapGuard.wrap(() => Navigator.pop(context)),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ]),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.onTap});
  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = user.roleTitle?.trim() ?? '';
    final (badge, badgeColor) = user.company != null
        ? ('Verified', const Color(0xFF7EE2B0))
        : user.companyRequestPending
            ? ('Pending', const Color(0xFFFFD27A))
            : ('No company', Colors.white70);
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2547), Color(0xFF5B45C9)],
          ),
        ),
        child: InkWell(
          onTap: TapGuard.wrap(onTap),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .5), width: 1.5),
                  ),
                  child: InitialsAvatar(
                      name: user.name.isEmpty ? user.email : user.name,
                      size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name.isEmpty ? 'Add your name' : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(role.isEmpty ? user.email : role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: .75))),
                      ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.business_rounded,
                    size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      user.company?.name ??
                          user.pendingCompanyName ??
                          'Not a member yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: badgeColor)),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _Stat(value: user.stats.posts, label: 'Posts'),
                  _Stat(value: user.stats.reactions, label: 'Reactions'),
                  _Stat(value: user.stats.comments, label: 'Comments'),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text('$value',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: Colors.white.withValues(alpha: .7))),
        ]),
      );
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.steps, required this.onStep});
  final List<_Setup> steps;
  final ValueChanged<_Setup> onStep;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF3DFAB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'FINISH SETTING UP · ${steps.length} ${steps.length == 1 ? 'STEP' : 'STEPS'} LEFT',
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB7791F))),
          const SizedBox(height: 4),
          for (final step in steps)
            InkWell(
              onTap: TapGuard.wrap(() => onStep(step)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  const Icon(Icons.radio_button_unchecked_rounded,
                      size: 16, color: Color(0xFFB7791F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        switch (step) {
                          _Setup.name => 'Add your name',
                          _Setup.company => 'Choose your company',
                          _Setup.email => 'Verify your email',
                        },
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5C4310))),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 16, color: Color(0xFFB7791F)),
                ]),
              ),
            ),
        ]),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: .8,
                fontWeight: FontWeight.w800,
                color: _muted)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(children: children),
      );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tone = danger ? _danger : _accent;
    return Material(
      color: selected ? const Color(0xFFEFEBFF) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: TapGuard.wrap(onTap),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : danger
                        ? const Color(0xFFFDECEC)
                        : const Color(0xFFF3F1FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18,
                  color: selected || danger ? tone : const Color(0xFF6B6880)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: danger
                                ? _danger
                                : selected
                                    ? _accent
                                    : _ink)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 11.5, color: _muted)),
                  ]),
            ),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration:
                    const BoxDecoration(color: _accent, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}
