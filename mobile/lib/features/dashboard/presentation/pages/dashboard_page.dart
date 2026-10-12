import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/auth/domain/entities/app_user.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_links.dart';
import '../../../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../../../core/presentation/widgets/offline_banner.dart';
import '../../../../core/presentation/widgets/page_hero.dart';
import '../../../feed/domain/entities/announcement.dart';
import '../../../feed/domain/entities/community_post.dart';
import '../../../feed/domain/entities/community_scope.dart';
import '../../../feed/presentation/bloc/feed_bloc.dart';
import '../../../feed/presentation/cubit/community_scope_cubit.dart';
import '../../../feed/presentation/widgets/post_options_sheet.dart';
import '../../../feed/presentation/widgets/post_poll.dart';
import '../../../feed/presentation/widgets/post_reactions.dart';
import '../../../feed/presentation/widgets/hashtag_text.dart';
import '../../../feed/domain/entities/post_reaction.dart';
import '../../../feed/domain/entities/topic.dart';
import '../../../feed/domain/entities/block_entry.dart';
import '../../../profile/presentation/widgets/choose_company_sheet.dart';
import '../../../profile/presentation/widgets/posting_gate.dart';
import '../../../../core/presentation/tap_guard.dart';
import '../../../webpage/domain/webpage_type.dart';
import '../../../webpage/presentation/pages/webpage_page.dart';

