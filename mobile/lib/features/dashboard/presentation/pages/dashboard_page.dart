import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../feed/domain/entities/community_post.dart';
import '../../../feed/domain/entities/community_scope.dart';
import '../../../feed/presentation/bloc/feed_bloc.dart';
import '../../../feed/presentation/cubit/community_scope_cubit.dart';
import '../../../profile/presentation/widgets/posting_gate.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.trending = false});
  final bool trending;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: sl<CommunityScopeCubit>()),
          BlocProvider(
              create: (_) => sl<FeedBloc>()..add(const FeedRequested())),
        ],
        child: BlocListener<CommunityScopeCubit, CommunityScope>(
          listener: (context, scope) =>
              context.read<FeedBloc>().add(FeedScopeChanged(scope)),
          child: _FeedView(trending: trending),
        ),
      );
}

class _FeedView extends StatefulWidget {
  const _FeedView({required this.trending});
  final bool trending;

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView> {
  bool _checkingProfile = false;

  bool get _trending => widget.trending;

  @override
  void initState() {
    super.initState();
    final scopeCubit = context.read<CommunityScopeCubit>();
    final hasCompany =
        context.read<AuthBloc>().state.session?.user?.company != null;
    if (scopeCubit.state == CommunityScope.company && !hasCompany) {
      scopeCubit.select(CommunityScope.global);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(message), behavior: SnackBarBehavior.floating));

  Future<void> _compose({String starter = ''}) async {
    setState(() => _checkingProfile = true);
    final canPost = await ensureCanPost(context);
    if (!mounted) return;
    setState(() => _checkingProfile = false);
    if (!canPost) return;

    final companyName =
        context.read<AuthBloc>().state.session?.user?.company?.name;
    final result = await showModalBottomSheet<(String, bool)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) =>
          _ComposePostSheet(companyName: companyName, starter: starter),
    );
    if (!mounted || result == null) return;
    context
        .read<FeedBloc>()
        .add(PostCreateRequested(body: result.$1, anonymous: result.$2));
  }

  void _selectScope(CommunityScope scope, AppUser? user) {
    if (scope == CommunityScope.company && user?.company == null) {
      _snack(user?.pendingCompanyName != null
          ? '“${user!.pendingCompanyName}” is waiting for approval. You’ll see your company community once it’s approved.'
          : 'Join a company to see your company community.');
      return;
    }
    context.read<CommunityScopeCubit>().select(scope);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    return BlocConsumer<FeedBloc, FeedState>(
      listenWhen: (previous, current) =>
          current.message != null && current.messageId != previous.messageId,
      listener: (context, state) => _snack(state.message!),
      builder: (context, state) {
        final posts = [...state.posts];
        if (_trending) {
          posts.sort((a, b) =>
              (b.likes + b.comments).compareTo(a.likes + a.comments));
        }
        final loading =
            state.status == FeedStatus.loading || state.status == FeedStatus.initial;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: _trending
              ? null
              : FloatingActionButton(
                  onPressed: _checkingProfile ? null : _compose,
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  tooltip: 'New post',
                  child: _checkingProfile
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.edit_rounded),
                ),
          body: RefreshIndicator(
            color: _accent,
            onRefresh: () async =>
                context.read<FeedBloc>().add(const FeedRequested()),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _CommunityHero(
                  scope: state.scope,
                  trending: _trending,
                  user: user,
                  onScopeSelected: (scope) => _selectScope(scope, user),
                ),
                if (!_trending) ...[
                  const SizedBox(height: 14),
                  _StartPostBar(
                    initials: user?.initials ?? '?',
                    busy: _checkingProfile,
                    onTap: () => _compose(),
                  ),
                ],
                const SizedBox(height: 20),
                _SectionHeader(
                  title: _trending ? 'Trending now' : 'Latest posts',
                  count: loading ? null : posts.length,
                  onRefresh: () =>
                      context.read<FeedBloc>().add(const FeedRequested()),
                ),
                const SizedBox(height: 10),
                if (loading && posts.isEmpty)
                  ...List.generate(3, (_) => const _PostSkeleton())
                else if (state.status == FeedStatus.failure && posts.isEmpty)
                  _FeedError(
                      onRetry: () =>
                          context.read<FeedBloc>().add(const FeedRequested()))
                else if (posts.isEmpty)
                  _EmptyFeed(
                    scope: state.scope,
                    onCompose: _trending ? null : _compose,
                  )
                else
                  for (var i = 0; i < posts.length; i++)
                    _PostCard(
                      post: posts[i],
                      rank: _trending ? i + 1 : null,
                      showCompany: state.scope == CommunityScope.global,
                      onLike: () => posts[i].canReact
                          ? context
                              .read<FeedBloc>()
                              .add(PostLikeRequested(posts[i].id))
                          : _snack(
                              'You can react to posts from your own company.'),
                      onComment: () =>
                          _snack('Comments are coming soon to the app.'),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommunityHero extends StatelessWidget {
  const _CommunityHero({
    required this.scope,
    required this.trending,
    required this.user,
    required this.onScopeSelected,
  });
  final CommunityScope scope;
  final bool trending;
  final AppUser? user;
  final ValueChanged<CommunityScope> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    final global = scope == CommunityScope.global;
    final companyName = user?.company?.name ?? 'Your company';
    final (overline, title, subtitle) = trending
        ? (
            global ? 'ACROSS OFFICE GOSSIP' : companyName.toUpperCase(),
            'Trending conversations',
            global
                ? 'What people everywhere are reacting to.'
                : 'What your coworkers are talking about.'
          )
        : global
            ? (
                'GLOBAL COMMUNITY',
                'One community,\nmany voices.',
                'Meet people and ideas from across Office Gossip.'
              )
            : (
                companyName.toUpperCase(),
                'Your work,\nout loud.',
                'A little more connected, one conversation at a time.'
              );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: global
              ? const [Color(0xFF5B45D1), Color(0xFF8E74F0)]
              : const [Color(0xFF3F6FD8), Color(0xFF6F9BF2)],
        ),
        boxShadow: [
          BoxShadow(
              color: (global ? _accent : const Color(0xFF3F6FD8))
                  .withValues(alpha: .25),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ScopeSwitcher(
          scope: scope,
          companyName: user?.company?.name,
          companyLocked: user?.company == null,
          onSelected: onScopeSelected,
        ),
        const SizedBox(height: 18),
        Text(overline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(
                color: Color(0xFFEDEAFF), fontSize: 13, height: 1.4)),
      ]),
    );
  }
}

class _ScopeSwitcher extends StatelessWidget {
  const _ScopeSwitcher({
    required this.scope,
    required this.companyName,
    required this.companyLocked,
    required this.onSelected,
  });
  final CommunityScope scope;
  final String? companyName;
  final bool companyLocked;
  final ValueChanged<CommunityScope> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(
            child: _ScopeOption(
              icon: Icons.public_rounded,
              label: 'Global',
              selected: scope == CommunityScope.global,
              onTap: () => onSelected(CommunityScope.global),
            ),
          ),
          Expanded(
            child: _ScopeOption(
              icon: companyLocked
                  ? Icons.lock_outline_rounded
                  : Icons.business_rounded,
              label: companyName ?? 'Company',
              selected: scope == CommunityScope.company,
              onTap: () => onSelected(CommunityScope.company),
            ),
          ),
        ]),
      );
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? _accent : Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? _accent : Colors.white)),
              ),
            ]),
          ),
        ),
      );
}

