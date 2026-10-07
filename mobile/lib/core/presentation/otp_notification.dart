import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// iOS-style banner for when the sign-up code email couldn't be sent and the
/// API returned the code instead. Tapping it calls [onUse]; it hides itself
/// when the code expires. Call [OtpNotification.dismiss] to remove it early.
abstract final class OtpNotification {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String code,
    required Duration expiresIn,
    required VoidCallback onUse,
  }) {
    dismiss();
    final expiresAt = DateTime.now().add(expiresIn);
    _entry = OverlayEntry(
      builder: (_) => _OtpBanner(
        code: code,
        expiresAt: expiresAt,
        onUse: () {
          onUse();
          dismiss();
        },
        onClose: dismiss,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _OtpBanner extends StatefulWidget {
  const _OtpBanner({
    required this.code,
    required this.expiresAt,
    required this.onUse,
    required this.onClose,
  });
  final String code;
  final DateTime expiresAt;
  final VoidCallback onUse;
  final VoidCallback onClose;

  @override
  State<_OtpBanner> createState() => _OtpBannerState();
}

class _OtpBannerState extends State<_OtpBanner>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF5B45D1);
  static const _muted = Color(0xFF7B7888);

  late final AnimationController _slide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420))
    ..forward();
  late final Timer _ticker;
  Duration _left = Duration.zero;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final left = widget.expiresAt.difference(DateTime.now());
    if (left <= Duration.zero) {
      widget.onClose();
      return;
    }
    if (mounted) setState(() => _left = left);
  }

  Future<void> _close() async {
    await _slide.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _ticker.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final ink = dark ? const Color(0xFFF4F3F8) : const Color(0xFF111111);
    final seconds = _left.inSeconds;
    final countdown =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 10,
      right: 10,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _slide,
                curve: Curves.easeOutBack,
                reverseCurve: Curves.easeIn)),
        child: GestureDetector(
          onTap: widget.onUse,
          onVerticalDragUpdate: (details) => setState(() =>
              _dragOffset = (_dragOffset + details.delta.dy).clamp(-120, 0)),
          onVerticalDragEnd: (details) {
            if (_dragOffset < -30 || (details.primaryVelocity ?? 0) < -300) {
              _close();
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                liveRegion: true,
                button: true,
                label:
                    'Your sign-up code is ${widget.code.split('').join(' ')}. '
                    'Tap to fill it in.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(13, 12, 6, 12),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xE62C2C32)
                            : const Color(0xE6F6F5F8),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                            width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF8A72F0), _accent],
                              ),
                            ),
                            child: const Icon(Icons.visibility_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Expanded(
                                    child: Text('OFFICE GOSSIP',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                            color: _muted)),
                                  ),
                                  Text('now',
                                      style: TextStyle(
                                          fontSize: 11.5, color: _muted)),
                                ]),
                                const SizedBox(height: 2),
                                Text('Your sign-up code',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ink)),
                                const SizedBox(height: 1),
                                Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                        text: widget.code,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                            color: dark
                                                ? const Color(0xFFB3A5FF)
                                                : _accent)),
                                    TextSpan(
                                        text:
                                            ' is your verification code. Expires in $countdown.'),
                                  ]),
                                  style: TextStyle(
                                      fontSize: 13.5, height: 1.35, color: ink),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                    'We couldn’t email it right now · Tap to fill it in',
                                    style: TextStyle(
                                        fontSize: 11.5, color: _muted)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _close,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Dismiss',
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
