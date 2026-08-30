import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// When [GpuShaderBox.inputColor] or [GpuShaderSampler.inputColor] is set,
/// `param0..param3` contain its normalized red, green, blue, and alpha values.
/// The surface is cleared to transparent, so shader alpha composites over
/// whatever is behind the widget.

enum GpuShaderCompilePhase { compiling, succeeded, failed }

@immutable
class GpuShaderCompileStatus {
  const GpuShaderCompileStatus({
    required this.phase,
    this.elapsedMs,
    this.errors,
    this.hasPreviousOutput = false,
  });

  final GpuShaderCompilePhase phase;
  final int? elapsedMs;
  final String? errors;

  /// Whether the surface continues to paint a previously successful shader
  /// output while this status is active.
  final bool hasPreviousOutput;

  /// Whether a caller-provided initial fallback is needed to avoid an empty
  /// surface during the first compilation.
  bool get needsInitialFallback =>
      phase == GpuShaderCompilePhase.compiling && !hasPreviousOutput;
}

/// Coalesces and retains successful shader bundle compilations by source.
///
/// The cache contains bundle bytes, not element textures or uniforms. Several
/// frame instances can therefore reuse one compilation while continuing to
/// supply independent `u_child` textures and fill-color parameters.
@visibleForTesting
class GpuShaderBundleCache {
  GpuShaderBundleCache({this.maximumEntries = 32}) : assert(maximumEntries > 0);

  final int maximumEntries;
  final Map<String, Future<LiveCompileResult>> _entries = {};

  Future<LiveCompileResult> compile(
    String source,
    Future<LiveCompileResult> Function() compileSource,
  ) async {
    var compile = _entries[source];
    if (compile == null) {
      if (_entries.length >= maximumEntries) {
        _entries.remove(_entries.keys.first);
      }
      compile = compileSource();
      _entries[source] = compile;
    }
    final result = await compile;
    if (!result.ok && identical(_entries[source], compile)) {
      // A syntax error is normally followed by edited source. Removing failed
      // results also permits an unchanged source to retry a transient tool
      // failure when the caller increments its compilation revision.
      _entries.remove(source);
    }
    return result;
  }
}

/// Renders a runtime-compiled Flutter GPU fragment shader in a box.
class GpuShaderBox extends StatelessWidget {
  const GpuShaderBox({
    super.key,
    this.fragmentSource,
    this.fragmentAsset,
    this.onParams,
    this.inputColor,
    this.paused = false,
    this.timeScale = 1.0,
    this.rasterScale = 1.0,
    this.initialCompilingFallback,
    this.compilingOverlay,
    this.onTick,
  }) : assert(fragmentSource != null || fragmentAsset != null),
       assert(rasterScale > 0);

  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;

  /// Optional normalized RGBA input exposed as `u.param0..u.param3`.
  final Color? inputColor;
  final bool paused;
  final double timeScale;

  /// Additional physical resolution without changing layout or hit testing.
  /// Use this when an enclosing paint transform magnifies the shader output.
  final double rasterScale;

  /// Content painted during the first compilation, before any successful
  /// shader output exists. It is removed as soon as compilation finishes.
  final Widget? initialCompilingFallback;

  /// Optional overlay painted above the retained shader output while a new
  /// source or revision compiles. The unfiltered child is never substituted.
  final Widget? compilingOverlay;

  final void Function(double rawDt)? onTick;

  @override
  Widget build(BuildContext context) {
    return _GpuShaderSurface(
      fragmentSource: fragmentSource,
      fragmentAsset: fragmentAsset,
      onParams: onParams,
      inputColor: inputColor,
      paused: paused,
      timeScale: timeScale,
      rasterScale: rasterScale,
      initialCompilingFallback: initialCompilingFallback,
      compilingOverlay: compilingOverlay,
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
    this.inputColor,
    this.paused = false,
    this.timeScale = 1.0,
    this.interactive = true,
    this.capturePixelRatio = 2.0,
    this.rasterScale = 1.0,
    this.initialCompilingFallback,
    this.compilingOverlay,
    this.onTick,
    this.compilationRevision = 0,
    this.onCompileStatus,
  }) : assert(fragmentSource != null || fragmentAsset != null),
       assert(capturePixelRatio > 0),
       assert(rasterScale > 0);

