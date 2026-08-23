import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../flyover/world.dart';
import '../palette.dart';
import 'slides.dart';

/// The presentation.
///
/// Everything is an ordinary flutter_deck slide except slide 8, which owns a
/// live flutter_scene landscape, and slide 9, which is the Flutter GPU
/// gallery. The landscape is heavy to generate, so the build starts here at
/// launch and runs while the audience is still on slide 1.
class PresentationApp extends StatefulWidget {
  const PresentationApp({super.key});

  @override
  State<PresentationApp> createState() => _PresentationAppState();
}

class _PresentationAppState extends State<PresentationApp> {
  @override
  void initState() {
    super.initState();
    // Fire and forget: the flyover slide awaits the same future.
    FlyoverWorld.instance.ready;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterDeckApp(
      configuration: const FlutterDeckConfiguration(
        controls: FlutterDeckControlsConfiguration(
          presenterToolbarVisible: true,
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
      slides: buildSlides(),
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
      display: TextStyle(fontSize: 82, fontWeight: FontWeight.w300),
      header: TextStyle(fontSize: 44, fontWeight: FontWeight.w400),
      title: TextStyle(fontSize: 52, fontWeight: FontWeight.w400),
      subtitle: TextStyle(fontSize: 26, fontWeight: FontWeight.w400),
      bodyLarge: TextStyle(fontSize: 22),
      bodyMedium: TextStyle(fontSize: 19),
      bodySmall: TextStyle(fontSize: 13),
    ),
  ).copyWith(
    slideTheme: const FlutterDeckSlideThemeData(
      backgroundColor: paper,
      color: ink,
    ),
  );
}
