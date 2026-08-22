import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart'
    show WidgetTexture, WidgetTextureController, WidgetUpdatePolicy;
import 'package:vector_math/vector_math.dart' as vm;

import 'demos/demo.dart';
import 'gpu_kit.dart';
import 'live_compiler.dart';

/// ShaderBuilder-style widgets for raw Flutter GPU.
///
/// [GpuShaderBox] renders a fragment shader in an ordinary widget box, the
/// Flutter GPU equivalent of flutter_shaders' `ShaderBuilder`+paint.
/// [GpuShaderSampler] applies a fragment shader over a live child widget,
/// the equivalent of `AnimatedSampler`: the child is captured with
/// flutter_scene's [WidgetTexture] (zero-copy, capture-on-repaint) and bound
/// as `uniform sampler2D u_child`; pointer input is forwarded to the child
/// through the capture controller, so buttons and sliders keep working
/// under the effect.
///
/// Fragment contract (same as the gallery demos):
/// ```glsl
/// uniform FragInfo {
///   vec2 resolution; vec2 pointer;  // pointer is uv space, y up
///   float time; float param0; float param1; float param2; float param3;
/// } u;
/// in vec2 v_uv;          // y up
/// out vec4 frag_color;   // premultiplied alpha
/// uniform sampler2D u_child;  // GpuShaderSampler only (required there)
/// ```
/// The surface is cleared to transparent, so shader alpha composites over
/// whatever is behind the widget.

/// Renders a runtime-compiled Flutter GPU fragment shader in a box.
class GpuShaderBox extends StatelessWidget {
  const GpuShaderBox({
    super.key,
    this.fragmentSource,
    this.fragmentAsset,
    this.onParams,
    this.paused = false,
    this.timeScale = 1.0,
    this.onTick,
  }) : assert(fragmentSource != null || fragmentAsset != null);

  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;
  final bool paused;
  final double timeScale;
  final void Function(double rawDt)? onTick;

  @override
  Widget build(BuildContext context) {
    return _GpuShaderSurface(
      fragmentSource: fragmentSource,
      fragmentAsset: fragmentAsset,
      onParams: onParams,
      paused: paused,
      timeScale: timeScale,
      onTick: onTick,
    );
  }
}

/// Applies a runtime-compiled Flutter GPU fragment shader over a live child
/// widget. The fragment shader must declare `uniform sampler2D u_child`.
class GpuShaderSampler extends StatefulWidget {
  const GpuShaderSampler({
    super.key,
    required this.child,
    this.fragmentSource,
    this.fragmentAsset,
    this.onParams,
    this.paused = false,
    this.timeScale = 1.0,
    this.interactive = true,
    this.capturePixelRatio = 2.0,
    this.onTick,
  }) : assert(fragmentSource != null || fragmentAsset != null);

  final Widget child;
  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;
  final bool paused;
  final double timeScale;

  /// Forward pointer input (taps, drags, scroll) to the hosted child at the
  /// same position, so the child stays fully interactive under the effect.
  final bool interactive;

  final double capturePixelRatio;
  final void Function(double rawDt)? onTick;

  @override
  State<GpuShaderSampler> createState() => _GpuShaderSamplerState();
}

class _GpuShaderSamplerState extends State<GpuShaderSampler> {
  final WidgetTextureController _capture = WidgetTextureController();

  Offset _uv(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      Widget surface = _GpuShaderSurface(
        fragmentSource: widget.fragmentSource,
        fragmentAsset: widget.fragmentAsset,
        onParams: widget.onParams,
        paused: widget.paused,
        timeScale: widget.timeScale,
        childTexture: _capture,
        onTick: widget.onTick,
      );
      if (widget.interactive) {
        surface = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _capture.pointerDown(_uv(e.localPosition, size)),
          onPointerMove: (e) => _capture.pointerMove(_uv(e.localPosition, size)),
          onPointerUp: (e) => _capture.pointerUp(_uv(e.localPosition, size)),
          onPointerCancel: (_) => _capture.pointerCancel(),
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _capture.pointerScroll(_uv(e.localPosition, size), e.scrollDelta);
            }
          },
          child: surface,
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          // Invisible live host: zero layout space, captures on repaint.
          WidgetTexture(
            controller: _capture,
            width: size.width,
            height: size.height,
            pixelRatio: widget.capturePixelRatio,
            update: WidgetUpdatePolicy.everyFrame,
            child: widget.child,
          ),
          surface,
        ],
      );
    });
  }
}

/// The shared core: compiles the fragment shader once, owns a
/// [gpu.GpuImageSurface] and a [Ticker], renders a fullscreen triangle per
/// frame, and paints the presented image.
class _GpuShaderSurface extends StatefulWidget {
  const _GpuShaderSurface({
    this.fragmentSource,
    this.fragmentAsset,
    this.onParams,
    required this.paused,
    required this.timeScale,
    this.childTexture,
    this.onTick,
  });

  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;
  final bool paused;
  final double timeScale;
  final WidgetTextureController? childTexture;
  final void Function(double rawDt)? onTick;

  @override
  State<_GpuShaderSurface> createState() => _GpuShaderSurfaceState();
}

