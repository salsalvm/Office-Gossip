import 'package:flutter/material.dart';

enum HeroTone {
  violet([Color(0xFF5B45D1), Color(0xFF9479EE)]),
  ocean([Color(0xFF2F5FD0), Color(0xFF5FA2F5)]),
  sunset([Color(0xFFE2563B), Color(0xFFF5A04A)]),
  emerald([Color(0xFF0F8A6C), Color(0xFF3CC79A)]),
  midnight([Color(0xFF2A2547), Color(0xFF5A4BA8)]);

  const HeroTone(this.colors);
  final List<Color> colors;
}

/// Top-of-tab banner shared by Home, Trending, People and Profile.
///
/// Fixed [height] keeps every tab visually aligned; text is clamped to fit.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.tone,
    required this.overline,
    required this.title,
    required this.subtitle,
    this.icon,
    this.badge,
    this.action,
  });

  static const double height = 132;

  /// Shared padding for the pinned area above each tab's scrolling list.
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(16, 4, 16, 0);
  static const double gap = 10;

  final HeroTone tone;
  final String overline;
  final String title;
  final String subtitle;

  /// Shown in a frosted tile on the right; ignored when [badge] is given.
  final IconData? icon;
  final Widget? badge;

  /// Optional top-right control, e.g. an edit button.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tone.colors,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.colors.first.withValues(alpha: .28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(children: [
          Positioned(right: -40, top: -50, child: _glow(170)),
          Positioned(right: 60, bottom: -70, child: _glow(130)),
          Positioned(left: -30, bottom: -40, child: _glow(90)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        overline.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  badge ??
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: .25)),
                        ),
                        child: Icon(icon ?? Icons.auto_awesome_rounded,
                            color: Colors.white, size: 24),
                      ),
                  if (action != null) ...[const Spacer(), action!],
                ],
              ),
            ]),
          ),
        ]),
      );

  static Widget _glow(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .08),
        ),
      );
}
