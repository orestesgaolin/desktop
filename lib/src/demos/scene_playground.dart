import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
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
  final List<Node> _pillars = [];
  Node? _torus;

  bool _ready = false;
  double _time = 0;
  double _fps = 0;
  int _statTicks = 0;

  // Driven by the control card embedded IN the scene (WidgetComponent).
  double _spinSpeed = 0.5;
  bool _pillarsOn = true;
  WidgetComponent? _cardComponent;
  Node? _cardNode;
  Node? _cameraNode;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      _buildScene();
      setState(() => _ready = true);
    });
  }

  // Verification mode: disables the dithered effects (AO/SSR) whose noise
  // inflates screenshot payloads past the marionette transport limit.
  static const bool _captureFriendly = false;

  void _buildScene() {
    // "showcase" look preset from the flutter_scene-looks skill.
    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.0,
      bloomEnabled: true,
      bloomThreshold: 1.1,
      bloomIntensity: 0.2,
      bloomScatter: 0.7,
      ambientOcclusionEnabled: !_captureFriendly,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionBentNormals: true,
      ambientOcclusionSpecularMode: SpecularAmbientOcclusionMode.bentCone,
      ambientOcclusionIntensity: 1.0,
      screenSpaceReflectionsEnabled: !_captureFriendly,
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
      final pillar = Node(
        mesh: Mesh(
          CylinderGeometry(bottomRadius: 0.06, topRadius: 0.06, height: 2.4),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.03, 1)
            ..emissiveFactor = vm.Vector4(0.15, 0.85, 1.0, 1)
            ..emissiveStrength = 2.0,
        ),
      )..position =
          vm.Vector3(math.cos(angle) * 4.2, 1.3, math.sin(angle) * 4.2);
      _pillars.add(pillar);
      scene.add(pillar);
    }

    // A real, interactive Flutter widget living on a quad inside the scene:
    // SceneView hosts the subtree, re-captures it every frame, and raycasts
    // pointer input onto the surface. The card controls the scene around it.
    _cardComponent = WidgetComponent(
        child: _SceneControlCard(
          initialSpin: _spinSpeed,
          initialPillars: _pillarsOn,
          onSpinChanged: (v) => _spinSpeed = v,
          onPillarsChanged: (v) => _pillarsOn = v,
        ),
      size: const Size(250, 160),
      pixelRatio: 2.0,
      worldHeight: 1.15,
    );
    _cardNode = Node(name: 'control-card')
      ..position = vm.Vector3(0, 2.9, 0)
      ..addComponent(_cardComponent!);
    scene.add(_cardNode!);

    // Camera node driven by the orbit controller (input via CameraControls).
    _cameraNode = Node(name: 'camera')
      ..addComponent(CameraComponent(activateOnMount: true))
      ..addComponent(_orbit);
    scene.add(_cameraNode!);
  }

  double _rigAngle = 0;

  void _onTick(Duration elapsed, double dt) {
    final playback = widget.playback;
    final scaled = playback.paused ? 0.0 : dt * playback.speed;
    _time += scaled;
    _rigAngle += scaled * _spinSpeed;

    for (final pillar in _pillars) {
      pillar.visible = _pillarsOn;
    }

    // Billboard the in-scene control card toward the camera.
    final cameraNode = _cameraNode;
    if (cameraNode != null) {
      _cardNode?.lookAt(cameraNode.position);
    }

    _rig.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _rigAngle);
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

/// The widget rendered onto (and interactive on) the in-scene quad.
class _SceneControlCard extends StatefulWidget {
  const _SceneControlCard({
    required this.initialSpin,
    required this.initialPillars,
    required this.onSpinChanged,
    required this.onPillarsChanged,
  });

  final double initialSpin;
  final bool initialPillars;
  final ValueChanged<double> onSpinChanged;
  final ValueChanged<bool> onPillarsChanged;

  @override
  State<_SceneControlCard> createState() => _SceneControlCardState();
}

class _SceneControlCardState extends State<_SceneControlCard> {
  late double _spin = widget.initialSpin;
  late bool _pillars = widget.initialPillars;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF22D3EE);
    return Material(
      color: const Color(0xEE131824),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SCENE CONTROLS',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: accent)),
            Row(
              children: [
                const Expanded(
                    child: Text('Pillars',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600))),
                Switch(
                  value: _pillars,
                  activeThumbColor: accent,
                  onChanged: (v) {
                    setState(() => _pillars = v);
                    widget.onPillarsChanged(v);
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Spin',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Expanded(
                  child: Slider(
                    value: _spin,
                    min: 0,
                    max: 2,
                    activeColor: accent,
                    onChanged: (v) {
                      setState(() => _spin = v);
                      widget.onSpinChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
