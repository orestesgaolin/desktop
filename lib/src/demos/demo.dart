import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame.dart';

/// A self-contained Flutter GPU rendering demo.
///
/// Demos create their pipelines and static buffers once in [init], then
/// encode one or more render passes into the provided command buffer every
/// frame in [render].
abstract class GpuDemo {
  String get name;
  String get subtitle;

  /// Short interaction hint shown as an overlay (empty = no interaction).
  String get hint => '';

  IconData get icon;

  bool _ready = false;
  bool get isReady => _ready;

  void ensureReady(gpu.ShaderLibrary library) {
    if (_ready) return;
    init(library);
    _ready = true;
  }

  @protected
  void init(gpu.ShaderLibrary library);

  /// Encode this frame. [target] is the surface color texture to end up in.
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame);
}

gpu.Shader shaderOf(gpu.ShaderLibrary library, String name) {
  final shader = library[name];
  if (shader == null) {
    throw StateError('Shader bundle has no shader named "$name"');
  }
  return shader;
}