  final Widget child;
  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;

  /// Optional normalized RGBA input exposed as `u.param0..u.param3`.
  ///
  /// The captured child remains the primary `u_child` input. This additional
  /// value lets a frame shader retain an element's semantic fill color even
  /// when its output does not directly sample every source pixel.
  final Color? inputColor;
  final bool paused;
  final double timeScale;

  /// Forward pointer input (taps, drags, scroll) to the hosted child at the
  /// same position, so the child stays fully interactive under the effect.
  final bool interactive;

  final double capturePixelRatio;

  /// Additional physical resolution for both the captured child and shader
  /// output. It does not affect logical size, input coordinates, or shader
  /// compilation. This keeps sampled widgets sharp under an outer zoom.
  final double rasterScale;

  /// Content painted during the first compilation, before any successful
  /// shader output exists. For a frame shader, pass the ordinary frame visual
  /// so applying the effect never produces an empty frame.
  final Widget? initialCompilingFallback;

  /// Optional overlay painted above the retained shader output while a new
  /// source or revision compiles. The captured child remains off-screen.
  final Widget? compilingOverlay;

  final void Function(double rawDt)? onTick;

  /// Increment to compile the current source again, even when its text did
  /// not change. This supports an explicit Compile button after a failed run.
  final int compilationRevision;

  final ValueChanged<GpuShaderCompileStatus>? onCompileStatus;

  @override
  State<GpuShaderSampler> createState() => _GpuShaderSamplerState();
}

class _GpuShaderSamplerState extends State<GpuShaderSampler> {
  final WidgetTextureController _capture = WidgetTextureController();
  final GlobalKey _childKey = GlobalKey();

  // ----- input forwarding -----
  //
  // The hosted subtree opts out of normal hit testing, so pointer events are
  // re-dispatched into it by hand. Unlike WidgetTextureController's
  // forwarding (which dispatches child-local positions and so breaks widgets
  // that do `globalToLocal(details.globalPosition)` math, e.g. Slider), the
  // hit path here carries the child's global transform and events use true
  // screen coordinates — both globalPosition and localPosition come out
  // right, so drags on sliders work.
  static int _nextSyntheticPointer = 0x48000000;
  int? _pointer;
  HitTestResult? _path;
  Offset _last = Offset.zero;

  RenderBox? get _childBox {
    final render = _childKey.currentContext?.findRenderObject();
    return render is RenderBox && render.hasSize ? render : null;
  }