const _accent = Color(0xFF7357E8);
const _minTrendInteractions = 2;
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
              create: (_) =>
                  sl<FeedBloc>(param1: trending)..add(const FeedRequested())),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<CommunityScopeCubit, CommunityScope>(
              listener: (context, scope) =>
                  context.read<FeedBloc>().add(FeedScopeChanged(scope)),
            ),
            // Approval publishes held posts, so reload once a company lands.
            BlocListener<AuthBloc, AuthState>(
              listenWhen: (previous, current) =>
                  previous.session?.user?.company == null &&
                  current.session?.user?.company != null,
              listener: (context, _) =>
                  context.read<FeedBloc>().add(const FeedRequested()),
            ),
          ],
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
  final _dismissedAnnouncements = <String>{};
  bool _websitePromoDismissed = false;
  final _search = TextEditingController();
  Timer? _searchDebounce;

  bool get _trending => widget.trending;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Searches after a short pause; a single character is too broad to send.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final query = value.trim().length < 2 ? '' : value.trim();
      final feed = context.read<FeedBloc>();
      feed.add(FeedFilterChanged(tag: feed.state.tag, query: query));
    });
  }

  void _filterByTag(String? tag) {
    final feed = context.read<FeedBloc>();
    feed.add(FeedFilterChanged(tag: tag, query: feed.state.query));
  }

  void _clearFilter() {
    _searchDebounce?.cancel();
    _search.clear();
    FocusScope.of(context).unfocus();
    context.read<FeedBloc>().add(const FeedFilterChanged());
  }

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
    ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

  Future<void> _compose({String starter = ''}) async {
    setState(() => _checkingProfile = true);
    final canPost = await ensureCanPost(context);
    if (!mounted) return;
    setState(() => _checkingProfile = false);
    if (!canPost) return;

    final companyName =
        context.read<AuthBloc>().state.session?.user?.company?.name;
    final scope = context.read<CommunityScopeCubit>().state;
    final result = await showModalBottomSheet<(String, bool, List<String>?)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _ComposePostSheet(
          companyName: companyName, scope: scope, starter: starter),
    );
    if (!mounted || result == null) return;
    context.read<FeedBloc>().add(PostCreateRequested(
        body: result.$1, anonymous: result.$2, poll: result.$3));
  }

  Future<void> _openPostOptions(CommunityPost post) async {
    final option = await showPostOptionsSheet(context, post);
    if (!mounted || option == null) return;
    final feed = context.read<FeedBloc>();
    switch (option) {
      case PostOption.copy:
        await Clipboard.setData(ClipboardData(text: post.body));
        if (mounted) _snack('Post text copied.');
      case PostOption.save:
        _toggleSave(post);
      case PostOption.mute || PostOption.block:
        final block = option == PostOption.block;
        if (await confirmBlockAuthor(context, post, block: block)) {
          feed.add(PostAuthorBlockRequested(
              postId: post.id, kind: block ? BlockKind.block : BlockKind.mute));
        }
      case PostOption.edit:
        final body = await showEditPostSheet(context, post);
        if (body != null) {
          feed.add(PostEditRequested(postId: post.id, body: body));
        }
      case PostOption.archive:
        _toggleArchive(post);
      case PostOption.delete:
        if (await confirmDeletePost(context)) {
          feed.add(PostDeleteRequested(post.id));
        }
      case PostOption.report:
        await _report(post);
    }
  }

  void _toggleSave(CommunityPost post) => context
      .read<FeedBloc>()
      .add(PostSaveRequested(postId: post.id, saved: !post.saved));

  void _toggleArchive(CommunityPost post) => context
      .read<FeedBloc>()
      .add(PostArchiveRequested(postId: post.id, archived: !post.isArchived));

  Future<void> _report(CommunityPost post) async {
    final feed = context.read<FeedBloc>();
    final reason = await showReportReasonSheet(context);
    if (reason != null) {
      feed.add(PostReportRequested(postId: post.id, reason: reason));
    }
  }

  Future<void> _chooseCompany(AppUser user) async {
    final updated = await showChooseCompanySheet(context, user);
    if (updated?.company != null && mounted) {
      context.read<CommunityScopeCubit>().select(CommunityScope.company);
    }
  }

  void _selectScope(CommunityScope scope, AppUser? user) {
    if (scope == CommunityScope.company && user?.company == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(user?.pendingCompanyName != null
              ? '“${user!.pendingCompanyName}” is waiting for approval. You’ll see your company community once it’s approved.'
              : 'Join a company to see your company community.'),
          action: user == null
              ? null
              : SnackBarAction(
                  label: user.companyRequestPending
                      ? 'Check status'
                      : 'Choose company',
                  onPressed: () => _chooseCompany(user)),
        ));
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
        // Trending arrives ranked from the server, page by page.
        final posts = state.posts.where((post) => !post.isDeleted).toList();
        final loading = state.status == FeedStatus.loading ||
            state.status == FeedStatus.initial;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: _trending
              ? null
              : FloatingActionButton(
                  onPressed: TapGuard.wrap(_checkingProfile ? null : _compose),
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
            child: SlidableAutoCloseBehavior(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification &&
                      notification.metrics.axis == Axis.vertical &&
                      notification.metrics.extentAfter < 600 &&
                      state.hasMore &&
                      !state.loadingMore) {
                    context.read<FeedBloc>().add(const FeedMoreRequested());
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: PageHero.headerPadding,
                      sliver: SliverToBoxAdapter(
                        child: _CommunityHero(
                            scope: state.scope,
                            trending: _trending,
                            user: user),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHeader(
                        child: _ScopeSwitcher(
                          scope: state.scope,
                          companyName: user?.company?.name,
                          companyLocked: user?.company == null,
                          onSelected: (scope) => _selectScope(scope, user),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(children: [
                          if (!_trending) ...[
                            _StartPostBar(
                              name: user?.name.isNotEmpty == true
                                  ? user!.name
                                  : '?',
                              busy: _checkingProfile,
                              onTap: TapGuard.wrap(() => _compose()),
                            ),
                            const SizedBox(height: 12),
                            _FeedSearchField(
                              controller: _search,
                              onChanged: _onSearchChanged,
                              onClear: _clearFilter,
                            ),
                            if (state.topics.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _TopicChips(
                                topics: state.topics,
                                selected: state.tag,
                                onSelected: _filterByTag,
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                          _SectionHeader(
                            title: _trending
                                ? 'Trending now'
                                : state.query.isNotEmpty
                                    ? 'Results for “${state.query}”${state.tag != null ? ' in #${state.tag}' : ''}'
                                    : state.tag != null
                                        ? 'Posts tagged #${state.tag}'
                                        : 'Latest posts',
                            count: loading ? null : posts.length,
                            onRefresh: () => context
                                .read<FeedBloc>()
                                .add(const FeedRequested()),
                            onClear: state.filtered ? _clearFilter : null,
                          ),
                          const SizedBox(height: 6),
                        ]),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      sliver: SliverList.list(
                        children: [
                          if (state.offline)
                            OfflineBanner(
                              syncedAt: state.syncedAt,
                              onRetry: () => context
                                  .read<FeedBloc>()
                                  .add(const FeedRequested()),
                            ),
                          if (!_trending && !state.filtered)
                            for (final announcement in state.announcements)
                              if (!_dismissedAnnouncements
                                  .contains(announcement.id))
                                _AnnouncementCard(
                                  key: ValueKey(
                                      'announcement-${announcement.id}'),
                                  announcement: announcement,
                                  onDismiss: () => setState(() =>
                                      _dismissedAnnouncements
                                          .add(announcement.id)),
                                ),
                          if (loading && posts.isEmpty)
                            ...List.generate(3, (_) => const _PostSkeleton())
                          else if (state.status == FeedStatus.failure &&
                              posts.isEmpty)
                            _FeedError(
                                onRetry: () => context
                                    .read<FeedBloc>()
                                    .add(const FeedRequested()))
                          else if (posts.isEmpty && state.filtered)
                            _NoResults(
                              tag: state.tag,
                              query: state.query,
                              onClear: _clearFilter,
                              onCompose: state.tag != null &&
                                      state.query.isEmpty
                                  ? () => _compose(starter: '#${state.tag} ')
                                  : null,
                            )
                          else if (posts.isEmpty)
                            _EmptyFeed(
                              scope: state.scope,
                              trending: _trending,
                              onCompose: _trending ? null : _compose,
                            ),
                        ],
                      ),
                    ),
                    // Built lazily so only cards on screen are laid out.
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: posts.length,
                        findChildIndexCallback: (key) {
                          final index = posts
                              .indexWhere((post) => ValueKey(post.id) == key);
                          return index < 0 ? null : index;
                        },
                        itemBuilder: (context, i) {
                          final card = _PostCard(
                            post: posts[i],
                            rank: _trending ? i + 1 : null,
                            topHeat: posts.first.likes + posts.first.comments,
                            showCompany: state.scope == CommunityScope.global,
                            onReact: (reaction) => context
                                .read<FeedBloc>()
                                .add(PostReactionRequested(
                                    postId: posts[i].id, reaction: reaction)),
                            onTag: _trending ? null : _filterByTag,
                            onComment: () =>
                                _snack('Comments are coming soon to the app.'),
                            onMore: () => _openPostOptions(posts[i]),
                            onSave: () => _toggleSave(posts[i]),
                            onVote: (optionId) => context.read<FeedBloc>().add(
                                PostVoteRequested(
                                    postId: posts[i].id, optionId: optionId)),
                            onConfirmDelete: () => confirmDeletePost(context),
                            onDeleted: () => context
                                .read<FeedBloc>()
                                .add(PostDeleteRequested(posts[i].id)),
                            onArchive: () => _toggleArchive(posts[i]),
                            onReport: () => _report(posts[i]),
                          );
                          final promo = !_websitePromoDismissed &&
                              !state.filtered &&
                              i == (_trending ? 0 : 1);
                          return KeyedSubtree(
                            key: ValueKey(posts[i].id),
                            child: promo
                                ? Column(children: [
                                    card,
                                    _WebsitePromoCard(
                                      trending: _trending,
                                      onDismiss: () => setState(
                                          () => _websitePromoDismissed = true),
                                    ),
                                  ])
                                : card,
                          );
                        },
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverToBoxAdapter(
                        child: posts.isNotEmpty && !loading
                            ? _FeedFooter(
                                loadingMore: state.loadingMore,
                                hasMore: state.hasMore,
                                offline: state.offline,
                                onLoadMore: () => context
                                    .read<FeedBloc>()
                                    .add(const FeedMoreRequested()),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.offline,
    required this.onLoadMore,
  });
  final bool loadingMore;
  final bool hasMore;
  final bool offline;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (offline) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      child: Center(
        child: loadingMore
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : hasMore
                ? TextButton(
                    onPressed: TapGuard.wrap(onLoadMore),
                    child: const Text('Load more posts'))
                : const Text('You’re all caught up ✨',
                    style: TextStyle(fontSize: 12.5, color: _muted)),
      ),
    );
  }
}

/// Keeps the Global/Company switch visible while the hero and posts scroll.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader({required this.child});
  final Widget child;

  static const double _extent = 62;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        color: const Color(0xFFF8F7FC),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        alignment: Alignment.center,
        child: child,
      );

  @override
  bool shouldRebuild(_PinnedHeader oldDelegate) => oldDelegate.child != child;
}

class _CommunityHero extends StatelessWidget {
  const _CommunityHero({
    required this.scope,
    required this.trending,
    required this.user,
  });
  final CommunityScope scope;
  final bool trending;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final global = scope == CommunityScope.global;
    final companyName = user?.company?.name ?? 'Your company';
    if (trending) {
      return PageHero(
        tone: HeroTone.sunset,
        icon: Icons.local_fire_department_rounded,
        overline: global ? 'Across Office Gossip' : companyName,
        title: 'Trending conversations',
        subtitle: global
            ? 'What people everywhere are reacting to right now.'
            : 'What your coworkers are talking about right now.',
      );
    }
    return global
        ? const PageHero(
            tone: HeroTone.violet,
            icon: Icons.public_rounded,
            overline: 'Global community',
            title: 'One community,\nmany voices.',
            subtitle: 'Meet people and ideas from across Office Gossip.',
          )
        : PageHero(
            tone: HeroTone.ocean,
            icon: Icons.business_rounded,
            overline: companyName,
            title: 'Your work,\nout loud.',
            subtitle: 'A little more connected, one conversation at a time.',
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Expanded(
            child: _ScopeOption(
              icon: Icons.public_rounded,
              label: 'Global',
              selected: scope == CommunityScope.global,
              onTap: TapGuard.wrap(() => onSelected(CommunityScope.global)),
            ),
          ),
          Expanded(
            child: _ScopeOption(
              icon: companyLocked
                  ? Icons.lock_outline_rounded
                  : Icons.business_rounded,
              label: companyName ?? 'Company',
              selected: scope == CommunityScope.company,
              onTap: TapGuard.wrap(() => onSelected(CommunityScope.company)),
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
          onTap: TapGuard.wrap(onTap),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? Colors.white : _muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : _muted)),
              ),
            ]),
          ),
        ),
      );
}

