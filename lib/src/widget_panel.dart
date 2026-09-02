import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'demos/widget_stage.dart';

const _panelBg = Color(0xFFF5F3EE);
const _cardBg = Color(0xFFFDFCFA);
const _dim = Color(0xFF8B8578);
const _accent = Color(0xFF4F6F6A);

/// The real, interactive widgets that feed the Widget Stage demo.
///
/// One card per frame (round-robin) is snapshotted with
/// [RenderRepaintBoundary.toImage] — a texture-backed image on Impeller —
/// and wrapped zero-copy into a [gpu.Texture] via [gpu.Texture.fromImage],
/// then handed to [WidgetStageDemo.setCard].
class WidgetSourcePanel extends StatefulWidget {
  const WidgetSourcePanel({
    super.key,
    required this.demo,
    this.width = 312,
    this.margin = const EdgeInsets.fromLTRB(0, 0, 14, 14),
  });

  final WidgetStageDemo demo;
  final double? width;
  final EdgeInsets margin;

  @override
  State<WidgetSourcePanel> createState() => _WidgetSourcePanelState();
}

class _WidgetSourcePanelState extends State<WidgetSourcePanel>
    with TickerProviderStateMixin {
  final List<GlobalKey> _boundaryKeys =
      List.generate(kStageCardCount, (_) => GlobalKey());

  late final Ticker _captureTicker;
  late final AnimationController _progress;
  Timer? _clockTimer;

  int _nextCapture = 0;
  bool _captureInFlight = false;

  // Widget state that the user can poke at.
  bool _following = false;
  bool _bloom = true;
  bool _particles = false;
  double _hue = 190;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _captureTicker = createTicker((_) => _captureNext())..start();
    widget.demo.onCardTap = _pressRealWidget;
  }

  @override
  void dispose() {
    if (widget.demo.onCardTap == _pressRealWidget) {
      widget.demo.onCardTap = null;
    }
    _captureTicker.dispose();
    _progress.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  int _syntheticPointer = 0x3f000000;

  /// A tap on a 3D card maps back to the real widget: convert the card-local
  /// fraction into this panel's on-screen coordinates and dispatch a pointer
  /// down/up pair through the Flutter view that owns the source widget.
  void _pressRealWidget(int index, Offset fraction) {
    final renderObject =
        _boundaryKeys[index].currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
      return;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final position = topLeft +
        Offset(fraction.dx * renderObject.size.width,
            fraction.dy * renderObject.size.height);
    final viewId = View.of(context).viewId;
    final pointer = _syntheticPointer++;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      viewId: viewId,
      pointer: pointer,
      position: position,
      kind: PointerDeviceKind.touch,
    ));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      viewId: viewId,
      pointer: pointer,
      position: position,
      kind: PointerDeviceKind.touch,
    ));
  }

  Future<void> _captureNext() async {
    if (_captureInFlight) return;
    final index = _nextCapture;
    _nextCapture = (_nextCapture + 1) % kStageCardCount;

    final renderObject =
        _boundaryKeys[index].currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;

    _captureInFlight = true;
    try {
      // Texture-backed on Impeller; 2x for crispness in the 3D scene.
      final image = await renderObject.toImage(pixelRatio: 2.0);
      gpu.Texture texture;
      try {
        // Fast path: wrap the image's backing texture, zero copy.
        texture = gpu.Texture.fromImage(gpu.gpuContext, image);
      } catch (_) {
        // The backing texture has a format flutter_gpu cannot wrap (for
        // example a wide-gamut snapshot). Fall back to one CPU copy.
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) {
          image.dispose();
          return;
        }
        texture = gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible,
          image.width,
          image.height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt,
          enableRenderTargetUsage: false,
        );
        texture.overwrite(rgba);
      }
      widget.demo.setCard(index, texture, image);
    } catch (_) {
      // Not painted yet, or the copy failed; retry on a later frame.
    } finally {
      _captureInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = HSLColor.fromAHSL(1, _hue, 0.45, 0.42).toColor();
    return Container(
      width: widget.width,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1A2C2E31)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('LIVE WIDGETS',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: _accent)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Real Material widgets — poke them. Each frame one card is '
              'snapshotted (RepaintBoundary.toImage) and wrapped zero-copy '
              'into a gpu.Texture on the stage.',
              style: TextStyle(fontSize: 11, color: _dim, height: 1.45),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _boundary(0, _nowPlayingCard()),
                const SizedBox(height: 12),
                _boundary(1, _profileCard()),
                const SizedBox(height: 12),
                _boundary(2, _togglesCard()),
                const SizedBox(height: 12),
                _boundary(3, _clockCard(accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boundary(int index, Widget child) {
    return RepaintBoundary(
      key: _boundaryKeys[index],
      child: SizedBox(height: 128, child: child),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x212C2E31)),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _nowPlayingCard() {
    return _card(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF4F6F6A), Color(0xFFC6947A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.music_note,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Neon Drive',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const Text('Impeller FM',
                    style: TextStyle(fontSize: 11.5, color: _dim)),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress.value,
                      minHeight: 5,
                      backgroundColor: const Color(0x142C2E31),
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return _card(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: Color(0xFFE6E2D9),
            child: Text('DK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dominik',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('ships pixels', style: TextStyle(fontSize: 11.5, color: _dim)),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => setState(() => _following = !_following),
            style: FilledButton.styleFrom(
              backgroundColor:
                  _following ? const Color(0xFFE6E2D9) : _accent,
              foregroundColor: _following ? const Color(0xFF2C2E31) : Colors.white,
              visualDensity: VisualDensity.compact,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: Text(_following ? 'Following' : 'Follow'),
          ),
        ],
      ),
    );
  }

  Widget _togglesCard() {
    return _card(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toggleRow('Bloom', Icons.flare, _bloom,
              (v) => setState(() => _bloom = v)),
          const SizedBox(height: 6),
          _toggleRow('Particles', Icons.grain, _particles,
              (v) => setState(() => _particles = v)),
        ],
      ),
    );
  }

  Widget _toggleRow(
      String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Icon(icon, size: 17, color: value ? _accent : _dim),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        Switch(value: value, onChanged: onChanged, activeThumbColor: _accent),
      ],
    );
  }

  Widget _clockCard(Color accent) {
    String two(int n) => n.toString().padLeft(2, '0');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(
                '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
                style: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const Spacer(),
              Icon(Icons.palette_outlined, size: 16, color: accent),
            ],
          ),
          Slider(
            value: _hue,
            min: 0,
            max: 360,
            activeColor: accent,
            onChanged: (v) => setState(() => _hue = v),
          ),
        ],
      ),
    );
  }
}
