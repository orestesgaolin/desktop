// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../page.dart';

class Slide8 extends FlutterDeckSlideWidget {
  const Slide8({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/window-kinds',
          title: 'Full multi-window support',
          steps: 2,
          preloadImages: {
            'assets/images/regular.87ef9745dace73b5ebf4b0d1aba0db51.gif',
            'assets/images/dialog.1caa0909badaac0a391edd43758d143b.gif',
            'assets/images/satellite.ed178b92b9a794eade59f357b42d032a.gif',
            'assets/images/tooltip.06579f86a696fbcb798a0ee2e8396629.gif',
            'assets/images/popup.b3aade54ebd547823ebbcfbce218e2e4.gif',
          },
          speakerNotes:
              'Step one introduces experimental multi-window support in '
              'Flutter 3.47. Press → for the five basic window types and a '
              'staggered visual tour.\n\n'
              '[Sources]\n'
              '- User-provided assets: assets/images/regular*.gif, '
              'dialog*.gif, satellite*.gif, tooltip*.gif, and popup*.gif\n'
              '- https://flutter.dev/blog/desktop-windowing-apis',
        ),
      );

  static const _bullets = [
    'Flutter 3.47 adds experimental multi-window support.',
    'Five window types: regular, dialog, satellite, tooltip, and popup.',
  ];

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) => FlutterDeckSlideStepsBuilder(
      builder: (context, step) {
        final s = SlidePage.scaleOf(context);
        return SlidePage(
          label: 'Windowing · 2026',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Full multi-window support', style: PageText.title(s)),
              SizedBox(height: 24 * s),
              SizedBox(
                height: 112 * s,
                child: PageBullets(items: _bullets.take(step).toList()),
              ),
              SizedBox(height: 14 * s),
              Expanded(
                child: _WindowTypeGrid(visible: step >= 2, scale: s),
              ),
              SizedBox(height: 8 * s),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Source: https://flutter.dev/blog/desktop-windowing-apis',
                  style: PageText.footer(s),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _WindowType {
  const _WindowType(this.label, this.asset, this.start);

  final String label;
  final String asset;
  final double start;
}

class _WindowTypeGrid extends StatefulWidget {
  const _WindowTypeGrid({required this.visible, required this.scale});

  final bool visible;
  final double scale;

  @override
  State<_WindowTypeGrid> createState() => _WindowTypeGridState();
}

class _WindowTypeGridState extends State<_WindowTypeGrid>
    with SingleTickerProviderStateMixin {
  static const _windows = [
    _WindowType(
      'Regular',
      'assets/images/regular.87ef9745dace73b5ebf4b0d1aba0db51.gif',
      0,
    ),
    _WindowType(
      'Dialog',
      'assets/images/dialog.1caa0909badaac0a391edd43758d143b.gif',
      .12,
    ),
    _WindowType(
      'Satellite',
      'assets/images/satellite.ed178b92b9a794eade59f357b42d032a.gif',
      .24,
    ),
    _WindowType(
      'Tooltip',
      'assets/images/tooltip.06579f86a696fbcb798a0ee2e8396629.gif',
      .54,
    ),
    _WindowType(
      'Popup',
      'assets/images/popup.b3aade54ebd547823ebbcfbce218e2e4.gif',
      .66,
    ),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _WindowTypeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    widget.visible ? _controller.forward(from: 0) : _controller.reset();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = 16 * widget.scale;
      final tileWidth = (constraints.maxWidth - gap * 2) / 3;
      final rowHeight = (constraints.maxHeight - gap) / 2;

      Widget tile(int index) => SizedBox(
        width: tileWidth,
        height: rowHeight,
        child: _AnimatedWindowType(
          window: _windows[index],
          controller: _controller,
          scale: widget.scale,
        ),
      );

      return Column(
        children: [
          Row(
            children: [
              tile(0),
              SizedBox(width: gap),
              tile(1),
              SizedBox(width: gap),
              tile(2),
            ],
          ),
          SizedBox(height: gap),
          SizedBox(
            width: tileWidth * 2 + gap,
            child: Row(
              children: [
                tile(3),
                SizedBox(width: gap),
                tile(4),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _AnimatedWindowType extends StatelessWidget {
  const _AnimatedWindowType({
    required this.window,
    required this.controller,
    required this.scale,
  });

  final _WindowType window;
  final AnimationController controller;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        window.start,
        window.start + .28,
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = animation.value;
        if (progress == 0) return const SizedBox.expand();

        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * scale * (1 - progress)),
            child: Transform.scale(
              scale: .985 + .015 * progress,
              child: Semantics(
                image: true,
                label: '${window.label} window animation',
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8 * scale),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: panel,
                          border: Border.all(color: panelHi),
                        ),
                        child: Image.asset(
                          window.asset,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
