import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../slide_layouts.dart';

class Slide4 extends ImmersiveMediaSlideLayout {
  Slide4({super.key})
    : super(
        route: '/first-desktop-talk',
        title: 'My first Flutter desktop talk was in January 2020.',
        label: 'Six years watching desktop',
        aspectRatio: 1421 / 1226,
        steps: 2,
        speakerNotes:
            'My first talk about Flutter desktop was at Flutter Europe in '
            'January 2020. Press → to zoom into the audience comment in the '
            'bottom-left corner.\n\n'
            '[Sources]\n'
            '- User-provided asset: assets/images/flutter-europe-2020.png',
        mediaBuilder: (context) => FlutterDeckSlideStepsBuilder(
          builder: (context, step) => ClipRect(
            clipBehavior: Clip.hardEdge,
            child: AnimatedScale(
              scale: step >= 2 ? 2.3 : 1,
              alignment: Alignment.bottomLeft,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              filterQuality: FilterQuality.high,
              child: Image.asset(
                'assets/images/flutter-europe-2020.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      );
}
// ignore_for_file: file_names