class _StartPostBar extends StatelessWidget {
  const _StartPostBar({
    required this.initials,
    required this.busy,
    required this.onTap,
  });
  final String initials;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              _Avatar(label: initials, seed: initials),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Share something with your community…',
                    style: TextStyle(color: _muted, fontSize: 13)),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: const Color(0xFFF0EDFF),
                    borderRadius: BorderRadius.circular(11)),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent))
                    : const Icon(Icons.add_rounded, color: _accent),
              ),
            ]),
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.onRefresh,
  });
  final String title;
  final int? count;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFF0EDFF),
                borderRadius: BorderRadius.circular(20)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _accent)),
          ),
        ],
        const Spacer(),
        IconButton(
            onPressed: onRefresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: _muted)),
      ]);
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.showCompany,
    required this.onLike,
    required this.onComment,
    this.rank,
  });
  final CommunityPost post;
  final bool showCompany;
  final int? rank;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (!post.anonymous && post.role.isNotEmpty) post.role,
      if (showCompany && post.company.isNotEmpty) post.company,
      post.time,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (rank != null) ...[
            Text('#$rank',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: rank! <= 3 ? const Color(0xFFE0753F) : _muted)),
            const SizedBox(width: 10),
          ],
          post.anonymous
              ? const _AnonymousAvatar()
              : _Avatar(label: _initials(post.person), seed: post.person),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(post.anonymous ? 'Anonymous' : post.person,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: _ink)),
                ),
                if (post.anonymous) ...[
                  const SizedBox(width: 6),
                  const _Tag(label: 'Anonymous'),
                ],
              ]),
              const SizedBox(height: 2),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ]),
          ),
          IconButton(
              onPressed: () {},
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz_rounded, color: _muted)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 8, 8),
          child: Text(post.body,
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: _ink)),
        ),
        Row(children: [
          _ActionButton(
            icon: post.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: '${post.likes}',
            color: !post.canReact
                ? const Color(0xFFC2C0CB)
                : post.liked
                    ? const Color(0xFFE5484D)
                    : _muted,
            onTap: onLike,
          ),
          _ActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: '${post.comments}',
            color: _muted,
            onTap: onComment,
          ),
        ]),
      ]),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.seed});
  final String label;
  final String seed;

  static const _palette = [
    (Color(0xFFF0EDFF), Color(0xFF6650D8)),
    (Color(0xFFE6F4FF), Color(0xFF2F75C9)),
    (Color(0xFFFFF0E8), Color(0xFFD0632F)),
    (Color(0xFFE8F7EF), Color(0xFF2E8B5B)),
    (Color(0xFFFFEEF3), Color(0xFFC94374)),
  ];

  @override
  Widget build(BuildContext context) {
    final (background, foreground) =
        _palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(label,
          style: TextStyle(
              color: foreground, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}

class _AnonymousAvatar extends StatelessWidget {
  const _AnonymousAvatar();

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
            color: Color(0xFF2A2838), shape: BoxShape.circle),
        child: const Icon(Icons.visibility_off_rounded,
            size: 18, color: Colors.white),
      );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFF3F2F7),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: _muted)),
      );
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
              color: const Color(0xFFF1F0F5),
              borderRadius: BorderRadius.circular(6)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: Color(0xFFF1F0F5), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bar(120, 12),
            const SizedBox(height: 6),
            bar(80, 10),
          ]),
        ]),
        const SizedBox(height: 14),
        bar(double.infinity, 12),
        const SizedBox(height: 6),
        bar(200, 12),
      ]),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.scope, required this.onCompose});
  final CommunityScope scope;
  final void Function({String starter})? onCompose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border)),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFF0EDFF), shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: _accent),
          ),
          const SizedBox(height: 14),
          const Text('A FRESH START',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: _accent)),
          const SizedBox(height: 6),
          Text(
              scope == CommunityScope.global
                  ? 'The global community is quiet'
                  : 'Your community starts here',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          const Text(
              'Celebrate a small win, ask a question, or share something that made you smile.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: _muted)),
          if (onCompose != null) ...[
            const SizedBox(height: 16),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final (label, starter) in _starters)
                    ActionChip(
                      label: Text(label),
                      backgroundColor: const Color(0xFFF7F6FB),
                      side: const BorderSide(color: _border),
                      onPressed: () => onCompose!(starter: starter),
                    ),
                ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onCompose!(),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Write the first post'),
            ),
          ],
        ]),
      );
}

