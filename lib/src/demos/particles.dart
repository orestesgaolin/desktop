import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

const int _kParticleCount = 40000;

/// 40k GPU-instanced billboard sprites forming a spiral galaxy with
/// differential rotation, rendered with additive blending. The only
/// per-frame CPU work is one uniform buffer.
class ParticlesDemo extends GpuDemo {
  @override
  String get name => 'Galaxy Particles';
  @override
  String get subtitle => '${_kParticleCount ~/ 1000}k instanced sprites';
  @override
  String get hint => 'drag to orbit · scroll to zoom';
  @override
  IconData get icon => Icons.blur_circular;

  @override
  late final List<ShaderDoc> shaders = [
    ShaderDoc(
        name: 'ParticlesVertex',
        stage: 'vertex',
        asset: 'shaders/particles.vert'),
    ShaderDoc(
        name: 'ParticlesFragment',
        stage: 'fragment',
        asset: 'shaders/particles.frag'),
  ];

  late gpu.RenderPipeline _pipeline;
  late gpu.Shader _vert;
  late gpu.DeviceBuffer _corners;
  late gpu.DeviceBuffer _seeds;
  late UniformWriter _vertInfo;

  double _yaw = 0.9;
  double _pitch = 0.42;
  double _dist = 21.0;

  @override
  void init(gpu.ShaderLibrary library) {
    _vert = shaderOf(library, 'ParticlesVertex');
    final frag = shaderOf(library, 'ParticlesFragment');

    _pipeline = gpu.gpuContext.createRenderPipeline(
      _vert,
      frag,
      vertexLayout: gpu.VertexLayout(buffers: [
        gpu.VertexBuffer(strideInBytes: 8, attributes: [
          gpu.VertexAttribute(
              name: 'corner', format: gpu.VertexFormat.float32x2),
        ]),
        gpu.VertexBuffer(
          strideInBytes: 16,
          stepMode: gpu.VertexStepMode.instance,
          attributes: [
            gpu.VertexAttribute(name: 'seed', format: gpu.VertexFormat.float32x4),
          ],
        ),
      ]),
    );

    _corners = gpu.gpuContext.createDeviceBufferWithCopy(
      Float32List.fromList(<double>[-1, -1, 1, -1, -1, 1, 1, 1])
          .buffer
          .asByteData(),
    );

    final rng = math.Random(1337);
    final seeds = Float32List(_kParticleCount * 4);
    for (var i = 0; i < seeds.length; i++) {
      seeds[i] = rng.nextDouble();
    }
    _seeds = gpu.gpuContext.createDeviceBufferWithCopy(seeds.buffer.asByteData());

    _vertInfo = UniformWriter(_vert.getUniformSlot('VertInfo'));
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    _yaw += frame.dragDelta.dx * 0.008;
    _pitch = (_pitch + frame.dragDelta.dy * 0.008).clamp(0.03, 1.45);
    _dist = (_dist * math.exp(frame.scrollDelta * 0.0015)).clamp(3.5, 42.0);

    final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: target,
        clearValue: vm.Vector4(0.016, 0.020, 0.030, 1.0),
      ),
    ));

    pass.bindPipeline(_pipeline);
    pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(gpu.ColorBlendEquation(
      sourceColorBlendFactor: gpu.BlendFactor.one,
      destinationColorBlendFactor: gpu.BlendFactor.one,
      sourceAlphaBlendFactor: gpu.BlendFactor.zero,
      destinationAlphaBlendFactor: gpu.BlendFactor.one,
    ));

    final yaw = _yaw + frame.time * 0.03;
    final eye = vm.Vector3(
      math.cos(_pitch) * math.sin(yaw),
      math.sin(_pitch),
      math.cos(_pitch) * math.cos(yaw),
    )..scale(_dist);
    final view = vm.makeViewMatrix(eye, vm.Vector3.zero(), vm.Vector3(0, 1, 0));
    final proj = kClipCorrection *
        vm.makePerspectiveMatrix(55 * math.pi / 180, frame.aspect, 0.1, 200.0);
    final vm.Matrix4 viewProj = proj * view;
    final right = view.getRow(0);
    final up = view.getRow(1);

    _vertInfo
      ..setMat4('view_proj', viewProj)
      ..setVec4('cam_right', right.x, right.y, right.z, 0)
      ..setVec4('cam_up', up.x, up.y, up.z, 0)
      ..setFloat('time', frame.time)
      ..setFloat('size_scale', 1.0);
    pass.bindUniform(
        _vert.getUniformSlot('VertInfo'), _vertInfo.emplace(frame.transients));

    pass.bindVertexBuffer(
        gpu.BufferView(_corners,
            offsetInBytes: 0, lengthInBytes: _corners.sizeInBytes),
        slot: 0);
    pass.bindVertexBuffer(
        gpu.BufferView(_seeds,
            offsetInBytes: 0, lengthInBytes: _seeds.sizeInBytes),
        slot: 1);
    pass.draw(4, instanceCount: _kParticleCount);
  }
}
