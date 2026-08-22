import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../frame.dart';
import 'demo.dart';

/// flutter_scene showcase: the same Flutter GPU this app drives by hand,
/// wrapped in a retained scene graph with PBR materials, IBL, a
/// shadow-casting sun, screen-space reflections, and bloom.
class ScenePlaygroundDemo extends WidgetHostedDemo {
  @override
  String get name => 'Scene: PBR Studio';
  @override
  String get subtitle => 'flutter_scene — shadows, SSR, bloom';
  @override
  String get hint => 'drag to orbit · scroll to dolly';
  @override
  IconData get icon => Icons.diamond_outlined;

  @override
  Widget buildView(BuildContext context, PlaybackController playback) {
    return _PlaygroundView(key: ObjectKey(this), playback: playback);
  }
}

class _PlaygroundView extends StatefulWidget {
  const _PlaygroundView({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<_PlaygroundView> createState() => _PlaygroundViewState();
}

class _PlaygroundViewState extends State<_PlaygroundView> {
  final Scene scene = Scene();
  final OrbitCameraController _orbit = OrbitCameraController(
    target: vm.Vector3(0, 0.9, 0),
    distance: 7.5,
    polar: 0.35,
  );

  final Node _rig = Node(name: 'rig');
  final List<Node> _orbiters = [];
  Node? _torus;

  bool _ready = false;
  double _time = 0;
  double _fps = 0;
  int _statTicks = 0;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      _buildScene();
      setState(() => _ready = true);
    });
  }

  void _buildScene() {
    // "showcase" look preset from the flutter_scene-looks skill.
    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.0,
      bloomEnabled: true,
      bloomThreshold: 1.1,
      bloomIntensity: 0.2,
      bloomScatter: 0.7,
      ambientOcclusionEnabled: true,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionBentNormals: true,
      ambientOcclusionSpecularMode: SpecularAmbientOcclusionMode.bentCone,
      ambientOcclusionIntensity: 1.0,
      screenSpaceReflectionsEnabled: true,
      screenSpaceReflectionsIntensity: 1.0,
      vignetteEnabled: true,
      vignetteIntensity: 0.25,
    );
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.4, -1.0, -0.3),
      intensity: 4.0,
      castsShadow: true,
    );

    // Gradient sky fills the horizon and feeds the reflections.
    scene.skybox = Skybox(GradientSkySource(
      zenithColor: vm.Vector3(0.02, 0.03, 0.06),
      horizonColor: vm.Vector3(0.10, 0.12, 0.20),
      groundColor: vm.Vector3(0.02, 0.02, 0.03),
    ));

    // Glossy dark floor for the screen-space reflections.
    scene.add(Node(
      mesh: Mesh(
        PlaneGeometry(width: 24, depth: 24),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.04, 0.045, 0.06, 1)
          ..metallicFactor = 0.55
          ..roughnessFactor = 0.30,
      ),
    ));

    // Centerpiece: a gold torus with a glass icosphere floating inside.
    _torus = Node(
      mesh: Mesh(
        TorusGeometry(radius: 1.0, tubeRadius: 0.3, tubularSegments: 48),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(1.0, 0.75, 0.3, 1)
          ..metallicFactor = 1.0
          ..roughnessFactor = 0.18,
      ),
    )..position = vm.Vector3(0, 1.4, 0);
    scene.add(_torus!);

    scene.add(Node(
      mesh: Mesh(
        IcosphereGeometry(radius: 0.55, subdivisions: 3),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.05
          ..transmission = 1.0
          ..ior = 1.45,
      ),
    )..position = vm.Vector3(0, 1.4, 0));

    // A ring of orbiting satellites with varied materials.
    scene.add(_rig);
    final palette = [
      vm.Vector4(0.9, 0.2, 0.3, 1),
      vm.Vector4(0.2, 0.8, 0.9, 1),
      vm.Vector4(0.65, 0.4, 1.0, 1),
      vm.Vector4(0.3, 0.9, 0.4, 1),
    ];
    for (var i = 0; i < 4; i++) {
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = palette[i]
        ..metallicFactor = i.isEven ? 0.0 : 1.0
        ..roughnessFactor = 0.15 + 0.2 * i
        ..clearcoat = i.isEven ? 1.0 : 0.0;
      final node = Node(
        mesh: Mesh(
          i % 2 == 0
              ? SphereGeometry(radius: 0.3) as MeshGeometry
              : CuboidGeometry(vm.Vector3(0.45, 0.45, 0.45)),
          material,
        ),
      );
      _orbiters.add(node);
      _rig.add(node);
    }

    // Emissive pillars that feed the bloom pass.
    for (var i = 0; i < 3; i++) {
      final angle = i * 2 * math.pi / 3 + 0.5;
      scene.add(Node(
        mesh: Mesh(
          CylinderGeometry(bottomRadius: 0.06, topRadius: 0.06, height: 2.4),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.03, 1)
            ..emissiveFactor = vm.Vector4(0.15, 0.85, 1.0, 1)
            ..emissiveStrength = 2.0,
        ),
      )..position =
          vm.Vector3(math.cos(angle) * 4.2, 1.3, math.sin(angle) * 4.2));
    }

    // Camera node driven by the orbit controller (input via CameraControls).
    final cameraNode = Node(name: 'camera')
      ..addComponent(CameraComponent(activateOnMount: true))
      ..addComponent(_orbit);
    scene.add(cameraNode);
  }

  void _onTick(Duration elapsed, double dt) {
    final playback = widget.playback;
    _time += playback.paused ? 0 : dt * playback.speed;

    _rig.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _time * 0.5);
    for (var i = 0; i < _orbiters.length; i++) {
      final phase = i * math.pi / 2;
      _orbiters[i].position = vm.Vector3(
        math.cos(phase) * 2.6,
        1.1 + 0.45 * math.sin(_time * 1.4 + phase),
        math.sin(phase) * 2.6,
      );
    }
    _torus?.rotation =
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2 * 0.0 + _time * 0.6) *
            vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), _time * 0.35);

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
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return CameraControls(
      controller: _orbit,
      child: SceneView(scene, onTick: _onTick),
    );
  }
}
