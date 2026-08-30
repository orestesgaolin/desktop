import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/edge_window_demo.dart';
import '../../palette.dart';
import '../page.dart';

class Slide11 extends FlutterDeckSlideWidget {
  const Slide11({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/transparent-window',
          title: 'Beyond the rectangle',
          speakerNotes:
              '[Sources]\n'
              '- https://flutter.dev/blog/desktop-windowing-apis',
        ),
      );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) => const _TransparentWindowSlide(),
  );
}

class _TransparentWindowSlide extends StatefulWidget {
  const _TransparentWindowSlide();

  @override
  State<_TransparentWindowSlide> createState() =>
      _TransparentWindowSlideState();
}

class _TransparentWindowSlideState extends State<_TransparentWindowSlide> {
  final demo = EdgeWindowDemo.instance;

  @override
  void initState() {
    super.initState();
    demo.addListener(_changed);
  }

  @override
  void dispose() {
    demo.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);
    return SlidePage(
      label: 'LIVE WINDOWING',
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Beyond the\nrectangle.', style: PageText.title(s)),
                SizedBox(height: 28 * s),
                SizedBox(
                  width: 650 * s,
                  child: Text(
                    'A transparent Flutter popup, clipped into a living '
                    'contour and constrained directly to the display edge.',
                    style: PageText.body(s),
                  ),
                ),
                SizedBox(height: 38 * s),
                _LaunchButton(scale: s, open: demo.isOpen),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: AspectRatio(
              aspectRatio: .78,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: panel,
                  border: Border.all(color: panelHi),
                  borderRadius: BorderRadius.circular(24 * s),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        'DISPLAY',
                        style: PageText.label(s).copyWith(color: textDim),
                      ),
                    ),
                    Positioned(
                      top: 34 * s,
                      right: 0,
                      bottom: 34 * s,
                      width: 112 * s,
                      child: ClipPath(
                        clipper: const EdgeWaveClipper(EdgeWindowSide.right),
                        child: const ColoredBox(color: spruce),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchButton extends StatefulWidget {
  const _LaunchButton({required this.scale, required this.open});

  final double scale;
  final bool open;

  @override
  State<_LaunchButton> createState() => _LaunchButtonState();
}

class _LaunchButtonState extends State<_LaunchButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: hovered ? 1.025 : 1,
        duration: const Duration(milliseconds: 180),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: hovered ? clay : spruce,
            foregroundColor: paper,
            padding: EdgeInsets.symmetric(horizontal: 28 * s, vertical: 21 * s),
          ),
          onPressed: widget.open
              ? EdgeWindowDemo.instance.close
              : EdgeWindowDemo.instance.open,
          icon: Icon(widget.open ? Icons.close_rounded : Icons.blur_on_rounded),
          label: Text(
            widget.open ? 'Close transparent view' : 'Launch transparent view',
          ),
        ),
      ),
    );
  }
}
// ignore_for_file: file_names
