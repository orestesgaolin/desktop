// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/graphics_editor.dart';
import '../../frame.dart';
import '../../gallery.dart';

/// A full-slide design workspace. The canvas stays interactive during the talk.
class Slide19 extends FlutterDeckSlideWidget {
  const Slide19({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/design-canvas',
          title: 'Design canvas',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'The web version is available at '
              'https://roszkowski.dev/paperplane. Leave the URL visible in '
              'the top-right corner while demonstrating the editor. '
              'Swap the Hero card header and body slots, resize or rotate the '
              'component instance, then choose Custom GLSL, edit the fragment '
              'source, and compile it with the live impellerc workflow. Save '
              'the versioned document and import it again to restore the '
              'layout, components, slots, filters, and shader source.',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) => Theme(
        data: galleryTheme().copyWith(brightness: Brightness.dark),
        child: const _GraphicsEditorSlideBody(),
      ),
    );
  }
}

class _GraphicsEditorSlideBody extends StatefulWidget {
  const _GraphicsEditorSlideBody();

  @override
  State<_GraphicsEditorSlideBody> createState() =>
      _GraphicsEditorSlideBodyState();
}

class _GraphicsEditorSlideBodyState extends State<_GraphicsEditorSlideBody> {
  final PlaybackController _playback = PlaybackController();

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GraphicsEditorView(playback: _playback);
}
