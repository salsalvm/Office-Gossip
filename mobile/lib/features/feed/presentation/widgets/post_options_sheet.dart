import 'package:flutter/material.dart';

import '../../domain/entities/community_post.dart';
import '../../../../core/presentation/tap_guard.dart';

const _accent = Color(0xFF7357E8);
const _ink = Color(0xFF1F1D2B);
const _muted = Color(0xFF7B7888);
const _danger = Color(0xFFE5484D);

/// Entries in a post's three-dot menu. Add a value here, then handle it in
/// the dashboard's `_onPostOption` switch.
enum PostOption {
  copy('Copy text', Icons.copy_rounded),
  edit('Edit post', Icons.edit_outlined),
  archive('Archive post', Icons.archive_outlined),
  delete('Delete post', Icons.delete_outline_rounded, destructive: true),
  report('Report post', Icons.flag_outlined, destructive: true);

  const PostOption(this.label, this.icon, {this.destructive = false});
  final String label;
  final IconData icon;
  final bool destructive;

  bool isAvailableFor(CommunityPost post) => switch (this) {
        PostOption.copy => true,
        PostOption.edit ||
        PostOption.archive ||
        PostOption.delete =>
          post.isOwner,
        PostOption.report => true,
      };

  String labelFor(CommunityPost post) =>
      this == PostOption.archive && post.isArchived ? 'Unarchive post' : label;

  IconData iconFor(CommunityPost post) =>
      this == PostOption.archive && post.isArchived
          ? Icons.unarchive_outlined
          : icon;
}

const reportReasons = [
  'Harassment or bullying',
  'Hate speech',
  'Spam or misleading',
  'Shares private information',
  'Something else',
];

Future<PostOption?> showPostOptionsSheet(
    BuildContext context, CommunityPost post) {
  final options =
      PostOption.values.where((option) => option.isAvailableFor(post));
  return showModalBottomSheet<PostOption>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final option in options)
          ListTile(
            leading: Icon(option.iconFor(post),
                color: option.destructive ? _danger : _ink),
            title: Text(option.labelFor(post),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: option.destructive ? _danger : _ink)),
            onTap: TapGuard.wrap(() => Navigator.pop(sheetContext, option)),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<String?> showReportReasonSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Why are you reporting this post?',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Reports are anonymous and reviewed by our team.',
                  style: TextStyle(fontSize: 12, color: _muted)),
            ),
            for (final reason in reportReasons)
              ListTile(
                title: Text(reason),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: TapGuard.wrap(() => Navigator.pop(sheetContext, reason)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

Future<bool> confirmDeletePost(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
            'It will be removed from the feed for everyone. This can’t be undone.'),
        actions: [
          TextButton(
              onPressed: TapGuard.wrap(() => Navigator.pop(dialogContext, false)),
              child: const Text('Cancel')),
          TextButton(
              onPressed: TapGuard.wrap(() => Navigator.pop(dialogContext, true)),
              style: TextButton.styleFrom(foregroundColor: _danger),
              child: const Text('Delete')),
        ],
      ),
    ) ??
    false;

Future<String?> showEditPostSheet(BuildContext context, CommunityPost post) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _EditPostSheet(initial: post.body),
    );

/// Owns its controller so it is disposed only after the sheet has fully closed.
class _EditPostSheet extends StatefulWidget {
  const _EditPostSheet({required this.initial});
  final String initial;

  @override
  State<_EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<_EditPostSheet> {
  late final _body = TextEditingController(text: widget.initial);

  static const _maxLength = 500;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _body,
          builder: (context, value, _) {
            final text = value.text.trim();
            final unchanged = text == widget.initial.trim();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Edit post',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                const SizedBox(height: 14),
                TextField(
                  controller: _body,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8F7FC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: TapGuard.wrap(text.isEmpty || unchanged
                      ? null
                      : () => Navigator.pop(context, text)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: const Text('Save changes'),
                ),
              ],
            );
          },
        ),
      );
}
