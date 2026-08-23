import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../palette.dart';

/// Fixed landmarks of the flyover landscape.
///
/// The camera choreography in `camera_path.dart` is written against these, so
/// moving a landmark here moves the flight with it.
abstract final class Landmarks {
  /// Width and height of both dock panels, in world units.
  ///
  /// Wide enough that a 16:9 view is limited by the panel's height rather than
  /// its width, so the dock distance barely changes across display shapes.
  static const double panelWidth = 46;
  static const double panelHeight = 25;

  /// Centre of the monolith standing in the forest clearing. The deck's last
  /// "paper" slide is this panel, seen head-on.
  static final vm.Vector3 dockA = vm.Vector3(0, 15.5, 0);

  /// Centre of the panel in front of the pavilion. The flight lands here and
  /// the gallery slide takes over.
  static final vm.Vector3 dockB = vm.Vector3(0, 19, 190);

  /// Vertical field of view used while parked at a dock. The cruise widens it.
  static const double dockFovY = 46 * math.pi / 180;

  /// Distance from a panel at which it just covers a viewport of [aspect].
  static double dockDistance(double aspect) {
    final halfTan = math.tan(dockFovY / 2);
    final byHeight = panelHeight / (2 * halfTan);
    final byWidth = panelWidth / (2 * halfTan * aspect);
    return math.min(byHeight, byWidth) * 0.97;
  }
}

/// The procedural low-poly landscape the deck flies through: a noise
/// heightfield with lakes, an instanced spruce forest, scattered boulders, a
/// glass-and-concrete pavilion, and the two dock panels the slides live on.
///
/// One instance is shared by the whole app. [ready] builds it once, off the
/// critical path — the deck kicks it off at launch so the flyover slide has
/// nothing left to do but render.
class FlyoverWorld {
  FlyoverWorld._();

  static final FlyoverWorld instance = FlyoverWorld._();

  final Scene scene = Scene();

  Future<void>? _ready;

  /// Completes once the scene graph is populated and safe to render.
  Future<void> get ready => _ready ??= _build();

  /// Whether [ready] has already completed, so a view can skip its spinner.
  bool get isReady => _built;
  bool _built = false;

  /// Verification aid, off in a normal run: `GPU_FLYOVER_CAPTURE=1` drops the
  /// dithered screen-space effects (AO, SSR), whose noise inflates a captured
  /// frame past what the Marionette screenshot transport carries.
  static final bool captureFriendly =
      Platform.environment['GPU_FLYOVER_CAPTURE'] == '1';

  // ---------------------------------------------------------------- terrain

  // Extent of the heightfield. The flight runs up +Z from the clearing at the
  // origin to the pavilion; X is the lateral swing.
  static const double _minX = -170, _maxX = 170;
  static const double _minZ = -100, _maxZ = 310;
  static const double _spacing = 2.6;

  /// Sea level. Everything the heightfield puts below this is under water.
  static const double waterLevel = 0.0;

  final FastNoiseLite _hills = FastNoiseLite(seed: 20260823)
    ..noiseType = NoiseType.openSimplex2
    ..fractalType = FractalType.fbm
    ..octaves = 5
    ..frequency = 0.0052;

  final FastNoiseLite _detail = FastNoiseLite(seed: 4711)
    ..noiseType = NoiseType.openSimplex2
    ..fractalType = FractalType.fbm
    ..octaves = 3
    ..frequency = 0.021;

  final FastNoiseLite _forest = FastNoiseLite(seed: 991)
    ..noiseType = NoiseType.openSimplex2
    ..fractalType = FractalType.fbm
    ..octaves = 3
    ..frequency = 0.011;

  /// Ground height at [x], [z]. The heightfield mesh, the tree scatter and the
  /// boulder scatter all read this one function, so nothing floats.
  double terrainHeight(double x, double z) {
    var y = 4.0 + _hills.getNoise2(x, z) * 12.0 + _detail.getNoise2(x, z) * 1.7;
    // The big lake the flight skims across.
    y = _mix(y, -9.0, _region(x, z, -16, 100, 70, 52));
    // The plateau the pavilion sits on.
    y = _mix(y, 3.0, _region(x, z, 0, 226, 72, 60));
    // The clearing around the monolith.
    y = _mix(y, 1.6, _region(x, z, 0, -6, 42, 36));
    return y;
  }

  /// How strongly a point sits inside an elliptical region: 1 at the centre,
  /// 0 outside it, smooth across the outer 45%.
  double _region(
    double x,
    double z,
    double cx,
    double cz,
    double rx,
    double rz,
  ) {
    final dx = (x - cx) / rx;
    final dz = (z - cz) / rz;
    return 1.0 - _smoothstep(0.55, 1.0, math.sqrt(dx * dx + dz * dz));
  }