  (HitTestResult, Offset)? _hit(Offset local) {
    final box = _childBox;
    if (box == null) return null;
    final childToGlobal = box.getTransformTo(null);
    final global = MatrixUtils.transformPoint(childToGlobal, local);
    final result = BoxHitTestResult();
    result.addWithPaintTransform(
      transform: childToGlobal,
      position: global,
      hitTest: (result, position) => box.hitTest(result, position: position),
    );
    // The trailing binding entry routes the event into the pointer router
    // and closes the gesture arena, mirroring the live pointer pipeline.
    result.add(HitTestEntry(GestureBinding.instance));
    return (result, global);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) _cancel();
    final hit = _hit(e.localPosition);
    if (hit == null) return;
    final (path, global) = hit;
    _pointer = _nextSyntheticPointer++;
    _path = path;
    _last = global;
    GestureBinding.instance.dispatchEvent(
      PointerDownEvent(
        pointer: _pointer!,
        position: global,
        kind: PointerDeviceKind.touch,
      ),
      path,
    );
  }

  void _move(PointerMoveEvent e) {
    final pointer = _pointer;
    final path = _path;
    final box = _childBox;
    if (pointer == null || path == null || box == null) return;
    final global = MatrixUtils.transformPoint(
      box.getTransformTo(null),
      e.localPosition,
    );
    GestureBinding.instance.dispatchEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: global,
        delta: global - _last,
        kind: PointerDeviceKind.touch,
      ),
      path,
    );
    _last = global;
  }

  void _up(PointerUpEvent e) {
    final pointer = _pointer;
    final path = _path;
    _pointer = null;
    _path = null;
    if (pointer == null || path == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerUpEvent(
        pointer: pointer,
        position: _last,
        kind: PointerDeviceKind.touch,
      ),
      path,
    );
  }

  void _cancel() {
    final pointer = _pointer;
    final path = _path;
    _pointer = null;
    _path = null;
    if (pointer == null || path == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerCancelEvent(
        pointer: pointer,
        position: _last,
        kind: PointerDeviceKind.touch,
      ),
      path,
    );
  }

  void _scroll(PointerScrollEvent e) {
    final hit = _hit(e.localPosition);
    if (hit == null) return;
    final (path, global) = hit;
    GestureBinding.instance.dispatchEvent(
      PointerScrollEvent(position: global, scrollDelta: e.scrollDelta),
      path,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        Widget surface = _GpuShaderSurface(
          fragmentSource: widget.fragmentSource,
          fragmentAsset: widget.fragmentAsset,
          onParams: widget.onParams,
          inputColor: widget.inputColor,
          paused: widget.paused,
          timeScale: widget.timeScale,
          rasterScale: widget.rasterScale,
          initialCompilingFallback: widget.initialCompilingFallback,
          compilingOverlay: widget.compilingOverlay,
          childTexture: _capture,
          onTick: widget.onTick,
          compilationRevision: widget.compilationRevision,
          onCompileStatus: widget.onCompileStatus,
        );
        if (widget.interactive) {
          surface = Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: (_) => _cancel(),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _scroll(e);
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
              pixelRatio: widget.capturePixelRatio * widget.rasterScale,
              update: WidgetUpdatePolicy.everyFrame,
              child: KeyedSubtree(key: _childKey, child: widget.child),
            ),
            surface,
          ],
        );
      },
    );
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
    this.inputColor,
    required this.paused,
    required this.timeScale,
    required this.rasterScale,
    this.initialCompilingFallback,
    this.compilingOverlay,
    this.childTexture,
    this.onTick,
    this.compilationRevision = 0,
    this.onCompileStatus,
  });

  final String? fragmentSource;
  final String? fragmentAsset;
  final void Function(Float32List params)? onParams;
  final Color? inputColor;
  final bool paused;
  final double timeScale;
  final double rasterScale;
  final Widget? initialCompilingFallback;
  final Widget? compilingOverlay;
  final WidgetTextureController? childTexture;
  final void Function(double rawDt)? onTick;
  final int compilationRevision;
  final ValueChanged<GpuShaderCompileStatus>? onCompileStatus;

  @override
  State<_GpuShaderSurface> createState() => _GpuShaderSurfaceState();
}

