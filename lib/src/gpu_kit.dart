import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// Writes uniform struct members by name, using the shader's reflection data
/// for offsets and total size. This avoids hardcoding std140 layout rules.
class UniformWriter {
  /// [lenient] skips members the shader does not declare instead of throwing.
  /// Used by the live editor, where the user may trim the uniform block.
  UniformWriter(this.slot, {this.lenient = false}) {
    final size = slot.sizeInBytes;
    if (size == null) {
      throw StateError('Shader has no uniform struct "${slot.uniformName}"');
    }
    data = ByteData(size);
  }

  final gpu.UniformSlot slot;
  final bool lenient;
  late final ByteData data;
  final Map<String, int?> _offsets = <String, int?>{};

  int? _offset(String member) {
    if (!_offsets.containsKey(member)) {
      _offsets[member] = slot.getMemberOffsetInBytes(member);
    }
    final offset = _offsets[member];
    if (offset == null && !lenient) {
      throw StateError(
          'Uniform "${slot.uniformName}" has no member "$member"');
    }
    return offset;
  }

  void setFloat(String member, double x) {
    final o = _offset(member);
    if (o == null) return;
    data.setFloat32(o, x, Endian.little);
  }

  void setVec2(String member, double x, double y) {
    final o = _offset(member);
    if (o == null) return;
    data.setFloat32(o, x, Endian.little);
    data.setFloat32(o + 4, y, Endian.little);
  }

  void setVec4(String member, double x, double y, double z, double w) {
    final o = _offset(member);
    if (o == null) return;
    data.setFloat32(o, x, Endian.little);
    data.setFloat32(o + 4, y, Endian.little);
    data.setFloat32(o + 8, z, Endian.little);
    data.setFloat32(o + 12, w, Endian.little);
  }

  void setMat4(String member, vm.Matrix4 matrix) {
    final o = _offset(member);
    if (o == null) return;
    final storage = matrix.storage; // column-major, matches SPIR-V layout
    for (var i = 0; i < 16; i++) {
      data.setFloat32(o + i * 4, storage[i], Endian.little);
    }
  }

  gpu.BufferView emplace(gpu.HostBuffer transients) => transients.emplace(data);
}

gpu.PixelFormat? _stableColor;
gpu.PixelFormat? _stableDepthStencil;

/// The context's default color format, queried once and cached.
///
/// The live getter can start returning [gpu.PixelFormat.unknown] after the
/// engine renders a wide-gamut snapshot (RepaintBoundary.toImage on macOS),
/// which flutter_gpu's enum cannot map. Caching the first good answer — with
/// a Metal-friendly fallback — keeps surfaces and MSAA attachments working.
gpu.PixelFormat stableColorFormat() {
  var format = _stableColor;
  if (format != null) return format;
  format = gpu.gpuContext.defaultColorFormat;
  if (format == gpu.PixelFormat.unknown) {
    format = gpu.PixelFormat.b8g8r8a8UNormInt;
  }
  return _stableColor = format;
}

/// See [stableColorFormat]; same caching for the depth-stencil format.
gpu.PixelFormat stableDepthStencilFormat() {
  var format = _stableDepthStencil;
  if (format != null) return format;
  format = gpu.gpuContext.defaultDepthStencilFormat;
  if (format == gpu.PixelFormat.unknown) {
    format = gpu.PixelFormat.d32FloatS8UInt;
  }
  return _stableDepthStencil = format;
}

/// GL-style clip space (z in [-1, 1]) -> Metal/Impeller clip space
/// (z in [0, 1]).
final vm.Matrix4 kClipCorrection = vm.Matrix4(
  1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 0.5, 0, //
  0, 0, 0.5, 1,
);

gpu.DeviceBuffer? _fullscreenVertexBuffer;

/// A 3-vertex triangle covering the whole viewport (positions in clip space),
/// shared by all fullscreen fragment-shader demos.
gpu.BufferView fullscreenTriangle() {
  final buffer = _fullscreenVertexBuffer ??=
      gpu.gpuContext.createDeviceBufferWithCopy(
    Float32List.fromList(<double>[-1, -1, 3, -1, -1, 3]).buffer.asByteData(),
  );
  return gpu.BufferView(buffer,
      offsetInBytes: 0, lengthInBytes: buffer.sizeInBytes);
}

final gpu.VertexLayout kFullscreenLayout = gpu.VertexLayout(buffers: [
  gpu.VertexBuffer(
    strideInBytes: 8,
    attributes: [
      gpu.VertexAttribute(name: 'position', format: gpu.VertexFormat.float32x2),
    ],
  ),
]);
