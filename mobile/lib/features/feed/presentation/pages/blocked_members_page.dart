import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/presentation/tap_guard.dart';
import '../../../../core/presentation/widgets/initials_avatar.dart';
import '../../domain/entities/block_entry.dart';
import '../cubit/blocked_members_cubit.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFECEAF2);

/// Profile › Blocked & muted.
class BlockedMembersPage extends StatelessWidget {
  const BlockedMembersPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(builder: (_) => const BlockedMembersPage()));

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => sl<BlockedMembersCubit>()..load(),
        child: const _BlockedMembersView(),
      );
}

class _BlockedMembersView extends StatelessWidget {
  const _BlockedMembersView();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF7F6FA),
        appBar: AppBar(
          title: const Text('Blocked & muted',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: BlocConsumer<BlockedMembersCubit, BlockedMembersState>(
          listenWhen: (previous, current) =>
              previous.messageId != current.messageId &&
              current.message != null,
          listener: (context, state) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                content: Text(state.message!),
                behavior: SnackBarBehavior.floating)),
          builder: (context, state) {
            final cubit = context.read<BlockedMembersCubit>();
            if (state.status == BlockedMembersStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == BlockedMembersStatus.failure) {
              return _Message(
                icon: Icons.cloud_off_rounded,
                title: 'List unavailable',
                detail:
                    'We couldn’t load this list. Check your connection and try again.',
                action: FilledButton(
                  onPressed: TapGuard.wrap(cubit.load),
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  child: const Text('Try again'),
                ),
              );
            }
            if (state.entries.isEmpty) {
              return const _Message(
                icon: Icons.shield_outlined,
                title: 'You haven’t blocked or muted anyone',
                detail:
                    'Use the ⋮ menu on a post, or the menu on someone’s card in People.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 12),
                  child: Text(
                      'Blocked members can’t see your posts and you won’t see theirs. Muted members’ posts are hidden from your feeds.',
                      style: TextStyle(fontSize: 12.5, color: _muted)),
                ),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border)),
                  child: Column(children: [
                    for (var i = 0; i < state.entries.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 64, color: _border),
                      _BlockTile(
                        entry: state.entries[i],
                        busy: state.busyIds.contains(state.entries[i].id),
                        onRemove: () => cubit.remove(state.entries[i]),
                      ),
                    ],
                  ]),
                ),
              ],
            );
          },
        ),
      );
}

class _BlockTile extends StatelessWidget {
  const _BlockTile(
      {required this.entry, required this.busy, required this.onRemove});
  final BlockEntry entry;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final blocked = entry.kind == BlockKind.block;
    final detail = [
      blocked ? 'Blocked' : 'Muted',
      if (entry.anonymous) 'from an anonymous post',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: entry.anonymous
          ? Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: Color(0xFF2A2838), shape: BoxShape.circle),
              child: const Icon(Icons.visibility_off_rounded,
                  size: 18, color: Colors.white),
            )
          : InitialsAvatar(name: entry.label),
      title: Text(entry.label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      subtitle:
          Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : OutlinedButton(
              onPressed: TapGuard.wrap(onRemove),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: Color(0xFFDDD5FB)),
                  visualDensity: VisualDensity.compact),
              child: Text(blocked ? 'Unblock' : 'Unmute'),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon,
      required this.title,
      required this.detail,
      this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

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
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}