  // ------------------------------------------------------------------ build

  Future<void> _build() async {
    await Scene.initializeStaticResources();

    _applyLook();
    scene.add(Node(mesh: Mesh(_buildTerrain(), _terrainMaterial())));
    scene.add(Node(mesh: Mesh(_buildWater(), _waterMaterial())));
    _scatterForest();
    _scatterBoulders();
    _buildMonolith();
    _buildPavilion();
    _buildFlock();
    await _buildRoofSign();

    _built = true;
  }

  /// Advances everything in the world that moves. Driven from the view's
  /// `SceneView.onTick`, so the scene animates only while it is on screen.
  void tick(double dt) {
    _time += dt;
    for (var i = 0; i < _birds.length; i++) {
      _birds[i].place(i, _time, _parts);
    }
  }

  double _time = 0;

  void _applyLook() {
    // Pale Nordic daylight: a low raking sun, cool zenith, warm haze at the
    // horizon so the far treeline dissolves instead of ending.
    final sky = GradientSkySource(
      zenithColor: linear3(const Color(0xFF8FA8BC)) * 1.05,
      horizonColor: linear3(const Color(0xFFE2D9C8)) * 0.95,
      groundColor: linear3(const Color(0xFF5E6058)),
      sunDirection: vm.Vector3(-0.35, 0.30, 0.88)..normalize(),
      sunColor: vm.Vector3(4.4, 3.9, 3.1),
      sunSharpness: 900,
    );

    // The sky bindings go *inside* EnvironmentSettings, not on the scene
    // beside it: assigning `scene.environmentSettings` applies the whole
    // snapshot, and the snapshot's own (null) skybox, skyEnvironment and
    // sunLight overwrite anything set on the scene before it.
    scene.environmentSettings = EnvironmentSettings(
      // Draw the sky behind the world, light the world from that same sky, and
      // aim the shadow-casting sun at the sky's own sun so soft and hard light
      // agree.
      skybox: Skybox(sky),
      skyEnvironment: SkyEnvironment(sky, faceResolution: 128),
      sunLight: SunLight(
        sky,
        castsShadow: true,
        intensityScale: 0.85,
        shadowMaxDistance: 190,
        shadowMapResolution: 2048,
        shadowSoftness: 0.05,
        shadowNormalBias: 0.06,
      ),
      toneMapping: ToneMappingMode.aces,
      exposure: 0.92,
      environmentIntensity: 0.45,
      colorGradingEnabled: true,
      saturation: 1.06,
      contrast: 1.10,
      temperature: 0.03,
      fogEnabled: true,
      fogMode: FogMode.exponential,
      fogColor: linear3(const Color(0xFFD3CFC2)),
      fogDensity: 0.0017,
      bloomEnabled: true,
      bloomThreshold: 1.85,
      bloomIntensity: 0.16,
      bloomScatter: 0.7,
      ambientOcclusionEnabled: !captureFriendly,
      ambientOcclusionIntensity: 0.85,
      ambientOcclusionHalfResolution: true,
      screenSpaceReflectionsEnabled: !captureFriendly,
      screenSpaceReflectionsIntensity: 0.85,
      vignetteEnabled: true,
      vignetteIntensity: 0.12,
    );
  }

