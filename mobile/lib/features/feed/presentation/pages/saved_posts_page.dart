import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/tap_guard.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../domain/entities/community_post.dart';
import '../cubit/saved_posts_cubit.dart';
import '../widgets/post_poll.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);

/// Profile › Saved posts: the member's bookmarks, newest save first.
class SavedPostsPage extends StatelessWidget {
  const SavedPostsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(builder: (_) => const SavedPostsPage()));

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => sl<SavedPostsCubit>()..load(),
        child: const _SavedPostsView(),
      );
}

class _SavedPostsView extends StatelessWidget {
  const _SavedPostsView();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF7F6FA),
        appBar: AppBar(
          title: const Text('Saved posts',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: BlocConsumer<SavedPostsCubit, SavedPostsState>(
          listenWhen: (previous, current) =>
              previous.messageId != current.messageId &&
              current.message != null,
          listener: (context, state) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                content: Text(state.message!),
                behavior: SnackBarBehavior.floating)),
          builder: (context, state) {
            final cubit = context.read<SavedPostsCubit>();
            return switch (state.status) {
              SavedPostsStatus.loading =>
                const Center(child: CircularProgressIndicator()),
              SavedPostsStatus.failure => _Message(
                  icon: Icons.cloud_off_rounded,
                  title: 'Saved posts unavailable',
                  detail:
                      'We couldn’t load your saved posts. Check your connection and try again.',
                  actionLabel: 'Try again',
                  onAction: cubit.load,
                ),
              SavedPostsStatus.ready when state.posts.isEmpty => const _Message(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Save posts to read later',
                  detail:
                      'Tap the bookmark on any post and it will show up here.',
                ),
              SavedPostsStatus.ready => RefreshIndicator(
                  onRefresh: cubit.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: state.posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _SavedPostCard(
                      post: state.posts[i],
                      onUnsave: () => cubit.unsave(state.posts[i]),
                      onVote: (optionId) =>
                          cubit.vote(state.posts[i], optionId),
                    ),
                  ),
                ),
            };
          },
        ),
      );
}

class _SavedPostCard extends StatelessWidget {
  const _SavedPostCard(
      {required this.post, required this.onUnsave, required this.onVote});
  final CommunityPost post;
  final VoidCallback onUnsave;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (!post.anonymous && post.role.isNotEmpty) post.role,
      if (post.company.isNotEmpty) post.company,
      post.time,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          post.anonymous
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: Color(0xFF2A2838), shape: BoxShape.circle),
                  child: const Icon(Icons.visibility_off_rounded,
                      size: 18, color: Colors.white),
                )
              : InitialsAvatar(name: post.person),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post.anonymous ? 'Anonymous' : post.person,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 2),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ]),
          ),
          IconButton(
            onPressed: TapGuard.wrap(onUnsave),
            tooltip: 'Remove from saved',
            icon: const Icon(Icons.bookmark_rounded, color: _accent),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 10, 8),
          child: Text(post.body,
              style:
                  const TextStyle(fontSize: 14.5, height: 1.45, color: _ink)),
        ),
        if (post.poll != null)
          PostPollView(
              poll: post.poll!, showResults: post.isOwner, onVote: onVote),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: const Color(0xFFF0EDFF),
                  borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: _accent, size: 28),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _muted)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: TapGuard.wrap(onAction),
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: Text(actionLabel!),
              ),
            ],
          ]),
        ),
      );
}