class _StartPostBar extends StatelessWidget {
  const _StartPostBar({
    required this.name,
    required this.busy,
    required this.onTap,
  });
  final String name;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: TapGuard.wrap(busy ? null : onTap),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              InitialsAvatar(name: name),
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

class _FeedSearchField extends StatelessWidget {
  const _FeedSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onChanged,
        maxLength: 80,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Search posts',
          hintStyle: const TextStyle(color: _muted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: _muted),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: onClear,
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: _muted)),
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.4)),
        ),
      );
}

class _TopicChips extends StatelessWidget {
  const _TopicChips({
    required this.topics,
    required this.selected,
    required this.onSelected,
  });
  final List<Topic> topics;
  final String? selected;
  final ValueChanged<String?> onSelected;

  Widget _chip(String label, bool active, VoidCallback onTap, {int? count}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? _accent : Colors.white,
          shape: StadiumBorder(
              side: BorderSide(color: active ? _accent : _border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : _ink)),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Text('$count',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? const Color(0xFFE3DCFF) : _muted)),
                ],
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _chip('All', selected == null, () => onSelected(null)),
            for (final topic in topics)
              _chip('#${topic.tag}', selected == topic.tag,
                  () => onSelected(selected == topic.tag ? null : topic.tag),
                  count: topic.posts),
          ],
        ),
      );
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.tag,
    required this.query,
    required this.onClear,
    this.onCompose,
  });
  final String? tag;
  final String query;
  final VoidCallback onClear;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: Color(0xFFF0EDFF), shape: BoxShape.circle),
            child: Icon(
                query.isEmpty ? Icons.tag_rounded : Icons.search_off_rounded,
                color: _accent),
          ),
          const SizedBox(height: 12),
          Text(
              query.isNotEmpty
                  ? 'No posts match “$query”'
                  : 'No posts tagged #$tag yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(
              query.isNotEmpty
                  ? 'Try different words${tag != null ? ' or clear the topic' : ''}.'
                  : 'Be the first to start the #$tag conversation.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onCompose != null)
                FilledButton(
                  onPressed: TapGuard.wrap(onCompose),
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  child: Text('Post with #$tag'),
                ),
              OutlinedButton(
                  onPressed: onClear, child: const Text('Clear search')),
            ],
          ),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.onRefresh,
    this.onClear,
  });
  final String title;
  final int? count;
  final VoidCallback onRefresh;

  /// Shown while a search or topic filter is active.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Row(children: [
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
        ),
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
        if (onClear != null)
          TextButton(onPressed: onClear, child: const Text('Clear'))
        else
          IconButton(
              onPressed: TapGuard.wrap(onRefresh),
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, color: _muted)),
      ]);
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.showCompany,
    required this.onReact,
    this.onTag,
    required this.onComment,
    required this.onMore,
    required this.onDeleted,
    required this.onConfirmDelete,
    required this.onArchive,
    required this.onReport,
    required this.onSave,
    required this.onVote,
    this.rank,
    this.topHeat = 0,
  });
  final CommunityPost post;
  final VoidCallback onSave;
  final ValueChanged<String> onVote;
  final bool showCompany;

  /// Set on Trending, where cards get a warmer, ranked look.
  final int? rank;

  /// The leading post's interactions, the 100% mark of the heat bar.
  final int topHeat;
  final ValueChanged<PostReaction?> onReact;

  /// Tapping a #hashtag in the body; null leaves tags highlighted only.
  final ValueChanged<String>? onTag;
  final VoidCallback onComment;
  final VoidCallback onMore;
  final VoidCallback onDeleted;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onArchive;
  final VoidCallback onReport;

  /// A half swipe reveals actions. Owners: right = archive, left = delete.
  /// Everyone else: left = report.
  @override
  Widget build(BuildContext context) {
    final owner = post.isOwner;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Slidable(
          key: ValueKey('slide-${post.id}'),
          groupTag: 'feed',
          startActionPane: owner
              ? ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: .26,
                  children: [
                    _SwipeAction(
                      color: _accent,
                      icon: post.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      label: post.isArchived ? 'Unarchive' : 'Archive',
                      onPressed: TapGuard.wrap(onArchive),
                    ),
                  ],
                )
              : null,
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: .26,
            children: [
              owner
                  ? _SwipeAction(
                      color: const Color(0xFFE5484D),
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      onPressed: TapGuard.wrap(() async {
                        if (await onConfirmDelete()) onDeleted();
                      }),
                    )
                  : _SwipeAction(
                      color: const Color(0xFFE0753F),
                      icon: Icons.flag_outlined,
                      label: 'Report',
                      onPressed: TapGuard.wrap(onReport),
                    ),
            ],
          ),
          child: _buildCard(context),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final meta = [
      if (!post.anonymous && post.role.isNotEmpty) post.role,
      if (showCompany && post.company.isNotEmpty) post.company,
      post.time,
    ].join(' · ');
    final podium = rank != null && rank! <= 3;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: podium
                ? const Color(0xFFF6CDB0)
                : rank != null
                    ? const Color(0xFFF2E4DA)
                    : _border),
      ),
      child: Ink(
        decoration: rank == null
            ? null
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    podium ? const Color(0xFFFFF3EA) : const Color(0xFFFFF9F5),
                    Colors.white,
                  ],
                  stops: const [0, .45],
                ),
              ),
        child: InkWell(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onMore();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rank != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 12),
                  child: _TrendBanner(
                      rank: rank!,
                      heat: post.likes + post.comments,
                      topHeat: topHeat),
                ),
              Row(children: [
                post.anonymous
                    ? const _AnonymousAvatar()
                    : InitialsAvatar(name: post.person),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(
                                post.anonymous ? 'Anonymous' : post.person,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: _ink)),
                          ),
                          if (post.anonymous) ...[
                            const SizedBox(width: 6),
                            const _Tag(label: 'Anonymous'),
                          ],
                          if (post.isAdmin) ...[
                            const SizedBox(width: 6),
                            const _AdminTag(),
                          ],
                          if (post.isArchived) ...[
                            const SizedBox(width: 6),
                            const _Tag(label: 'Archived'),
                          ],
                          if (post.isPending) ...[
                            const SizedBox(width: 6),
                            const _Tag(label: 'Waiting for approval'),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 11, color: _muted)),
                      ]),
                ),
                IconButton(
                    onPressed: TapGuard.wrap(onMore),
                    tooltip: 'Post options',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_vert_rounded, color: _muted)),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 8, 8),
                child: HashtagText(post.body,
                    onTag: onTag,
                    style: const TextStyle(
                        fontSize: 14.5, height: 1.45, color: _ink)),
              ),
              if (post.poll != null)
                PostPollView(
                  poll: post.poll!,
                  showResults: post.isOwner,
                  onVote: post.isPending ? null : onVote,
                ),
              Row(children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: PostReactionButton(
                          post: post,
                          onReact: post.isPending ? null : onReact),
                    ),
                  ),
                ),
                if (AppConstants.commentsEnabled)
                  _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${post.comments}',
                    color: _muted,
                    onTap: post.isPending ? null : TapGuard.wrap(onComment),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: post.isPending ? null : TapGuard.wrap(onSave),
                  tooltip: post.saved ? 'Remove from saved' : 'Save post',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                      post.saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20,
                      color: post.saved ? _accent : _muted),
                ),
                Builder(
                  builder: (anchor) => _ActionButton(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    color: _muted,
                    onTap: TapGuard.wrap(() => _sharePost(anchor, post)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Rank medal, heat label and a bar relative to the #1 post.
class _TrendBanner extends StatelessWidget {
  const _TrendBanner({
    required this.rank,
    required this.heat,
    required this.topHeat,
  });
  final int rank;
  final int heat;
  final int topHeat;

  static const _flame = Color(0xFFE0753F);
  static const _medals = [
    [Color(0xFFFFB547), Color(0xFFF07B2B)],
    [Color(0xFFB9B6C9), Color(0xFF8E8AA3)],
    [Color(0xFFE2A27A), Color(0xFFB8693F)],
  ];

  @override
  Widget build(BuildContext context) {
    final share = topHeat <= 0 ? 1.0 : (heat / topHeat).clamp(.06, 1.0);
    final label = rank == 1
        ? 'Hottest right now'
        : share >= .6
            ? 'Heating up'
            : 'Rising';
    final medal = rank <= 3 ? _medals[rank - 1] : null;
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: medal == null ? null : LinearGradient(colors: medal),
          color: medal == null ? const Color(0xFFF6EEE8) : null,
          borderRadius: BorderRadius.circular(11),
          boxShadow: medal == null
              ? null
              : [
                  BoxShadow(
                      color: medal.last.withValues(alpha: .35),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: Text('$rank',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: medal == null ? _flame : Colors.white)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (rank <= 3) ...[
              const Icon(Icons.local_fire_department_rounded,
                  size: 15, color: _flame),
              const SizedBox(width: 3),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _flame)),
            ),
            Text('$heat ${heat == 1 ? 'interaction' : 'interactions'}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              color: _flame,
              backgroundColor: const Color(0xFFF6E7DD),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });
  final Announcement announcement;
  final VoidCallback onDismiss;

  String get _audienceLabel => switch (announcement.audience) {
        AnnouncementAudience.everyone => 'For everyone',
        AnnouncementAudience.user => 'Just for you',
        AnnouncementAudience.company => 'For your company',
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F0FF), Color(0xFFFFF4EC)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2DBFF)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: HeroTone.violet.colors),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.campaign_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const _AdminTag(),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('$_audienceLabel · ${announcement.time}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _muted)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(announcement.message,
                  style:
                      const TextStyle(fontSize: 14, height: 1.45, color: _ink)),
            ]),
          ),
          IconButton(
            onPressed: TapGuard.wrap(onDismiss),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
          ),
        ]),
      );
}