  MeshGeometry _buildTerrain() {
    final cols = ((_maxX - _minX) / _spacing).round() + 1;
    final rows = ((_maxZ - _minZ) / _spacing).round() + 1;

    // Deduplication would hash every one of ~20k vertices for nothing: a grid
    // never emits the same position twice.
    final builder = GeometryBuilder(deduplicate: false);

    final rock = linear(const Color(0xFF8A8781));
    final shore = linear(sand);
    final grass = linear(sage);
    final deep = linear(spruce);
    final silt = linear(const Color(0xFF6E6A5C));

    for (var r = 0; r < rows; r++) {
      final z = _minZ + r * _spacing;
      for (var c = 0; c < cols; c++) {
        final x = _minX + c * _spacing;
        final y = terrainHeight(x, z);

        // Slope read back out of the height field, so cliff faces turn rocky.
        final dx = terrainHeight(x + 1.4, z) - terrainHeight(x - 1.4, z);
        final dz = terrainHeight(x, z + 1.4) - terrainHeight(x, z - 1.4);
        final slope = math.sqrt(dx * dx + dz * dz) / 2.8;

        var tint = _mix4(silt, shore, _smoothstep(-3.0, 0.4, y));
        tint = _mix4(tint, grass, _smoothstep(0.4, 2.2, y));
        tint = _mix4(tint, deep, _smoothstep(3.0, 13.0, y) * 0.5);
        tint = _mix4(tint, rock, _smoothstep(0.5, 1.4, slope) * 0.85);
        // A little per-vertex variation keeps the flat facets from banding.
        final speck = 1.0 + _detail.getNoise2(x * 3.1, z * 3.1) * 0.05;

        builder
          ..color(_scaled(tint, speck))
          ..addVertex(vm.Vector3(x, y, z));
      }
    }

    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final v00 = r * cols + c;
        final v10 = v00 + 1;
        final v01 = v00 + cols;
        final v11 = v01 + 1;
        builder
          ..addTriangle(v00, v10, v01)
          ..addTriangle(v10, v11, v01);
      }
    }

    return builder.build();
  }

  Material _terrainMaterial() => PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
    ..vertexColorWeight = 1.0
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.96;

  MeshGeometry _buildWater() => PlaneGeometry(
        width: _maxX - _minX + 40,
        depth: _maxZ - _minZ + 40,
      );

  Material _waterMaterial() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(const Color(0xFF3E5A66))
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.055;

  // ----------------------------------------------------------------- forest

  void _scatterForest() {
    final rng = math.Random(20260823);

    final spruces = InstancedMesh(
      geometry: _spruceGeometry(),
      material: _foliageMaterial(0.9),
      cullInstances: true,
    );
    final birches = InstancedMesh(
      geometry: _birchGeometry(),
      material: _foliageMaterial(0.85),
      cullInstances: true,
    );

    final needle = linear(spruce);
    final needleAlt = linear(const Color(0xFF3F5F52));
    final leaf = linear(const Color(0xFF9BAE86));

    var placed = 0;
    for (var attempt = 0; attempt < 26000 && placed < 2600; attempt++) {
      final x = _minX + rng.nextDouble() * (_maxX - _minX);
      final z = _minZ + rng.nextDouble() * (_maxZ - _minZ);
      final y = terrainHeight(x, z);
      if (y < waterLevel + 1.1 || y > 22) continue;

      // Nothing grows on a cliff face.
      final dx = terrainHeight(x + 2, z) - terrainHeight(x - 2, z);
      final dz = terrainHeight(x, z + 2) - terrainHeight(x, z - 2);
      if (math.sqrt(dx * dx + dz * dz) / 4 > 0.62) continue;

      // Keep the built areas clear.
      if (_region(x, z, 0, 226, 72, 60) > 0.30) continue;
      if (_region(x, z, 0, -6, 30, 26) > 0.28) continue;

      // Clumped stands rather than an even sprinkle.
      final density = _forest.getNoise2(x, z) * 0.5 + 0.5;
      if (rng.nextDouble() > density * density * 1.5) continue;

      final s = 0.7 + rng.nextDouble() * 0.8;
      final transform = vm.Matrix4.translation(vm.Vector3(x, y - 0.3, z))
        ..rotateY(rng.nextDouble() * math.pi * 2)
        ..scaleByDouble(s, s * (0.85 + rng.nextDouble() * 0.5), s, 1.0);

      if (rng.nextDouble() < 0.17) {
        birches.addInstance(
          transform,
          color: _scaled(leaf, 0.85 + rng.nextDouble() * 0.3),
        );
      } else {
        spruces.addInstance(
          transform,
          color: _scaled(
            rng.nextBool() ? needle : needleAlt,
            0.8 + rng.nextDouble() * 0.45,
          ),
        );
      }
      placed++;
    }

    scene.add(
        Node(name: 'spruces')..addComponent(InstancedMeshComponent(spruces)));
    scene.add(
        Node(name: 'birches')..addComponent(InstancedMeshComponent(birches)));
  }

  Material _foliageMaterial(double roughness) => PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
    ..vertexColorWeight = 1.0
    ..metallicFactor = 0.0
    ..roughnessFactor = roughness;

  /// A spruce: three stacked cone tiers on a short trunk, base at y = 0.
  /// Seven radial segments each, so the silhouette stays deliberately faceted.
  MeshGeometry _spruceGeometry() {
    final builder = GeometryBuilder(deduplicate: false);
    final bark = linear(const Color(0xFF6B5847));

    // Foliage carries the instance colour, so its vertex colour is near-white
    // and only the tiers' relative brightness is baked in.
    _addPrism(builder,
        radius: 0.16, bottom: 0.0, top: 1.5, sides: 5, color: bark);
    _addCone(builder,
        radius: 1.35,
        bottom: 1.1,
        top: 3.6,
        sides: 7,
        color: vm.Vector4(0.92, 0.92, 0.92, 1));
    _addCone(builder,
        radius: 1.05,
        bottom: 3.0,
        top: 5.4,
        sides: 7,
        color: vm.Vector4(1.0, 1.0, 1.0, 1));
    _addCone(builder,
        radius: 0.70,
        bottom: 4.8,
        top: 7.0,
        sides: 7,
        color: vm.Vector4(1.1, 1.1, 1.1, 1));
    return builder.build();
  }

  /// A birch: a pale trunk under a rounded, faceted crown (a cone up and a
  /// cone down sharing a rim).
  MeshGeometry _birchGeometry() {
    final builder = GeometryBuilder(deduplicate: false);
    final bark = linear(const Color(0xFFD8D3C6));

    _addPrism(builder,
        radius: 0.13, bottom: 0.0, top: 2.8, sides: 5, color: bark);
    _addCone(builder,
        radius: 1.3,
        bottom: 3.0,
        top: 5.0,
        sides: 6,
        color: vm.Vector4(1, 1, 1, 1));
    _addCone(builder,
        radius: 1.3,
        bottom: 3.0,
        top: 1.7,
        sides: 6,
        color: vm.Vector4(0.88, 0.88, 0.88, 1));
    return builder.build();
  }

  // --------------------------------------------------------------- boulders

  void _scatterBoulders() {
    final rng = math.Random(31337);
    final mesh = InstancedMesh(
      geometry: IcosphereGeometry(radius: 1.0, subdivisions: 1),
      material: PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
        ..vertexColorWeight = 1.0
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.98,
      cullInstances: true,
    );
    final stone = linear(const Color(0xFF9A968D));

    var placed = 0;
    for (var attempt = 0; attempt < 9000 && placed < 700; attempt++) {
      final x = _minX + rng.nextDouble() * (_maxX - _minX);
      final z = _minZ + rng.nextDouble() * (_maxZ - _minZ);
      final y = terrainHeight(x, z);
      // Boulders belong on the shoreline and on the bare high ground.
      if (y < waterLevel - 1.6) continue;
      if (y > 3.0 && y < 13.0 && rng.nextDouble() < 0.8) continue;
      if (_region(x, z, 0, 226, 70, 56) > 0.3) continue;

      final s = 0.5 + rng.nextDouble() * 2.1;
      mesh.addInstance(
        vm.Matrix4.translation(vm.Vector3(x, y - s * 0.35, z))
          ..rotateY(rng.nextDouble() * math.pi)
          ..rotateX(rng.nextDouble() * 0.5)
          ..scaleByDouble(s, s * 0.65, s * 0.9, 1.0),
        color: _scaled(stone, 0.8 + rng.nextDouble() * 0.4),
      );
      placed++;
    }

    scene.add(
        Node(name: 'boulders')..addComponent(InstancedMeshComponent(mesh)));
  }

  // ----------------------------------------------------------------- panels

  /// A dock panel's face: unlit, so it reads as a lit screen rather than a
  /// shaded surface and holds the same value from every angle.
  ///
  /// The factor is not 1: an unlit material still goes through exposure and
  /// ACES tone mapping, which pulls a paper-white panel down to a mid grey.
  /// Pre-multiplying by [_panelGain] lands the rendered panel back on the
  /// deck's paper, so the wash can dissolve off it without a visible step.
  static const double _panelGain = 1.58;

  Material _panelMaterial() {
    final material = UnlitMaterial();
    material.baseColorFactor = _scaled(linear(paper), _panelGain);
    return material;
  }

  Node _panel(vm.Vector3 centre) => Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(
            Landmarks.panelWidth,
            Landmarks.panelHeight,
            0.9,
          )),
          _panelMaterial(),
        ),
      )..position = centre;

  void _buildMonolith() {
    final centre = Landmarks.dockA;
    scene.add(_panel(centre));

    // A dark frame standing just behind the panel gives it an edge to read
    // against the sky as the camera pulls away.
    scene.add(Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(
          Landmarks.panelWidth + 1.6,
          Landmarks.panelHeight + 1.6,
          0.6,
        )),
        PhysicallyBasedMaterial()
          ..baseColorFactor = linear(const Color(0xFF3A3D3F))
          ..metallicFactor = 0.25
          ..roughnessFactor = 0.5,
      ),
    )..position = centre + vm.Vector3(0, 0, 0.7));

    // Concrete plinth, sunk into the clearing.
    final base = centre.y - Landmarks.panelHeight / 2;
    _box(Landmarks.panelWidth + 4, 4.0, 6, _concrete(),
        vm.Vector3(centre.x, base - 1.4, centre.z + 0.6));
  }

  Material _signBoard() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(const Color(0xFF34383A))
    ..metallicFactor = 0.2
    ..roughnessFactor = 0.55;

  Material _concrete() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(const Color(0xFFE7E3DA))
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.72;

  Material _glass() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(const Color(0xFF16252B))
    ..metallicFactor = 0.35
    ..roughnessFactor = 0.09;

  Material _wood() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(clay)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.6;

  Material _steel() => PhysicallyBasedMaterial()
    ..baseColorFactor = linear(const Color(0xFFBFC3C4))
    ..metallicFactor = 0.85
    ..roughnessFactor = 0.28;

  void _add(MeshGeometry geometry, Material material, vm.Vector3 at) {
    scene.add(Node(mesh: Mesh(geometry, material))..position = at);
  }

  void _box(double w, double h, double d, Material material, vm.Vector3 at) {
    _add(CuboidGeometry(vm.Vector3(w, h, d)), material, at);
  }

  /// The pavilion the flight lands at: a glazed ground floor under a long
  /// white cantilever, a smaller upper volume, and a steel ring landmark.
  /// Everything faces −Z, the direction the camera arrives from.
  void _buildPavilion() {
    // The pavilion sits well behind the landing panel (z = 190), so the
    // cantilever clears it instead of cutting across it.
    const z = 228.0; // plateau centre
    const podiumTop = 4.0;

    // The podium reaches forward under the panel; the step below it runs on
    // toward the camera so the approach lands on a plaza, not on grass.
    _box(104, 2.4, 92, _concrete(), vm.Vector3(0, podiumTop - 1.2, z - 12));
    _box(132, 1.2, 118, _concrete(), vm.Vector3(0, podiumTop - 2.6, z - 22));

    // Glazed ground floor; its facade lands at z = 194.
    _box(78, 11, 40, _glass(), vm.Vector3(0, podiumTop + 5.5, z + 2));
    for (var i = -6; i <= 6; i++) {
      _box(0.9, 11.4, 1.4, _concrete(),
          vm.Vector3(i * 6.2, podiumTop + 5.5, z - 18.4));
    }

    // The cantilever: a long white slab reaching out over the approach.
    _box(88, 2.6, 34, _concrete(), vm.Vector3(0, podiumTop + 12.3, z - 6));
    _box(84, 0.4, 30, _wood(), vm.Vector3(0, podiumTop + 10.8, z - 6));
    for (final cx in <double>[-38, 38]) {
      for (final cz in <double>[z - 20, z + 6]) {
        _add(
          CylinderGeometry(
              bottomRadius: 0.55,
              topRadius: 0.55,
              height: 12,
              radialSegments: 12),
          _steel(),
          vm.Vector3(cx, podiumTop + 6, cz),
        );
      }
    }

    // Upper volume, set back and offset.
    _box(54, 9, 26, _concrete(), vm.Vector3(-8, podiumTop + 18.1, z + 4));
    _box(54.6, 3.4, 26.6, _glass(), vm.Vector3(-8, podiumTop + 18.6, z + 4));
    _box(60, 1.4, 32, _concrete(), vm.Vector3(-8, podiumTop + 23.3, z + 4));

    // Steel ring landmark, stood on edge beside the pavilion.
    scene.add(Node(
      mesh: Mesh(
        TorusGeometry(
            radius: 15, tubeRadius: 0.55, tubularSegments: 40,
            radialSegments: 8),
        _steel(),
      ),
    )
      ..position = vm.Vector3(58, podiumTop + 15, z - 6)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2));

    // Warm interior lights behind the glass, so the pavilion reads as
    // inhabited when the camera closes in.
    final glow = PhysicallyBasedMaterial()
      ..baseColorFactor = linear(const Color(0xFFFFE9C8))
      ..emissiveFactor = linear(const Color(0xFFFFD9A0))
      ..emissiveStrength = 3.0;
    for (var i = -4; i <= 4; i++) {
      _box(4.0, 0.25, 0.25, glow, vm.Vector3(i * 8.0, podiumTop + 9.6, z + 6));
    }

    // The landing panel, freestanding on the podium in front of the facade.
    final dock = Landmarks.dockB;
    scene.add(_panel(dock));
    _box(Landmarks.panelWidth + 3, 0.8, 3.4, _steel(),
        vm.Vector3(dock.x, dock.y - Landmarks.panelHeight / 2 - 0.4, dock.z));
    for (final fx in <double>[
      -Landmarks.panelWidth / 2 - 1.0,
      Landmarks.panelWidth / 2 + 1.0,
    ]) {
      _box(1.2, Landmarks.panelHeight + 2.4, 1.2, _steel(),
          vm.Vector3(dock.x + fx, dock.y, dock.z));
    }
    _box(Landmarks.panelWidth + 6, 3.0, 5.0, _concrete(),
        vm.Vector3(dock.x, podiumTop + 1.0, dock.z));
  }

  // ------------------------------------------------------------ roof sign

  /// The Flutter & Friends logo, standing on the pavilion's upper roof and
  /// facing the approach.
  ///
  /// Unlit and alpha-blended: the artwork is a sticker with its own white
  /// keyline, so shading it would only muddy it, and it has to stay legible
  /// against a bright sky.
  Future<void> _buildRoofSign() async {
    const height = 18.0;
    const width = height * 1.1716; // the artwork's aspect
    // High enough on its posts to clear the landing panel on the approach —
    // and still behind it at the dock, where the panel fills the frame.
    final centre = vm.Vector3(-8, 49.0, 219);

    final Texture2D logo;
    try {
      // The asset carries a transparent margin, which is why no clamped
      // address mode is set here: the sampler's default wrap only ever
      // reaches those empty pixels. (Passing one is awkward anyway — the
      // analyzer resolves flutter_scene's conditional gpu export to its stub,
      // so `gpu.SamplerAddressMode` is a different type to it.)
      logo = await Texture2D.fromAsset(
        'assets/images/flutter-and-friends.png',
      );
    } catch (_) {
      // A missing logo is not worth losing the landscape over.
      return;
    }

    // Unlit is not the same as untouched: the artwork still goes through
    // exposure and ACES, which drains it. The same gain the dock panels use
    // puts the blues back.
    final sign = UnlitMaterial(colorTexture: logo)
      ..alphaMode = AlphaMode.blend
      ..baseColorFactor = vm.Vector4(_panelGain, _panelGain, _panelGain, 1);

    scene.add(Node(mesh: Mesh(_signQuad(width, height), sign))
      ..position = centre);

    // A dark backing board: the artwork is a sticker with a white keyline,
    // which disappears against concrete and pops against charcoal. It also
    // gives the sign a back, so it still reads as an object from behind.
    _box(width + 1.4, height + 1.4, 0.35, _signBoard(),
        centre + vm.Vector3(0, 0, 0.3));
    for (final x in <double>[-width / 3, width / 3]) {
      _box(0.55, 12, 0.55, _steel(),
          vm.Vector3(centre.x + x, centre.y - height / 2 - 6.0, centre.z + 0.3));
    }
  }

  /// A quad in the XY plane facing −Z, with the texture the right way up.
  ///
  /// Authored by hand rather than rotating a [PlaneGeometry], because that
  /// leaves the artwork's orientation up to the primitive's UV convention.
  MeshGeometry _signQuad(double width, double height) {
    final builder = GeometryBuilder(deduplicate: false);
    final hw = width / 2;
    final hh = height / 2;
    builder.normal(vm.Vector3(0, 0, -1));

    int corner(double x, double y, double u, double v) {
      builder.texCoord(vm.Vector2(u, v));
      return builder.addVertex(vm.Vector3(x, y, 0));
    }

    final tl = corner(-hw, hh, 0, 0);
    final tr = corner(hw, hh, 1, 0);
    final br = corner(hw, -hh, 1, 1);
    final bl = corner(-hw, -hh, 0, 1);
    builder
      ..addTriangle(tl, br, tr)
      ..addTriangle(tl, bl, br);
    return builder.build();
  }

  // ---------------------------------------------------------------- the flock

  final List<_Dash> _birds = [];
  _DashParts? _parts;

  /// A flock of simplified Dashes, three loose circles over the places the
  /// flight passes: the clearing, the lake, and the pavilion.
  ///
  /// Every bird is the same six meshes drawn instanced — body, belly, beak,
  /// tail, wings, eyes — so the whole flock costs six draw calls no matter how
  /// many there are, and [tick] just rewrites the transforms.
  void _buildFlock() {
    final rng = math.Random(505);
    final parts = _DashParts();
    _parts = parts;

    void flock({
      required vm.Vector3 centre,
      required double radius,
      required int count,
      required double scale,
    }) {
      for (var i = 0; i < count; i++) {
        _birds.add(_Dash(
          centre: centre,
          radius: radius * (0.55 + rng.nextDouble() * 0.7),
          lift: (rng.nextDouble() - 0.5) * 11,
          speed: (0.16 + rng.nextDouble() * 0.12) * (rng.nextBool() ? 1 : -1),
          phase: rng.nextDouble() * math.pi * 2,
          scale: scale * (0.8 + rng.nextDouble() * 0.5),
          bobRate: 0.7 + rng.nextDouble() * 0.5,
          flapRate: 5.0 + rng.nextDouble() * 2.5,
        ));
        parts.reserve();
      }
    }

    flock(centre: vm.Vector3(30, 36, -12), radius: 32, count: 7, scale: 1.15);
    flock(centre: vm.Vector3(-16, 20, 100), radius: 48, count: 9, scale: 1.30);
    flock(centre: vm.Vector3(14, 46, 216), radius: 36, count: 8, scale: 1.15);

    parts.attach(scene);
  }

  // ------------------------------------------------------- geometry helpers

  /// A closed cone between [bottom] and [top]. A [top] below [bottom] gives an
  /// upside-down cone with its winding flipped to match.
  void _addCone(
    GeometryBuilder builder, {
    required double radius,
    required double bottom,
    required double top,
    required int sides,
    required vm.Vector4 color,
  }) {
    builder.color(color);
    final flip = top < bottom;
    final apex = builder.addVertex(vm.Vector3(0, top, 0));
    final centre = builder.addVertex(vm.Vector3(0, bottom, 0));
    final rim = <int>[
      for (var i = 0; i < sides; i++)
        builder.addVertex(vm.Vector3(
          math.cos(i * 2 * math.pi / sides) * radius,
          bottom,
          math.sin(i * 2 * math.pi / sides) * radius,
        )),
    ];
    for (var i = 0; i < sides; i++) {
      final a = rim[i];
      final b = rim[(i + 1) % sides];
      if (flip) {
        builder
          ..addTriangle(apex, a, b)
          ..addTriangle(centre, b, a);
      } else {
        builder
          ..addTriangle(apex, b, a)
          ..addTriangle(centre, a, b);
      }
    }
  }

  /// A closed prism (a low-segment cylinder), used for trunks.
  void _addPrism(
    GeometryBuilder builder, {
    required double radius,
    required double bottom,
    required double top,
    required int sides,
    required vm.Vector4 color,
  }) {
    builder.color(color);
    final lower = <int>[];
    final upper = <int>[];
    for (var i = 0; i < sides; i++) {
      final a = i * 2 * math.pi / sides;
      final x = math.cos(a) * radius;
      final z = math.sin(a) * radius;
      lower.add(builder.addVertex(vm.Vector3(x, bottom, z)));
      upper.add(builder.addVertex(vm.Vector3(x, top, z)));
    }
    final cap = builder.addVertex(vm.Vector3(0, top, 0));
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      builder
        ..addTriangle(lower[i], upper[j], upper[i])
        ..addTriangle(lower[i], lower[j], upper[j])
        ..addTriangle(cap, upper[i], upper[j]);
    }
  }
}

