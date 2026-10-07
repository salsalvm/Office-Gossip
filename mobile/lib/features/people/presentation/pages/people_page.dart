import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/constants/app_links.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../../../core/presentation/widgets/offline_banner.dart';
import '../../../../core/presentation/widgets/page_hero.dart';
import '../../../feed/domain/entities/community_member.dart';
import '../bloc/people_bloc.dart';
import '../../../../core/presentation/tap_guard.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  /// Opens the native share sheet; falls back to copying the link.
  Future<void> _invite(BuildContext anchor, String? companyName) async {
    final where = companyName == null ? '' : ' at $companyName';
    final text =
        'Join me$where on Office Gossip — a kinder corner of the internet for coworkers. Sign up here: ${AppLinks.webDomain}';
    final box = anchor.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: 'Join me on Office Gossip',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _snack('Invite link copied — paste it to your coworkers.');
    }
  }

  List<CommunityMember> _filter(List<CommunityMember> people) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return people;
    return people
        .where((p) =>
            p.name.toLowerCase().contains(query) ||
            p.role.toLowerCase().contains(query) ||
            p.team.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    final companyName = user?.company?.name;

    return BlocBuilder<PeopleBloc, PeopleState>(builder: (context, state) {
      final people = _filter(state.people);
      final loading = (state.status == PeopleStatus.loading ||
              state.status == PeopleStatus.initial) &&
          state.people.isEmpty;

      return Column(children: [
        Padding(
          padding: PageHero.headerPadding,
          child: Column(children: [
            PageHero(
              tone: HeroTone.emerald,
              icon: Icons.groups_rounded,
              overline: companyName ?? 'Your community',
              title: 'People',
              subtitle: companyName != null
                  ? 'Get to know the folks who make $companyName what it is.'
                  : 'Your coworkers will appear here once you join a company.',
              action: companyName == null
                  ? null
                  : Builder(
                      builder: (anchor) => IconButton.filledTonal(
                        onPressed: TapGuard.wrap(() => _invite(anchor, companyName)),
                        tooltip: 'Invite coworkers',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: .18),
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 18),
                      ),
                    ),
            ),
            const SizedBox(height: PageHero.gap),
            TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Find someone by name, role, or team',
                hintStyle: const TextStyle(fontSize: 13, color: _muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _muted),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: TapGuard.wrap(() {
                          _search.clear();
                          setState(() => _query = '');
                        }),
                        icon: const Icon(Icons.close_rounded, color: _muted)),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _accent, width: 1.4)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Members',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              if (!loading) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE6F6F0),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${people.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F8A6C))),
                ),
              ],
            ]),
            const SizedBox(height: 8),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _accent,
            onRefresh: () async =>
                context.read<PeopleBloc>().add(const PeopleRequested()),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
              children: [
                if (state.offline)
                  OfflineBanner(
                    syncedAt: state.syncedAt,
                    onRetry: () =>
                        context.read<PeopleBloc>().add(const PeopleRequested()),
                  ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.status == PeopleStatus.failure)
                  _PeopleMessage(
                    icon: Icons.cloud_off_rounded,
                    title: 'People unavailable',
                    detail: state.message ?? 'We couldn’t load your community.',
                    onRetry: () =>
                        context.read<PeopleBloc>().add(const PeopleRequested()),
                  )
                else if (state.people.isEmpty)
                  _PeopleMessage(
                    icon: Icons.group_add_outlined,
                    title: companyName == null
                        ? 'No company community yet'
                        : 'No members to show yet',
                    detail: user?.pendingCompanyName != null
                        ? '“${user!.pendingCompanyName}” is waiting for approval. You’ll see coworkers here once it’s approved.'
                        : 'Invite coworkers to join your company on Office Gossip.',
                    actionLabel:
                        companyName == null ? null : 'Invite coworkers',
                    onAction: companyName == null
                        ? null
                        : (anchor) => _invite(anchor, companyName),
                  )
                else if (people.isEmpty)
                  const _PeopleMessage(
                    icon: Icons.search_off_rounded,
                    title: 'No people found',
                    detail: 'Try searching another name, role, or team.',
                  )
                else ...[
                  for (final person in people)
                    _PersonCard(person: person, isYou: person.id == user?.id),
                  if (companyName != null && _query.trim().isEmpty)
                    _InviteCard(
                      companyName: companyName,
                      alone: state.people.every((p) => p.id == user?.id),
                      onInvite: (anchor) => _invite(anchor, companyName),
                    ),
                ],
              ],
            ),
          ),
        ),
      ]);
    });
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.isYou});
  final CommunityMember person;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final detail = [
      person.role.isNotEmpty ? person.role : 'Community member',
      if (person.team.isNotEmpty) person.team,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        InitialsAvatar(name: person.name, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: _ink)),
              ),
              if (isYou) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF0EDFF),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('You',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _accent)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: _muted),
      ]),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.companyName,
    required this.alone,
    required this.onInvite,
  });
  final String companyName;
  final bool alone;
  final void Function(BuildContext anchor) onInvite;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F0FF), Color(0xFFFFF5EE)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2DBFF)),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: HeroTone.violet.colors),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.group_add_rounded,
                  color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        alone
                            ? 'It’s just you for now'
                            : 'Bring your team along',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
                    const SizedBox(height: 3),
                    Text(
                        alone
                            ? 'You’re one of the first from $companyName. Invite your coworkers to join you.'
                            : 'Know someone at $companyName who isn’t here yet? Send them an invite.',
                        style: const TextStyle(
                            fontSize: 12.5, height: 1.4, color: _muted)),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Builder(
            builder: (anchor) => FilledButton.icon(
              onPressed: TapGuard.wrap(() => onInvite(anchor)),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: _accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Invite coworkers'),
            ),
          ),
        ]),
      );
}

class _PeopleMessage extends StatelessWidget {
  const _PeopleMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;
  final String? actionLabel;
  final void Function(BuildContext anchor)? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border)),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: Color(0xFFE6F6F0), shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFF0F8A6C)),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: TapGuard.wrap(onRetry), child: const Text('Try again')),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            Builder(
              builder: (anchor) => FilledButton.icon(
                onPressed: TapGuard.wrap(() => onAction!(anchor)),
                style: FilledButton.styleFrom(backgroundColor: _accent),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ]),
      );
}
