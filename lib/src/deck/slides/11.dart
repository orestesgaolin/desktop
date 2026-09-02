import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/browser_demo.dart';
import '../../gallery.dart';

/// A browser workspace with enough room to feel like a product rather than a
/// gallery tile. Its tabs can still detach into independent native windows.
class Slide11 extends FlutterDeckSlideWidget {
  const Slide11({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/windowed-browser',
          title: 'A browser tab can become a window',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'The demo runs without clicks: the local Windowing API page '
              'detaches into a native window, revealing Flutter & Friends in '
              'the main browser, then returns with its navigation state.\n\n'
              '[Sources]\n'
              '- https://flutter.dev/blog/desktop-windowing-apis\n'
              '- https://flutterfriends.dev/',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) =>
          Theme(data: galleryTheme(), child: const _AutomatedBrowserDemo()),
    );
  }
}

class _AutomatedBrowserDemo extends StatefulWidget {
  const _AutomatedBrowserDemo();

  @override
  State<_AutomatedBrowserDemo> createState() => _AutomatedBrowserDemoState();
}

class _AutomatedBrowserDemoState extends State<_AutomatedBrowserDemo> {
  final BrowserWorkspace _workspace = BrowserWorkspace.instance;

  BrowserTab get _apiTab => _workspace.tabs.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_workspace.isDetached(_apiTab)) {
        _workspace.reattach(_apiTab);
      } else {
        _workspace.select(_apiTab);
      }
    });
  }

  @override
  void dispose() {
    if (_workspace.isDetached(_apiTab)) _workspace.reattach(_apiTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const BrowserWorkspaceView();
}
// ignore_for_file: file_names
