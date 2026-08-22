import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import 'demo.dart';

/// flutter_scene asset pipeline + animation: the Khronos sample Fox (CC0),
/// converted from .glb at build time by the flutter_scene hook, with its
/// skinned Walk and Run clips blended against each other over time.
class SceneFoxDemo extends WidgetHostedDemo {
  @override
  String get name => 'Scene: Animated Fox';
  @override
  String get subtitle => 'glTF pipeline, blended skeletal clips';
  @override
  String get hint => 'drag to orbit · walk and run blend over time';
  @override
  IconData get icon => Icons.pets;

  @override
  Widget buildView(BuildContext context, PlaybackController playback) {
    return _FoxView(key: ObjectKey(this), playback: playback);
  }
}

class _FoxView extends StatefulWidget {
  const _FoxView({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<_FoxView> createState() => _FoxViewState();
}

class _FoxViewState extends State<_FoxView> {
  final Scene scene = Scene();
  final OrbitCameraController _orbit = OrbitCameraController(
    target: vm.Vector3(0, 1.0, 0),
    distance: 5.0,
    polar: 0.25,
    azimuth: 0.7,
  );

  AnimationClip? _walk;
  AnimationClip? _run;

  bool _ready = false;
  String? _error;
  double _time = 0;
  double _fps = 0;
  int _statTicks = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Scene.initializeStaticResources();
      final fox = await loadScene('assets/Fox.glb');
      if (!mounted) return;

      // The Fox sample is ~75 units tall; bring it into meters.
      fox.scale = vm.Vector3.all(0.026);
      scene.add(fox);

      final walk = fox.findAnimationByName('Walk');
      final run = fox.findAnimationByName('Run');
      if (walk != null) {
        _walk = fox.createAnimationClip(walk)
          ..loop = true
          ..weight = 1
          ..play();
      }
      if (run != null) {
        _run = fox.createAnimationClip(run)
          ..loop = true
          ..weight = 0
          ..play();
      }

      // "stylized" look preset from the flutter_scene-looks skill.
      scene.environmentSettings = EnvironmentSettings(
        toneMapping: ToneMappingMode.aces,
        colorGradingEnabled: true,
        saturation: 1.25,
        contrast: 1.1,
        brightness: 1.05,
        temperature: 0.1,
        bloomEnabled: true,
        bloomThreshold: 0.9,
        bloomIntensity: 0.28,
        bloomScatter: 0.8,
        vignetteEnabled: true,
        vignetteIntensity: 0.2,
      );
      scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.5, -1.0, -0.35),
        intensity: 3.5,
        castsShadow: true,
      );

      scene.add(Node(
        mesh: Mesh(
          DiscGeometry(radius: 3.2, segments: 64),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.16, 0.2, 0.16, 1)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.9,
        ),
      ));

      final cameraNode = Node(name: 'camera')
        ..addComponent(CameraComponent(activateOnMount: true))
        ..addComponent(_orbit);
      scene.add(cameraNode);

      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onTick(Duration elapsed, double dt) {
    final playback = widget.playback;
    final speed = playback.paused ? 0.0 : playback.speed;
    _time += dt * speed;

    // Crossfade walk <-> run on a slow cycle; playback controls scale both.
    final blend =
        0.5 + 0.5 * MathUtils.smoothTri(_time * 0.15);
    _walk
      ?..weight = 1 - blend
      ..playbackTimeScale = speed;
    _run
      ?..weight = blend
      ..playbackTimeScale = speed * 1.0;

    if (dt > 0) {
      _fps = _fps == 0 ? 1 / dt : _fps * 0.95 + (1 / dt) * 0.05;
    }
    if (++_statTicks >= 20) {
      _statTicks = 0;
      widget.playback.stats.value = '${_fps.round()} fps · SceneView';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText('Failed to load Fox scene:\n$_error',
              style: const TextStyle(fontSize: 12)),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return CameraControls(
      controller: _orbit,
      child: SceneView(scene, onTick: _onTick),
    );
  }
}

/// Small triangle-wave helper with smooth turnarounds, in [-1, 1].
class MathUtils {
  static double smoothTri(double t) {
    final phase = (t % 1.0) * 2.0;
    final tri = phase < 1.0 ? phase * 2 - 1 : 3 - phase * 2;
    // Smootherstep the linear ramp for gentle blend turnarounds.
    final x = (tri + 1) / 2;
    return (x * x * (3 - 2 * x)) * 2 - 1;
  }
}
