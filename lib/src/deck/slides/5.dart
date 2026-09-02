import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../config.dart';
import '../page.dart';

/// A restrained, horizontal history of Flutter's desktop support.
class Slide5 extends FlutterDeckSlideWidget {
  const Slide5({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/desktop-timeline',
          title: 'Six years of Flutter desktop',
          steps: 6,
          speakerNotes:
              'Flutter desktop milestones from early access to native '
              'multi-window support. Use ← and → to '
              'move through one milestone at a time.\n\n'
              '[Sources]\n'
              '- https://flutter.dev/blog/announcing-flutter-1-12-what-a-year\n'
              '- https://developers.googleblog.com/en/announcing-flutter-2/\n'
              '- https://flutter.dev/blog/introducing-flutter-3\n'
              '- https://docs.flutter.dev/release/release-notes/release-notes-3.16.0\n'
              '- https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads\n'
              '- https://docs.flutter.dev/release/release-notes/release-notes-3.35.0\n'
              '- https://flutter.dev/blog/whats-new-in-flutter-3-44\n'
              '- https://flutter.dev/blog/desktop-windowing-apis\n'
              '- https://docs.flutter.dev/release/release-notes/release-notes-3.47.0',
        ),
      );

  static const _events = [
    _TimelineEvent(
      date: 'MAR 2021',
      release: 'Flutter 2.0',
      description: 'Windows, macOS and Linux enter early access',
    ),
    _TimelineEvent(
      date: '2022',
      release: 'Flutter 2.10 / 3.0',
      description: 'Windows stabilizes first; macOS and Linux follow',
    ),
    _TimelineEvent(
      date: '2022—2024',
      release: 'The quiet years',
      description: 'Stable, but not fully desktop-ready',
    ),
    _TimelineEvent(
      date: '2024',
      release: 'Windowing work begins',
      description: 'Canonical and Google\nstart the new API',
    ),
    _TimelineEvent(
      date: 'AUG 2025',
      release: 'Flutter 3.35',
      description: 'Merged threads\n+ native interop',
    ),
    _TimelineEvent(
      date: 'MAY—AUG 2026',
      release: 'Canonical + Flutter 3.47',
      description: 'Desktop roadmap, Impeller\nand multi-window',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: 'Flutter desktop',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 1020 * s,
                child: Text(
                  configuration?.title ?? '',
                  style: PageText.title(s),
                ),
              ),
              SizedBox(height: 34 * s),
              Expanded(
                child: FlutterDeckSlideStepsBuilder(
                  builder: (context, step) => LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final cardWidth = 190 * s;
                      final axisY = constraints.maxHeight * 0.50;
                      final usableWidth = width - cardWidth;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: cardWidth / 2,
                            right: cardWidth / 2,
                            top: axisY,
                            child: Container(
                              height: 1.2 * s,
                              color: spruce.withValues(alpha: 0.34),
                            ),
                          ),
                          for (var index = 0; index < _events.length; index++)
                            _TimelineMilestone(
                              event: _events[index],
                              index: index,
                              left: usableWidth * index / (_events.length - 1),
                              width: cardWidth,
                              axisY: axisY,
                              scale: s,
                              visible: index < step,
                            ),
                        ],
                      );
                    },
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

class _TimelineEvent {
  const _TimelineEvent({
    required this.date,
    required this.release,
    required this.description,
  });

  final String date;
  final String release;
  final String description;
}

class _TimelineMilestone extends StatelessWidget {
  const _TimelineMilestone({
    required this.event,
    required this.index,
    required this.left,
    required this.width,
    required this.axisY,
    required this.scale,
    required this.visible,
  });

  final _TimelineEvent event;
  final int index;
  final double left;
  final double width;
  final double axisY;
  final double scale;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final above = index.isEven;
    final accent = index == Slide5._events.length - 1;
    final dotSize = (accent ? 18 : 13) * scale;
    final stemHeight = 28 * scale;
    final cardHeight = 154 * scale;
    final cardTop = above
        ? axisY - stemHeight - cardHeight
        : axisY + stemHeight + 13 * scale;

    return Positioned(
      left: left,
      top: 0,
      width: width,
      bottom: 0,
      child: AnimatedOpacity(
        key: ValueKey('timeline-event-$index'),
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : Offset(0, above ? 0.025 : -0.025),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: width / 2 - 0.6 * scale,
                top: above ? axisY - stemHeight : axisY,
                child: Container(
                  width: 1.2 * scale,
                  height: stemHeight,
                  color: accent ? clay : spruce.withValues(alpha: 0.52),
                ),
              ),
              Positioned(
                left: width / 2 - dotSize / 2,
                top: axisY - dotSize / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent ? clay : paper,
                    border: Border.all(
                      color: accent ? clay : spruce,
                      width: 2 * scale,
                    ),
                  ),
                  child: SizedBox(width: dotSize, height: dotSize),
                ),
              ),
              Positioned(
                left: 0,
                top: cardTop,
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.date,
                      style: PageText.label(scale).copyWith(
                        color: accent ? clay : spruce,
                        fontSize: 14.5 * scale,
                        letterSpacing: 1.7 * scale,
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      event.release,
                      style: TextStyle(
                        fontFamily: deckFontFamily,
                        fontSize: 18 * scale,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      event.description,
                      style: TextStyle(
                        fontFamily: deckFontFamily,
                        fontSize: 16 * scale,
                        height: 1.28,
                        fontWeight: FontWeight.w400,
                        color: ink.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ignore_for_file: file_names
