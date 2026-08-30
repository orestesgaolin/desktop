// Flutter's desktop windowing API is experimental and currently internal.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';

import '../palette.dart';

enum EdgeWindowSide { left, right }

/// Owns the independent transparent window created by the deck's demo slide.
///
/// Flutter owns the window, its transparent pixels, and its lifecycle. On
/// macOS, a small host call supplies borderless styling and absolute placement,
/// which the experimental regular-window controller does not expose.
class EdgeWindowDemo extends ChangeNotifier {
  EdgeWindowDemo._() {
    _platform.setMethodCallHandler(_handlePlatformCall);
  }

  static final EdgeWindowDemo instance = EdgeWindowDemo._();
  static const _platform = MethodChannel('gpu_playground/edge_window');

  WindowController? _parent;
  WindowController? _window;
  EdgeWindowSide _side = EdgeWindowSide.right;
  String _screenName = 'Locating display…';
  Offset _position = Offset.zero;

  WindowController? get window => _window;
  EdgeWindowSide get side => _side;
  String get screenName => _screenName;
  String get positionLabel =>
      'X ${_position.dx.round()}  ·  Y ${_position.dy.round()}';
  bool get isOpen => _window != null;

  void attach(WindowController parent) {
    _parent = parent;
  }

  void open([EdgeWindowSide side = EdgeWindowSide.right]) {
    _side = side;
    if (_window == null) {
      if (_parent == null) return;
      const size = Size(380, 580);
      _window = WindowController(
        size: size,
        constraints: const BoxConstraints.tightFor(width: 380, height: 580),
        title: 'Floating frame',
        delegate: _EdgeWindowDelegate(this),
      );
      notifyListeners();
      _snapToScreenEdge();
      return;
    }
    dock(side);
  }

  void dock(EdgeWindowSide side) {
    _side = side;
    notifyListeners();
    _snapToScreenEdge();
  }

  void beginDrag() {
    if (!Platform.isMacOS || _window == null) return;
    unawaited(_platform.invokeMethod<void>('beginDrag'));
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'didSnap' && call.arguments is String) {
      final nextSide = switch (call.arguments as String) {
        'left' => EdgeWindowSide.left,
        'right' => EdgeWindowSide.right,
        _ => null,
      };
      if (nextSide != null && nextSide != _side) {
        _side = nextSide;
        notifyListeners();
      }
      return;
    }
    if (call.method == 'didUpdateWindow' && call.arguments is Map) {
      final details = Map<Object?, Object?>.from(call.arguments as Map);
      final screenName = details['screenName'];
      final x = details['x'];
      final y = details['y'];
      if (screenName is! String || x is! num || y is! num) return;
      _screenName = screenName;
      _position = Offset(x.toDouble(), y.toDouble());
      notifyListeners();
    }
  }

  void close() {
    final window = _window;
    if (window == null) return;
    _window = null;
    notifyListeners();
    window.destroy();
  }

  void _destroyed() {
    if (_window == null) return;
    _window = null;
    notifyListeners();
  }

  Future<void> _snapToScreenEdge() async {
    if (!Platform.isMacOS) return;
    await WidgetsBinding.instance.endOfFrame;
    try {
      await _platform.invokeMethod<void>('dock', _side.name);
    } on MissingPluginException {
      // Other desktop hosts keep the independently managed Flutter window.
    }
  }
}

class _EdgeWindowDelegate with WindowControllerDelegate {
  _EdgeWindowDelegate(this.demo);

  final EdgeWindowDemo demo;

  @override
  void onWindowDestroyed() {
    demo._destroyed();
    super.onWindowDestroyed();
  }
}

class EdgeWindowView extends StatefulWidget {
  const EdgeWindowView({super.key});

  @override
  State<EdgeWindowView> createState() => _EdgeWindowViewState();
}