double _mix(double a, double b, double t) => a + (b - a) * t;

vm.Vector4 _mix4(vm.Vector4 a, vm.Vector4 b, double t) =>
    vm.Vector4(_mix(a.x, b.x, t), _mix(a.y, b.y, t), _mix(a.z, b.z, t), 1.0);

/// [color] scaled in RGB only — alpha stays 1, which is what both the
/// instance-colour multiplier and a base-colour factor want.
vm.Vector4 _scaled(vm.Vector4 color, double k) =>
    vm.Vector4(color.x * k, color.y * k, color.z * k, 1.0);

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}


/// One bird's flight: a slow circle, a lazy bob, and a wing beat.
class _Dash {
  _Dash({
    required this.centre,
    required this.radius,
    required this.lift,
    required this.speed,
    required this.phase,
    required this.scale,
    required this.bobRate,
    required this.flapRate,
  });

  final vm.Vector3 centre;
  final double radius;
  final double lift;
  final double speed;
  final double phase;
  final double scale;
  final double bobRate;
  final double flapRate;

  /// Rewrites this bird's instance transforms for time [t].
  void place(int index, double t, _DashParts? parts) {
    if (parts == null) return;

    final angle = phase + t * speed;
    final position = vm.Vector3(
      centre.x + math.cos(angle) * radius,
      centre.y + lift + math.sin(t * bobRate + phase) * 1.7,
      centre.z + math.sin(angle) * radius,
    );

    // Heading is the tangent of the circle; the lean into it is constant,
    // which is all a bird at this distance needs to read as banking.
    final yaw = math.atan2(-math.sin(angle) * speed, math.cos(angle) * speed);
    final body = vm.Matrix4.translation(position)
      ..rotateY(yaw)
      ..rotateZ(speed > 0 ? -0.22 : 0.22)
      ..scaleByDouble(scale, scale, scale, 1.0);

    parts.place(index, body, math.sin(t * flapRate + phase) * 0.68);
  }
}

