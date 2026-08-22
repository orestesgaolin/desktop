import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

const String kShaderBundlePath = 'build/shaderbundles/playground.shaderbundle';

gpu.ShaderLibrary? _library;

/// Loads (once) the impellerc-compiled shader bundle produced by the build
/// hook in `hook/build.dart`.
Future<gpu.ShaderLibrary> loadShaderLibrary() async {
  if (_library != null) return _library!;
  final library = await gpu.ShaderLibrary.fromAsset(kShaderBundlePath);
  if (library == null) {
    throw Exception('Could not parse shader bundle at $kShaderBundlePath');
  }
  return _library = library;
}

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
