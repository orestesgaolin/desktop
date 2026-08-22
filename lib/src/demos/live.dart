import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

/// The starting source shown in the live editor: glowing neon orbit rings
/// plus a light that follows the pointer.
const String kLiveTemplate = '''
// Live GLSL, ShaderToy style. Edit and press Run (cmd+enter).
// Contract: this FragInfo block (members are optional), `in vec2 v_uv`
// with y up, and an opaque `out vec4 frag_color`.
uniform FragInfo {
  vec2 resolution;  // viewport in pixels
  vec2 pointer;     // pointer, uv space (y up)
  float time;       // seconds (respects the speed slider)
  float param0; float param1; float param2; float param3;
} u;

in vec2 v_uv;
out vec4 frag_color;

vec3 palette(float t) {
  return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void main() {
  float aspect = u.resolution.x / u.resolution.y;
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0);
  vec2 m = (u.pointer - 0.5) * vec2(aspect, 1.0);

  vec3 col = vec3(0.0);
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    vec2 q = p;
    q.x += 0.30 * sin(u.time * 0.7 + fi * 1.7);
    q.y += 0.30 * cos(u.time * 0.9 + fi * 2.3);
    float d = abs(length(q) - 0.24 - 0.05 * fi) + 0.012;
    col += palette(fi * 0.19 + u.time * 0.08) * (0.010 / d);
  }
  col += vec3(0.85, 0.95, 1.0) * (0.02 / (length(p - m) + 0.03));

  frag_color = vec4(col, 1.0);
}
''';

/// A demo whose pipeline is compiled at runtime from user-typed GLSL
/// (via `impellerc` + [gpu.ShaderLibrary.fromBytes]). The editor panel owns
/// compilation; this class only swaps pipelines and renders.
class LiveShaderDemo extends GpuDemo {
  @override
  String get name => 'Live Editor';
  @override
  String get subtitle => 'Runtime-compiled GLSL, ShaderToy style';
  @override
  String get hint => 'edit the GLSL on the right · cmd+enter runs it';
  @override
  IconData get icon => Icons.code;

  /// Editor state lives on the demo so it survives switching tiles.
  String source = kLiveTemplate;
  bool hasCompiledOnce = false;

  gpu.RenderPipeline? _pipeline;
  UniformWriter? _fragInfo;
  gpu.Shader? _frag;

  @override
  void init(gpu.ShaderLibrary library) {
    // Nothing to prepare: pipelines arrive from the editor via [apply].
  }

  /// Builds a pipeline from a freshly compiled shader bundle and swaps it in.
  /// Throws if the bundle cannot be parsed or the pipeline cannot be built;
  /// the previous pipeline stays active in that case.
  Future<void> apply(ByteData bundleBytes) async {
    final library = await gpu.ShaderLibrary.fromBytes(bundleBytes);
    if (library == null) {
      throw Exception('Could not parse the compiled shader bundle');
    }
    final vert = library['LiveVertex'];
    final frag = library['LiveFragment'];
    if (vert == null || frag == null) {
      throw Exception('Compiled bundle is missing the Live shaders');
    }
    final pipeline = gpu.gpuContext.createRenderPipeline(
      vert,
      frag,
      vertexLayout: kFullscreenLayout,
    );
    final slot = frag.getUniformSlot('FragInfo');
    _fragInfo = slot.sizeInBytes != null
        ? UniformWriter(slot, lenient: true)
        : null;
    _frag = frag;
    _pipeline = pipeline;
    hasCompiledOnce = true;
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: target,
        clearValue: vm.Vector4(0.016, 0.018, 0.026, 1.0),
      ),
    ));

    final pipeline = _pipeline;
    if (pipeline == null) return; // Nothing compiled yet: just the clear.

    try {
      pass.bindPipeline(pipeline);
      pass.bindVertexBuffer(fullscreenTriangle());
      final fragInfo = _fragInfo;
      if (fragInfo != null) {
        fragInfo
          ..setVec2('resolution', target.width.toDouble(),
              target.height.toDouble())
          ..setVec2('pointer', frame.pointerUv.dx, frame.pointerUv.dy)
          ..setFloat('time', frame.time)
          ..setFloat('param0', 0)
          ..setFloat('param1', 0)
          ..setFloat('param2', 0)
          ..setFloat('param3', 0);
        pass.bindUniform(
            _frag!.getUniformSlot('FragInfo'), fragInfo.emplace(frame.transients));
      }
      pass.draw(3);
    } catch (_) {
      // Drop a pipeline that fails to encode so the next frame is clean.
      _pipeline = null;
      _fragInfo = null;
      rethrow;
    }
  }
}