const _starters = [
  ('✨ A team win', 'A small win from my team this week: '),
  ('💬 A question', 'Quick question for everyone: '),
  ('👏 A shoutout', 'Shoutout to '),
];

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border)),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded, size: 36, color: _muted),
          const SizedBox(height: 10),
          const Text('Feed unavailable',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('We couldn’t reach the community. Check your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      );
}

/// Owns its controller so it is disposed only after the sheet has fully closed.
class _ComposePostSheet extends StatefulWidget {
  const _ComposePostSheet({required this.companyName, required this.starter});
  final String? companyName;
  final String starter;

  @override
  State<_ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<_ComposePostSheet> {
  late final _body = TextEditingController(text: widget.starter);
  bool _anonymous = true;

  static const _maxLength = 500;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _useStarter(String starter) {
    _body.text = starter;
    _body.selection = TextSelection.collapsed(offset: starter.length);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _body,
          builder: (context, value, _) {
            final text = value.text.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text((widget.companyName ?? 'Your community').toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: _accent)),
                const SizedBox(height: 4),
                const Text('Start a conversation',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(height: 4),
                const Text(
                    'Shared with your company and visible in the Global community.',
                    style: TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 14),
                TextField(
                  controller: _body,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        'What’s happening at work? Share a thought, a win, or a question…',
                    hintStyle: const TextStyle(fontSize: 13, color: _muted),
                    filled: true,
                    fillColor: const Color(0xFFF8F7FC),
                    counterText: '',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (label, starter) in _starters)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(label,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: _border),
                              onPressed: () => _useStarter(starter),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Text('${value.text.length}/$_maxLength',
                      style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFFF8F7FC),
                      borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    value: _anonymous,
                    onChanged: (v) => setState(() => _anonymous = v),
                    activeThumbColor: _accent,
                    secondary: Icon(
                        _anonymous
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: _accent),
                    title: const Text('Post anonymously',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                        _anonymous
                            ? 'Your name and role stay hidden'
                            : 'Coworkers will see your name and role',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: text.isEmpty
                      ? null
                      : () => Navigator.pop(context, (text, _anonymous)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Share post'),
                ),
              ],
            );
          },
        ),
      );
}
