// ignore_for_file: file_names
import 'package:flutter/material.dart';

import '../../palette.dart';
import '../config.dart';
import '../page.dart';
import '../slide_layouts.dart';

class Slide29 extends ClosingSlideLayout {
  Slide29({super.key})
    : super(
        route: '/the-capability-is-here',
        navigationTitle: 'The capability is here',
        title: 'The capability is here. The apps are up to us.',
        subtitle: 'Questions?',
        link: deckConfig.website,
        // additionalLinks: const ['github.com/orestesgaolin/desktop'],
        footerBuilder: (context) {
          final s = SlidePage.scaleOf(context);
          return SizedBox(
            height: 150 * s,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SpeakerPortrait(scale: s),
                SizedBox(width: 18 * s),
                SizedBox(
                  width: 126 * s,
                  child: Image.asset(
                    'assets/images/matej-knopp.png',
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(width: 28 * s),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share your feedback about Flutter on desktop with Matej.',
                        style: PageText.body(s).copyWith(fontSize: 16 * s),
                      ),
                      SizedBox(height: 7 * s),
                      Text(
                        'github.com/knopp',
                        style: PageText.body(s).copyWith(
                          color: clay,
                          fontWeight: FontWeight.w600,
                          fontSize: 14 * s,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 40 * s),
                SizedBox(
                  width: 330 * s,
                  child: Text(
                    '“For years desktop was the most appealing platform” — Parker L.',
                    style: PageText.body(s).copyWith(
                      color: ink.withValues(alpha: .62),
                      fontStyle: FontStyle.italic,
                      fontSize: 16 * s,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _SpeakerPortrait extends StatelessWidget {
  const _SpeakerPortrait({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 126 * scale,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.asset(
            'assets/images/dominik_roszkowski_speaker_3.jpg',
            width: 106 * scale,
            height: 106 * scale,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: 8 * scale),
        Text(
          'Dominik Roszkowski',
          maxLines: 1,
          style: PageText.footer(scale).copyWith(color: ink),
        ),
      ],
    ),
  );
}
