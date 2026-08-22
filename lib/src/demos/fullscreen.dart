import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

/// A demo that renders one fullscreen fragment shader.
///
/// All fullscreen shaders share the same `FragInfo` uniform contract:
/// resolution (px), pointer (uv, y up), time (s), and four generic params
/// filled by [onFrame], which also owns any interaction state.
class FullscreenDemo extends GpuDemo {
  FullscreenDemo({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.shaderName,
    this.hint = '',
    this.onFrame,
  });

  @override
  final String name;
  @override
  final String subtitle;
  @override
  final String hint;
  @override
  final IconData icon;

  final String shaderName;
  final void Function(FrameContext frame, Float32List params)? onFrame;

  final Float32List _params = Float32List(4);

  late gpu.RenderPipeline _pipeline;
  late gpu.Shader _frag;
  late UniformWriter _fragInfo;

  @override
  void init(gpu.ShaderLibrary library) {
    final vert = shaderOf(library, 'FullscreenVertex');
    _frag = shaderOf(library, shaderName);
    _pipeline = gpu.gpuContext.createRenderPipeline(
      vert,
      _frag,
      vertexLayout: kFullscreenLayout,
    );
    _fragInfo = UniformWriter(_frag.getUniformSlot('FragInfo'));
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    onFrame?.call(frame, _params);

    final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: target,
        clearValue: vm.Vector4(0, 0, 0, 1),
      ),
    ));

    pass.bindPipeline(_pipeline);
    pass.bindVertexBuffer(fullscreenTriangle());

    _fragInfo
      ..setVec2('resolution', target.width.toDouble(), target.height.toDouble())
      ..setVec2('pointer', frame.pointerUv.dx, frame.pointerUv.dy)
      ..setFloat('time', frame.time)
      ..setFloat('param0', _params[0])
      ..setFloat('param1', _params[1])
      ..setFloat('param2', _params[2])
      ..setFloat('param3', _params[3]);
    pass.bindUniform(
        _frag.getUniformSlot('FragInfo'), _fragInfo.emplace(frame.transients));

    pass.draw(3);
  }
}
