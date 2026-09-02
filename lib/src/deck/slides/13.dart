import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/edge_window_demo.dart';
import '../../palette.dart';
import '../code_snippet.dart';
import '../page.dart';

class Slide13 extends FlutterDeckSlideWidget {
  const Slide13({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/transparent-window',
          title: 'Transparent and frameless windows',
          steps: 4,
          speakerNotes:
              'Each step shows one part of the AppKit bridge used by the live '
              'demo: native styling, global display placement, drag and snap '
              'behavior, then hit testing for the non-rectangular Flutter '
              'surface. These are gaps in the current regular '
              'WindowController API rather than a proposal for a general '
              'cross-platform abstraction.\n\n'
              '[Sources]\n'
              '- https://flutter.dev/blog/desktop-windowing-apis',
        ),
      );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) => FlutterDeckSlideStepsBuilder(
      builder: (context, step) => _TransparentWindowSlide(step: step),
    ),
  );
}

class _TransparentWindowSlide extends StatefulWidget {
  const _TransparentWindowSlide({required this.step});

  final int step;

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
    final index = (widget.step - 1).clamp(0, _steps.length - 1);
    final current = _steps[index];
    return SlidePage(
      label: 'LIVE WINDOWING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Transparent and frameless windows',
                  style: PageText.title(s),
                ),
              ),
              SizedBox(width: 28 * s),
              _LaunchButton(scale: s, open: demo.isOpen),
            ],
          ),
          SizedBox(height: 24 * s),
          Row(
            children: [
              Text(
                '${index + 1}'.padLeft(2, '0'),
                style: PageText.label(s).copyWith(color: clay),
              ),
              SizedBox(width: 18 * s),
              Expanded(
                child: Text(
                  current.title,
                  style: PageText.lead(s)
                      .copyWith(color: ink, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${index + 1} / ${_steps.length}',
                style: PageText.footer(s),
              ),
            ],
          ),
          SizedBox(height: 20 * s),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: DecoratedBox(
                key: ValueKey(index),
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(18 * s),
                  border: Border.all(color: spruce.withValues(alpha: .28)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(32 * s),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SwiftCodeSnippet(
                      code: current.code,
                      style: TextStyle(
                        color: paper,
                        fontFamily: 'Menlo',
                        fontSize: 21 * s,
                        height: 1.44,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 10 * s),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Source: macos/Runner/AppDelegate.swift',
              style: PageText.footer(s),
            ),
          ),
        ],
      ),
    );
  }

  static const _steps = <_NativeCodeStep>[
    _NativeCodeStep(
      title: 'Borderless, transparent, floating window styling',
      code: '''popup.styleMask = [.borderless]
popup.isOpaque = false
popup.backgroundColor = .clear
popup.hasShadow = false
popup.level = .floating''',
    ),
    _NativeCodeStep(
      title: 'Absolute placement against the display’s visible frame',
      code: '''let area = screen.visibleFrame
let origin = NSPoint(
  x: side == "left"
    ? area.minX
    : area.maxX - popup.frame.width,
  y: area.midY - popup.frame.height / 2
)

popup.setFrameOrigin(origin)''',
    ),
    _NativeCodeStep(
      title: 'Custom dragging and edge-snap behavior',
      code: '''let mouse = NSEvent.mouseLocation
popup.setFrameOrigin(NSPoint(
  x: startOrigin.x + mouse.x - startMouse.x,
  y: startOrigin.y + mouse.y - startMouse.y
))

let side = distanceToLeft <= distanceToRight
  ? "left"
  : "right"
popup.animator().setFrameOrigin(target)''',
    ),
    _NativeCodeStep(
      title: 'Native hit testing that matches Flutter’s ClipPath',
      code: '''let localPoint = CGPoint(
  x: mouse.x - popup.frame.minX,
  y: popup.frame.maxY - mouse.y
)

let visiblePixel = edgeWindowPath(
  size: popup.frame.size,
  side: edgeSide
).contains(localPoint)

popup.ignoresMouseEvents =
  !controlRegionIsSafe && !visiblePixel''',
    ),
  ];
}

class _NativeCodeStep {
  const _NativeCodeStep({required this.title, required this.code});

  final String title;
  final String code;
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
