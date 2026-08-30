import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../flyover/world.dart';
import '../palette.dart';
import 'config.dart';
import 'slides.dart';

const _deckConfiguration = FlutterDeckConfiguration(
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
);

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
  final _position = _DeckPositionPlugin();

  @override
  void initState() {
    super.initState();
    // Fire and forget: the flyover slide awaits the same future.
    if (widget._preloadFlyover) FlyoverWorld.instance.ready;
  }

  @override
  Widget build(BuildContext context) {
    final positionBeforeRebuild = _position.snapshot;
    final slides = [
      for (final slide in buildSlides())
        _ReloadableSlide(
          slide: slide,
          initial: slide.configuration?.route == positionBeforeRebuild?.route,
        ),
    ];

    if (positionBeforeRebuild != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _position.restore(positionBeforeRebuild),
      );
    }

    return FlutterDeckApp(
      configuration: _deckConfiguration,
      lightTheme: deckTheme(),
      darkTheme: deckTheme(),
      themeMode: ThemeMode.light,
      plugins: [_position],
      // Construct slide widgets in build so changes to constructor arguments
      // are visible immediately after hot reload. [_position] independently
      // restores the active route and step after flutter_deck updates its
      // router for the regenerated list.
      slides: slides,
    );
  }
}

class _ReloadableSlide extends FlutterDeckSlideWidget {
  _ReloadableSlide({required this.slide, required bool initial})
    : super(
        configuration: _configurationFor(
          slide.configuration!.mergeWithGlobal(_deckConfiguration),
          initial: initial,
        ),
      );

  final FlutterDeckSlideWidget slide;

  @override
  Widget build(BuildContext context) => slide;

  static FlutterDeckSlideConfiguration _configurationFor(
    FlutterDeckSlideConfiguration configuration, {
    required bool initial,
  }) => FlutterDeckSlideConfiguration(
    route: configuration.route,
    hidden: configuration.hidden,
    initial: initial,
    preloadImages: configuration.preloadImages,
    speakerNotes: configuration.speakerNotes,
    steps: configuration.steps,
    title: configuration.title,
    footer: configuration.footer,
    header: configuration.header,
    progressIndicator: configuration.progressIndicator,
    showProgress: configuration.showProgress,
    transition: configuration.transition,
  );
}

typedef _DeckPosition = ({String route, int step});

class _DeckPositionPlugin extends FlutterDeckPlugin {
  FlutterDeck? _deck;
  _DeckPosition? snapshot;

  @override
  void init(FlutterDeck flutterDeck) {
    _deck = flutterDeck;
    flutterDeck.router.addListener(_capture);
    _capture();
  }

  @override
  void dispose() {
    _deck?.router.removeListener(_capture);
    _deck = null;
  }

  void _capture() {
    final router = _deck?.router;
    if (router == null) return;
    snapshot = (
      route: router.currentSlideConfiguration.route,
      step: router.currentStep,
    );
  }

  void restore(_DeckPosition position) {
    final router = _deck?.router;
    if (router == null) return;

    final slideIndex = router.slides.indexWhere(
      (slide) => slide.route == position.route,
    );
    if (slideIndex == -1) return;

    if (router.currentSlideIndex != slideIndex) {
      router.goToSlide(slideIndex + 1);
    }

    final steps = router.currentSlideConfiguration.steps;
    final step = position.step > steps ? steps : position.step;
    if (step > 1) router.goToStep(step);
    _capture();
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