/// The instanced meshes every Dash is drawn from, plus the local placement of
/// each part on the bird.
class _DashParts {
  _DashParts() {
    final ball = IcosphereGeometry(radius: 0.5, subdivisions: 1);
    final cone = CylinderGeometry(
      bottomRadius: 0.5,
      topRadius: 0.0,
      height: 1,
      radialSegments: 6,
    );

    body = _mesh(ball, const Color(0xFF54C5F8), 0.55);
    belly = _mesh(ball, const Color(0xFFE4F5FE), 0.7);
    beak = _mesh(cone, const Color(0xFFFFC24B), 0.5);
    tail = _mesh(cone, const Color(0xFF3AAEE8), 0.6);
    wing = _mesh(_dashWingGeometry(), const Color(0xFF3AAEE8), 0.6);
    eye = _mesh(ball, const Color(0xFF23262A), 0.35);
  }

  late final InstancedMesh body;
  late final InstancedMesh belly;
  late final InstancedMesh beak;
  late final InstancedMesh tail;
  late final InstancedMesh wing;
  late final InstancedMesh eye;

  static InstancedMesh _mesh(Geometry geometry, Color color, double roughness) {
    return InstancedMesh(
      geometry: geometry,
      material: PhysicallyBasedMaterial()
        ..baseColorFactor = linear(color)
        ..metallicFactor = 0.0
        ..roughnessFactor = roughness,
      cullInstances: true,
    );
  }

