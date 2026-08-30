import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_playground/src/gpu_widgets.dart';
import 'package:gpu_playground/src/live_compiler.dart';

void main() {
  test('requests an initial fallback only for a first compilation', () {
    expect(
      const GpuShaderCompileStatus(phase: GpuShaderCompilePhase.compiling)
          .needsInitialFallback,
      isTrue,
    );
    expect(
      const GpuShaderCompileStatus(
        phase: GpuShaderCompilePhase.compiling,
        hasPreviousOutput: true,
      ).needsInitialFallback,
      isFalse,
    );
    expect(
      const GpuShaderCompileStatus(phase: GpuShaderCompilePhase.failed)
          .needsInitialFallback,
      isFalse,
    );
  });

  test(
    'coalesces in-flight work and reuses a successful shader bundle',
    () async {
      final cache = GpuShaderBundleCache();
      final pending = Completer<LiveCompileResult>();
      var compileCount = 0;

      Future<LiveCompileResult> compile() {
        compileCount++;
        return pending.future;
      }

      final first = cache.compile('same shader source', compile);
      final rebuiltElement = cache.compile('same shader source', compile);
      expect(compileCount, 1);

      pending.complete(LiveCompileResult.ok(ByteData(4), 12));
      final firstResult = await first;
      expect(await rebuiltElement, same(firstResult));
      expect(
        await cache.compile('same shader source', compile),
        same(firstResult),
      );
      expect(compileCount, 1);
    },
  );

  test('does not retain a failed shader compilation', () async {
    final cache = GpuShaderBundleCache();
    var compileCount = 0;

    Future<LiveCompileResult> compile() async {
      compileCount++;
      return const LiveCompileResult.failed('compiler unavailable', 3);
    }

    expect((await cache.compile('retryable source', compile)).ok, isFalse);
    expect((await cache.compile('retryable source', compile)).ok, isFalse);
    expect(compileCount, 2);
  });
}
