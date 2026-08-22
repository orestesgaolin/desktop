import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'demos/demo.dart';
import 'frame.dart';
import 'gpu_kit.dart';

/// Hosts a [GpuDemo]: owns the GPU image surface sized to the widget,
/// drives a frame loop with a [Ticker], gathers pointer input, and paints
/// the presented image.
class GpuSurfaceView extends StatefulWidget {
  const GpuSurfaceView({
    super.key,
    required this.demo,
    required this.playback,
    required this.library,
  });

  final GpuDemo demo;
  final PlaybackController playback;
  final gpu.ShaderLibrary library;

  @override
  State<GpuSurfaceView> createState() => _GpuSurfaceViewState();
}

class _GpuSurfaceViewState extends State<GpuSurfaceView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final gpu.HostBuffer _transients = gpu.gpuContext.createHostBuffer();

  gpu.GpuImageSurface? _surface;
  ui.Image? _image;
  String? _error;

  double _time = 0;
  Duration? _lastElapsed;
  double _fps = 0;
  int _statFrames = 0;

  Size _size = Size.zero;
  double _dpr = 1;

  Offset _pointer = Offset.zero;
  bool _pointerDown = false;
  Offset _pendingDrag = Offset.zero;
  double _pendingScroll = 0;
  double _dragDistance = 0;
  Offset? _pendingTapUv;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(GpuSurfaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.demo != widget.demo) {
      _pendingDrag = Offset.zero;
      _pendingScroll = 0;
      _time = 0;
      if (_error != null) {
        _error = null;
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dtRaw = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    if (!mounted || _size.isEmpty) return;

    final playback = widget.playback;
    final scale = playback.renderScale * _dpr;
    final w = (_size.width * scale).round().clamp(8, 8192);
    final h = (_size.height * scale).round().clamp(8, 8192);

    try {
      var surface = _surface;
      if (surface == null) {
        surface = _surface =
            gpu.gpuContext.createImageSurface(w, h, format: stableColorFormat());
      } else if (surface.width != w || surface.height != h) {
        surface.resize(w, h);
      }

      widget.demo.ensureReady(widget.library);

      final dt = playback.paused ? 0.0 : dtRaw * playback.speed;
      _time += dt;

      _transients.reset();
      final frame = FrameContext(
        transients: _transients,
        time: _time,
        dt: dt,
        widthPx: w,
        heightPx: h,
        sizeLogical: _size,
        pointerUv: Offset(
          (_pointer.dx / _size.width).clamp(0.0, 1.0),
          (1 - _pointer.dy / _size.height).clamp(0.0, 1.0),
        ),
        pointerDown: _pointerDown,
        dragDelta: _pendingDrag,
        scrollDelta: _pendingScroll,
        tapUv: _pendingTapUv,
      );
      _pendingDrag = Offset.zero;
      _pendingScroll = 0;
      _pendingTapUv = null;

      final surfaceFrame = surface.acquireNextFrame();
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      try {
        widget.demo.render(commandBuffer, surfaceFrame.colorTexture, frame);
      } catch (_) {
        surfaceFrame.discard();
        rethrow;
      }
      surfaceFrame.present(commandBuffer);
      commandBuffer.submit();

      final old = _image;
      _image = surface.currentImage;
      old?.dispose();
      _repaint.value++;

      if (dtRaw > 0) {
        _fps = _fps == 0 ? 1 / dtRaw : _fps * 0.95 + (1 / dtRaw) * 0.05;
      }
      if (++_statFrames >= 20) {
        _statFrames = 0;
        playback.stats.value = '${_fps.round()} fps · $w×$h';
      }
    } catch (e) {
      _ticker.stop();
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 40),
              const SizedBox(height: 12),
              Text('Render error in "${widget.demo.name}"',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(_error!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _ticker.start();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Resume'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      _size = Size(constraints.maxWidth, constraints.maxHeight);
      return Listener(
        onPointerHover: (e) => _pointer = e.localPosition,
        onPointerDown: (e) {
          _pointerDown = true;
          _pointer = e.localPosition;
          _dragDistance = 0;
        },
        onPointerMove: (e) {
          _pointer = e.localPosition;
          _pendingDrag += e.delta;
          _dragDistance += e.delta.distance;
        },
        onPointerUp: (e) {
          _pointerDown = false;
          if (_dragDistance < 8 && !_size.isEmpty) {
            _pendingTapUv = Offset(
              (e.localPosition.dx / _size.width).clamp(0.0, 1.0),
              (1 - e.localPosition.dy / _size.height).clamp(0.0, 1.0),
            );
          }
        },
        onPointerCancel: (_) => _pointerDown = false,
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _pendingScroll += e.scrollDelta.dy;
        },
        child: CustomPaint(
          painter: _SurfacePainter(_repaint, () => _image),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

class _SurfacePainter extends CustomPainter {
  _SurfacePainter(Listenable repaint, this.imageProvider)
      : super(repaint: repaint);

  final ui.Image? Function() imageProvider;

  @override
  void paint(Canvas canvas, Size size) {
    final image = imageProvider();
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SurfacePainter oldDelegate) => true;
}
