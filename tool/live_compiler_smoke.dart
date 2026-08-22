// Smoke test for the runtime shader compiler (no Flutter needed):
//   dart run tool/live_compiler_smoke.dart
import 'dart:io';

import 'package:gpu_playground/src/live_compiler.dart';

Future<void> main() async {
  final compiler = LiveShaderCompiler();
  stdout.writeln('impellerc: ${await compiler.findImpellerc()}');

  const good = '''
uniform FragInfo {
  vec2 resolution;
  vec2 pointer;
  float time;
  float param0; float param1; float param2; float param3;
} u;
in vec2 v_uv;
out vec4 frag_color;
void main() { frag_color = vec4(v_uv, 0.5 + 0.5 * sin(u.time), 1.0); }
''';
  final ok = await compiler.compile(good);
  stdout.writeln(ok.ok
      ? 'GOOD: compiled ${ok.bytes!.lengthInBytes} bytes '
          'in ${ok.elapsedMs} ms'
      : 'GOOD source unexpectedly failed:\n${ok.errors}');

  final bad = await compiler.compile('void main() { this is not glsl }');
  stdout.writeln(bad.ok
      ? 'BAD source unexpectedly compiled'
      : 'BAD: failed as expected in ${bad.elapsedMs} ms, errors:\n'
          '${bad.errors}');

  exitCode = ok.ok && !bad.ok ? 0 : 1;
}
