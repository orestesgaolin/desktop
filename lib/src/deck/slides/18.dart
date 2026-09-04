import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../gallery.dart';

/// The Flutter GPU playground, landed on as a slide.
///
/// It carries its own Material theme, because the deck's `MaterialApp` is
/// themed for slides, not for the gallery's controls.
class Slide18 extends FlutterDeckSlideWidget {
  const Slide18({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/gpu-playground',
          title: 'Flutter GPU shaders',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'Live Flutter GPU demos. Every pixel here comes out of a '
              'render pass; the shader editor is behind the {} button.',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) =>
          Theme(data: galleryTheme(), child: const BootstrapScreen()),
    );
  }
}
// ignore_for_file: file_names