  // Local placement of each part on a bird facing +Z. The cones are modelled
  // along +Y, so they are turned a quarter turn to point along the body.
  static final vm.Matrix4 _body =
      vm.Matrix4.identity()..scaleByDouble(1.10, 1.05, 1.26, 1.0);
  static final vm.Matrix4 _belly =
      vm.Matrix4.translation(vm.Vector3(0, -0.13, 0.10))
        ..scaleByDouble(0.98, 0.86, 1.04, 1.0);
  static final vm.Matrix4 _beak =
      vm.Matrix4.translation(vm.Vector3(0, -0.02, 0.62))
        ..rotateX(math.pi / 2)
        ..scaleByDouble(0.20, 0.36, 0.20, 1.0);
  static final vm.Matrix4 _tail =
      vm.Matrix4.translation(vm.Vector3(0, 0.08, -0.60))
        ..rotateX(-math.pi / 2)
        ..scaleByDouble(0.40, 0.46, 0.14, 1.0);
  static final vm.Matrix4 _eyeLeft =
      vm.Matrix4.translation(vm.Vector3(-0.22, 0.14, 0.48))
        ..scaleByDouble(0.17, 0.17, 0.17, 1.0);
  static final vm.Matrix4 _eyeRight =
      vm.Matrix4.translation(vm.Vector3(0.22, 0.14, 0.48))
        ..scaleByDouble(0.17, 0.17, 0.17, 1.0);
  static final vm.Matrix4 _wingRoot =
      vm.Matrix4.translation(vm.Vector3(0.40, 0.10, -0.02));
  // The left wing is the right one mirrored; InstancedMesh tracks the flipped
  // winding from the transform's determinant, so it still shades correctly.
  static final vm.Matrix4 _wingMirror =
      vm.Matrix4.identity()..scaleByDouble(-1, 1, 1, 1.0);

