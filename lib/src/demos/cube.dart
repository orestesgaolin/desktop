import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

/// Depth-tested, back-face-culled, 4x MSAA spinning cube with a neon
/// procedural surface. Drag to take over the rotation.
class CubeDemo extends GpuDemo {
  @override
  String get name => 'Neon Cube';
  @override
  String get subtitle => 'Depth buffer, culling, 4x MSAA';
  @override
  String get hint => 'drag to rotate';
  @override
  IconData get icon => Icons.view_in_ar;

  late gpu.RenderPipeline _pipeline;
  late gpu.Shader _vert;
  late gpu.Shader _frag;
  late gpu.DeviceBuffer _vertices;
  late gpu.DeviceBuffer _indices;
  late UniformWriter _vertInfo;
  late UniformWriter _fragInfo;
  late bool _msaa;

  gpu.Texture? _depth;
  gpu.Texture? _msaaColor;

  double _yawExtra = 0;
  double _pitchExtra = 0;

  @override
  void init(gpu.ShaderLibrary library) {
    _vert = shaderOf(library, 'CubeVertex');
    _frag = shaderOf(library, 'CubeFragment');
    _msaa = gpu.gpuContext.doesSupportOffscreenMSAA;

    _pipeline = gpu.gpuContext.createRenderPipeline(
      _vert,
      _frag,
      vertexLayout: gpu.VertexLayout(buffers: [
        gpu.VertexBuffer(strideInBytes: 24, attributes: [
          gpu.VertexAttribute(
              name: 'position', format: gpu.VertexFormat.float32x3),
          gpu.VertexAttribute(
              name: 'normal',
              format: gpu.VertexFormat.float32x3,
              offsetInBytes: 12),
        ]),
      ]),
    );

    _buildGeometry();
    _vertInfo = UniformWriter(_vert.getUniformSlot('VertInfo'));
    _fragInfo = UniformWriter(_frag.getUniformSlot('FragInfo'));
  }

  void _buildGeometry() {
    final verts = <double>[];
    // Each face: normal n and tangent basis (u, v) with cross(u, v) == n so
    // that the corner order below is counter-clockwise seen from outside.
    void face(vm.Vector3 n, vm.Vector3 u, vm.Vector3 v) {
      const corners = <List<double>>[
        [-1, -1],
        [1, -1],
        [1, 1],
        [-1, 1],
      ];
      for (final c in corners) {
        final p = n + u * c[0] + v * c[1];
        verts.addAll([p.x, p.y, p.z, n.x, n.y, n.z]);
      }
    }

    face(vm.Vector3(1, 0, 0), vm.Vector3(0, 0, -1), vm.Vector3(0, 1, 0));
    face(vm.Vector3(-1, 0, 0), vm.Vector3(0, 0, 1), vm.Vector3(0, 1, 0));
    face(vm.Vector3(0, 1, 0), vm.Vector3(1, 0, 0), vm.Vector3(0, 0, -1));
    face(vm.Vector3(0, -1, 0), vm.Vector3(1, 0, 0), vm.Vector3(0, 0, 1));
    face(vm.Vector3(0, 0, 1), vm.Vector3(1, 0, 0), vm.Vector3(0, 1, 0));
    face(vm.Vector3(0, 0, -1), vm.Vector3(-1, 0, 0), vm.Vector3(0, 1, 0));

    final idx = <int>[];
    for (var f = 0; f < 6; f++) {
      final b = f * 4;
      idx.addAll([b, b + 1, b + 2, b, b + 2, b + 3]);
    }

    _vertices = gpu.gpuContext.createDeviceBufferWithCopy(
        Float32List.fromList(verts).buffer.asByteData());
    _indices = gpu.gpuContext.createDeviceBufferWithCopy(
        Uint16List.fromList(idx).buffer.asByteData());
  }

  void _ensureAttachments(int w, int h) {
    if (_depth != null && _depth!.width == w && _depth!.height == h) return;
    final samples = _msaa ? 4 : 1;
    _depth = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      w,
      h,
      format: gpu.gpuContext.defaultDepthStencilFormat,
      sampleCount: samples,
      enableShaderReadUsage: false,
    );
    _msaaColor = _msaa
        ? gpu.gpuContext.createTexture(
            gpu.StorageMode.deviceTransient,
            w,
            h,
            format: gpu.gpuContext.defaultColorFormat,
            sampleCount: 4,
            enableShaderReadUsage: false,
          )
        : null;
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    _ensureAttachments(target.width, target.height);

    _yawExtra += frame.dragDelta.dx * 0.010;
    _pitchExtra += frame.dragDelta.dy * 0.010;

    final clear = vm.Vector4(0.031, 0.035, 0.055, 1.0);
    final colorAttachment = _msaa
        ? gpu.ColorAttachment(
            texture: _msaaColor!,
            resolveTexture: target,
            storeAction: gpu.StoreAction.multisampleResolve,
            clearValue: clear,
          )
        : gpu.ColorAttachment(texture: target, clearValue: clear);

    final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
      colorAttachment,
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: _depth!,
        depthClearValue: 1.0,
      ),
    ));

    pass.bindPipeline(_pipeline);
    pass.setDepthWriteEnable(true);
    pass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    pass.setCullMode(gpu.CullMode.backFace);
    pass.setWindingOrder(gpu.WindingOrder.counterClockwise);

    final t = frame.time;
    final proj = kClipCorrection *
        vm.makePerspectiveMatrix(
            50 * math.pi / 180, frame.aspect, 0.1, 100.0);
    final eye = vm.Vector3(0, 1.6, 4.6);
    final view = vm.makeViewMatrix(eye, vm.Vector3.zero(), vm.Vector3(0, 1, 0));
    final model = vm.Matrix4.rotationY(t * 0.7 + _yawExtra) *
        vm.Matrix4.rotationX(0.45 * math.sin(t * 0.43) + _pitchExtra) *
        vm.Matrix4.rotationZ(0.22 * math.sin(t * 0.31));
    final vm.Matrix4 mvp = proj * view * model;

    _vertInfo
      ..setMat4('mvp', mvp)
      ..setMat4('model', model);
    pass.bindUniform(
        _vert.getUniformSlot('VertInfo'), _vertInfo.emplace(frame.transients));

    final light = vm.Vector3(0.5, 0.8, 0.6).normalized();
    _fragInfo
      ..setVec4('light_dir', light.x, light.y, light.z, 0)
      ..setVec4('camera_pos', eye.x, eye.y, eye.z, 0)
      ..setFloat('time', t);
    pass.bindUniform(
        _frag.getUniformSlot('FragInfo'), _fragInfo.emplace(frame.transients));

    pass.bindVertexBuffer(gpu.BufferView(_vertices,
        offsetInBytes: 0, lengthInBytes: _vertices.sizeInBytes));
    pass.bindIndexBuffer(
        gpu.BufferView(_indices,
            offsetInBytes: 0, lengthInBytes: _indices.sizeInBytes),
        gpu.IndexType.int16);
    pass.drawIndexed(36);
  }
}
