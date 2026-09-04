import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../flyover/flyover_view.dart';

/// The slide that breaks the deck open.
///
/// Entering the slide starts the flight immediately. The camera pulls away
/// from the first panel, crosses the landscape, and lands on the second panel.
/// The wash returns at the landing, so advancing to the next beat is seamless.
class Slide17 extends FlutterDeckSlideWidget {
  const Slide17({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/flyover',
          title: '3D flyover',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'The flight starts when this slide opens (20 s). It lands on the '
              'pavilion panel and moves to the gallery on its own — no '
              'keypress. Press → during the flight to cut it short.',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) => FlyoverView(
        playing: true,
        onLanded: () {
          final deck = context.flutterDeck;
          deck.goToSlide(deck.slideNumber + 1);
        },
      ),
    );
  }
}
// ignore_for_file: file_names
