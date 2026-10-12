import 'package:flutter/material.dart';

import '../../../../core/presentation/tap_guard.dart';
import '../../domain/entities/community_post.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _border = Color(0xFFE3DEF3);

/// Results show once the member has voted (or on their own post); tapping the
/// chosen option again takes the vote back.
class PostPollView extends StatelessWidget {
  const PostPollView({
    super.key,
    required this.poll,
    required this.showResults,
    required this.onVote,
  });

  final PostPoll poll;
  final bool showResults;

  /// Null disables voting (e.g. a post still waiting for approval).
  final ValueChanged<String>? onVote;

  @override
  Widget build(BuildContext context) {
    final reveal = showResults || poll.myVote != null;
    final votes =
        '${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _PollOptionTile(
              label: option.label,
              percent: poll.percentFor(option),
              mine: poll.myVote == option.id,
              reveal: reveal,
              onTap: onVote == null
                  ? null
                  : TapGuard.wrap(() => onVote!(option.id)),
            ),
          ),
        Text(
          poll.myVote != null
              ? '$votes · Tap your choice to undo'
              : reveal
                  ? votes
                  : '$votes · Vote to see results',
          style: const TextStyle(fontSize: 11.5, color: _muted),
        ),
      ]),
    );
  }
}

class _PollOptionTile extends StatelessWidget {
  const _PollOptionTile({
    required this.label,
    required this.percent,
    required this.mine,
    required this.reveal,
    required this.onTap,
  });

  final String label;
  final int percent;
  final bool mine;
  final bool reveal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: mine,
        label: reveal ? '$label, $percent percent' : label,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: mine ? const Color(0xFF9D8CF0) : _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              if (reveal)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent / 100,
                    child: ColoredBox(
                        color: mine
                            ? const Color(0xFFDCD4FB)
                            : const Color(0xFFEFEBFA)),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  if (mine) ...[
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: _accent),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _ink)),
                  ),
                  if (reveal)
                    Text('$percent%',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _accent)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
