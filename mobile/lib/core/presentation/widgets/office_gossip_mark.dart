import 'package:flutter/material.dart';

class OfficeGossipMark extends StatelessWidget {
  const OfficeGossipMark({super.key, this.size = 42});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.only(top: size * .11, bottom: size * .09),
        decoration: BoxDecoration(
          color: const Color(0xFF7357E8),
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_rounded,
                color: Colors.white, size: size * .55),
            Text('OG',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * .19,
                    height: .95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4)),
          ],
        ),
      );
}
