// Runtime GLSL -> shader bundle compilation by shelling out to the SDK's
// `impellerc`. Pure dart:io (no Flutter imports) so it can be smoke-tested
// with `dart run tool/live_compiler_smoke.dart`.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The fullscreen-triangle vertex shader compiled into every live bundle, so
/// the pipeline links a vertex and fragment shader from the same library.
/// Keep in sync with `shaders/fullscreen.vert`.
const String kLiveVertexSource = '''
in vec2 position;

out vec2 v_uv;

void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  v_uv = position * 0.5 + 0.5;
}
''';

class LiveCompileResult {
  const LiveCompileResult.ok(this.bytes, this.elapsedMs) : errors = null;
  const LiveCompileResult.failed(this.errors, this.elapsedMs) : bytes = null;

  final ByteData? bytes;
  final String? errors;
  final int elapsedMs;

  bool get ok => bytes != null;
}

/// Finds `impellerc` once and compiles fragment shader source into a
/// `.shaderbundle` in a temp directory.
class LiveShaderCompiler {
  String? _impellerc;

  /// Locates impellerc: $IMPELLERC env var, then the `flutter` on PATH
  /// (symlinks resolved, so FVM shims work), then any FVM-installed SDK
  /// (preferring the master channel).
  Future<String> findImpellerc() async {
    if (_impellerc != null) return _impellerc!;

    final candidates = <String>[];
    final env = Platform.environment['IMPELLERC'];
    if (env != null && env.isNotEmpty) candidates.add(env);

    try {
      final which = await Process.run('which', ['flutter']);
      if (which.exitCode == 0) {
        final flutterPath =
            await File((which.stdout as String).trim()).resolveSymbolicLinks();
        final sdkBin = File(flutterPath).parent.path;
        candidates.addAll(_engineArtifacts('$sdkBin/cache'));
      }
    } catch (_) {
      // No flutter on PATH; fall through to the FVM scan.
    }

    final home = Platform.environment['HOME'] ?? '';
    final fvmVersions = Directory('$home/fvm/versions');
    if (fvmVersions.existsSync()) {
      final versions = fvmVersions.listSync().whereType<Directory>().toList()
        ..sort((a, b) {
          // Prefer the master channel, then reverse-alphabetical (newest).
          int rank(Directory d) => d.path.endsWith('/master') ? 0 : 1;
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : b.path.compareTo(a.path);
        });
      for (final v in versions) {
        candidates.addAll(_engineArtifacts('${v.path}/bin/cache'));
      }
    }

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return _impellerc = candidate;
      }
    }
    throw Exception(
      'impellerc not found. Set the IMPELLERC environment variable to the '
      'binary inside your Flutter SDK '
      '(bin/cache/artifacts/engine/darwin-*/impellerc).',
    );
  }

  List<String> _engineArtifacts(String cacheDir) {
    final engine = Directory('$cacheDir/artifacts/engine');
    if (!engine.existsSync()) return const [];
    return [
      for (final d in engine.listSync().whereType<Directory>())
        if (d.path.split('/').last.startsWith('darwin-')) '${d.path}/impellerc',
    ];
  }

  Future<LiveCompileResult> compile(String fragmentSource) async {
    final stopwatch = Stopwatch()..start();
    final impellerc = await findImpellerc();
    final shaderLib = '${File(impellerc).parent.path}/shader_lib';

    final temp = await Directory.systemTemp.createTemp('gpu_playground_live');
    try {
      await File('${temp.path}/live.vert').writeAsString(kLiveVertexSource);
      await File('${temp.path}/live.frag').writeAsString(fragmentSource);
      final manifest = jsonEncode({
        'LiveVertex': {'type': 'vertex', 'file': 'live.vert'},
        'LiveFragment': {'type': 'fragment', 'file': 'live.frag'},
      });
      final bundlePath = '${temp.path}/live.shaderbundle';

      final result = await Process.run(impellerc, [
        '--sl=$bundlePath',
        '--shader-bundle=$manifest',
        '--include=${temp.path}',
        '--include=$shaderLib',
      ], workingDirectory: temp.path);

      if (result.exitCode != 0) {
        final log = '${result.stderr}\n${result.stdout}'
            .replaceAll('${temp.path}/', '')
            .trim();
        return LiveCompileResult.failed(
          log.isEmpty ? 'impellerc failed (exit ${result.exitCode})' : log,
          stopwatch.elapsedMilliseconds,
        );
      }

      final bytes = await File(bundlePath).readAsBytes();
      return LiveCompileResult.ok(
        ByteData.sublistView(bytes),
        stopwatch.elapsedMilliseconds,
      );
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // Best-effort temp cleanup.
      }
    }
  }
}