class _GpuShaderSurfaceState extends State<_GpuShaderSurface>
    with SingleTickerProviderStateMixin {
  static final LiveShaderCompiler _compiler = GpuDemo.compiler;

  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final gpu.HostBuffer _transients = gpu.gpuContext.createHostBuffer();
  final Float32List _params = Float32List(4);

  gpu.RenderPipeline? _pipeline;
  gpu.Shader? _frag;
  UniformWriter? _fragInfo;
  String? _error;
  String? _compiledFor;

  gpu.GpuImageSurface? _surface;
  ui.Image? _image;
  double _time = 0;
  Duration? _lastElapsed;
  Size _size = Size.zero;
  double _dpr = 1;
  Offset _pointer = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _compile();
  }

  @override
  void didUpdateWidget(_GpuShaderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fragmentSource != widget.fragmentSource ||
        oldWidget.fragmentAsset != widget.fragmentAsset) {
      _compile();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _compile() async {
    final key = widget.fragmentSource ?? widget.fragmentAsset!;
    if (_compiledFor == key) return;
    _compiledFor = key;
    try {
      final source =
          widget.fragmentSource ?? await rootBundle.loadString(widget.fragmentAsset!);
      final result = await _compiler.compileBundle({
        'SurfaceVertex': (stage: 'vertex', source: kLiveVertexSource),
        'SurfaceFragment': (stage: 'fragment', source: source),
      });
      if (!mounted || _compiledFor != key) return;
      if (!result.ok) {
        setState(() => _error = result.errors);
        return;
      }
      final library = await gpu.ShaderLibrary.fromBytes(result.bytes!);
      final vert = library!['SurfaceVertex']!;
      final frag = library['SurfaceFragment']!;
      final pipeline = gpu.gpuContext.createRenderPipeline(
        vert,
        frag,
        vertexLayout: kFullscreenLayout,
      );
      final slot = frag.getUniformSlot('FragInfo');
      setState(() {
        _pipeline = pipeline;
        _frag = frag;
        _fragInfo =
            slot.sizeInBytes != null ? UniformWriter(slot, lenient: true) : null;
        _error = null;
      });
    } catch (e) {
      if (mounted && _compiledFor == key) setState(() => _error = '$e');
    }
  }

  void _onTick(Duration elapsed) {
    final rawDt = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (!mounted || _size.isEmpty) return;
    widget.onTick?.call(rawDt);

    final pipeline = _pipeline;
    if (pipeline == null) return;

    // flutter_scene's gpu barrel re-exports package:flutter_gpu verbatim on
    // native, but the analyzer resolves its conditional export to a stub, so
    // the capture texture needs a runtime cast to unify the types.
    final Object? childTextureObj = widget.childTexture?.texture;
    if (widget.childTexture != null && childTextureObj == null) {
      return; // Sampler with no capture yet.
    }
    final childTexture = childTextureObj as gpu.Texture?;

    _time += widget.paused ? 0 : rawDt * widget.timeScale;

    final w = (_size.width * _dpr).round().clamp(8, 8192);
    final h = (_size.height * _dpr).round().clamp(8, 8192);

    try {
      var surface = _surface;
      if (surface == null) {
        surface = _surface =
            gpu.gpuContext.createImageSurface(w, h, format: stableColorFormat());
      } else if (surface.width != w || surface.height != h) {
        surface.resize(w, h);
      }

      widget.onParams?.call(_params);

      final frame = surface.acquireNextFrame();
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      _transients.reset();
      try {
        final pass =
            commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: frame.colorTexture,
            clearValue: vm.Vector4.zero(),
          ),
        ));
        pass.bindPipeline(pipeline);
        pass.bindVertexBuffer(fullscreenTriangle());
        final fragInfo = _fragInfo;
        if (fragInfo != null) {
          fragInfo
            ..setVec2('resolution', w.toDouble(), h.toDouble())
            ..setVec2('pointer', (_pointer.dx / _size.width).clamp(0.0, 1.0),
                (1 - _pointer.dy / _size.height).clamp(0.0, 1.0))
            ..setFloat('time', _time)
            ..setFloat('param0', _params[0])
            ..setFloat('param1', _params[1])
            ..setFloat('param2', _params[2])
            ..setFloat('param3', _params[3]);
          pass.bindUniform(_frag!.getUniformSlot('FragInfo'),
              fragInfo.emplace(_transients));
        }
        if (childTexture != null) {
          pass.bindTexture(_frag!.getUniformSlot('u_child'), childTexture,
              sampler: gpu.SamplerOptions(
                minFilter: gpu.MinMagFilter.linear,
                magFilter: gpu.MinMagFilter.linear,
              ));
        }
        pass.draw(3);
      } catch (_) {
        frame.discard();
        rethrow;
      }
      frame.present(commandBuffer);
      commandBuffer.submit();

      final old = _image;
      _image = surface.currentImage;
      old?.dispose();
      _repaint.value++;
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
          padding: const EdgeInsets.all(12),
          child: SelectableText(_error!,
              style: const TextStyle(fontSize: 10, color: Color(0xFFA6543E))),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      _size = Size(constraints.maxWidth, constraints.maxHeight);
      return MouseRegion(
        onHover: (e) => _pointer = e.localPosition,
        child: CustomPaint(
          painter: _ImagePainter(_repaint, () => _image),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(Listenable repaint, this.imageProvider)
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
  bool shouldRepaint(_ImagePainter oldDelegate) => true;
}
