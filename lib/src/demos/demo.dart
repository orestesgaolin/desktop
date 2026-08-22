import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame.dart';
import '../live_compiler.dart';

/// One editable shader source belonging to a demo.
class ShaderDoc {
  ShaderDoc({
    required this.name,
    required this.stage,
    this.asset,
    String? source,
  }) : source = source ?? '';

  /// Bundle entry name, e.g. 'TriangleVertex'. Must match what the demo's
  /// [GpuDemo.init] looks up in the compiled library.
  final String name;

  /// 'vertex' or 'fragment'.
  final String stage;

  /// Asset path holding the initial GLSL (e.g. 'shaders/triangle.vert'), or
  /// null when [source] is provided inline.
  final String? asset;

  /// The current (possibly user-edited) GLSL source.
  String source;

  String get label =>
      asset?.split('/').last ?? (stage == 'vertex' ? 'vert' : 'frag');
}

/// A self-contained Flutter GPU rendering demo.
///
/// Every demo's GLSL is compiled at runtime: sources (asset files or inline
/// strings, both user-editable) go through the SDK's `impellerc` and load
/// via `ShaderLibrary.fromBytes`. [init] then builds pipelines from the
/// fresh library; [render] encodes one frame.
abstract class GpuDemo {
  static final LiveShaderCompiler compiler = LiveShaderCompiler();

  String get name;
  String get subtitle;

  /// Short interaction hint shown as an overlay (empty = no interaction).
  String get hint => '';

  IconData get icon;

  /// Whether the shader editor should open automatically for this demo.
  bool get editorByDefault => false;

  /// The editable shader sources this demo is built from.
  List<ShaderDoc> get shaders;

  bool _ready = false;
  bool get isReady => _ready;

  Future<void>? _firstCompile;

  /// Loads sources and compiles the first pipeline. Idempotent while in
  /// flight or after success; a failure clears the cache so it can be
  /// retried.
  Future<void> ensureReady() {
    return _firstCompile ??= () async {
      try {
        for (final doc in shaders) {
          if (doc.source.isEmpty && doc.asset != null) {
            doc.source = await rootBundle.loadString(doc.asset!);
          }
        }
        final error = await recompile();
        if (error != null) {
          throw Exception(error);
        }
      } catch (_) {
        _firstCompile = null;
        rethrow;
      }
    }();
  }

  /// Compiles the current (possibly edited) sources and rebuilds pipelines.
  /// Returns null on success or the error text on failure; on failure the
  /// previously built pipelines stay active.
  Future<String?> recompile() async {
    final result = await compiler.compileBundle({
      for (final doc in shaders)
        doc.name: (stage: doc.stage, source: doc.source),
    });
    if (!result.ok) return result.errors;
    final library = await gpu.ShaderLibrary.fromBytes(result.bytes!);
    if (library == null) return 'Could not parse the compiled shader bundle';
    try {
      init(library);
    } catch (e) {
      return 'Pipeline rebuild failed: $e';
    }
    _ready = true;
    return null;
  }

  /// (Re)builds pipelines and static resources from a freshly compiled
  /// library. Called after every successful [recompile].
  @protected
  void init(gpu.ShaderLibrary library);

  /// Encode this frame. [target] is the surface color texture to end up in.
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame);
}

/// A gallery entry rendered by its own widget subtree (for example
/// flutter_scene's SceneView, which drives its own frame loop) instead of the
/// shared GpuSurfaceView. It has no editable shader documents.
abstract class WidgetHostedDemo extends GpuDemo {
  @override
  List<ShaderDoc> get shaders => const [];

  @override
  bool get isReady => true;

  @override
  Future<void> ensureReady() => Future.value();

  @override
  void init(gpu.ShaderLibrary library) {}

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {}

  /// Builds the viewport widget for this demo.
  Widget buildView(BuildContext context, PlaybackController playback);
}

gpu.Shader shaderOf(gpu.ShaderLibrary library, String name) {
  final shader = library[name];
  if (shader == null) {
    throw StateError('Shader bundle has no shader named "$name"');
  }
  return shader;
}
