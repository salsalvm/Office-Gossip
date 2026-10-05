import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/office_gossip_mark.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  static const _violet = Color(0xFF7357E8);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const OfficeGossipMark(size: 96),
              const SizedBox(height: 22),
              const Text('Office Gossip',
                  style: TextStyle(
                      fontSize: 27,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111))),
              const SizedBox(height: 8),
              const Text('A kinder corner of the internet',
                  style: TextStyle(fontSize: 14, color: Color(0xFF555555))),
              const SizedBox(height: 34),
              const SizedBox(
                  width: 112,
                  child: LinearProgressIndicator(
                      minHeight: 4,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      color: _violet,
                      backgroundColor: Color(0x337357E8))),
            ]),
          ),
        ),
      );
}