class _GpuShaderSurfaceState extends State<_GpuShaderSurface>
    with SingleTickerProviderStateMixin {
  static final LiveShaderCompiler _compiler = GpuDemo.compiler;
  static final GpuShaderBundleCache _bundleCache = GpuShaderBundleCache();

  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final gpu.HostBuffer _transients = gpu.gpuContext.createHostBuffer();
  final Float32List _params = Float32List(4);

  gpu.RenderPipeline? _pipeline;
  gpu.Shader? _frag;
  UniformWriter? _fragInfo;
  String? _error;
  String? _compiledFor;
  bool _compiling = false;
  bool _hasPreviousOutputForCompile = false;

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
        oldWidget.fragmentAsset != widget.fragmentAsset ||
        oldWidget.compilationRevision != widget.compilationRevision) {
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
    final sourceKey = widget.fragmentSource ?? widget.fragmentAsset!;
    final key = '${widget.compilationRevision}:$sourceKey';
    if (_compiledFor == key) return;
    _compiledFor = key;
    _compiling = true;
    final hasPreviousOutput = _pipeline != null && _image != null;
    _hasPreviousOutputForCompile = hasPreviousOutput;
    void report(GpuShaderCompileStatus status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _compiledFor == key) {
          widget.onCompileStatus?.call(status);
        }
      });
    }

    report(
      GpuShaderCompileStatus(
        phase: GpuShaderCompilePhase.compiling,
        hasPreviousOutput: hasPreviousOutput,
      ),
    );
    try {
      final source =
          widget.fragmentSource ??
          await rootBundle.loadString(widget.fragmentAsset!);
      final result = await _bundleCache.compile(
        source,
        () => _compiler.compileBundle({
          'SurfaceVertex': (stage: 'vertex', source: kLiveVertexSource),
          'SurfaceFragment': (stage: 'fragment', source: source),
        }),
      );
      if (!mounted || _compiledFor != key) return;
      if (!result.ok) {
        setState(() {
          _compiling = false;
          _error = result.errors;
        });
        report(
          GpuShaderCompileStatus(
            phase: GpuShaderCompilePhase.failed,
            elapsedMs: result.elapsedMs,
            errors: result.errors,
            hasPreviousOutput: hasPreviousOutput,
          ),
        );
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
        _compiling = false;
        _pipeline = pipeline;
        _frag = frag;
        _fragInfo = slot.sizeInBytes != null
            ? UniformWriter(slot, lenient: true)
            : null;
        _error = null;
      });
      report(
        GpuShaderCompileStatus(
          phase: GpuShaderCompilePhase.succeeded,
          elapsedMs: result.elapsedMs,
        ),
      );
    } catch (e) {
      if (mounted && _compiledFor == key) {
        setState(() {
          _compiling = false;
          _error = '$e';
        });
        report(
          GpuShaderCompileStatus(
            phase: GpuShaderCompilePhase.failed,
            errors: '$e',
            hasPreviousOutput: hasPreviousOutput,
          ),
        );
      }
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

    final physicalScale = _dpr * widget.rasterScale;
    final w = (_size.width * physicalScale).round().clamp(8, 8192);
    final h = (_size.height * physicalScale).round().clamp(8, 8192);

    try {
      var surface = _surface;
      if (surface == null) {
        surface = _surface = gpu.gpuContext.createImageSurface(
          w,
          h,
          format: stableColorFormat(),
        );
      } else if (surface.width != w || surface.height != h) {
        surface.resize(w, h);
      }

      _params.fillRange(0, _params.length, 0);
      final inputColor = widget.inputColor;
      if (inputColor != null) {
        _params
          ..[0] = inputColor.r
          ..[1] = inputColor.g
          ..[2] = inputColor.b
          ..[3] = inputColor.a;
      }
      widget.onParams?.call(_params);

      final frame = surface.acquireNextFrame();
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      _transients.reset();
      try {
        final pass = commandBuffer.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(
              texture: frame.colorTexture,
              clearValue: vm.Vector4.zero(),
            ),
          ),
        );
        pass.bindPipeline(pipeline);
        pass.bindVertexBuffer(fullscreenTriangle());
        final fragInfo = _fragInfo;
        if (fragInfo != null) {
          fragInfo
            ..setVec2('resolution', w.toDouble(), h.toDouble())
            ..setVec2(
              'pointer',
              (_pointer.dx / _size.width).clamp(0.0, 1.0),
              (1 - _pointer.dy / _size.height).clamp(0.0, 1.0),
            )
            ..setFloat('time', _time)
            ..setFloat('param0', _params[0])
            ..setFloat('param1', _params[1])
            ..setFloat('param2', _params[2])
            ..setFloat('param3', _params[3]);
          pass.bindUniform(
            _frag!.getUniformSlot('FragInfo'),
            fragInfo.emplace(_transients),
          );
        }
        if (childTexture != null) {
          pass.bindTexture(
            _frag!.getUniformSlot('u_child'),
            childTexture,
            sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear,
            ),
          );
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
    final Widget output;
    if (_error != null && _pipeline == null) {
      output = Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _error!,
            style: const TextStyle(fontSize: 10, color: Color(0xFFA6543E)),
          ),
        ),
      );
    } else {
      output = LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, constraints.maxHeight);
          return MouseRegion(
            onHover: (e) => _pointer = e.localPosition,
            child: CustomPaint(
              painter: _ImagePainter(_repaint, () => _image),
              child: const SizedBox.expand(),
            ),
          );
        },
      );
    }
    Widget visibleContent = output;
    final fallback = widget.initialCompilingFallback;
    if (_compiling && !_hasPreviousOutputForCompile && fallback != null) {
      visibleContent = SizedBox.expand(child: fallback);
    }
    final overlay = widget.compilingOverlay;
    if (!_compiling || overlay == null) return visibleContent;
    return Stack(
      fit: StackFit.expand,
      children: [
        visibleContent,
        IgnorePointer(child: overlay),
      ],
    );
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
