import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../flyover/world.dart';
import '../palette.dart';
import 'config.dart';
import 'slides.dart';

/// The presentation.
///
/// Most slides use shared layouts; the browser, native windowing, GPU,
/// flutter_scene, and design-editor beats remain live, full-slide demos. The
/// landscape is heavy to generate,
/// so the build starts here at launch and runs while the audience is still on
/// slide 1.
class PresentationApp extends StatefulWidget {
  const PresentationApp({super.key}) : _preloadFlyover = true;

  @visibleForTesting
  const PresentationApp.withoutFlyoverPreload({super.key})
    : _preloadFlyover = false;

  final bool _preloadFlyover;

  @override
  State<PresentationApp> createState() => _PresentationAppState();
}

class _PresentationAppState extends State<PresentationApp> {
  late final List<FlutterDeckSlideWidget> _slides = buildSlides();

  @override
  void initState() {
    super.initState();
    // Fire and forget: the flyover slide awaits the same future.
    if (widget._preloadFlyover) FlyoverWorld.instance.ready;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterDeckApp(
      configuration: const FlutterDeckConfiguration(
        controls: FlutterDeckControlsConfiguration(
          presenterToolbarVisible: true,
          shortcuts: FlutterDeckShortcutsConfiguration(
            toggleMarker: {
              SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true),
            },
            toggleNavigationDrawer: {
              SingleActivator(LogicalKeyboardKey.period, meta: true),
            },
          ),
        ),
        progressIndicator: FlutterDeckProgressIndicator.solid(
          color: spruce,
          backgroundColor: panelHi,
        ),
        transition: FlutterDeckTransition.fade(),
      ),
      lightTheme: deckTheme(),
      darkTheme: deckTheme(),
      themeMode: ThemeMode.light,
      // Keep the same widget instances across rebuilds. flutter_deck treats a
      // newly-created list as a dynamic slide update and resets its router,
      // which otherwise sends the deck back to the beginning on hot reload.
      slides: _slides,
    );
  }
}

/// The deck's theme: the same quiet Scandinavian palette as the gallery, with
/// a type ramp small enough that a slide is not all headline.
FlutterDeckThemeData deckTheme() {
  final material = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: paper,
    fontFamily: deckFontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: spruce,
      brightness: Brightness.light,
      surface: paper,
      onSurface: ink,
    ),
  );

  // Not `FlutterDeckThemeData.fromTheme`: its internal merge keeps the
  // package's default blue Material theme and drops the one passed in, so the
  // deck's `MaterialApp` would ignore the palette entirely.
  return FlutterDeckThemeData(
    theme: material,
    textTheme: const FlutterDeckTextTheme(
      display: TextStyle(
        fontFamily: deckFontFamily,
        fontSize: 82,
        fontWeight: FontWeight.w300,
      ),
      header: TextStyle(
        fontFamily: deckFontFamily,
        fontSize: 44,
        fontWeight: FontWeight.w400,
      ),
      title: TextStyle(
        fontFamily: deckFontFamily,
        fontSize: 52,
        fontWeight: FontWeight.w400,
      ),
      subtitle: TextStyle(
        fontFamily: deckFontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w400,
      ),
      bodyLarge: TextStyle(fontFamily: deckFontFamily, fontSize: 22),
      bodyMedium: TextStyle(fontFamily: deckFontFamily, fontSize: 19),
      bodySmall: TextStyle(fontFamily: deckFontFamily, fontSize: 13),
    ),
  ).copyWith(
    slideTheme: const FlutterDeckSlideThemeData(
      backgroundColor: paper,
      color: ink,
    ),
  );
}
