import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

/// The mandatory "hello triangle", animated entirely on the GPU.
class TriangleDemo extends GpuDemo {
  @override
  String get name => 'Hello Triangle';
  @override
  String get subtitle => 'One draw call, two shaders';
  @override
  IconData get icon => Icons.change_history;

  @override
  late final List<ShaderDoc> shaders = [
    ShaderDoc(
        name: 'TriangleVertex',
        stage: 'vertex',
        asset: 'shaders/triangle.vert'),
    ShaderDoc(
        name: 'TriangleFragment',
        stage: 'fragment',
        asset: 'shaders/triangle.frag'),
  ];

  late gpu.RenderPipeline _pipeline;
  late gpu.Shader _vert;
  late gpu.Shader _frag;
  late gpu.DeviceBuffer _vertices;
  late UniformWriter _vertInfo;
  late UniformWriter _fragInfo;

  @override
  void init(gpu.ShaderLibrary library) {
    _vert = shaderOf(library, 'TriangleVertex');
    _frag = shaderOf(library, 'TriangleFragment');
    _pipeline = gpu.gpuContext.createRenderPipeline(
      _vert,
      _frag,
      vertexLayout: gpu.VertexLayout(buffers: [
        gpu.VertexBuffer(strideInBytes: 20, attributes: [
          gpu.VertexAttribute(
              name: 'position', format: gpu.VertexFormat.float32x2),
          gpu.VertexAttribute(
              name: 'color',
              format: gpu.VertexFormat.float32x3,
              offsetInBytes: 8),
        ]),
      ]),
    );

    // x, y, r, g, b — dusty blue, sage, clay.
    _vertices = gpu.gpuContext.createDeviceBufferWithCopy(
      Float32List.fromList(<double>[
        0.00, 0.66, 0.42, 0.53, 0.62, //
        -0.57, -0.33, 0.56, 0.63, 0.53, //
        0.57, -0.33, 0.76, 0.58, 0.46, //
      ]).buffer.asByteData(),
    );

    _vertInfo = UniformWriter(_vert.getUniformSlot('VertInfo'));
    _fragInfo = UniformWriter(_frag.getUniformSlot('FragInfo'));
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: target,
        clearValue: vm.Vector4(0.937, 0.925, 0.902, 1.0),
      ),
    ));

    pass.bindPipeline(_pipeline);
    pass.bindVertexBuffer(gpu.BufferView(_vertices,
        offsetInBytes: 0, lengthInBytes: _vertices.sizeInBytes));

    _vertInfo
      ..setFloat('time', frame.time)
      ..setFloat('aspect', frame.aspect);
    pass.bindUniform(
        _vert.getUniformSlot('VertInfo'), _vertInfo.emplace(frame.transients));

    _fragInfo.setFloat('time', frame.time);
    pass.bindUniform(
        _frag.getUniformSlot('FragInfo'), _fragInfo.emplace(frame.transients));

    pass.draw(3);
  }
}
