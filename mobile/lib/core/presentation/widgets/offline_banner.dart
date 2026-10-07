import 'package:flutter/material.dart';

import '../../utils/cached.dart';
import '../tap_guard.dart';

/// Shown above cached content when the latest refresh failed.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.syncedAt, this.onRetry});

  final DateTime? syncedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF6DFB1)),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: Color(0xFFB7791F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: 'You’re offline',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
                    text: syncedAt == null
                        ? ' · showing saved content'
                        : ' · updated ${syncedAgo(syncedAt!)}'),
              ]),
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A5512)),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: TapGuard.wrap(onRetry),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7A5512),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      );
}