class _AdminTag extends StatelessWidget {
  const _AdminTag();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: HeroTone.violet.colors),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_rounded, size: 11, color: Colors.white),
          SizedBox(width: 3),
          Text('Admin',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      );
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CustomSlidableAction(
        onPressed: (_) {
          HapticFeedback.selectionClick();
          onPressed();
        },
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      );
}

Future<void> _sharePost(BuildContext anchor, CommunityPost post) async {
  final author = post.anonymous ? 'Anonymous' : post.person;
  final text =
      '“${post.body}”\n\n— $author on Office Gossip\n${AppLinks.webDomain}';
  final box = anchor.findRenderObject() as RenderBox?;
  final messenger = ScaffoldMessenger.of(anchor);
  try {
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: 'A post on Office Gossip',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  } on Object {
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('Post copied — paste it anywhere.')));
  }
}

/// In-feed card linking to the Office Gossip website: open it in-app or share it.
class _WebsitePromoCard extends StatelessWidget {
  const _WebsitePromoCard({required this.trending, required this.onDismiss});
  final bool trending;
  final VoidCallback onDismiss;

  Future<void> _share(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final messenger = ScaffoldMessenger.of(anchor);
    const text =
        'Join me on Office Gossip — a kinder corner of the internet for coworkers. ${AppLinks.webDomain}';
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: 'Office Gossip',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } on Object {
      await Clipboard.setData(const ClipboardData(text: text));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Website link copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = (trending ? HeroTone.sunset : HeroTone.violet).colors;
    final host = Uri.parse(AppLinks.webDomain).host;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
        boxShadow: [
          BoxShadow(
              color: colors.first.withValues(alpha: .28),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(children: [
        Positioned(right: -40, top: -50, child: _glow(150)),
        Positioned(left: 90, bottom: -60, child: _glow(100)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    trending
                        ? '🔥 TRENDING ON THE WEB'
                        : '💻 OFFICE GOSSIP ON THE WEB',
                    style: const TextStyle(
                        fontSize: 9.5,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const Spacer(),
              IconButton(
                onPressed: TapGuard.wrap(onDismiss),
                tooltip: 'Hide',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: Colors.white70),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(13),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .3)),
                  ),
                  child: const Icon(Icons.language_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            trending
                                ? 'Follow the hottest threads on a bigger screen'
                                : 'Take Office Gossip to your desktop',
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(height: 3),
                        Text(
                            trending
                                ? 'Rankings, heat and every reaction, live in your browser.'
                                : 'Same community, same account — sign in from any browser.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.white.withValues(alpha: .85))),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: TapGuard.wrap(() => openWebpage(
                        context, WebpageType.company,
                        domain: AppLinks.webDomain, title: 'Office Gossip')),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colors.first,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11))),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (anchor) => OutlinedButton.icon(
                    onPressed: TapGuard.wrap(() => _share(anchor)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: .6)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11))),
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('Share',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  static Widget _glow(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white.withValues(alpha: .08)),
      );
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: TapGuard.wrap(onTap),
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
          borderRadius: BorderRadius.circular(14),
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
  const _EmptyFeed(
      {required this.scope, required this.onCompose, this.trending = false});
  final CommunityScope scope;
  final bool trending;
  final void Function({String starter})? onCompose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border)),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFF0EDFF), shape: BoxShape.circle),
            child: Icon(
                trending
                    ? Icons.local_fire_department_rounded
                    : Icons.auto_awesome_rounded,
                color: _accent),
          ),
          const SizedBox(height: 14),
          Text(trending ? 'NOTHING HOT YET' : 'A FRESH START',
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: _accent)),
          const SizedBox(height: 6),
          Text(
              trending
                  ? 'Nothing is trending yet'
                  : scope == CommunityScope.global
                      ? 'The global community is quiet'
                      : 'Your community starts here',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(
              trending
                  ? 'Posts from the last 3 days start trending once they collect $_minTrendInteractions or more likes and comments.'
                  : 'Celebrate a small win, ask a question, or share something that made you smile.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
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
                      onPressed:
                          TapGuard.wrap(() => onCompose!(starter: starter)),
                    ),
                ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: TapGuard.wrap(() => onCompose!()),
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
            borderRadius: BorderRadius.circular(14),
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
          OutlinedButton(
              onPressed: TapGuard.wrap(onRetry),
              child: const Text('Try again')),
        ]),
      );
}

