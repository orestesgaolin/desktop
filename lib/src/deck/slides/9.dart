import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/browser_demo.dart';
import '../../gallery.dart';

/// A browser workspace with enough room to feel like a product rather than a
/// gallery tile. Its tabs can still detach into independent native windows.
class Slide9 extends FlutterDeckSlideWidget {
  const Slide9({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/windowed-browser',
          title: 'A browser tab can become a window',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'A live WKWebView browser. Detach the active tab into a native '
              'Flutter window, then return it without losing navigation state.',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) =>
          Theme(data: galleryTheme(), child: const BrowserWorkspaceView()),
    );
  }
}
// ignore_for_file: file_names
