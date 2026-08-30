import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../flyover/flyover_view.dart';
import '../../palette.dart';
import '../page.dart';

/// The slide that breaks the deck open.
///
/// Step 1 is an ordinary paper slide — except the paper is a wash over a live
/// 3D view parked head-on against a monolith standing in a forest. Step 2
/// lifts the wash and flies the camera out of the clearing, over the treeline,
/// low across the lake and up to the pavilion, landing square on a second
/// panel. The wash returns at the landing, so advancing to the next beat is
/// seamless.
class Slide15 extends FlutterDeckSlideWidget {
  const Slide15({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/flyover',
          title: 'A scene, not just a screen',
          steps: 2,
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'Press → once to launch the flight (20 s). It lands on the '
              'pavilion panel and moves to the gallery on its own — no '
              'second keypress. Press → during the flight to cut it short.',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) => FlutterDeckSlideStepsBuilder(
        builder: (context, step) => FlyoverView(
          playing: step >= 2,
          dockOverlay: const _FlyoverDock(),
          // Not `next()`: this slide has steps, and next() would advance the
          // step rather than the slide. The landing always hands off to the
          // slide after this one.
          onLanded: () {
            final deck = context.flutterDeck;
            deck.goToSlide(deck.slideNumber + 1);
          },
        ),
      ),
    );
  }
}

/// What the audience sees before the camera moves: a normal-looking slide.
class _FlyoverDock extends StatelessWidget {
  const _FlyoverDock();

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);
    return SlidePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Icon(
                Icons.keyboard_arrow_right_rounded,
                size: 20 * s,
                color: clay,
              ),
              SizedBox(width: 8 * s),
              Text('CONTINUE', style: PageText.label(s).copyWith(color: clay)),
            ],
          ),
        ],
      ),
    );
  }
}
// ignore_for_file: file_names