/// Owns its controller so it is disposed only after the sheet has fully closed.
class _ComposePostSheet extends StatefulWidget {
  const _ComposePostSheet(
      {required this.companyName, required this.scope, required this.starter});
  final String? companyName;
  final CommunityScope scope;
  final String starter;

  @override
  State<_ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<_ComposePostSheet> {
  late final _body = TextEditingController(text: widget.starter);
  bool _anonymous = true;
  bool _submitted = false;

  /// Null while the post has no poll.
  List<TextEditingController>? _pollOptions;

  static const _maxLength = 500;
  static const _pollMaxOptions = 4;
  static const _pollOptionMaxLength = 80;

  @override
  void dispose() {
    _body.dispose();
    for (final option in _pollOptions ?? const <TextEditingController>[]) {
      option.dispose();
    }
    super.dispose();
  }

  List<String>? get _poll =>
      _pollOptions?.map((option) => option.text.trim()).toList();

  bool get _pollReady {
    final poll = _poll;
    if (poll == null) return true;
    return poll.length >= 2 &&
        poll.every((option) => option.isNotEmpty) &&
        poll.map((option) => option.toLowerCase()).toSet().length ==
            poll.length;
  }

  void _addPoll() => setState(() => _pollOptions = [
        TextEditingController(),
        TextEditingController(),
      ]);

  void _removePoll() {
    final options = _pollOptions;
    setState(() => _pollOptions = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final option in options ?? const <TextEditingController>[]) {
        option.dispose();
      }
    });
  }

  void _removeOption(int index) {
    final removed = _pollOptions![index];
    setState(() => _pollOptions!.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Widget _pollEditor() {
    final options = _pollOptions!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
      decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.poll_outlined, size: 18, color: _accent),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Poll options',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          TextButton(
              onPressed: TapGuard.wrap(_removePoll),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE5484D)),
              child: const Text('Remove')),
        ]),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: options[i],
                  maxLength: _pollOptionMaxLength,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Option ${i + 1}',
                    isDense: true,
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _border)),
                  ),
                ),
              ),
              if (options.length > 2)
                IconButton(
                  onPressed: TapGuard.wrap(() => _removeOption(i)),
                  tooltip: 'Remove option',
                  visualDensity: VisualDensity.compact,
                  icon:
                      const Icon(Icons.close_rounded, size: 18, color: _muted),
                ),
            ]),
          ),
        if (options.length < _pollMaxOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: TapGuard.wrap(() =>
                  setState(() => _pollOptions!.add(TextEditingController()))),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add option'),
            ),
          ),
        if (!_pollReady &&
            options.every((option) => option.text.trim().isNotEmpty))
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text('Each option must be different.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFFE5484D))),
          ),
      ]),
    );
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
            final global = widget.scope == CommunityScope.global;
            final company = widget.companyName ?? 'your company';
            return SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    (global
                            ? 'Global community'
                            : widget.companyName ?? 'Your company')
                        .toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: _accent)),
                const SizedBox(height: 4),
                const Text('Start a conversation',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                const SizedBox(height: 4),
                Text(
                    global
                        ? 'Visible to everyone in the Global community and shared with $company.'
                        : 'Shared with $company coworkers and also visible in the Global community.',
                    style: const TextStyle(fontSize: 12, color: _muted)),
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
                              onPressed:
                                  TapGuard.wrap(() => _useStarter(starter)),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Text('${value.text.length}/$_maxLength',
                      style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
                const SizedBox(height: 8),
                if (_pollOptions == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: TapGuard.wrap(_addPoll),
                      icon: const Icon(Icons.poll_outlined, size: 18),
                      label: const Text('Add a poll'),
                      style: TextButton.styleFrom(foregroundColor: _accent),
                    ),
                  )
                else
                  _pollEditor(),
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
                  onPressed:
                      TapGuard.wrap(text.isEmpty || _submitted || !_pollReady
                          ? null
                          : () {
                              setState(() => _submitted = true);
                              Navigator.pop(context, (text, _anonymous, _poll));
                            }),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Share post'),
                ),
              ],
            ));
          },
        ),
      );
}
