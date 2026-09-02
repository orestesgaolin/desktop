import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import '../gpu_kit.dart';
import 'demo.dart';

/// Number of distinct source widgets (fed by WidgetSourcePanel).
const int kStageCardCount = 4;

/// Slots on the carousel ring; each source card appears twice.
const int _kSlots = kStageCardCount * 2;

/// Real Flutter widgets rendered inside a Flutter GPU 3D scene.
///
/// The companion `WidgetSourcePanel` snapshots live widgets with
/// `RepaintBoundary.toImage` and hands them here via [setCard]; the images
/// are wrapped zero-copy with `gpu.Texture.fromImage` and drawn as quads on
/// a cover-flow carousel with depth, MSAA, and floor reflections.
class WidgetStageDemo extends GpuDemo {
  @override
  String get name => 'Widget Stage';
  @override
  String get subtitle => 'Live widgets as GPU textures';
  @override
  String get hint =>
      'click a card to press the real widget · drag / scroll spins the ring';
  @override
  IconData get icon => Icons.style;

  /// Invoked when a tap on the stage lands on a card. [fraction] is the hit
  /// position inside the card: (0,0) top-left .. (1,1) bottom-right, in the
  /// source widget's orientation. Set by WidgetSourcePanel, which forwards
  /// the press to the real widget.
  void Function(int cardIndex, Offset fraction)? onCardTap;

  static const double _kRadius = 2.9;
  static const double _kFloorY = -0.62;
  static const double _kHalfH = 0.38;

  @override
  late final List<ShaderDoc> shaders = [
    ShaderDoc(name: 'CardVertex', stage: 'vertex', asset: 'shaders/card.vert'),
    ShaderDoc(
        name: 'CardFragment', stage: 'fragment', asset: 'shaders/card.frag'),
  ];

  late gpu.RenderPipeline _pipeline;
  late gpu.Shader _vert;
  late gpu.Shader _frag;
  late gpu.DeviceBuffer _quad;
  late UniformWriter _vertInfo;
  late UniformWriter _fragInfo;
  late bool _msaa;

  gpu.Texture? _depth;
  gpu.Texture? _msaaColor;

  final List<gpu.Texture?> _textures =
      List<gpu.Texture?>.filled(kStageCardCount, null);
  final List<ui.Image?> _images =
      List<ui.Image?>.filled(kStageCardCount, null);
  final List<double> _aspects = List<double>.filled(kStageCardCount, 2.0);

  double _theta = 0;
  double _target = 0;

  /// Called by WidgetSourcePanel after each snapshot. Keeps the image alive
  /// alongside its zero-copy texture wrapper and disposes the previous pair.
  void setCard(int index, gpu.Texture texture, ui.Image image) {
    _images[index]?.dispose();
    _textures[index] = texture;
    _images[index] = image;
    _aspects[index] = image.width / image.height;
  }

  @override
  void init(gpu.ShaderLibrary library) {
    _vert = shaderOf(library, 'CardVertex');
    _frag = shaderOf(library, 'CardFragment');
    _msaa = gpu.gpuContext.doesSupportOffscreenMSAA;

    _pipeline = gpu.gpuContext.createRenderPipeline(
      _vert,
      _frag,
      vertexLayout: gpu.VertexLayout(buffers: [
        gpu.VertexBuffer(strideInBytes: 16, attributes: [
          gpu.VertexAttribute(
              name: 'position', format: gpu.VertexFormat.float32x2),
          gpu.VertexAttribute(
              name: 'uv', format: gpu.VertexFormat.float32x2,
              offsetInBytes: 8),
        ]),
      ]),
    );

    // Unit quad as a triangle strip: x, y, u, v. uv y=1 is the card's top
    // (image row 0), matching how ui.Image texels are laid out.
    _quad = gpu.gpuContext.createDeviceBufferWithCopy(
      Float32List.fromList(<double>[
        -1, -1, 0, 1, //
        1, -1, 1, 1, //
        -1, 1, 0, 0, //
        1, 1, 1, 0, //
      ]).buffer.asByteData(),
    );

    _vertInfo = UniformWriter(_vert.getUniformSlot('VertInfo'));
    _fragInfo = UniformWriter(_frag.getUniformSlot('FragInfo'));
  }

