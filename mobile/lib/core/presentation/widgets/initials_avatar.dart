import 'package:flutter/material.dart';

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Circle with a person's initials; colour is stable per [seed].
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 40,
  });

  final String name;
  final double size;

  static const _palette = [
    (Color(0xFFF0EDFF), Color(0xFF6650D8)),
    (Color(0xFFE6F4FF), Color(0xFF2F75C9)),
    (Color(0xFFFFF0E8), Color(0xFFD0632F)),
    (Color(0xFFE8F7EF), Color(0xFF2E8B5B)),
    (Color(0xFFFFEEF3), Color(0xFFC94374)),
  ];

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _palette[
        name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: size * .36,
        ),
      ),
    );
  }
}
