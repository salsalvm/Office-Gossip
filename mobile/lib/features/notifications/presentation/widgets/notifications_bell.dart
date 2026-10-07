import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/presentation/tap_guard.dart';

const _ink = Color(0xFF1F1D2B);
const _accent = Color(0xFF7357E8);
const _muted = Color(0xFF8D8A9B);
const _border = Color(0xFFECEAF2);

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.actorName,
    required this.postExcerpt,
    required this.time,
    required this.unread,
    this.comment,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'reaction',
        actorName: json['actorName'] as String? ?? 'Someone',
        postExcerpt: json['postExcerpt'] as String? ?? '',
        comment: json['comment'] as String?,
        time: json['time'] as String? ?? '',
        unread: json['unread'] as bool? ?? false,
      );

  final String id;

  /// `reaction`, `comment`, or `follow`.
  final String type;
  bool get isComment => type == 'comment';
  bool get isFollow => type == 'follow';
  final String actorName;
  final String postExcerpt;
  final String? comment;
  final String time;
  final bool unread;
}

/// App-bar bell: unread badge plus a sheet of likes and comments on the
/// member's posts.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  final _items = ValueNotifier<List<ActivityItem>?>(null);
  final _failed = ValueNotifier<bool>(false);
  int _unread = 0;
  StreamSubscription<RemoteMessage>? _pushes;

  Dio get _dio => sl<Dio>();

  @override
  void initState() {
    super.initState();
    _load();
    if (Firebase.apps.isNotEmpty) {
      _pushes = FirebaseMessaging.onMessage.listen(_onPush);
    }
  }

  @override
  void dispose() {
    _pushes?.cancel();
    _items.dispose();
    _failed.dispose();
    super.dispose();
  }

  void _onPush(RemoteMessage message) {
    _load();
    final note = message.notification;
    if (!mounted || note == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text([note.title, note.body]
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .join(': ')),
      ));
  }

  Future<void> _load() async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>(ApiEndpoints.notifications);
      final data = response.data ?? const {};
      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((item) => ActivityItem.fromJson(item as Map<String, dynamic>))
          .toList();
      _items.value = items;
      _failed.value = false;
      if (mounted) setState(() => _unread = data['unreadCount'] as int? ?? 0);
    } on Object {
      _failed.value = _items.value == null;
    }
  }

  Future<void> _open() async {
    final hadUnread = _unread > 0;
    _load();
    if (hadUnread) {
      setState(() => _unread = 0);
      unawaited(_dio
          .post<dynamic>(ApiEndpoints.notificationsRead)
          .then((_) {}, onError: (_) {}));
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) =>
          _ActivitySheet(items: _items, failed: _failed, onRetry: _load),
    );
    final items = _items.value;
    if (items != null) {
      _items.value = [
        for (final item in items)
          ActivityItem(
            id: item.id,
            type: item.type,
            actorName: item.actorName,
            postExcerpt: item.postExcerpt,
            comment: item.comment,
            time: item.time,
            unread: false,
          ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message:
            _unread > 0 ? 'Notifications ($_unread unread)' : 'Notifications',
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(side: BorderSide(color: _border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: TapGuard.wrap(_open),
            child: SizedBox.square(
              dimension: 42,
              child: Center(
                child: Badge(
                  isLabelVisible: _unread > 0,
                  label: Text(_unread > 9 ? '9+' : '$_unread'),
                  backgroundColor: const Color(0xFFE5484D),
                  child: const Icon(Icons.notifications_none_rounded,
                      size: 22, color: _ink),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ActivitySheet extends StatelessWidget {
  const _ActivitySheet({
    required this.items,
    required this.failed,
    required this.onRetry,
  });
  final ValueNotifier<List<ActivityItem>?> items;
  final ValueNotifier<bool> failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                      SizedBox(height: 2),
                      Text('Likes, comments, and new followers',
                          style: TextStyle(fontSize: 12, color: _muted)),
                    ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: _border),
          Flexible(
            child: ListenableBuilder(
              listenable: Listenable.merge([items, failed]),
              builder: (context, _) {
                final list = items.value;
                if (list == null && failed.value) {
                  return _SheetMessage(
                    icon: Icons.cloud_off_rounded,
                    title: 'Couldn’t load notifications',
                    body: 'Check your connection and try again.',
                    action: TextButton(
                        onPressed: TapGuard.wrap(onRetry), child: const Text('Try again')),
                  );
                }
                if (list == null) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (list.isEmpty) {
                  return const _SheetMessage(
                    icon: Icons.notifications_none_rounded,
                    title: 'No notifications yet',
                    body:
                        'When someone likes or comments on your posts, or follows you, you’ll see it here.',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                      8, 6, 8, 16 + MediaQuery.paddingOf(context).bottom),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) => _ActivityTile(item: list[i]),
                );
              },
            ),
          ),
        ]),
      );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
        decoration: BoxDecoration(
          color: item.unread ? const Color(0xFFF5F2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isFollow
                  ? const Color(0xFFE4F2E9)
                  : item.isComment
                      ? const Color(0xFFE9E4FF)
                      : const Color(0xFFFFE8EA),
            ),
            child: Icon(
              item.isFollow
                  ? Icons.person_add_alt_1_rounded
                  : item.isComment
                      ? Icons.chat_bubble_rounded
                      : Icons.favorite_rounded,
              size: 18,
              color: item.isFollow
                  ? const Color(0xFF2F8A57)
                  : item.isComment
                      ? const Color(0xFF5B45D1)
                      : const Color(0xFFE5484D),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: item.actorName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: item.isFollow
                          ? ' started following you'
                          : item.isComment
                              ? ' commented on your post'
                              : ' liked your post'),
                ]),
                style: const TextStyle(fontSize: 14, height: 1.35, color: _ink),
              ),
              if (item.comment != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF3F1F8),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(item.comment!,
                      style: const TextStyle(fontSize: 13, color: _ink)),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                  item.postExcerpt.isEmpty
                      ? item.time
                      : '“${item.postExcerpt}” · ${item.time}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
          if (item.unread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 8, top: 6),
              decoration:
                  const BoxDecoration(color: _accent, shape: BoxShape.circle),
            ),
        ]),
      );
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            28, 28, 28, 28 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Color(0xFFF0EDFF), shape: BoxShape.circle),
            child: Icon(icon, color: _accent),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _muted)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ]),
      );
}