class _EdgeWindowViewState extends State<EdgeWindowView> {
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
    return SizedBox(
      width: 380,
      height: 580,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: clay,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: ClipPath(
            clipper: EdgeWaveClipper(demo.side),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff537d74), Color(0xff183e39)],
                    ),
                  ),
                ),
                const _DriftingOrbs(),
                _PanelContent(
                  side: demo.side,
                  screenName: demo.screenName,
                  positionLabel: demo.positionLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.side,
    required this.screenName,
    required this.positionLabel,
  });

  final EdgeWindowSide side;
  final String screenName;
  final String positionLabel;

  @override
  Widget build(BuildContext context) {
    final leftPadding = side == EdgeWindowSide.right ? 92.0 : 30.0;
    final rightPadding = side == EdgeWindowSide.left ? 92.0 : 30.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(leftPadding, 34, rightPadding, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => EdgeWindowDemo.instance.beginDrag(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          _LiveIndicator(),
                          Spacer(),
                          Icon(
                            Icons.drag_indicator_rounded,
                            color: Color(0x99e9e2d8),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Close edge window',
                onPressed: EdgeWindowDemo.instance.close,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Floating\nframe.',
            style: TextStyle(
              color: Color(0xfff4eee4),
              fontSize: 31,
              height: .98,
              letterSpacing: -.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            screenName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xfff0aa8d),
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            positionLabel,
            style: const TextStyle(
              color: Color(0xfff4eee4),
              fontSize: 18,
              letterSpacing: .3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'A transparent Flutter surface.',
            style: TextStyle(
              color: Color(0xffd5e1dd),
              height: 1.45,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 26),
          const Center(child: _PlusOneButton()),
          const SizedBox(height: 28),
          SegmentedButton<EdgeWindowSide>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: EdgeWindowSide.left,
                icon: Icon(Icons.keyboard_double_arrow_left_rounded),
                label: Text('Left'),
              ),
              ButtonSegment(
                value: EdgeWindowSide.right,
                icon: Icon(Icons.keyboard_double_arrow_right_rounded),
                label: Text('Right'),
              ),
            ],
            selected: {side},
            onSelectionChanged: (value) {
              EdgeWindowDemo.instance.dock(value.single);
            },
          ),
          const Spacer(),
          Text(
            'DRAG HEADER  ·  ${side.name.toUpperCase()} EDGE',
            style: const TextStyle(
              color: Color(0xffe5a081),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusOneButton extends StatefulWidget {
  const _PlusOneButton();

  @override
  State<_PlusOneButton> createState() => _PlusOneButtonState();
}

class _PlusOneButtonState extends State<_PlusOneButton>
    with SingleTickerProviderStateMixin {
  bool hovered = false;
  bool pressed = false;

  int count = 0;

  late final AnimationController ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    ripple.dispose();
    super.dispose();
  }

  void _activate() {
    ripple.forward(from: 0);
    setState(() => count++);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) => setState(() => pressed = false),
        onTap: _activate,
        child: AnimatedScale(
          scale: pressed ? .92 : (hovered ? 1.06 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hovered
                  ? const Color(0xfff0b095)
                  : const Color(0xffd88f72),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xffe9a083)
                      .withValues(alpha: hovered ? .48 : .24),
                  blurRadius: hovered ? 34 : 20,
                  spreadRadius: hovered ? 5 : 1,
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: ripple,
              builder: (context, child) => CustomPaint(
                painter: _RipplePainter(ripple.value),
                child: child,
              ),
              child: Center(
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: Color(0xff173b36),
                    fontSize: 34,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || progress == 1) return;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide * .48 * progress,
      Paint()
        ..color = const Color(0xffffe2d5).withValues(alpha: 1 - progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(
          opacity: Tween(begin: .35, end: 1.0).animate(animation),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xfff0aa8d),
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 9),
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'LIVE VIEW',
          style: TextStyle(
            color: Color(0xffe9e2d8),
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DriftingOrbs extends StatefulWidget {
  const _DriftingOrbs();

  @override
  State<_DriftingOrbs> createState() => _DriftingOrbsState();
}

class _DriftingOrbsState extends State<_DriftingOrbs>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => CustomPaint(painter: _OrbPainter(animation.value)),
  );
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .055);
    for (var i = 0; i < 5; i++) {
      final phase = t * math.pi * 2 + i * 1.7;
      canvas.drawCircle(
        Offset(
          size.width * (.35 + .12 * math.sin(phase)),
          size.height * (.16 + i * .18) + 13 * math.cos(phase * .8),
        ),
        18 + i * 5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => oldDelegate.t != t;
}

class EdgeWaveClipper extends CustomClipper<Path> {
  const EdgeWaveClipper(this.side);

  final EdgeWindowSide side;

  @override
  Path getClip(Size size) {
    if (side == EdgeWindowSide.right) {
      return Path()
        ..moveTo(94, 0)
        ..cubicTo(30, 75, 106, 132, 54, 205)
        ..cubicTo(10, 270, 104, 327, 55, 397)
        ..cubicTo(18, 455, 92, 512, 72, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0)
        ..close();
    }
    return Path()
      ..moveTo(size.width - 94, 0)
      ..cubicTo(
        size.width - 30,
        75,
        size.width - 106,
        132,
        size.width - 54,
        205,
      )
      ..cubicTo(
        size.width - 10,
        270,
        size.width - 104,
        327,
        size.width - 55,
        397,
      )
      ..cubicTo(
        size.width - 18,
        455,
        size.width - 92,
        512,
        size.width - 72,
        size.height,
      )
      ..lineTo(0, size.height)
      ..lineTo(0, 0)
      ..close();
  }

  @override
  bool shouldReclip(EdgeWaveClipper oldClipper) => oldClipper.side != side;
}
