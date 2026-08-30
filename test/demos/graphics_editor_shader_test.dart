import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_playground/src/demos/demo.dart';
import 'package:gpu_playground/src/demos/graphics_editor.dart';
import 'package:gpu_playground/src/live_compiler.dart';

void main() {
  test('all design canvas GLSL effects compile with Impeller', () async {
    expect(graphicsEditorShaderSources, hasLength(3));

    for (final source in graphicsEditorShaderSources) {
      final result = await GpuDemo.compiler.compileBundle({
        'SurfaceVertex': (stage: 'vertex', source: kLiveVertexSource),
        'SurfaceFragment': (stage: 'fragment', source: source),
      });
      expect(result.ok, isTrue, reason: result.errors);
      expect(result.bytes, isNotNull);
    }

    final invalid = await GpuDemo.compiler.compileBundle({
      'SurfaceVertex': (stage: 'vertex', source: kLiveVertexSource),
      'SurfaceFragment': (
        stage: 'fragment',
        source: 'void main() { this is not valid GLSL }',
      ),
    });
    expect(invalid.ok, isFalse);
    expect(invalid.errors, contains('SurfaceFragment'));
  });
}
