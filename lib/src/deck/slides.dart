import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../flyover/flyover_view.dart';
import '../gallery.dart';
import '../palette.dart';
import 'page.dart';

/// Placeholder copy. Every slide outside the flyover and the gallery is a
/// stand-in, so the deck can be rehearsed before the real content exists.
abstract final class Lorem {
  static const String lead =
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do '
      'eiusmod tempor incididunt ut labore et dolore magna aliqua.';

  static const String paragraph =
      'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris '
      'nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in '
      'reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla '
      'pariatur.';

  static const String paragraphAlt =
      'Excepteur sint occaecat cupidatat non proident, sunt in culpa qui '
      'officia deserunt mollit anim id est laborum. Sed ut perspiciatis unde '
      'omnis iste natus error sit voluptatem accusantium doloremque.';

  static const List<String> bullets = [
    'Lorem ipsum dolor sit amet',
    'Consectetur adipiscing elit',
    'Sed do eiusmod tempor incididunt',
    'Ut labore et dolore magna aliqua',
  ];
}

// --------------------------------------------------------------------------
// Ordinary slides
// --------------------------------------------------------------------------

/// The opening slide.
class TitleSlide extends FlutterDeckSlideWidget {
  const TitleSlide({super.key})
      : super(
          configuration: const FlutterDeckSlideConfiguration(
            route: '/title',
            title: 'Title',
            speakerNotes: 'Welcome. The deck is ordinary until slide 8.',
          ),
        );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          showNumber: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('LOREM · IPSUM · MMXXVI', style: PageText.label(s)),
              SizedBox(height: 28 * s),
              Text('Dolor sit amet,\nconsectetur.',
                  style: PageText.display(s)),
              SizedBox(height: 34 * s),
              Container(width: 90 * s, height: 1.4, color: clay),
              SizedBox(height: 30 * s),
              SizedBox(
                width: 620 * s,
                child: Text(Lorem.lead, style: PageText.lead(s)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A statement slide: one large line, nothing else.
class StatementSlide extends FlutterDeckSlideWidget {
  StatementSlide({
    super.key,
    required String route,
    required this.label,
    required this.statement,
    required this.footnote,
  }) : super(configuration: FlutterDeckSlideConfiguration(route: route));

  final String label;
  final String statement;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 1000 * s,
                child: Text(statement, style: PageText.display(s)),
              ),
              SizedBox(height: 32 * s),
              SizedBox(
                width: 640 * s,
                child: Text(footnote, style: PageText.body(s)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A title with a two-column body — the deck's workhorse layout.
class ProseSlide extends FlutterDeckSlideWidget {
  ProseSlide({
    super.key,
    required String route,
    required this.label,
    required this.title,
    this.columns = const [Lorem.paragraph, Lorem.paragraphAlt],
  }) : super(configuration: FlutterDeckSlideConfiguration(route: route));

  final String label;
  final String title;
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 900 * s, child: Text(title, style: PageText.title(s))),
              SizedBox(height: 44 * s),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final column in columns) ...[
                      Expanded(
                        child: Text(column, style: PageText.body(s)),
                      ),
                      SizedBox(width: 64 * s),
                    ],
                    SizedBox(width: 120 * s),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A title with a bullet list, revealed one item per step.
class BulletsSlide extends FlutterDeckSlideWidget {
  BulletsSlide({
    super.key,
    required String route,
    required this.label,
    required this.title,
    this.items = Lorem.bullets,
  }) : super(
          configuration: FlutterDeckSlideConfiguration(
            route: route,
            steps: items.length,
          ),
        );

  final String label;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 900 * s, child: Text(title, style: PageText.title(s))),
              SizedBox(height: 48 * s),
              Expanded(
                child: FlutterDeckSlideStepsBuilder(
                  builder: (context, step) => SizedBox(
                    width: 860 * s,
                    child: PageBullets(items: items.take(step).toList()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A pull quote.
class QuoteSlide extends FlutterDeckSlideWidget {
  QuoteSlide({
    super.key,
    required String route,
    required this.quote,
    required this.attribution,
  }) : super(configuration: FlutterDeckSlideConfiguration(route: route));

  final String quote;
  final String attribution;

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: 'Sententia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 1020 * s,
                child: Text(
                  '“$quote”',
                  style: PageText.title(s).copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              SizedBox(height: 36 * s),
              Text(attribution, style: PageText.label(s).copyWith(color: clay)),
            ],
          ),
        );
      },
    );
  }
}

/// The closing slide.
class ClosingSlide extends FlutterDeckSlideWidget {
  const ClosingSlide({super.key})
      : super(
          configuration: const FlutterDeckSlideConfiguration(
            route: '/gratias',
            title: 'Gratias',
          ),
        );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          showNumber: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Gratias ago', style: PageText.display(s)),
              SizedBox(height: 28 * s),
              Container(width: 90 * s, height: 1.4, color: spruce),
              SizedBox(height: 26 * s),
              Text(Lorem.lead, style: PageText.lead(s)),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------------
// The flyover
// --------------------------------------------------------------------------

/// The slide that breaks the deck open.
///
/// Step 1 is an ordinary paper slide — except the paper is a wash over a live
/// 3D view parked head-on against a monolith standing in a forest. Step 2
/// lifts the wash and flies the camera out of the clearing, over the treeline,
/// low across the lake and up to the pavilion, landing square on a second
/// panel. The wash returns at the landing, so advancing to the gallery slide
/// is seamless.
class FlyoverSlide extends FlutterDeckSlideWidget {
  const FlyoverSlide({super.key})
      : super(
          configuration: const FlutterDeckSlideConfiguration(
            route: '/flyover',
            title: 'Flyover',
            steps: 2,
            showProgress: false,
            transition: FlutterDeckTransition.fade(),
            speakerNotes:
                'Press → once to launch the flight (13 s). It lands on the '
                'pavilion panel and holds there; press → again for the '
                'gallery.',
          ),
        );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) => FlutterDeckSlideStepsBuilder(
        builder: (context, step) => FlyoverView(
          playing: step >= 2,
          dockOverlay: const _FlyoverDock(),
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
      label: 'Sectio VIII',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 980 * s,
            child: Text('Et hinc\nlonge aliter.', style: PageText.display(s)),
          ),
          SizedBox(height: 32 * s),
          SizedBox(
            width: 620 * s,
            child: Text(Lorem.paragraph, style: PageText.body(s)),
          ),
          SizedBox(height: 40 * s),
          Row(
            children: [
              Icon(Icons.keyboard_arrow_right_rounded,
                  size: 20 * s, color: clay),
              SizedBox(width: 8 * s),
              Text('CONTINUA', style: PageText.label(s).copyWith(color: clay)),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// The gallery
// --------------------------------------------------------------------------

/// The Flutter GPU playground, landed on as a slide.
///
/// It carries its own Material theme, because the deck's `MaterialApp` is
/// themed for slides, not for the gallery's controls.
class GallerySlide extends FlutterDeckSlideWidget {
  const GallerySlide({super.key})
      : super(
          configuration: const FlutterDeckSlideConfiguration(
            route: '/gpu-playground',
            title: 'GPU Playground',
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
      builder: (context) => Theme(
        data: galleryTheme(),
        child: const BootstrapScreen(),
      ),
    );
  }
}

// --------------------------------------------------------------------------

/// The deck, in order. Slides 1–7 are ordinary; 8 is the flyover, which lands
/// on 9, the live GPU gallery; 10 onwards carries on as normal.
List<FlutterDeckSlideWidget> buildSlides() => [
      const TitleSlide(),
      BulletsSlide(
        route: '/agenda',
        label: 'Index',
        title: 'Quattuor capitula, unum iter.',
      ),
      ProseSlide(
        route: '/context',
        label: 'Sectio I',
        title: 'Neque porro quisquam est qui dolorem ipsum.',
      ),
      StatementSlide(
        route: '/fact',
        label: 'Sectio II',
        statement: '78 %',
        footnote: Lorem.paragraph,
      ),
      BulletsSlide(
        route: '/method',
        label: 'Sectio III',
        title: 'Temporibus autem quibusdam.',
        items: const [
          'At vero eos et accusamus',
          'Iusto odio dignissimos ducimus',
          'Qui blanditiis praesentium',
        ],
      ),
      QuoteSlide(
        route: '/quote',
        quote: 'Nemo enim ipsam voluptatem quia voluptas sit aspernatur',
        attribution: 'Cicero, De Finibus',
      ),
      ProseSlide(
        route: '/before',
        label: 'Sectio VII',
        title: 'Itaque earum rerum hic tenetur a sapiente delectus.',
      ),
      const FlyoverSlide(),
      const GallerySlide(),
      ProseSlide(
        route: '/after',
        label: 'Sectio X',
        title: 'Nam libero tempore, cum soluta nobis est eligendi optio.',
      ),
      StatementSlide(
        route: '/fact-two',
        label: 'Sectio XI',
        statement: '16 ms',
        footnote: Lorem.paragraphAlt,
      ),
      BulletsSlide(
        route: '/next',
        label: 'Sectio XII',
        title: 'Omnis dolor repellendus.',
      ),
      const ClosingSlide(),
    ];
