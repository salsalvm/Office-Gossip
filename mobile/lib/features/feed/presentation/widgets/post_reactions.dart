import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_reaction.dart';

const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _accent = Color(0xFF7357E8);

Color _reactionColor(PostReaction reaction) => switch (reaction) {
      PostReaction.love => const Color(0xFFE5484D),
      PostReaction.laugh || PostReaction.wow => const Color(0xFFC88A06),
      PostReaction.fire => const Color(0xFFE0602B),
      PostReaction.clap => _accent,
    };

/// Tap: ❤️ or remove your reaction. Long-press (or the small ＋): pick an emoji.
class PostReactionButton extends StatelessWidget {
  const PostReactionButton({
    super.key,
    required this.post,
    required this.onReact,
  });

  final CommunityPost post;

  /// Called with the chosen reaction, or null to remove the member's reaction.
  final ValueChanged<PostReaction?>? onReact;

  Future<void> _pick(BuildContext context) async {
    final onReact = this.onReact;
    if (onReact == null) return;
    HapticFeedback.selectionClick();
    final picked = await showReactionPicker(context, current: post.myReaction);
    if (picked != null) onReact(picked == post.myReaction ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final mine = post.myReaction;
    final enabled = onReact != null;
    final color = mine == null ? _muted : _reactionColor(mine);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: mine == null
            ? 'React with love. Long press for more reactions'
            : 'You reacted ${mine.label}. Tap to remove',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onReact!(mine == null ? PostReaction.love : null);
                }
              : null,
          onLongPress: enabled ? () => _pick(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: mine == null
                    ? Icon(Icons.favorite_border_rounded,
                        key: const ValueKey('none'), size: 20, color: color)
                    : Text(mine.emoji,
                        key: ValueKey(mine),
                        style: const TextStyle(fontSize: 18, height: 1.1)),
              ),
              const SizedBox(width: 6),
              Text(mine?.label ?? 'React',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ]),
          ),
        ),
      ),
      if (enabled)
        IconButton(
          onPressed: () => _pick(context),
          tooltip: 'More reactions',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.add_reaction_outlined, size: 18, color: _muted),
        ),
      if (post.likes > 0) ...[
        const SizedBox(width: 2),
        ReactionSummary(post: post),
      ],
    ]);
  }
}

/// Up to three most-used emoji, overlapped, followed by the total.
class ReactionSummary extends StatelessWidget {
  const ReactionSummary({super.key, required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final top = post.topReactions;
    return Semantics(
      label: '${post.likes} ${post.likes == 1 ? 'reaction' : 'reactions'}',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: top.isEmpty ? 0 : 20.0 + (top.length - 1) * 14,
          height: 22,
          child: Stack(children: [
            for (var i = 0; i < top.length; i++)
              Positioned(
                left: i * 14.0,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A2A2540), blurRadius: 3),
                    ],
                  ),
                  child: Text(top[i].emoji,
                      style: const TextStyle(fontSize: 11, height: 1.1)),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 5),
        Text('${post.likes}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
      ]),
    );
  }
}

/// Floating emoji bar anchored above [context]'s widget. Resolves to the
/// tapped reaction, or null when dismissed.
Future<PostReaction?> showReactionPicker(BuildContext context,
    {PostReaction? current}) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final origin = box != null && overlay != null
      ? box.localToGlobal(Offset.zero, ancestor: overlay)
      : Offset.zero;
  return showGeneralDialog<PostReaction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close reactions',
    barrierColor: Colors.black.withValues(alpha: .04),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      final size = MediaQuery.sizeOf(dialogContext);
      const width = 5 * 48.0 + 16;
      final left = origin.dx.clamp(12.0, size.width - width - 12);
      final top = (origin.dy - 64).clamp(
          MediaQuery.paddingOf(dialogContext).top + 8, size.height - 80);
      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          child: _ReactionBar(current: current),
        ),
      ]);
    },
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .9, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        alignment: Alignment.bottomLeft,
        child: child,
      ),
    ),
  );
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({this.current});
  final PostReaction? current;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 10,
        shadowColor: const Color(0x402A2540),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final reaction in PostReaction.values)
              Tooltip(
                message: reaction.label,
                child: InkResponse(
                  radius: 26,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop(reaction);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reaction == current
                          ? const Color(0xFFF0EDFF)
                          : Colors.transparent,
                    ),
                    child: Text(reaction.emoji,
                        semanticsLabel: reaction.label,
                        style: const TextStyle(
                            fontSize: 28, height: 1.1, color: _ink)),
                  ),
                ),
              ),
          ]),
        ),
      );
}
