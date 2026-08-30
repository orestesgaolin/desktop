import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../slide_layouts.dart';

class Slide3 extends ImmersiveMediaSlideLayout {
  Slide3({super.key})
    : super(
        route: '/recognize-any-flutter-apps',
        title: 'Recognize any Flutter apps here?',
        label: 'The desktop test',
        aspectRatio: 2306 / 736,
        steps: 2,
        speakerNotes:
            'Start with the unmarked desktop, then press → to reveal the '
            'annotated version. Park the answer until the close.\n\n'
            '[Sources]\n'
            '- User-provided assets: assets/images/desktop.png and '
            'assets/images/desktop2.png',
        mediaBuilder: (context) => FlutterDeckSlideStepsBuilder(
          builder: (context, step) {
            final asset = step < 2
                ? 'assets/images/desktop.png'
                : 'assets/images/desktop2.png';
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: Image.asset(
                asset,
                key: ValueKey(asset),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            );
          },
        ),
      );
}
// ignore_for_file: file_names