  void _ensureAttachments(int w, int h) {
    if (_depth != null &&
        _depth!.width == w &&
        _depth!.height == h &&
        (!_msaa || _msaaColor != null)) {
      return;
    }
    final samples = _msaa ? 4 : 1;
    _depth = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      w,
      h,
      format: stableDepthStencilFormat(),
      sampleCount: samples,
      enableShaderReadUsage: false,
    );
    _msaaColor = _msaa
        ? gpu.gpuContext.createTexture(
            gpu.StorageMode.deviceTransient,
            w,
            h,
            format: stableColorFormat(),
            sampleCount: 4,
            enableShaderReadUsage: false,
          )
        : null;
  }

  @override
  void render(gpu.CommandBuffer commandBuffer, gpu.Texture target,
      FrameContext frame) {
    _ensureAttachments(target.width, target.height);

    _target += frame.dragDelta.dx * 0.006 + frame.scrollDelta * 0.002;
    _target += frame.dt * 0.10; // gentle idle spin
    _theta += (_target - _theta) * math.min(1, frame.dt * 7);

    final clear = vm.Vector4(0.914, 0.902, 0.878, 1.0);
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
    pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
    pass.setDepthWriteEnable(true);
    pass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    pass.setColorBlendEnable(true); // premultiplied: one, oneMinusSourceAlpha

    final proj = kClipCorrection *
        vm.makePerspectiveMatrix(38 * math.pi / 180, frame.aspect, 0.1, 60.0);
    final view = vm.makeViewMatrix(
        vm.Vector3(0, 0.65, 9.6), vm.Vector3(0, -0.10, 0), vm.Vector3(0, 1, 0));
    final vm.Matrix4 viewProj = proj * view;

    if (frame.tapUv != null && onCardTap != null) {
      final hit = _hitTest(frame.tapUv!, viewProj, frame.time);
      if (hit != null) {
        final callback = onCardTap!;
        // Defer out of the ticker callback before synthesizing input.
        Future(() => callback(hit.$1, hit.$2));
      }
    }

    // Painter's order: farthest slots first so premultiplied blending
    // composites the transparent rounded corners correctly.
    final slots = <(int card, double angle, double cos)>[
      for (var i = 0; i < _kSlots; i++)
        (
          i % kStageCardCount,
          _theta + i * (2 * math.pi / _kSlots),
          math.cos(_theta + i * (2 * math.pi / _kSlots)),
        ),
    ]..sort((a, b) => a.$3.compareTo(b.$3));

    void drawSlot((int, double, double) slot, {required bool reflection}) {
      final (card, angle, cosA) = slot;
      final texture = _textures[card];
      if (texture == null) return;

      vm.Matrix4 model = _cardModel(card, angle, frame.time);
      if (reflection) {
        final y = _floatY(card, frame.time);
        final position = _slotPosition(card, angle, frame.time);
        model = vm.Matrix4.translation(
                vm.Vector3(position.x, 2 * _kFloorY - y, position.z)) *
            vm.Matrix4.rotationY(angle) *
            vm.Matrix4.diagonal3(
                vm.Vector3(_aspects[card] * _kHalfH, -_kHalfH, 1));
      }

      _vertInfo.setMat4('mvp', viewProj * model);
      pass.bindUniform(_vert.getUniformSlot('VertInfo'),
          _vertInfo.emplace(frame.transients));

      final facing =
          ((cosA + 0.4) / 1.3).clamp(0.0, 1.0); // 0 behind .. 1 front
      _fragInfo
        ..setFloat('facing', facing * facing)
        ..setFloat('reflection', reflection ? 1 : 0)
        ..setFloat('time', frame.time);
      pass.bindUniform(_frag.getUniformSlot('FragInfo'),
          _fragInfo.emplace(frame.transients));

      pass.bindTexture(_frag.getUniformSlot('card_tex'), texture,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
          ));

      pass.bindVertexBuffer(gpu.BufferView(_quad,
          offsetInBytes: 0, lengthInBytes: _quad.sizeInBytes));
      pass.draw(4);
    }

    for (final slot in slots) {
      drawSlot(slot, reflection: true);
    }
    for (final slot in slots) {
      drawSlot(slot, reflection: false);
    }
  }

  double _floatY(int card, double time) =>
      0.05 * math.sin(time * 1.3 + card * 1.9);

  vm.Vector3 _slotPosition(int card, double angle, double time) => vm.Vector3(
        _kRadius * math.sin(angle),
        _floatY(card, time),
        _kRadius * math.cos(angle),
      );

  vm.Matrix4 _cardModel(int card, double angle, double time) =>
      vm.Matrix4.translation(_slotPosition(card, angle, time)) *
      vm.Matrix4.rotationY(angle) *
      vm.Matrix4.diagonal3(vm.Vector3(_aspects[card] * _kHalfH, _kHalfH, 1));

  /// Tests [tapUv] (uv space, y up) against the projected triangles of each
  /// front-facing card. Returns the nearest hit as
  /// (cardIndex, fraction), where fraction is (0,0) top-left ..
  /// (1,1) bottom-right in the source widget's orientation.
  (int, Offset)? _hitTest(Offset tapUv, vm.Matrix4 viewProj, double time) {
    const corners = <(double, double, Offset)>[
      (-1, -1, Offset(0, 1)),
      (1, -1, Offset(1, 1)),
      (-1, 1, Offset(0, 0)),
      (1, 1, Offset(1, 0)),
    ];
    const triangles = <(int, int, int)>[(0, 1, 2), (2, 1, 3)];

    var bestDepth = double.infinity;
    (int, Offset)? best;
    for (var i = 0; i < _kSlots; i++) {
      final card = i % kStageCardCount;
      if (_textures[card] == null) continue;
      final angle = _theta + i * (2 * math.pi / _kSlots);
      // Only cards facing the camera accept presses.
      if (math.cos(angle) < 0.05) continue;

      final mvp = viewProj * _cardModel(card, angle, time);
      final projected = <_ProjectedCardVertex>[];
      for (final (x, y, fraction) in corners) {
        final clip = mvp.transform(vm.Vector4(x, y, 0, 1));
        if (clip.w <= 1e-6) {
          projected.clear();
          break;
        }
        final invW = 1 / clip.w;
        projected.add(_ProjectedCardVertex(
          position: Offset(
            clip.x * invW * 0.5 + 0.5,
            clip.y * invW * 0.5 + 0.5,
          ),
          fraction: fraction,
          invW: invW,
          depth: clip.z * invW,
        ));
      }
      if (projected.length != corners.length) continue;

      for (final (a, b, c) in triangles) {
        final weights = _barycentric(tapUv, projected[a].position,
            projected[b].position, projected[c].position);
        if (weights == null) continue;

        final vertices = [projected[a], projected[b], projected[c]];
        final perspectiveWeights = <double>[
          weights.$1 * vertices[0].invW,
          weights.$2 * vertices[1].invW,
          weights.$3 * vertices[2].invW,
        ];
        final weightSum = perspectiveWeights.reduce((a, b) => a + b);
        if (weightSum.abs() < 1e-9) continue;

        final fraction = Offset(
          (perspectiveWeights[0] * vertices[0].fraction.dx +
                  perspectiveWeights[1] * vertices[1].fraction.dx +
                  perspectiveWeights[2] * vertices[2].fraction.dx) /
              weightSum,
          (perspectiveWeights[0] * vertices[0].fraction.dy +
                  perspectiveWeights[1] * vertices[1].fraction.dy +
                  perspectiveWeights[2] * vertices[2].fraction.dy) /
              weightSum,
        );
        final depth = weights.$1 * vertices[0].depth +
            weights.$2 * vertices[1].depth +
            weights.$3 * vertices[2].depth;
        if (depth >= bestDepth) continue;
        bestDepth = depth;
        best = (card, fraction);
      }
    }
    return best;
  }
}

class _ProjectedCardVertex {
  const _ProjectedCardVertex({
    required this.position,
    required this.fraction,
    required this.invW,
    required this.depth,
  });

  final Offset position;
  final Offset fraction;
  final double invW;
  final double depth;
}

(double, double, double)? _barycentric(
    Offset point, Offset a, Offset b, Offset c) {
  final denominator =
      (b.dy - c.dy) * (a.dx - c.dx) + (c.dx - b.dx) * (a.dy - c.dy);
  if (denominator.abs() < 1e-9) return null;
  final first = ((b.dy - c.dy) * (point.dx - c.dx) +
          (c.dx - b.dx) * (point.dy - c.dy)) /
      denominator;
  final second = ((c.dy - a.dy) * (point.dx - c.dx) +
          (a.dx - c.dx) * (point.dy - c.dy)) /
      denominator;
  final third = 1 - first - second;
  const tolerance = -1e-6;
  if (first < tolerance || second < tolerance || third < tolerance) {
    return null;
  }
  return (first, second, third);
}