  /// Adds slots for one more bird. Called once per bird at build time so the
  /// per-frame path only ever rewrites transforms.
  void reserve() {
    final identity = vm.Matrix4.identity();
    body.addInstance(identity);
    belly.addInstance(identity);
    beak.addInstance(identity);
    tail.addInstance(identity);
    eye.addInstance(identity);
    eye.addInstance(identity);
    wing.addInstance(identity);
    wing.addInstance(identity);
  }

  void place(int index, vm.Matrix4 bodyTransform, double flap) {
    body.setInstanceTransform(index, bodyTransform.multiplied(_body));
    belly.setInstanceTransform(index, bodyTransform.multiplied(_belly));
    beak.setInstanceTransform(index, bodyTransform.multiplied(_beak));
    tail.setInstanceTransform(index, bodyTransform.multiplied(_tail));
    eye.setInstanceTransform(index * 2, bodyTransform.multiplied(_eyeLeft));
    eye.setInstanceTransform(index * 2 + 1, bodyTransform.multiplied(_eyeRight));

    final beat = vm.Matrix4.identity()..rotateZ(flap);
    final right = bodyTransform.multiplied(_wingRoot).multiplied(beat);
    wing.setInstanceTransform(index * 2, right);
    wing.setInstanceTransform(index * 2 + 1, right.multiplied(_wingMirror));
  }

  void attach(Scene scene) {
    for (final mesh in <InstancedMesh>[body, belly, beak, tail, wing, eye]) {
      scene.add(Node()..addComponent(InstancedMeshComponent(mesh)));
    }
  }
}

/// One wing: a flat tapered blade reaching out along +X from the shoulder,
/// emitted front and back so it is visible whichever way the bird banks.
MeshGeometry _dashWingGeometry() {
  final builder = GeometryBuilder(deduplicate: false);
  const outline = <List<double>>[
    [0.02, 0.34],
    [1.05, 0.13],
    [1.02, -0.17],
    [0.02, -0.40],
  ];
  final front = <int>[
    for (final p in outline) builder.addVertex(vm.Vector3(p[0], 0, p[1])),
  ];
  builder
    ..addTriangle(front[0], front[1], front[2])
    ..addTriangle(front[0], front[2], front[3])
    ..addTriangle(front[0], front[2], front[1])
    ..addTriangle(front[0], front[3], front[2]);
  return builder.build();
}
