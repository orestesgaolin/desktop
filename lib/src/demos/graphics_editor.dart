import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../frame.dart';
import '../gpu_widgets.dart';
import 'graphics_document.dart';

const _shell = Color(0xFF171717);
const _panel = Color(0xFF202020);
const _panelHi = Color(0xFF292929);
const _menuSurface = Color(0xFF454545);
const _line = Color(0xFF393939);
const _muted = Color(0xFFA4A4A4);
const _accent = Color(0xFF8D7CFF);

enum _LayerKind { rectangle, ellipse, line, text, image, component }

enum _LayerFilter { none, mono, sepia, warm }

enum _CanvasEffect { none, paper, halftone, ripple, custom }

enum _GuideAxis { horizontal, vertical }

const _textFontFamilies = <String>[
  'System',
  'Avenir Next',
  'Helvetica Neue',
  'Futura',
  'Georgia',
  'Menlo',
];

enum _LayerCommand {
  copy,
  cut,
  paste,
  delete,
  duplicate,
  rename,
  moveToFront,
  moveToBack,
  focus,
  editComponent,
}

class _AlignmentGuide {
  const _AlignmentGuide({required this.axis, required this.position});

  final _GuideAxis axis;
  final double position;
}

class _SnapResult {
  const _SnapResult({required this.position, required this.guides});

  final Offset position;
  final List<_AlignmentGuide> guides;
}

class _AxisSnap {
  const _AxisSnap({required this.correction, required this.target});

  final double correction;
  final double target;
}

enum _ResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesRight =>
      this == topRight || this == right || this == bottomRight;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get movesBottom =>
      this == bottomLeft || this == bottom || this == bottomRight;
  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomRight ||
      this == bottomLeft;
}

Offset _rotateOffset(Offset offset, double angle) {
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return Offset(
    offset.dx * cosine - offset.dy * sine,
    offset.dx * sine + offset.dy * cosine,
  );
}

double _snapRotation(double angle) {
  const step = math.pi / 4;
  return (angle / step).round() * step;
}

class _DesignLayer {
  _DesignLayer({
    required this.id,
    required this.name,
    required this.kind,
    required this.position,
    required this.size,
    required this.color,
    this.text,
    this.rotation = 0,
    this.borderRadius = 0,
    this.imageSource,
    this.componentId,
    this.parentId,
    this.parentSlot,
    Map<String, String?>? slots,
    Map<String, Object?>? properties,
  }) : slots = Map<String, String?>.of(slots ?? const {}),
       properties = Map<String, Object?>.of(properties ?? const {});

  final String id;
  String name;
  _LayerKind kind;
  Offset position;
  Size size;
  Color color;
  String? text;
  double rotation;
  double borderRadius;
  GraphicsImageSource? imageSource;
  _LayerFilter filter = _LayerFilter.none;
  String? componentId;
  String? parentId;
  String? parentSlot;
  final Map<String, String?> slots;
  final Map<String, Object?> properties;

  _CanvasEffect get shaderEffect => _enumByName(
    _CanvasEffect.values,
    properties['shaderEffect'] as String? ?? 'none',
    'node.properties.shaderEffect',
  );

  set shaderEffect(_CanvasEffect value) =>
      properties['shaderEffect'] = value.name;
}

class GraphicsEditorView extends StatefulWidget {
  const GraphicsEditorView({
    super.key,
    required this.playback,
    this.enableShaders = true,
  });

  final PlaybackController playback;

  /// Tests can exercise the complete editor workflow without a GPU context.
  final bool enableShaders;

  @override
  State<GraphicsEditorView> createState() => _GraphicsEditorViewState();
}

class _GraphicsEditorViewState extends State<GraphicsEditorView> {
  static const _maximumImportedDocumentBytes = 32 * 1024 * 1024;
  static const _historyPlaybackStep = Duration(milliseconds: 240);

  static const _documentTypes = <XTypeGroup>[
    XTypeGroup(label: 'GPU design document', extensions: ['gpudoc', 'json']),
  ];

  final _prompt = TextEditingController(
    text: 'Design a mobile app with a header, cards, and bottom navigation',
  );
  late final TextEditingController _shaderSource = TextEditingController(
    text: _effectSource(_CanvasEffect.halftone),
  );
  final GlobalKey _workspaceKey = GlobalKey();
  final List<_DesignLayer> _layers = [];
  final Map<String, GraphicsComponentDefinition> _components = {
    for (final component in _defaultComponentDefinitions())
      component.id: component,
  };
  int _nextId = 1;
  String? _selectedId;
  String _documentName = 'Mobile app';
  Size _documentSize = const Size(840, 520);
  Map<String, Object?> _documentMetadata = {
    'generator': 'gpu_playground',
    'gridUnit': 8,
  };
  String _documentStatus = '';
  bool _documentStatusIsError = false;
  double _zoom = 1;
  double _gridUnit = 8;
  String? _activeMoveLayerId;
  Offset? _activeMoveRawPosition;
  List<_AlignmentGuide> _activeGuides = const [];
  _CanvasEffect _canvasEffect = _CanvasEffect.none;
  String _appliedCustomShader = _effectSource(_CanvasEffect.halftone);
  String _lastGoodCustomShader = _effectSource(_CanvasEffect.halftone);
  int _shaderCompilationRevision = 0;
  String? _shaderTargetLayerId;
  GpuShaderCompileStatus? _shaderStatus;
  late GraphicsDocumentHistory _history;
  final Map<String, String?> _selectionByHistoryState = {};
  Timer? _historyPlaybackTimer;
  bool _isPlayingHistory = false;
  int? _historyPlaybackIndex;
  String? _historyPlaybackRestoreSelectedId;
  List<_DesignLayer> _clipboard = const [];
  String? _renamingLayerId;
  String? _editingTextLayerId;
  final TextEditingController _inlineEditor = TextEditingController();
  final FocusNode _renameFocus = FocusNode();
  final FocusNode _textEditFocus = FocusNode();
  String? _editingComponentLayerId;
  String? _selectedComponentSlot;
  double _panZoomStartZoom = 1;
  Offset _panOffset = Offset.zero;
  Offset _panZoomSceneFocal = Offset.zero;
  double _fitScale = 1;
  Size _workspaceSize = Size.zero;
  int? _viewportPanPointer;
  Offset? _viewportPanPosition;

  _DesignLayer? get _selected {
    for (final layer in _layers) {
      if (layer.id == _selectedId) return layer;
    }
    return null;
  }

  _DesignLayer? _layerById(String? id) {
    if (id == null) return null;
    for (final layer in _layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  Iterable<_DesignLayer> _descendantsOf(String parentId) sync* {
    for (final child in _layers.where((layer) => layer.parentId == parentId)) {
      yield child;
      yield* _descendantsOf(child.id);
    }
  }

  bool _canReparent(String childId, String parentId) {
    final parent = _layerById(parentId);
    if (parent == null ||
        parent.kind == _LayerKind.text ||
        parent.kind == _LayerKind.line) {
      return false;
    }
    if (childId == parentId ||
        _descendantsOf(childId).any((layer) => layer.id == parentId)) {
      return false;
    }
    var parentDepth = 1;
    var ancestor = parent;
    while (ancestor.parentId != null) {
      parentDepth++;
      ancestor = _layerById(ancestor.parentId)!;
    }
    var subtreeDepth = 1;
    void inspectSubtree(String id, int depth) {
      subtreeDepth = math.max(subtreeDepth, depth);
      for (final child in _layers.where((layer) => layer.parentId == id)) {
        inspectSubtree(child.id, depth + 1);
      }
    }

    inspectSubtree(childId, 1);
    return parentDepth + subtreeDepth <= GraphicsDocument.maximumNestingDepth;
  }

  void _reparentLayer(String childId, String? parentId) {
    final child = _layerById(childId);
    if (child == null || child.parentId == parentId) return;
    if (parentId != null && !_canReparent(childId, parentId)) return;
    _commitMutation(() {
      child.parentId = parentId;
      child.parentSlot = null;
      _selectedId = child.id;
    });
  }

  void _moveLayerRelative(
    String childId,
    String targetId, {
    required bool above,
  }) {
    final child = _layerById(childId);
    final target = _layerById(targetId);
    if (child == null || target == null || child.id == target.id) return;
    if (target.parentId != null && !_canReparent(childId, target.parentId!)) {
      return;
    }
    _commitMutation(() {
      _layers.remove(child);
      child.parentId = target.parentId;
      child.parentSlot = null;
      final targetIndex = _layers.indexOf(target);
      _layers.insert(above ? targetIndex + 1 : targetIndex, child);
      _selectedId = child.id;
    });
  }

  String _newNodeId() {
    while (true) {
      final candidate = 'node-${_nextId++}';
      if (_layers.every((node) => node.id != candidate)) return candidate;
    }
  }

  @override
  void initState() {
    super.initState();
    _buildStarterComposition();
    final starterStates = _starterAutoplayStates();
    _history = GraphicsDocumentHistory(starterStates.first);
    for (final state in starterStates.skip(1)) {
      _history.commit(state);
    }
    _rememberHistorySelection(_history.current);
  }

  @override
  void dispose() {
    _historyPlaybackTimer?.cancel();
    _prompt.dispose();
    _shaderSource.dispose();
    _inlineEditor.dispose();
    _renameFocus.dispose();
    _textEditFocus.dispose();
    super.dispose();
  }

  void _buildStarterComposition() {
    final appBackgroundId = _newNodeId();
    final headerId = _newNodeId();
    final featuredCardId = _newNodeId();
    _layers
      ..clear()
      ..addAll([
        _DesignLayer(
          id: appBackgroundId,
          name: 'Phone frame',
          kind: _LayerKind.rectangle,
          position: const Offset(260, 8),
          size: const Size(320, 504),
          color: const Color(0xFFF4F2ED),
          borderRadius: 32,
        ),
        _DesignLayer(
          id: headerId,
          name: 'Header',
          kind: _LayerKind.rectangle,
          position: const Offset(276, 24),
          size: const Size(288, 54),
          color: const Color(0xFFFFFFFF),
          borderRadius: 22,
          parentId: appBackgroundId,
        ),
        _DesignLayer(
          id: 'starter-header-title',
          name: 'Header title',
          kind: _LayerKind.text,
          position: const Offset(294, 29),
          size: const Size(220, 22),
          color: const Color(0xFF1D1C22),
          text: 'Good morning',
          parentId: headerId,
          properties: const {'fontSize': 14.0, 'bold': true},
        ),
        _DesignLayer(
          id: 'starter-header-caption',
          name: 'Header caption',
          kind: _LayerKind.text,
          position: const Offset(294, 53),
          size: const Size(250, 20),
          color: const Color(0xFF77747F),
          text: 'Your workspace, at a glance',
          parentId: headerId,
          properties: const {'fontSize': 10.0},
        ),
        _DesignLayer(
          id: featuredCardId,
          name: 'Featured card',
          kind: _LayerKind.rectangle,
          position: const Offset(276, 90),
          size: const Size(288, 136),
          color: const Color(0xFF5A49C7),
          borderRadius: 26,
          parentId: appBackgroundId,
          properties: const {'shaderEffect': 'paper'},
        ),
        _DesignLayer(
          id: 'starter-feature-label',
          name: 'Featured label',
          kind: _LayerKind.text,
          position: const Offset(294, 103),
          size: const Size(220, 22),
          color: const Color(0xFFDAD5FF),
          text: 'FEATURED',
          parentId: featuredCardId,
          properties: const {'fontSize': 9.0, 'bold': true},
        ),
        _DesignLayer(
          id: 'starter-feature-title',
          name: 'Featured title',
          kind: _LayerKind.text,
          position: const Offset(294, 132),
          size: const Size(250, 26),
          color: const Color(0xFFFFFFFF),
          text: 'Build better habits',
          parentId: featuredCardId,
          properties: const {'fontSize': 16.0, 'bold': true},
        ),
        _DesignLayer(
          id: 'starter-feature-copy',
          name: 'Featured copy',
          kind: _LayerKind.text,
          position: const Offset(294, 169),
          size: const Size(252, 44),
          color: const Color(0xFFE8E5FF),
          text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
          parentId: featuredCardId,
          properties: const {'fontSize': 11.0},
        ),
        _DesignLayer(
          id: 'starter-card-focus',
          name: 'Focus card',
          kind: _LayerKind.rectangle,
          position: const Offset(276, 238),
          size: const Size(138, 104),
          color: const Color(0xFFFFD76A),
          borderRadius: 22,
          parentId: appBackgroundId,
        ),
        _DesignLayer(
          id: 'starter-card-focus-copy',
          name: 'Focus card copy',
          kind: _LayerKind.text,
          position: const Offset(290, 250),
          size: const Size(110, 80),
          color: const Color(0xFF27231A),
          text: 'Focus\n\nLorem ipsum dolor sit amet.',
          parentId: 'starter-card-focus',
          properties: const {'fontSize': 10.0},
        ),
        _DesignLayer(
          id: 'starter-card-progress',
          name: 'Progress card',
          kind: _LayerKind.rectangle,
          position: const Offset(426, 238),
          size: const Size(138, 104),
          color: const Color(0xFFB8DED7),
          borderRadius: 22,
          parentId: appBackgroundId,
        ),
        _DesignLayer(
          id: 'starter-card-progress-copy',
          name: 'Progress card copy',
          kind: _LayerKind.text,
          position: const Offset(440, 250),
          size: const Size(110, 80),
          color: const Color(0xFF16322D),
          text: 'Progress\n\nLorem ipsum dolor sit amet.',
          parentId: 'starter-card-progress',
          properties: const {'fontSize': 10.0},
        ),
        _DesignLayer(
          id: 'starter-activity-card',
          name: 'Activity card',
          kind: _LayerKind.rectangle,
          position: const Offset(276, 354),
          size: const Size(288, 70),
          color: const Color(0xFFFFFFFF),
          borderRadius: 22,
          parentId: appBackgroundId,
        ),
        _DesignLayer(
          id: 'starter-activity-copy',
          name: 'Activity copy',
          kind: _LayerKind.text,
          position: const Offset(294, 365),
          size: const Size(252, 48),
          color: const Color(0xFF34313A),
          text: 'Recent activity\nLorem ipsum dolor sit amet, consectetur.',
          parentId: 'starter-activity-card',
          properties: const {'fontSize': 10.0},
        ),
        _DesignLayer(
          id: 'starter-activity-divider',
          name: 'Activity divider',
          kind: _LayerKind.line,
          position: const Offset(294, 397),
          size: const Size(252, 12),
          color: const Color(0xFFE3DFD7),
          parentId: 'starter-activity-card',
          properties: const {'strokeWidth': 1.0, 'strokeCap': 'butt'},
        ),
        _DesignLayer(
          id: 'starter-bottom-nav',
          name: 'Bottom navigation',
          kind: _LayerKind.rectangle,
          position: const Offset(276, 436),
          size: const Size(288, 60),
          color: const Color(0xFF201E26),
          borderRadius: 26,
          parentId: appBackgroundId,
        ),
        _DesignLayer(
          id: 'starter-nav-home',
          name: 'Home icon',
          kind: _LayerKind.image,
          position: const Offset(306, 454),
          size: const Size(20, 20),
          color: const Color(0xFFF8F6F1),
          imageSource: _embeddedSvg(_homeIconSvg),
          parentId: 'starter-bottom-nav',
          properties: const {
            'fit': 'contain',
            'tintWithLayerColor': true,
            'imageName': 'home.svg',
          },
        ),
        _DesignLayer(
          id: 'starter-nav-search',
          name: 'Search icon',
          kind: _LayerKind.image,
          position: const Offset(370, 454),
          size: const Size(20, 20),
          color: const Color(0xFFAAA6B1),
          imageSource: _embeddedSvg(_searchIconSvg),
          parentId: 'starter-bottom-nav',
          properties: const {
            'fit': 'contain',
            'tintWithLayerColor': true,
            'imageName': 'search.svg',
          },
        ),
        _DesignLayer(
          id: 'starter-nav-saved',
          name: 'Saved icon',
          kind: _LayerKind.image,
          position: const Offset(434, 454),
          size: const Size(20, 20),
          color: const Color(0xFFAAA6B1),
          imageSource: _embeddedSvg(_savedIconSvg),
          parentId: 'starter-bottom-nav',
          properties: const {
            'fit': 'contain',
            'tintWithLayerColor': true,
            'imageName': 'saved.svg',
          },
        ),
        _DesignLayer(
          id: 'starter-nav-profile',
          name: 'Profile icon',
          kind: _LayerKind.image,
          position: const Offset(498, 454),
          size: const Size(20, 20),
          color: const Color(0xFFAAA6B1),
          imageSource: _embeddedSvg(_profileIconSvg),
          parentId: 'starter-bottom-nav',
          properties: const {
            'fit': 'contain',
            'tintWithLayerColor': true,
            'imageName': 'profile.svg',
          },
        ),
        _DesignLayer(
          id: 'starter-header-photo',
          name: 'Header photo',
          kind: _LayerKind.image,
          position: const Offset(506, 31),
          size: const Size(46, 40),
          color: Colors.white,
          borderRadius: 12,
          imageSource: const GraphicsImageSource.uri(
            uri: 'asset:assets/images/stockholm-header.jpg',
            mimeType: 'image/jpeg',
          ),
          parentId: headerId,
          properties: const {
            'fit': 'cover',
            'imageName': 'stockholm-header.jpg',
          },
        ),
      ]);
    _selectedId = featuredCardId;
  }

  List<GraphicsDocument> _starterAutoplayStates() {
    final finished = _documentSnapshot();
    final visibleNames = <String>{};
    final states = <GraphicsDocument>[];

    GraphicsDocument copyVisibleState(
      Iterable<String> addedNames, {
      void Function(List<GraphicsDocumentNode> nodes)? adjust,
    }) {
      visibleNames.addAll(addedNames);
      final state = GraphicsDocument.decode(finished.encode(pretty: false));
      state.nodes.removeWhere((node) => !visibleNames.contains(node.name));
      adjust?.call(state.nodes);
      state.validate();
      states.add(state);
      return state;
    }

    GraphicsDocumentNode named(List<GraphicsDocumentNode> nodes, String name) =>
        nodes.firstWhere((node) => node.name == name);

    void makeDraft(
      List<GraphicsDocumentNode> nodes,
      String name, {
      double x = 330,
      double y = 210,
      double width = 130,
      double height = 110,
    }) {
      final node = named(nodes, name);
      node
        ..x = x
        ..y = y
        ..width = width
        ..height = height
        ..borderRadius = 0
        ..color = const Color(0xFF69A99D).toARGB32();
      node.properties['shaderEffect'] = 'none';
    }

    // The sequence is intentionally visual: every state represents one
    // construction action that can be inspected, saved, imported, or replayed.
    copyVisibleState(const []); // 1. Empty canvas.
    copyVisibleState(const [
      'Phone frame',
    ], adjust: (nodes) => makeDraft(nodes, 'Phone frame'));
    copyVisibleState(
      const [],
      adjust: (nodes) {
        final frame = named(nodes, 'Phone frame');
        frame
          ..x = 260
          ..y = 8
          ..width = 320
          ..height = 504
          ..borderRadius = 0
          ..color = const Color(0xFF69A99D).toARGB32();
      },
    );
    copyVisibleState(const []); // 4. Apply the phone surface and radius.
    copyVisibleState(const [
      'Header',
    ], adjust: (nodes) => makeDraft(nodes, 'Header', y: 40, height: 54));
    copyVisibleState(const ['Header title']);
    copyVisibleState(const ['Header caption']);
    copyVisibleState(const ['Header photo']);
    copyVisibleState(const [
      'Featured card',
    ], adjust: (nodes) => makeDraft(nodes, 'Featured card', y: 100));
    copyVisibleState(
      const [],
      adjust: (nodes) =>
          named(nodes, 'Featured card').properties['shaderEffect'] = 'none',
    );
    copyVisibleState(const []); // 11. Apply the card shader.
    copyVisibleState(const ['Featured label']);
    copyVisibleState(const ['Featured title']);
    copyVisibleState(const ['Featured copy']);
    copyVisibleState(const [
      'Focus card',
    ], adjust: (nodes) => makeDraft(nodes, 'Focus card', y: 238));
    copyVisibleState(const []); // 16. Place and style the focus card.
    copyVisibleState(const ['Focus card copy']);
    copyVisibleState(const [
      'Progress card',
    ], adjust: (nodes) => makeDraft(nodes, 'Progress card', y: 238));
    copyVisibleState(const []); // 19. Place and style the progress card.
    copyVisibleState(const ['Progress card copy']);
    copyVisibleState(const [
      'Activity card',
    ], adjust: (nodes) => makeDraft(nodes, 'Activity card', y: 354));
    copyVisibleState(const []); // 22. Place and style the activity card.
    copyVisibleState(const ['Activity copy']);
    copyVisibleState(const ['Activity divider']);
    copyVisibleState(
      const ['Bottom navigation'],
      adjust: (nodes) =>
          makeDraft(nodes, 'Bottom navigation', y: 436, width: 288, height: 60),
    );
    copyVisibleState(const []); // 26. Apply the navigation surface.
    copyVisibleState(const ['Home icon']);
    copyVisibleState(const ['Search icon']);
    copyVisibleState(const ['Saved icon']);
    copyVisibleState(const ['Profile icon']);

    assert(states.length == 30);
    assert(states.last.encode(pretty: false) == finished.encode(pretty: false));
    return states;
  }

  void _generateFromPrompt() {
    FocusManager.instance.primaryFocus?.unfocus();
    _commitMutation(() {
      _buildStarterComposition();
      final prompt = _prompt.text.toLowerCase();
      if (prompt.contains('pink')) {
        _layers.firstWhere((layer) => layer.id == _selectedId).color =
            const Color(0xFFE85D9E);
      }
    });
  }

  void _addLayer(_LayerKind kind) {
    _commitMutation(() {
      String? componentId;
      if (kind == _LayerKind.component) {
        componentId = 'component-${DateTime.now().microsecondsSinceEpoch}';
        _components[componentId] = GraphicsComponentDefinition(
          id: componentId,
          name: 'Custom component',
          width: 320,
          height: 220,
        );
      }
      final layer = _DesignLayer(
        id: _newNodeId(),
        name: switch (kind) {
          _LayerKind.rectangle => 'Rectangle',
          _LayerKind.ellipse => 'Ellipse',
          _LayerKind.line => 'Line',
          _LayerKind.text => 'Text',
          _LayerKind.image => 'Image',
          _LayerKind.component => 'Custom component',
        },
        kind: kind,
        position: const Offset(330, 210),
        size: kind == _LayerKind.text
            ? const Size(190, 54)
            : kind == _LayerKind.line
            ? const Size(180, 20)
            : kind == _LayerKind.component
            ? const Size(320, 220)
            : const Size(130, 110),
        color: kind == _LayerKind.text
            ? const Color(0xFF252525)
            : const Color(0xFF69A99D),
        text: kind == _LayerKind.text ? 'New text' : null,
        componentId: componentId,
        properties: kind == _LayerKind.line
            ? const {'strokeWidth': 3.0, 'strokeCap': 'round'}
            : null,
      );
      _layers.add(layer);
      _selectedId = layer.id;
      if (kind == _LayerKind.component) {
        _editingComponentLayerId = layer.id;
      }
    });
  }

  Future<void> _addImage() async {
    const imageTypes = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'],
    );
    final file = await openFile(acceptedTypeGroups: const [imageTypes]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final extension = file.name.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'svg' => 'image/svg+xml',
      _ => 'image/png',
    };
    if (mime == 'image/svg+xml') {
      try {
        utf8.decode(bytes);
      } on FormatException {
        setState(() {
          _documentStatus =
              'Import failed: ${file.name} is not valid UTF-8 SVG.';
          _documentStatusIsError = true;
        });
        return;
      }
    }
    _commitMutation(() {
      final layer = _DesignLayer(
        id: _newNodeId(),
        name: file.name,
        kind: _LayerKind.image,
        position: const Offset(270, 150),
        size: const Size(300, 220),
        color: Colors.white,
        imageSource: GraphicsImageSource.embedded(
          mimeType: mime,
          data: base64Encode(bytes),
        ),
        properties: {
          'imageName': file.name,
          'fit': mime == 'image/svg+xml' ? 'contain' : 'cover',
        },
      );
      _layers.add(layer);
      _selectedId = layer.id;
    });
  }

  void _deleteSelected() {
    final selected = _selected;
    if (selected == null) return;
    _deleteLayer(selected);
  }

  void _deleteLayer(_DesignLayer selected) {
    _commitMutation(() {
      for (final child in _layers.where(
        (layer) => layer.parentId == selected.id,
      )) {
        child.parentId = selected.parentId;
        child.parentSlot = null;
      }
      _layers.remove(selected);
      _selectedId = _layers.isEmpty ? null : _layers.last.id;
    });
  }

  _DesignLayer _cloneLayer(_DesignLayer source, {String? id}) => _DesignLayer(
    id: id ?? source.id,
    name: source.name,
    kind: source.kind,
    position: source.position,
    size: source.size,
    color: source.color,
    text: source.text,
    rotation: source.rotation,
    borderRadius: source.borderRadius,
    imageSource: source.imageSource,
    componentId: source.componentId,
    parentId: source.parentId,
    parentSlot: source.parentSlot,
    slots: source.slots,
    properties: _deepCopyMap(source.properties),
  )..filter = source.filter;

  List<_DesignLayer> _copySubtree(_DesignLayer root) => [
    _cloneLayer(root),
    for (final child in _descendantsOf(root.id)) _cloneLayer(child),
  ];

  void _copyLayer(_DesignLayer layer) {
    setState(() {
      _selectedId = layer.id;
      _clipboard = _copySubtree(layer);
    });
  }

  void _cutLayer(_DesignLayer layer) {
    _clipboard = _copySubtree(layer);
    _deleteLayer(layer);
  }

  void _pasteLayers({List<_DesignLayer>? source}) {
    final templates = source ?? _clipboard;
    if (templates.isEmpty) return;
    _commitMutation(() {
      final idMap = <String, String>{
        for (final template in templates) template.id: _newNodeId(),
      };
      final pasted = <_DesignLayer>[];
      for (final template in templates) {
        final clone = _cloneLayer(template, id: idMap[template.id])
          ..name = '${template.name} copy'
          ..position += const Offset(20, 20)
          ..parentId = idMap[template.parentId]
          ..parentSlot = idMap.containsKey(template.parentId)
              ? template.parentSlot
              : null;
        pasted.add(clone);
      }
      _layers.addAll(pasted);
      _selectedId = pasted.first.id;
    });
  }

  void _duplicateLayer(_DesignLayer layer) =>
      _pasteLayers(source: _copySubtree(layer));

  void _moveLayerToEdge(_DesignLayer layer, {required bool front}) {
    _commitMutation(() {
      _layers.remove(layer);
      final siblingIndices = <int>[
        for (var index = 0; index < _layers.length; index++)
          if (_layers[index].parentId == layer.parentId) index,
      ];
      if (front) {
        final index = siblingIndices.isEmpty
            ? _layers.length
            : siblingIndices.last + 1;
        _layers.insert(index, layer);
      } else {
        final index = siblingIndices.isEmpty ? 0 : siblingIndices.first;
        _layers.insert(index, layer);
      }
      _selectedId = layer.id;
    });
  }

  void _focusLayer(_DesignLayer layer) {
    final scaleForLayer = math.min(
      (_workspaceSize.width * 0.62) / layer.size.width,
      (_workspaceSize.height * 0.62) / layer.size.height,
    );
    final zoom = (scaleForLayer / _fitScale).clamp(0.25, 8).toDouble();
    setState(() {
      _selectedId = layer.id;
      _zoom = zoom;
      final nextScale = _fitScale * zoom;
      final nextBase =
          _workspaceSize.center(Offset.zero) -
          Offset(
            _documentSize.width * nextScale / 2,
            _documentSize.height * nextScale / 2,
          );
      _panOffset =
          _workspaceSize.center(Offset.zero) -
          layer.position * nextScale -
          Offset(
            layer.size.width * nextScale / 2,
            layer.size.height * nextScale / 2,
          ) -
          nextBase;
    });
  }

  void _fitCanvas() => setState(() {
    _zoom = 1;
    _panOffset = Offset.zero;
  });

  void _beginComponentEdit(_DesignLayer layer) {
    if (layer.kind != _LayerKind.component || layer.componentId == null) return;
    setState(() {
      _selectedId = layer.id;
      _editingComponentLayerId = layer.id;
      _selectedComponentSlot = null;
    });
    _focusLayer(layer);
  }

  void _addComponentSlot(_DesignLayer layer) {
    final definition = _components[layer.componentId];
    if (definition == null) return;
    var index = definition.slotFrames.length + 1;
    while (definition.slotFrames.containsKey('slot-$index')) {
      index++;
    }
    final name = 'slot-$index';
    _commitMutation(() {
      definition.slotFrames[name] = const GraphicsComponentSlotFrame(
        x: 24,
        y: 24,
        width: 120,
        height: 72,
      );
      definition.slots[name] = <String>[];
      _selectedComponentSlot = name;
    });
  }

  void _updateComponentSlot(
    _DesignLayer instance,
    String name,
    GraphicsComponentSlotFrame frame,
  ) {
    final definition = _components[instance.componentId];
    if (definition == null) return;
    setState(() {
      definition.slotFrames[name] = frame;
      _layoutSlottedChildren(instance, definition);
    });
  }

  void _finishComponentSlotEdit() => _commitHistory();

  void _deleteComponentSlot(_DesignLayer instance, String slotName) {
    final definition = _components[instance.componentId];
    if (definition == null ||
        (!definition.slots.containsKey(slotName) &&
            !definition.slotFrames.containsKey(slotName))) {
      return;
    }
    final instanceIds = {
      for (final layer in _layers)
        if (layer.componentId == definition.id) layer.id,
    };
    _commitMutation(() {
      definition
        ..slots.remove(slotName)
        ..slotFrames.remove(slotName);
      for (final layer in _layers) {
        if (instanceIds.contains(layer.id)) {
          layer.slots.remove(slotName);
        }
        if (instanceIds.contains(layer.parentId) &&
            layer.parentSlot == slotName) {
          layer
            ..parentId = null
            ..parentSlot = null;
        }
      }
      if (_selectedComponentSlot == slotName) {
        _selectedComponentSlot = null;
      }
    });
  }

  Future<void> _showComponentSlotMenu(
    BuildContext context,
    _DesignLayer instance,
    String slotName,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final delete = await showMenu<bool>(
      context: context,
      color: _menuSurface,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('delete-component-slot'),
          value: true,
          child: Text('Delete slot'),
        ),
      ],
    );
    if (!mounted || delete != true) return;
    _deleteComponentSlot(instance, slotName);
  }

  void _assignLayerToSlot(
    _DesignLayer instance,
    String slotName,
    String childId,
  ) {
    if (!_canReparent(childId, instance.id)) return;
    final child = _layerById(childId);
    final definition = _components[instance.componentId];
    final slot = definition?.slotFrames[slotName];
    if (child == null || definition == null || slot == null) return;
    final definitionWidth = definition.width ?? instance.size.width;
    final definitionHeight = definition.height ?? instance.size.height;
    final sx = instance.size.width / definitionWidth;
    final sy = instance.size.height / definitionHeight;
    _commitMutation(() {
      child
        ..parentId = instance.id
        ..parentSlot = slotName
        ..position = instance.position + Offset(slot.x * sx, slot.y * sy)
        ..size = Size(slot.width * sx, slot.height * sy);
      _selectedId = child.id;
    });
  }

  void _layoutSlottedChildren(
    _DesignLayer instance,
    GraphicsComponentDefinition definition,
  ) {
    final definitionWidth = definition.width ?? instance.size.width;
    final definitionHeight = definition.height ?? instance.size.height;
    final sx = instance.size.width / definitionWidth;
    final sy = instance.size.height / definitionHeight;
    for (final child in _layers.where(
      (candidate) =>
          candidate.parentId == instance.id && candidate.parentSlot != null,
    )) {
      final slot = definition.slotFrames[child.parentSlot];
      if (slot == null) continue;
      child
        ..position = instance.position + Offset(slot.x * sx, slot.y * sy)
        ..size = Size(slot.width * sx, slot.height * sy);
    }
  }

  void _beginRename(_DesignLayer layer) {
    setState(() {
      _selectedId = layer.id;
      _renamingLayerId = layer.id;
      _editingTextLayerId = null;
      _inlineEditor.text = layer.name;
      _inlineEditor.selection = TextSelection.collapsed(
        offset: _inlineEditor.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _renamingLayerId == layer.id) {
        _renameFocus.requestFocus();
      }
    });
  }

  void _beginTextEdit(_DesignLayer layer) {
    if (layer.kind != _LayerKind.text) return;
    setState(() {
      _selectedId = layer.id;
      _editingTextLayerId = layer.id;
      _renamingLayerId = null;
      _inlineEditor.text = layer.text ?? '';
      _inlineEditor.selection = TextSelection.collapsed(
        offset: _inlineEditor.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingTextLayerId == layer.id) {
        _textEditFocus.requestFocus();
      }
    });
  }

  void _finishInlineEdit({required bool text, bool cancel = false}) {
    final id = text ? _editingTextLayerId : _renamingLayerId;
    final layer = _layerById(id);
    final value = text ? _inlineEditor.text : _inlineEditor.text.trim();
    if (text) {
      _editingTextLayerId = null;
    } else {
      _renamingLayerId = null;
    }
    if (!cancel && layer != null && (text || value.isNotEmpty)) {
      _commitMutation(() {
        if (text) {
          layer.text = value;
        } else {
          layer.name = value;
        }
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _showLayerMenu(
    BuildContext context,
    _DesignLayer layer,
    Offset globalPosition,
  ) async {
    setState(() => _selectedId = layer.id);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<_LayerCommand>(
      context: context,
      color: _menuSurface,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final command in _LayerCommand.values)
          if (command != _LayerCommand.editComponent ||
              layer.kind == _LayerKind.component)
            PopupMenuItem(
              value: command,
              enabled: command != _LayerCommand.paste || _clipboard.isNotEmpty,
              child: Text(
                switch (command) {
                  _LayerCommand.copy => 'Copy',
                  _LayerCommand.cut => 'Cut',
                  _LayerCommand.paste => 'Paste',
                  _LayerCommand.delete => 'Delete',
                  _LayerCommand.duplicate => 'Duplicate',
                  _LayerCommand.rename => 'Rename',
                  _LayerCommand.moveToFront => 'Move to front',
                  _LayerCommand.moveToBack => 'Move to back',
                  _LayerCommand.focus => 'Focus selection',
                  _LayerCommand.editComponent => 'Edit component',
                },
                style: TextStyle(
                  color: command == _LayerCommand.paste && _clipboard.isEmpty
                      ? Colors.white38
                      : Colors.white,
                ),
              ),
            ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _LayerCommand.copy:
        _copyLayer(layer);
      case _LayerCommand.cut:
        _cutLayer(layer);
      case _LayerCommand.paste:
        _pasteLayers();
      case _LayerCommand.delete:
        _deleteLayer(layer);
      case _LayerCommand.duplicate:
        _duplicateLayer(layer);
      case _LayerCommand.rename:
        _beginRename(layer);
      case _LayerCommand.moveToFront:
        _moveLayerToEdge(layer, front: true);
      case _LayerCommand.moveToBack:
        _moveLayerToEdge(layer, front: false);
      case _LayerCommand.focus:
        _focusLayer(layer);
      case _LayerCommand.editComponent:
        _beginComponentEdit(layer);
    }
  }

  void _compileCustomShader() {
    final target = _layerById(_shaderTargetLayerId);
    _commitMutation(() {
      if (target == null) {
        _canvasEffect = _CanvasEffect.custom;
        _appliedCustomShader = _shaderSource.text;
      } else {
        target
          ..shaderEffect = _CanvasEffect.custom
          ..properties['customShader'] = _shaderSource.text
          ..properties['appliedCustomShader'] = _shaderSource.text;
      }
      _shaderCompilationRevision++;
      _shaderStatus = const GpuShaderCompileStatus(
        phase: GpuShaderCompilePhase.compiling,
      );
    });
  }

  void _onShaderStatus(GpuShaderCompileStatus status) {
    if (!mounted ||
        _isPlayingHistory ||
        (_canvasEffect != _CanvasEffect.custom &&
            _shaderTargetLayerId == null)) {
      return;
    }
    setState(() {
      _shaderStatus = status;
      if (status.phase == GpuShaderCompilePhase.succeeded) {
        final target = _layerById(_shaderTargetLayerId);
        if (target == null) {
          _lastGoodCustomShader = _appliedCustomShader;
        } else {
          target.properties['lastGoodCustomShader'] =
              target.properties['appliedCustomShader'];
        }
        _history.commit(_documentSnapshot());
      } else if (status.phase == GpuShaderCompilePhase.failed) {
        final target = _layerById(_shaderTargetLayerId);
        if (target != null) {
          target.properties['appliedCustomShader'] =
              target.properties['lastGoodCustomShader'] ??
              _lastGoodCustomShader;
        }
      }
    });
  }

  GraphicsDocument _documentSnapshot() => GraphicsDocument(
    name: _documentName,
    canvasWidth: _documentSize.width,
    canvasHeight: _documentSize.height,
    nodes: [for (final layer in _layers) _serializeLayer(layer)],
    components: _components.values.toList(),
    canvasEffect: _canvasEffect.name,
    customShader: _shaderSource.text,
    appliedCustomShader: _lastGoodCustomShader,
    metadata: {..._documentMetadata, 'gridUnit': _gridUnit},
  );

  GraphicsDocumentNode _serializeLayer(_DesignLayer layer) =>
      GraphicsDocumentNode(
        id: layer.id,
        name: layer.name,
        kind: layer.kind.name,
        x: layer.position.dx,
        y: layer.position.dy,
        width: layer.size.width,
        height: layer.size.height,
        rotation: layer.rotation,
        borderRadius: layer.borderRadius,
        color: layer.color.toARGB32(),
        filter: layer.filter.name,
        text: layer.text,
        imageSource: layer.imageSource,
        componentId: layer.componentId,
        parentId: layer.parentId,
        parentSlot: layer.parentSlot,
        slots: Map.of(layer.slots),
        properties: _deepCopyMap(layer.properties),
      );

  Future<void> _saveDocument() async {
    try {
      _commitHistory();
      final location = await getSaveLocation(
        suggestedName: '${_safeFileName(_documentName)}.gpudoc',
        acceptedTypeGroups: _documentTypes,
        canCreateDirectories: true,
      );
      if (location == null) return;
      final bytes = Uint8List.fromList(utf8.encode('${_history.encode()}\n'));
      await XFile.fromData(
        bytes,
        mimeType: 'application/json',
        name: location.path.split('/').last,
      ).saveTo(location.path);
      if (!mounted) return;
      setState(() {
        _documentStatus = 'Saved ${location.path.split('/').last}';
        _documentStatusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentStatus = 'Save failed: $error';
        _documentStatusIsError = true;
      });
    }
  }

  Future<void> _importDocument() async {
    try {
      final file = await openFile(acceptedTypeGroups: _documentTypes);
      if (file == null) return;
      if (await file.length() > _maximumImportedDocumentBytes) {
        throw const GraphicsDocumentFormatException(
          'Document exceeds the 32 MB import limit.',
        );
      }
      final importedHistory = GraphicsDocumentHistory.decode(
        await file.readAsString(),
      );
      for (final document in importedHistory.sequence(
        Iterable<int>.generate(importedHistory.length),
      )) {
        _validateSupportedDocument(document);
      }
      if (!mounted) return;
      setState(() {
        _stopHistoryPlayback(restoreCurrent: false, notify: false);
        _history = importedHistory;
        _applyDocument(importedHistory.current, resetViewport: true);
        _selectionByHistoryState
          ..clear()
          ..[_historyStateKey(importedHistory.current)] = _selectedId;
        _documentStatus = 'Imported ${file.name}';
        _documentStatusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentStatus = 'Import failed: $error';
        _documentStatusIsError = true;
      });
    }
  }

  _DesignLayer _deserializeLayer(GraphicsDocumentNode node) => _DesignLayer(
    id: node.id,
    name: node.name,
    kind: _enumByName(_LayerKind.values, node.kind, 'node.kind'),
    position: Offset(node.x, node.y),
    size: Size(node.width, node.height),
    color: Color(node.color),
    text: node.text,
    rotation: node.rotation,
    borderRadius: node.borderRadius,
    imageSource: node.imageSource,
    componentId: node.componentId,
    parentId: node.parentId,
    parentSlot: node.parentSlot,
    slots: Map.of(node.slots),
    properties: _deepCopyMap(node.properties),
  )..filter = _enumByName(_LayerFilter.values, node.filter, 'node.filter');

  void _validateSupportedDocument(GraphicsDocument document) {
    _enumByName(_CanvasEffect.values, document.canvasEffect, 'effects.canvas');
    for (final node in document.nodes) {
      final layer = _deserializeLayer(node);
      if (layer.kind == _LayerKind.line) {
        final strokeWidth = layer.properties['strokeWidth'];
        final strokeCap = layer.properties['strokeCap'];
        if (strokeWidth is! num ||
            !strokeWidth.toDouble().isFinite ||
            strokeWidth <= 0 ||
            (strokeCap != null &&
                strokeCap != 'round' &&
                strokeCap != 'butt')) {
          throw GraphicsDocumentFormatException(
            'Line node "${layer.id}" has invalid stroke properties.',
          );
        }
      }
      if (layer.kind == _LayerKind.text) {
        final fontFamily = layer.properties['fontFamily'];
        if (fontFamily != null &&
            (fontFamily is! String ||
                fontFamily.trim().isEmpty ||
                fontFamily.length > 128)) {
          throw GraphicsDocumentFormatException(
            'Text node "${layer.id}" has an invalid font family.',
          );
        }
        final fontSize = layer.properties['fontSize'];
        if (fontSize != null &&
            (fontSize is! num ||
                !fontSize.toDouble().isFinite ||
                fontSize < 8 ||
                fontSize > 96)) {
          throw GraphicsDocumentFormatException(
            'Text node "${layer.id}" has an invalid font size.',
          );
        }
        for (final property in const ['bold', 'italic']) {
          final value = layer.properties[property];
          if (value != null && value is! bool) {
            throw GraphicsDocumentFormatException(
              'Text node "${layer.id}" has an invalid $property value.',
            );
          }
        }
      }
      final shaderIncludesChildren = layer.properties['shaderIncludesChildren'];
      if (shaderIncludesChildren != null && shaderIncludesChildren is! bool) {
        throw GraphicsDocumentFormatException(
          'Node "${layer.id}" has an invalid shader scope.',
        );
      }
      final source = layer.imageSource;
      if (source?.type == 'embedded' && source?.mimeType == 'image/svg+xml') {
        try {
          utf8.decode(base64Decode(source!.data!));
        } on FormatException {
          throw GraphicsDocumentFormatException(
            'SVG node "${layer.id}" must contain valid UTF-8.',
          );
        }
      }
    }
    _gridUnitFromDocument(document);
  }

  double _gridUnitFromDocument(GraphicsDocument document) {
    final value = document.metadata['gridUnit'];
    if (value == null) return 8;
    if (value is! num ||
        !value.toDouble().isFinite ||
        value < 2 ||
        value > 128) {
      throw const GraphicsDocumentFormatException(
        'metadata.gridUnit must be a number between 2 and 128.',
      );
    }
    return value.toDouble();
  }

  void _applyDocument(GraphicsDocument document, {bool resetViewport = false}) {
    final layers = [for (final node in document.nodes) _deserializeLayer(node)];
    _documentName = document.name;
    _documentSize = Size(document.canvasWidth, document.canvasHeight);
    _documentMetadata = Map<String, Object?>.of(document.metadata);
    _gridUnit = _gridUnitFromDocument(document);
    _activeMoveLayerId = null;
    _activeMoveRawPosition = null;
    _activeGuides = const [];
    _editingComponentLayerId = null;
    _selectedComponentSlot = null;
    if (resetViewport) {
      _panOffset = Offset.zero;
      _zoom = 1;
    }
    _components
      ..clear()
      ..addEntries(document.components.map((item) => MapEntry(item.id, item)));
    _layers
      ..clear()
      ..addAll(layers);
    _selectedId = _layers.isEmpty ? null : _layers.last.id;
    _canvasEffect = _enumByName(
      _CanvasEffect.values,
      document.canvasEffect,
      'effects.canvas',
    );
    _shaderSource.text = document.customShader;
    _lastGoodCustomShader = document.appliedCustomShader.isEmpty
        ? _effectSource(_CanvasEffect.halftone)
        : document.appliedCustomShader;
    _appliedCustomShader = _lastGoodCustomShader;
    _shaderStatus = null;
  }

  void _commitMutation(VoidCallback mutation) {
    _stopHistoryPlayback(restoreCurrent: true, notify: false);
    setState(() {
      mutation();
      _history.commit(_documentSnapshot());
    });
  }

  bool get _editableHasFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _runDocumentShortcut(VoidCallback action) {
    if (_editingTextLayerId != null || _renamingLayerId != null) return;
    if (!_editableHasFocus) action();
  }

  void _commitHistory() {
    _stopHistoryPlayback(restoreCurrent: true, notify: false);
    if (_history.commit(_documentSnapshot()) && mounted) setState(() {});
  }

  String _historyStateKey(GraphicsDocument document) =>
      document.encode(pretty: false);

  void _rememberHistorySelection(GraphicsDocument document) {
    _selectionByHistoryState[_historyStateKey(document)] = _selectedId;
  }

  String? _rememberedSelection(GraphicsDocument document) =>
      _selectionByHistoryState[_historyStateKey(document)];

  void _undo() {
    _stopHistoryPlayback(restoreCurrent: true, notify: false);
    _rememberHistorySelection(_history.current);
    final selectedId = _selectedId;
    final document = _history.undo();
    if (document == null) return;
    final rememberedId = _rememberedSelection(document);
    setState(() {
      _applyDocument(document);
      if (_layerById(selectedId) != null) {
        _selectedId = selectedId;
      } else if (_layerById(rememberedId) != null) {
        _selectedId = rememberedId;
      }
    });
  }

  void _redo() {
    _stopHistoryPlayback(restoreCurrent: true, notify: false);
    _rememberHistorySelection(_history.current);
    final selectedId = _selectedId;
    final document = _history.redo();
    if (document == null) return;
    final rememberedId = _rememberedSelection(document);
    setState(() {
      _applyDocument(document);
      if (_layerById(rememberedId) != null) {
        _selectedId = rememberedId;
      } else if (_layerById(selectedId) != null) {
        _selectedId = selectedId;
      }
    });
  }

  void _toggleHistoryPlayback() {
    if (_isPlayingHistory) {
      _stopHistoryPlayback(restoreCurrent: true, notify: true);
      return;
    }
    if (_history.length < 2) return;
    final sequence = _history.sequence(Iterable<int>.generate(_history.length));
    var index = 0;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isPlayingHistory = true;
      _historyPlaybackIndex = index;
      _historyPlaybackRestoreSelectedId = _selectedId;
      _renamingLayerId = null;
      _editingTextLayerId = null;
      _editingComponentLayerId = null;
      _applyDocument(sequence.first);
    });
    _historyPlaybackTimer = Timer.periodic(_historyPlaybackStep, (timer) {
      index++;
      if (!mounted || index >= sequence.length) {
        _stopHistoryPlayback(restoreCurrent: true, notify: mounted);
        return;
      }
      setState(() {
        _historyPlaybackIndex = index;
        _applyDocument(sequence[index]);
      });
    });
  }

  void _stopHistoryPlayback({
    required bool restoreCurrent,
    required bool notify,
  }) {
    _historyPlaybackTimer?.cancel();
    _historyPlaybackTimer = null;
    if (!_isPlayingHistory) return;
    _isPlayingHistory = false;
    _historyPlaybackIndex = null;
    if (restoreCurrent) {
      _applyDocument(_history.current);
      final restoreId = _historyPlaybackRestoreSelectedId;
      if (_layerById(restoreId) != null) _selectedId = restoreId;
    }
    _historyPlaybackRestoreSelectedId = null;
    if (notify && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _saveDocument,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            _importDocument,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _redo,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          _runDocumentShortcut(() {
            if (_selected case final layer?) _copyLayer(layer);
          });
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          _runDocumentShortcut(() {
            if (_selected case final layer?) _cutLayer(layer);
          });
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
            _runDocumentShortcut(_pasteLayers),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          _runDocumentShortcut(() {
            if (_selected case final layer?) _duplicateLayer(layer);
          });
        },
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _runDocumentShortcut(_deleteSelected),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _runDocumentShortcut(_deleteSelected),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: _shell,
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 12),
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLayersPanel(),
                      Expanded(child: _buildWorkspace()),
                      _buildInspector(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded, size: 20, color: _accent),
          const SizedBox(width: 9),
          Text(
            _documentName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 20),
          _toolButton(Icons.near_me_outlined, 'Move', () {}),
          _toolButton(
            Icons.crop_square_rounded,
            'Rectangle',
            () => _addLayer(_LayerKind.rectangle),
            key: const Key('add-rectangle'),
          ),
          _toolButton(
            Icons.circle_outlined,
            'Ellipse',
            () => _addLayer(_LayerKind.ellipse),
          ),
          _toolButton(
            Icons.horizontal_rule_rounded,
            'Line',
            () => _addLayer(_LayerKind.line),
            key: const Key('add-line'),
          ),
          _toolButton(
            Icons.title_rounded,
            'Text',
            () => _addLayer(_LayerKind.text),
          ),
          _toolButton(
            Icons.image_outlined,
            'Image',
            _addImage,
            key: const Key('add-image'),
          ),
          _toolButton(
            Icons.widgets_outlined,
            'Component',
            () => _addLayer(_LayerKind.component),
            key: const Key('add-component'),
          ),
          const SizedBox(width: 8),
          _toolButton(
            Icons.file_open_outlined,
            'Import document · ⌘O',
            _importDocument,
            key: const Key('import-document'),
          ),
          _toolButton(
            Icons.save_outlined,
            'Save document · ⌘S',
            _saveDocument,
            key: const Key('save-document'),
          ),
          _toolButton(
            Icons.undo_rounded,
            'Undo · ⌘Z',
            _undo,
            key: const Key('undo-document'),
            enabled: _history.canUndo && !_isPlayingHistory,
          ),
          _toolButton(
            Icons.redo_rounded,
            'Redo · ⇧⌘Z',
            _redo,
            key: const Key('redo-document'),
            enabled: _history.canRedo && !_isPlayingHistory,
          ),
          _toolButton(
            _isPlayingHistory ? Icons.stop_rounded : Icons.play_arrow_rounded,
            _isPlayingHistory
                ? 'Stop autoplay'
                : 'Autoplay ${_history.length} build states',
            _toggleHistoryPlayback,
            key: const Key('play-history'),
            enabled: _history.length > 1,
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${(_historyPlaybackIndex ?? _history.currentIndex) + 1}/'
              '${_history.length}',
              key: const Key('history-position'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 9.5),
            ),
          ),
          const Spacer(),
          if (_documentStatus.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                _documentStatus,
                key: const Key('document-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _documentStatusIsError
                      ? const Color(0xFFFF8870)
                      : const Color(0xFF76B889),
                  fontSize: 9.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: 360,
            height: 36,
            decoration: BoxDecoration(
              color: _shell,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.auto_awesome, size: 15, color: _accent),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('design-prompt'),
                    controller: _prompt,
                    onSubmitted: (_) => _generateFromPrompt(),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 9),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('generate-design'),
                  onPressed: _generateFromPrompt,
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    Key? key,
    bool enabled = true,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18, color: _muted),
    );
  }

  Widget _buildLayersPanel() {
    return Container(
      width: 190,
      color: _panel,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading('LAYERS'),
          const SizedBox(height: 9),
          Expanded(
            child: DragTarget<String>(
              key: const Key('layers-root-drop'),
              onWillAcceptWithDetails: (details) =>
                  _layerById(details.data)?.parentId != null,
              onAcceptWithDetails: (details) =>
                  _reparentLayer(details.data, null),
              builder: (context, candidates, rejected) => DecoratedBox(
                decoration: BoxDecoration(
                  border: candidates.isEmpty
                      ? null
                      : Border.all(color: _accent.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  key: const Key('layers-list'),
                  children: _buildLayerTree(null, 0).toList(),
                ),
              ),
            ),
          ),
          const Divider(color: _line),
          Row(
            children: [
              const Icon(Icons.add, size: 15, color: _muted),
              const SizedBox(width: 5),
              Text(
                '${_layers.length} objects',
                key: const Key('object-count'),
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete selected layer',
                visualDensity: VisualDensity.compact,
                onPressed: _selected == null ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _buildLayerTree(String? parentId, int depth) sync* {
    final siblings = _layers
        .where((layer) => layer.parentId == parentId)
        .toList()
        .reversed
        .toList();
    for (final layer in siblings) {
      yield _LayerDropZone(
        key: ValueKey('layer-drop-above-${layer.id}'),
        depth: depth,
        onAccept: (childId) =>
            _moveLayerRelative(childId, layer.id, above: true),
      );
      yield _LayerTile(
        layer: layer,
        depth: depth,
        selected: layer.id == _selectedId,
        canContainChildren:
            layer.kind != _LayerKind.text && layer.kind != _LayerKind.line,
        canAccept: (childId) => _canReparent(childId, layer.id),
        onAccept: (childId) => _reparentLayer(childId, layer.id),
        onTap: () => setState(() => _selectedId = layer.id),
        onSecondaryTapDown: (details) =>
            _showLayerMenu(context, layer, details.globalPosition),
        renaming: _renamingLayerId == layer.id,
        renameController: _inlineEditor,
        renameFocus: _renameFocus,
        onRenameSubmitted: (_) => _finishInlineEdit(text: false),
        onRenameCancelled: () => _finishInlineEdit(text: false, cancel: true),
      );
      yield* _buildLayerTree(layer.id, depth + 1);
    }
    if (siblings.isNotEmpty) {
      final last = siblings.last;
      yield _LayerDropZone(
        key: ValueKey('layer-drop-below-${last.id}'),
        depth: depth,
        onAccept: (childId) =>
            _moveLayerRelative(childId, last.id, above: false),
      );
    }
  }

  void _moveLayerWithSnapping(
    _DesignLayer layer,
    Offset documentDelta,
    double displayScale,
  ) {
    if (_activeMoveLayerId != layer.id || _activeMoveRawPosition == null) {
      _activeMoveLayerId = layer.id;
      _activeMoveRawPosition = layer.position;
    }
    final rawPosition = _activeMoveRawPosition! + documentDelta;
    _activeMoveRawPosition = rawPosition;
    final snapped = _snapPosition(layer, rawPosition, displayScale);
    final appliedDelta = snapped.position - layer.position;
    layer.position = snapped.position;
    for (final descendant in _descendantsOf(layer.id)) {
      descendant.position += appliedDelta;
    }
    _activeGuides = snapped.guides;
  }

  void _rotateLayerWithDescendants(_DesignLayer layer, double rotation) {
    final delta = rotation - layer.rotation;
    if (delta.abs() < 0.000001) return;
    final pivot = layer.position + layer.size.center(Offset.zero);
    for (final descendant in _descendantsOf(layer.id)) {
      final center = descendant.position + descendant.size.center(Offset.zero);
      final rotatedCenter = pivot + _rotateOffset(center - pivot, delta);
      descendant
        ..position = rotatedCenter - descendant.size.center(Offset.zero)
        ..rotation += delta;
    }
    layer.rotation = rotation;
  }

  _SnapResult _snapPosition(
    _DesignLayer layer,
    Offset rawPosition,
    double displayScale,
  ) {
    final horizontalTargets = <double>{};
    final verticalTargets = <double>{};
    final parent = _layerById(layer.parentId);
    final bounds = parent == null
        ? Offset.zero & _documentSize
        : parent.position & parent.size;
    horizontalTargets.addAll([bounds.left, bounds.center.dx, bounds.right]);
    verticalTargets.addAll([bounds.top, bounds.center.dy, bounds.bottom]);
    for (final sibling in _layers.where(
      (candidate) =>
          candidate.id != layer.id && candidate.parentId == layer.parentId,
    )) {
      final frame = sibling.position & sibling.size;
      horizontalTargets.addAll([frame.left, frame.center.dx, frame.right]);
      verticalTargets.addAll([frame.top, frame.center.dy, frame.bottom]);
    }

    final threshold = 6 / displayScale;
    final xSnap = _nearestAxisSnap(
      anchors: [
        rawPosition.dx,
        rawPosition.dx + layer.size.width / 2,
        rawPosition.dx + layer.size.width,
      ],
      targets: horizontalTargets,
      threshold: threshold,
    );
    final ySnap = _nearestAxisSnap(
      anchors: [
        rawPosition.dy,
        rawPosition.dy + layer.size.height / 2,
        rawPosition.dy + layer.size.height,
      ],
      targets: verticalTargets,
      threshold: threshold,
    );

    var x = rawPosition.dx;
    var y = rawPosition.dy;
    final guides = <_AlignmentGuide>[];
    if (xSnap != null) {
      x += xSnap.correction;
      guides.add(
        _AlignmentGuide(axis: _GuideAxis.vertical, position: xSnap.target),
      );
    } else {
      final gridX = (x / _gridUnit).round() * _gridUnit;
      if ((gridX - x).abs() <= threshold) x = gridX;
    }
    if (ySnap != null) {
      y += ySnap.correction;
      guides.add(
        _AlignmentGuide(axis: _GuideAxis.horizontal, position: ySnap.target),
      );
    } else {
      final gridY = (y / _gridUnit).round() * _gridUnit;
      if ((gridY - y).abs() <= threshold) y = gridY;
    }
    return _SnapResult(position: Offset(x, y), guides: guides);
  }

  _AxisSnap? _nearestAxisSnap({
    required List<double> anchors,
    required Set<double> targets,
    required double threshold,
  }) {
    _AxisSnap? best;
    for (final anchor in anchors) {
      for (final target in targets) {
        final correction = target - anchor;
        if (correction.abs() <= threshold &&
            (best == null || correction.abs() < best.correction.abs())) {
          best = _AxisSnap(correction: correction, target: target);
        }
      }
    }
    return best;
  }

  void _finishMove() {
    setState(() {
      _activeMoveLayerId = null;
      _activeMoveRawPosition = null;
      _activeGuides = const [];
    });
    _commitHistory();
  }

  double get _displayScale => _fitScale * _zoom;

  Offset get _baseTranslation =>
      _workspaceSize.center(Offset.zero) -
      Offset(
        _documentSize.width * _displayScale / 2,
        _documentSize.height * _displayScale / 2,
      );

  Matrix4 get _sceneToViewportMatrix {
    final translation = _baseTranslation + _panOffset;
    return Matrix4.identity()
      ..setEntry(0, 0, _displayScale)
      ..setEntry(1, 1, _displayScale)
      ..setEntry(0, 3, translation.dx)
      ..setEntry(1, 3, translation.dy);
  }

  Offset _viewportToScene(Offset viewportPoint) {
    final translation = _baseTranslation + _panOffset;
    return (viewportPoint - translation) / _displayScale;
  }

  void _setZoomAround(double requestedZoom, Offset focalPoint) {
    if (_activeMoveLayerId != null) return;
    final nextZoom = requestedZoom.clamp(0.25, 8).toDouble();
    if (nextZoom == _zoom) return;
    final scenePoint = _viewportToScene(focalPoint);
    setState(() {
      _zoom = nextZoom;
      final nextScale = _fitScale * nextZoom;
      final nextBase =
          _workspaceSize.center(Offset.zero) -
          Offset(
            _documentSize.width * nextScale / 2,
            _documentSize.height * nextScale / 2,
          );
      _panOffset = focalPoint - scenePoint * nextScale - nextBase;
    });
  }

  void _zoomFromCenter(double zoom) {
    final box = _workspaceKey.currentContext?.findRenderObject() as RenderBox?;
    _setZoomAround(zoom, box?.size.center(Offset.zero) ?? Offset.zero);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (_activeMoveLayerId != null || resolved is! PointerScrollEvent) return;
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isMetaPressed || keyboard.isControlPressed) {
        final factor = math.exp(-resolved.scrollDelta.dy * 0.0015);
        _setZoomAround(_zoom * factor, resolved.localPosition);
      } else {
        setState(() => _panOffset -= resolved.scrollDelta);
      }
    });
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    if (_activeMoveLayerId != null) return;
    _panZoomStartZoom = _zoom;
    _panZoomSceneFocal = _viewportToScene(event.localPosition);
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_activeMoveLayerId != null) return;
    final nextZoom = (_panZoomStartZoom * event.scale)
        .clamp(0.25, 8)
        .toDouble();
    final nextScale = _fitScale * nextZoom;
    final nextBase =
        _workspaceSize.center(Offset.zero) -
        Offset(
          _documentSize.width * nextScale / 2,
          _documentSize.height * nextScale / 2,
        );
    final focalPoint = event.localPosition + event.pan;
    setState(() {
      _zoom = nextZoom;
      _panOffset = focalPoint - _panZoomSceneFocal * nextScale - nextBase;
    });
  }

  void _panViewport(Offset screenDelta) {
    if (_activeMoveLayerId != null) return;
    setState(() => _panOffset += screenDelta);
  }

  bool _isViewportPanStart(PointerDownEvent event) =>
      event.buttons & kMiddleMouseButton != 0 ||
      (event.buttons & kPrimaryMouseButton != 0 &&
          HardwareKeyboard.instance.isLogicalKeyPressed(
            LogicalKeyboardKey.space,
          ));

  void _handleViewportPointerDown(PointerDownEvent event) {
    if (!_isViewportPanStart(event) || _activeMoveLayerId != null) return;
    _viewportPanPointer = event.pointer;
    _viewportPanPosition = event.localPosition;
  }

  void _handleViewportPointerMove(PointerMoveEvent event) {
    if (_viewportPanPointer != event.pointer || _viewportPanPosition == null) {
      return;
    }
    final delta = event.localPosition - _viewportPanPosition!;
    _viewportPanPosition = event.localPosition;
    _panViewport(delta);
  }

  void _handleViewportPointerEnd(PointerEvent event) {
    if (_viewportPanPointer != event.pointer) return;
    _viewportPanPointer = null;
    _viewportPanPosition = null;
  }

  Widget _buildWorkspace() {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          Expanded(
            child: Listener(
              key: _workspaceKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handleViewportPointerDown,
              onPointerMove: _handleViewportPointerMove,
              onPointerUp: _handleViewportPointerEnd,
              onPointerCancel: _handleViewportPointerEnd,
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: _handlePanZoomStart,
              onPointerPanZoomUpdate: _handlePanZoomUpdate,
              child: LayoutBuilder(
                key: const Key('canvas-input'),
                builder: (context, constraints) {
                  final fit = math.min(
                    (constraints.maxWidth - 54) / _documentSize.width,
                    (constraints.maxHeight - 40) / _documentSize.height,
                  );
                  _fitScale = fit.clamp(0.2, 1.0);
                  _workspaceSize = constraints.biggest;
                  final scene = Positioned(
                    left: 0,
                    top: 0,
                    width: _documentSize.width,
                    height: _documentSize.height,
                    child: Transform(
                      key: const Key('canvas-viewport'),
                      transform: _sceneToViewportMatrix,
                      alignment: Alignment.topLeft,
                      child: _buildFilteredArtboard(_displayScale),
                    ),
                  );
                  return ClipRect(
                    child: Stack(clipBehavior: Clip.none, children: [scene]),
                  );
                },
              ),
            ),
          ),
          _buildZoomBar(),
        ],
      ),
    );
  }

  Widget _buildFilteredArtboard(double displayScale) {
    final artboard = _Artboard(
      layers: _layers,
      components: _components,
      selectedId: _selectedId,
      displayScale: displayScale,
      onSelect: (id) => setState(() {
        _selectedId = id;
        _activeGuides = const [];
      }),
      onMove: (layer, delta) =>
          setState(() => _moveLayerWithSnapping(layer, delta, displayScale)),
      onMoveEnd: _finishMove,
      onResize: (layer, handle, delta, proportional) => setState(() {
        _resizeLayer(layer, handle, delta, proportional: proportional);
      }),
      onResizeEnd: _commitHistory,
      onRotate: (layer, angle) =>
          setState(() => _rotateLayerWithDescendants(layer, angle)),
      onRotateEnd: _commitHistory,
      editingTextId: _editingTextLayerId,
      inlineEditor: _inlineEditor,
      textEditFocus: _textEditFocus,
      enableShaders: widget.enableShaders,
      playback: widget.playback,
      shaderRevision: _shaderCompilationRevision,
      fallbackCustomShader: _lastGoodCustomShader,
      onDoubleSelect: (layer) {
        setState(() => _selectedId = layer.id);
        if (layer.kind == _LayerKind.text) _beginTextEdit(layer);
      },
      onTextEditFinished: ({required bool cancel}) =>
          _finishInlineEdit(text: true, cancel: cancel),
      onSecondaryTapDown: (layer, details) =>
          _showLayerMenu(context, layer, details.globalPosition),
      onShaderStatus: _onShaderStatus,
      editingComponentId: _editingComponentLayerId,
      selectedComponentSlot: _selectedComponentSlot,
      onSelectComponentSlot: (name) =>
          setState(() => _selectedComponentSlot = name),
      onUpdateComponentSlot: _updateComponentSlot,
      onFinishComponentSlotEdit: _finishComponentSlotEdit,
      onAssignLayerToSlot: _assignLayerToSlot,
      onComponentSlotSecondaryTapDown: (instance, name, details) =>
          _showComponentSlotMenu(
            context,
            instance,
            name,
            details.globalPosition,
          ),
    );

    final filteredArtboard =
        !widget.enableShaders || _canvasEffect == _CanvasEffect.none
        ? artboard
        : GpuShaderSampler(
            key: const ValueKey('canvas-shader'),
            fragmentSource: _canvasEffect == _CanvasEffect.custom
                ? _appliedCustomShader
                : _effectSource(_canvasEffect),
            paused: widget.playback.paused,
            timeScale: widget.playback.speed,
            capturePixelRatio: 1.25,
            rasterScale: (_displayScale * 4).round().clamp(2, 8) / 4,
            initialCompilingFallback: artboard,
            compilingOverlay: _ShaderCompilingOverlay(
              displayScale: displayScale,
            ),
            compilationRevision: _shaderCompilationRevision,
            onCompileStatus: _onShaderStatus,
            child: artboard,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(ignoring: _isPlayingHistory, child: filteredArtboard),
        if (_gridUnit * displayScale >= 10)
          IgnorePointer(
            child: CustomPaint(
              key: const Key('faint-grid'),
              painter: _GridPainter(
                unit: _gridUnit,
                displayScale: displayScale,
              ),
            ),
          ),
        if (_activeGuides.isNotEmpty)
          IgnorePointer(
            child: CustomPaint(
              key: const Key('alignment-guides'),
              painter: _AlignmentGuidePainter(
                guides: _activeGuides,
                displayScale: displayScale,
              ),
            ),
          ),
      ],
    );
  }

  void _resizeLayer(
    _DesignLayer layer,
    _ResizeHandle handle,
    Offset canvasDelta, {
    required bool proportional,
  }) {
    const minimumSize = Size(42, 32);
    const maximumSize = Size(720, 440);
    final oldSize = layer.size;
    final localDelta = _rotateOffset(canvasDelta, -layer.rotation);

    var width = oldSize.width;
    var height = oldSize.height;
    if (handle.movesLeft) width -= localDelta.dx;
    if (handle.movesRight) width += localDelta.dx;
    if (handle.movesTop) height -= localDelta.dy;
    if (handle.movesBottom) height += localDelta.dy;

    if (proportional && handle.isCorner) {
      final widthScale = width / oldSize.width;
      final heightScale = height / oldSize.height;
      final requestedScale = (widthScale - 1).abs() >= (heightScale - 1).abs()
          ? widthScale
          : heightScale;
      final minimumScale = math.max(
        minimumSize.width / oldSize.width,
        minimumSize.height / oldSize.height,
      );
      final maximumScale = math.min(
        maximumSize.width / oldSize.width,
        maximumSize.height / oldSize.height,
      );
      final scale = requestedScale.clamp(minimumScale, maximumScale);
      width = oldSize.width * scale;
      height = oldSize.height * scale;
    } else {
      width = width.clamp(minimumSize.width, maximumSize.width);
      height = height.clamp(minimumSize.height, maximumSize.height);
    }

    final newSize = Size(width, height);
    final localCenterShift = Offset(
      handle.movesLeft
          ? (oldSize.width - newSize.width) / 2
          : handle.movesRight
          ? (newSize.width - oldSize.width) / 2
          : 0,
      handle.movesTop
          ? (oldSize.height - newSize.height) / 2
          : handle.movesBottom
          ? (newSize.height - oldSize.height) / 2
          : 0,
    );
    final oldCenter =
        layer.position + Offset(oldSize.width / 2, oldSize.height / 2);
    final newCenter =
        oldCenter + _rotateOffset(localCenterShift, layer.rotation);
    layer
      ..size = newSize
      ..position = newCenter - Offset(newSize.width / 2, newSize.height / 2);
    if (layer.componentId case final componentId?) {
      final definition = _components[componentId];
      if (definition != null) _layoutSlottedChildren(layer, definition);
    }
  }

  Widget _buildZoomBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_4x4, size: 14, color: _muted),
          const SizedBox(width: 7),
          Text(
            '${_documentSize.width.round()} × ${_documentSize.height.round()}',
            style: const TextStyle(color: _muted, fontSize: 10.5),
          ),
          const SizedBox(width: 16),
          const Text('Grid', style: TextStyle(color: _muted, fontSize: 10.5)),
          const SizedBox(width: 6),
          PopupMenuButton<double>(
            key: const Key('grid-unit'),
            tooltip: 'Grid unit',
            initialValue: _gridUnit,
            color: _menuSurface,
            position: PopupMenuPosition.over,
            onSelected: (value) => _commitMutation(() => _gridUnit = value),
            itemBuilder: (context) => [
              for (final unit in const [4.0, 8.0, 16.0, 32.0])
                PopupMenuItem(value: unit, child: Text('${unit.round()} px')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_gridUnit.round()} px',
                    style: const TextStyle(color: Colors.white, fontSize: 10.5),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 14, color: _muted),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('fit-canvas'),
            tooltip: 'Scale canvas to fit',
            visualDensity: VisualDensity.compact,
            onPressed: _fitCanvas,
            icon: const Icon(
              Icons.fit_screen_outlined,
              size: 15,
              color: _muted,
            ),
          ),
          IconButton(
            key: const Key('zoom-out'),
            tooltip: 'Zoom out',
            visualDensity: VisualDensity.compact,
            onPressed: () => _zoomFromCenter(_zoom - 0.25),
            icon: const Icon(Icons.remove, size: 14, color: _muted),
          ),
          SizedBox(
            width: 130,
            child: Slider(
              key: const Key('canvas-zoom'),
              value: _zoom,
              min: 0.25,
              max: 8,
              onChanged: _zoomFromCenter,
            ),
          ),
          IconButton(
            key: const Key('zoom-in'),
            tooltip: 'Zoom in',
            visualDensity: VisualDensity.compact,
            onPressed: () => _zoomFromCenter(_zoom + 0.25),
            icon: const Icon(Icons.add, size: 14, color: _muted),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: _muted, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspector() {
    final layer = _selected;
    final component = layer?.componentId == null
        ? null
        : _components[layer!.componentId];
    final editingComponent = _layerById(_editingComponentLayerId);
    final editingDefinition = editingComponent?.componentId == null
        ? null
        : _components[editingComponent!.componentId];
    return Container(
      width: _canvasEffect == _CanvasEffect.custom ? 390 : 224,
      color: _panel,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: layer == null
          ? const Center(
              child: Text('Select an object', style: TextStyle(color: _muted)),
            )
          : ListView(
              children: [
                const _PanelHeading('DESIGN'),
                const SizedBox(height: 13),
                Text(
                  layer.name,
                  key: const Key('selected-layer-name'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (layer.parentId != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Inside ${_layerById(layer.parentId)?.name ?? layer.parentId}',
                    key: const Key('selected-layer-parent'),
                    style: const TextStyle(color: _accent, fontSize: 10),
                  ),
                ],
                const SizedBox(height: 16),
                _propertyRow(
                  'X',
                  layer.position.dx.round().toString(),
                  'Y',
                  layer.position.dy.round().toString(),
                  firstKey: const Key('x-value'),
                  secondKey: const Key('y-value'),
                ),
                const SizedBox(height: 8),
                _propertyRow(
                  'W',
                  layer.size.width.round().toString(),
                  'H',
                  layer.size.height.round().toString(),
                  firstKey: const Key('width-value'),
                  secondKey: const Key('height-value'),
                ),
                const SizedBox(height: 18),
                const _PanelHeading('ROTATION'),
                Slider(
                  key: const Key('layer-rotation'),
                  value: layer.rotation.clamp(-math.pi, math.pi),
                  min: -math.pi,
                  max: math.pi,
                  onChanged: (value) =>
                      setState(() => _rotateLayerWithDescendants(layer, value)),
                  onChangeEnd: (_) => _commitHistory(),
                ),
                Text(
                  key: const Key('rotation-value'),
                  '${(layer.rotation * 180 / math.pi).round()}°',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: _muted, fontSize: 10.5),
                ),
                const SizedBox(height: 14),
                if (layer.kind == _LayerKind.text) ...[
                  const _PanelHeading('FONT'),
                  const SizedBox(height: 8),
                  PopupMenuButton<String>(
                    key: const Key('text-font-family'),
                    tooltip: 'Font family',
                    initialValue:
                        layer.properties['fontFamily'] as String? ?? 'System',
                    color: _menuSurface,
                    position: PopupMenuPosition.under,
                    onSelected: (fontFamily) => _commitMutation(() {
                      if (fontFamily == 'System') {
                        layer.properties.remove('fontFamily');
                      } else {
                        layer.properties['fontFamily'] = fontFamily;
                      }
                    }),
                    itemBuilder: (context) => [
                      for (final fontFamily in _textFontFamilies)
                        PopupMenuItem(
                          value: fontFamily,
                          child: Text(
                            fontFamily,
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: fontFamily == 'System'
                                  ? null
                                  : fontFamily,
                            ),
                          ),
                        ),
                    ],
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _menuSurface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              layer.properties['fontFamily'] as String? ??
                                  'System',
                              key: const Key('text-font-family-value'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'SIZE',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      const Spacer(),
                      Text(
                        '${((layer.properties['fontSize'] as num?) ?? 18).round()} px',
                        key: const Key('text-font-size-value'),
                        style: const TextStyle(color: _muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('text-font-size'),
                    value: ((layer.properties['fontSize'] as num?) ?? 18)
                        .toDouble()
                        .clamp(8, 96),
                    min: 8,
                    max: 96,
                    divisions: 88,
                    onChanged: (value) =>
                        setState(() => layer.properties['fontSize'] = value),
                    onChangeEnd: (_) => _commitHistory(),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('text-bold'),
                          onPressed: () => _commitMutation(
                            () => layer.properties['bold'] =
                                layer.properties['bold'] != true,
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: layer.properties['bold'] == true
                                ? _accent.withValues(alpha: 0.28)
                                : Colors.transparent,
                          ),
                          child: const Tooltip(
                            message: 'Bold',
                            child: Icon(Icons.format_bold, size: 17),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('text-italic'),
                          onPressed: () => _commitMutation(
                            () => layer.properties['italic'] =
                                layer.properties['italic'] != true,
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: layer.properties['italic'] == true
                                ? _accent.withValues(alpha: 0.28)
                                : Colors.transparent,
                          ),
                          child: const Tooltip(
                            message: 'Italic',
                            child: Icon(Icons.format_italic, size: 17),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                const _PanelHeading('FILL'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in const [
                      Color(0xFF5244B9),
                      Color(0xFFE85D9E),
                      Color(0xFFFF785A),
                      Color(0xFF69A99D),
                      Color(0xFFF4CB45),
                      Color(0xFF252525),
                    ])
                      InkWell(
                        onTap: () => _commitMutation(() => layer.color = color),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          width: 23,
                          height: 23,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: layer.color == color
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const Key('custom-color'),
                      onPressed: () => _pickCustomColor(layer),
                      icon: const Icon(Icons.colorize, size: 14),
                      label: const Text('Custom'),
                    ),
                  ],
                ),
                if (layer.kind == _LayerKind.rectangle ||
                    layer.kind == _LayerKind.image) ...[
                  const SizedBox(height: 18),
                  const _PanelHeading('CORNER RADIUS'),
                  Slider(
                    key: const Key('border-radius'),
                    value: layer.borderRadius.clamp(
                      0,
                      math.min(layer.size.width, layer.size.height) / 2,
                    ),
                    min: 0,
                    max: math.max(
                      1,
                      math.min(layer.size.width, layer.size.height) / 2,
                    ),
                    onChanged: (value) =>
                        setState(() => layer.borderRadius = value),
                    onChangeEnd: (_) => _commitHistory(),
                  ),
                  Text(
                    '${layer.borderRadius.round()} px',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: _muted, fontSize: 10.5),
                  ),
                ],
                if (layer.kind == _LayerKind.line) ...[
                  const SizedBox(height: 18),
                  const _PanelHeading('STROKE WIDTH'),
                  Slider(
                    key: const Key('line-stroke-width'),
                    value: ((layer.properties['strokeWidth'] as num?) ?? 3)
                        .toDouble()
                        .clamp(1, 24),
                    min: 1,
                    max: 24,
                    onChanged: (value) =>
                        setState(() => layer.properties['strokeWidth'] = value),
                    onChangeEnd: (_) => _commitHistory(),
                  ),
                ],
                const SizedBox(height: 20),
                if (editingComponent != null && editingDefinition != null) ...[
                  Row(
                    children: [
                      const Expanded(child: _PanelHeading('COMPONENT EDITOR')),
                      TextButton(
                        key: const Key('finish-component-edit'),
                        onPressed: () => setState(() {
                          _editingComponentLayerId = null;
                          _selectedComponentSlot = null;
                        }),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Drag slot frames on the component. Drop any layer from Layers into a slot.',
                    style: TextStyle(color: _muted, fontSize: 10, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('add-component-slot'),
                    onPressed: () => _addComponentSlot(editingComponent),
                    icon: const Icon(Icons.add_box_outlined, size: 15),
                    label: const Text('Add slot'),
                  ),
                  if (editingDefinition.slotFrames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final name in editingDefinition.slotFrames.keys)
                      GestureDetector(
                        key: Key('component-slot-row-$name'),
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) => _showComponentSlotMenu(
                          context,
                          editingComponent,
                          name,
                          details.globalPosition,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            selected: _selectedComponentSlot == name,
                            title: Text(name),
                            subtitle: Text(
                              '${editingDefinition.slotFrames[name]!.width.round()} × ${editingDefinition.slotFrames[name]!.height.round()}',
                            ),
                            onTap: () =>
                                setState(() => _selectedComponentSlot = name),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 18),
                ],
                if (component != null && component.slots.isNotEmpty) ...[
                  const _PanelHeading('COMPONENT SLOTS'),
                  const SizedBox(height: 7),
                  for (final slot in component.slots.entries) ...[
                    _ComponentSlotPicker(
                      key: Key('${slot.key}-slot'),
                      label: slot.key,
                      value: layer.slots[slot.key],
                      allowedComponents: slot.value,
                      definitions: _components,
                      excludedComponentId: layer.componentId,
                      onChanged: (value) =>
                          _commitMutation(() => layer.slots[slot.key] = value),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 20),
                ],
                const _PanelHeading('LAYER FILTER'),
                const SizedBox(height: 7),
                DropdownButtonFormField<_LayerFilter>(
                  isExpanded: true,
                  initialValue: layer.filter,
                  dropdownColor: _menuSurface,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _fieldDecoration(),
                  items: [
                    for (final filter in _LayerFilter.values)
                      DropdownMenuItem(
                        value: filter,
                        child: Text(_filterName(filter)),
                      ),
                  ],
                  onChanged: (value) =>
                      _commitMutation(() => layer.filter = value!),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: _PanelHeading('FRAME SHADER')),
                    if (layer.shaderEffect != _CanvasEffect.none)
                      const Icon(Icons.blur_on, size: 14, color: _accent),
                  ],
                ),
                const SizedBox(height: 7),
                DropdownButtonFormField<_CanvasEffect>(
                  key: const Key('frame-effect'),
                  isExpanded: true,
                  initialValue: layer.shaderEffect,
                  dropdownColor: _menuSurface,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _fieldDecoration(),
                  items: [
                    for (final effect in _CanvasEffect.values)
                      DropdownMenuItem(
                        value: effect,
                        child: Text(_effectName(effect)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _commitMutation(() => layer.shaderEffect = value);
                    if (value == _CanvasEffect.custom) {
                      _shaderTargetLayerId = layer.id;
                      _shaderSource.text =
                          layer.properties['customShader'] as String? ??
                          _lastGoodCustomShader;
                    } else if (_shaderTargetLayerId == layer.id) {
                      _shaderTargetLayerId = null;
                    }
                  },
                ),
                if (layer.shaderEffect != _CanvasEffect.none &&
                    layer.kind != _LayerKind.text &&
                    layer.kind != _LayerKind.line) ...[
                  const SizedBox(height: 9),
                  DropdownButtonFormField<bool>(
                    key: const Key('frame-shader-scope'),
                    isExpanded: true,
                    initialValue:
                        layer.properties['shaderIncludesChildren'] == true,
                    dropdownColor: _menuSurface,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _fieldDecoration(),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('Frame only')),
                      DropdownMenuItem(
                        value: true,
                        child: Text('Frame + children'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _commitMutation(
                        () =>
                            layer.properties['shaderIncludesChildren'] = value,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: _PanelHeading('ARTBOARD SHADER')),
                    const Icon(Icons.memory, size: 14, color: _accent),
                  ],
                ),
                const SizedBox(height: 7),
                DropdownButtonFormField<_CanvasEffect>(
                  key: const Key('canvas-effect'),
                  isExpanded: true,
                  initialValue: _canvasEffect,
                  dropdownColor: _menuSurface,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _fieldDecoration(),
                  items: [
                    for (final effect in _CanvasEffect.values)
                      DropdownMenuItem(
                        value: effect,
                        child: Text(_effectName(effect)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _shaderTargetLayerId = null;
                    _commitMutation(() => _canvasEffect = value);
                  },
                ),
                if (_canvasEffect == _CanvasEffect.custom ||
                    layer.shaderEffect == _CanvasEffect.custom) ...[
                  const SizedBox(height: 9),
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): _compileCustomShader,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): _compileCustomShader,
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 190,
                          child: TextField(
                            key: const Key('custom-shader-source'),
                            controller: _shaderSource,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            keyboardType: TextInputType.multiline,
                            style: const TextStyle(
                              color: Color(0xFFD7D7D7),
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              height: 1.35,
                            ),
                            decoration: _fieldDecoration().copyWith(
                              contentPadding: const EdgeInsets.all(9),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('compile-custom-shader'),
                          onPressed:
                              _shaderStatus?.phase ==
                                  GpuShaderCompilePhase.compiling
                              ? null
                              : _compileCustomShader,
                          icon:
                              _shaderStatus?.phase ==
                                  GpuShaderCompilePhase.compiling
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('Compile  ⌘⏎'),
                        ),
                        const SizedBox(height: 7),
                        _ShaderStatusText(status: _shaderStatus),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 9),
                  const Text(
                    'Runtime GLSL samples the live artboard. Editing remains active through the effect.',
                    style: TextStyle(color: _muted, fontSize: 10, height: 1.4),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _pickCustomColor(_DesignLayer layer) async {
    var hsv = HSVColor.fromColor(layer.color);
    final hexController = TextEditingController(
      text:
          '#${layer.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(HSVColor next) {
            setDialogState(() {
              hsv = next;
              hexController.text =
                  '#${hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
            });
          }

          return AlertDialog(
            backgroundColor: _menuSurface,
            title: const Text(
              'Custom fill color',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const Key('custom-color-preview'),
                    height: 54,
                    decoration: BoxDecoration(
                      color: hsv.toColor(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  _colorSlider(
                    'Hue',
                    hsv.hue,
                    0,
                    360,
                    (value) => update(hsv.withHue(value)),
                  ),
                  _colorSlider(
                    'Saturation',
                    hsv.saturation,
                    0,
                    1,
                    (value) => update(hsv.withSaturation(value)),
                  ),
                  _colorSlider(
                    'Brightness',
                    hsv.value,
                    0,
                    1,
                    (value) => update(hsv.withValue(value)),
                  ),
                  _colorSlider(
                    'Opacity',
                    hsv.alpha,
                    0,
                    1,
                    (value) => update(hsv.withAlpha(value)),
                  ),
                  TextField(
                    key: const Key('custom-color-hex'),
                    controller: hexController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                    decoration: _fieldDecoration().copyWith(
                      labelText: '#AARRGGBB or #RRGGBB',
                      labelStyle: const TextStyle(color: Colors.white70),
                    ),
                    onChanged: (source) {
                      final parsed = _parseHexColor(source);
                      if (parsed != null) {
                        setDialogState(() => hsv = HSVColor.fromColor(parsed));
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('apply-custom-color'),
                onPressed: () => Navigator.pop(
                  context,
                  _parseHexColor(hexController.text) ?? hsv.toColor(),
                ),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    // The route future completes before the dialog's exit animation removes
    // its EditableText. Dispose after that animation releases the controller.
    await Future<void>.delayed(kThemeAnimationDuration);
    hexController.dispose();
    if (result != null && mounted) {
      _commitMutation(() => layer.color = result);
    }
  }

  Widget _colorSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(label, style: const TextStyle(color: Colors.white70)),
      ),
      Expanded(
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ],
  );

  Widget _propertyRow(
    String a,
    String av,
    String b,
    String bv, {
    Key? firstKey,
    Key? secondKey,
  }) {
    return Row(
      children: [
        Expanded(
          child: _PropertyValue(key: firstKey, label: a, value: av),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PropertyValue(key: secondKey, label: b, value: bv),
        ),
      ],
    );
  }
}

class _Artboard extends StatelessWidget {
  const _Artboard({
    required this.layers,
    required this.components,
    required this.selectedId,
    required this.displayScale,
    required this.onSelect,
    required this.onMove,
    required this.onMoveEnd,
    required this.onResize,
    required this.onResizeEnd,
    required this.onRotate,
    required this.onRotateEnd,
    required this.editingTextId,
    required this.inlineEditor,
    required this.textEditFocus,
    required this.enableShaders,
    required this.playback,
    required this.shaderRevision,
    required this.fallbackCustomShader,
    required this.onDoubleSelect,
    required this.onTextEditFinished,
    required this.onSecondaryTapDown,
    required this.onShaderStatus,
    required this.editingComponentId,
    required this.selectedComponentSlot,
    required this.onSelectComponentSlot,
    required this.onUpdateComponentSlot,
    required this.onFinishComponentSlotEdit,
    required this.onAssignLayerToSlot,
    required this.onComponentSlotSecondaryTapDown,
  });

  final List<_DesignLayer> layers;
  final Map<String, GraphicsComponentDefinition> components;
  final String? selectedId;
  final double displayScale;
  final ValueChanged<String?> onSelect;
  final void Function(_DesignLayer, Offset) onMove;
  final VoidCallback onMoveEnd;
  final void Function(_DesignLayer, _ResizeHandle, Offset, bool) onResize;
  final VoidCallback onResizeEnd;
  final void Function(_DesignLayer, double) onRotate;
  final VoidCallback onRotateEnd;
  final String? editingTextId;
  final TextEditingController inlineEditor;
  final FocusNode textEditFocus;
  final bool enableShaders;
  final PlaybackController playback;
  final int shaderRevision;
  final String fallbackCustomShader;
  final ValueChanged<_DesignLayer> onDoubleSelect;
  final void Function({required bool cancel}) onTextEditFinished;
  final void Function(_DesignLayer, TapDownDetails) onSecondaryTapDown;
  final ValueChanged<GpuShaderCompileStatus> onShaderStatus;
  final String? editingComponentId;
  final String? selectedComponentSlot;
  final ValueChanged<String> onSelectComponentSlot;
  final void Function(_DesignLayer, String, GraphicsComponentSlotFrame)
  onUpdateComponentSlot;
  final VoidCallback onFinishComponentSlotEdit;
  final void Function(_DesignLayer, String, String) onAssignLayerToSlot;
  final void Function(_DesignLayer, String, TapDownDetails)
  onComponentSlotSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final selectedLayer = layers
        .where((layer) => layer.id == selectedId)
        .firstOrNull;
    return DecoratedBox(
      key: const Key('artboard'),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F0E8),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 34,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: 32,
              top: 26,
              child: Text(
                'STUDIO / 26',
                style: TextStyle(
                  color: Color(0xFF8B8578),
                  fontSize: 10,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final layer in layers) _buildCanvasLayer(layer),
            if (editingComponentId case final componentLayerId?)
              if (layers
                      .where((layer) => layer.id == componentLayerId)
                      .firstOrNull
                  case final instance?)
                if (components[instance.componentId] case final definition?)
                  _ComponentSlotEditorOverlay(
                    instance: instance,
                    definition: definition,
                    displayScale: displayScale,
                    selectedSlot: selectedComponentSlot,
                    onSelect: onSelectComponentSlot,
                    onUpdate: (name, frame) =>
                        onUpdateComponentSlot(instance, name, frame),
                    onEditEnd: onFinishComponentSlotEdit,
                    onAccept: (name, childId) =>
                        onAssignLayerToSlot(instance, name, childId),
                    onSecondaryTapDown: (name, details) =>
                        onComponentSlotSecondaryTapDown(
                          instance,
                          name,
                          details,
                        ),
                  ),
            if (selectedLayer != null && selectedLayer.id != editingTextId)
              _SelectionOverlay(
                key: ValueKey('selection-${selectedLayer.id}'),
                layer: selectedLayer,
                displayScale: displayScale,
                onResize: (handle, delta) => onResize(
                  selectedLayer,
                  handle,
                  delta,
                  HardwareKeyboard.instance.isShiftPressed,
                ),
                onResizeEnd: onResizeEnd,
                onRotate: (angle) => onRotate(
                  selectedLayer,
                  HardwareKeyboard.instance.isShiftPressed
                      ? _snapRotation(angle)
                      : angle,
                ),
                onRotateEnd: onRotateEnd,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasLayer(_DesignLayer layer) {
    return _CanvasLayer(
      key: ValueKey(layer.id),
      layer: layer,
      component: layer.componentId == null
          ? null
          : components[layer.componentId],
      componentDefinitions: components,
      shaderOwner: _shaderOwnerFor(layer),
      selected: layer.id == selectedId,
      onSelect: () => onSelect(layer.id),
      onDoubleSelect: () => onDoubleSelect(layer),
      onSecondaryTapDown: (details) => onSecondaryTapDown(layer, details),
      onMove: (delta) => onMove(layer, delta),
      onMoveEnd: onMoveEnd,
      editingText: editingTextId == layer.id,
      inlineEditor: inlineEditor,
      textEditFocus: textEditFocus,
      onTextEditFinished: onTextEditFinished,
      enableShaders: enableShaders,
      playback: playback,
      shaderRevision: shaderRevision,
      displayScale: displayScale,
      fallbackCustomShader: fallbackCustomShader,
      onShaderStatus: onShaderStatus,
    );
  }

  _DesignLayer? _shaderOwnerFor(_DesignLayer layer) {
    if (layer.shaderEffect != _CanvasEffect.none) return layer;
    var parentId = layer.parentId;
    while (parentId != null) {
      final parent = layers
          .where((candidate) => candidate.id == parentId)
          .firstOrNull;
      if (parent == null) return null;
      if (parent.shaderEffect != _CanvasEffect.none &&
          parent.properties['shaderIncludesChildren'] == true) {
        return parent;
      }
      parentId = parent.parentId;
    }
    return null;
  }
}

class _CanvasLayer extends StatelessWidget {
  const _CanvasLayer({
    super.key,
    required this.layer,
    required this.component,
    required this.componentDefinitions,
    required this.shaderOwner,
    required this.selected,
    required this.onSelect,
    required this.onDoubleSelect,
    required this.onSecondaryTapDown,
    required this.onMove,
    required this.onMoveEnd,
    required this.editingText,
    required this.inlineEditor,
    required this.textEditFocus,
    required this.onTextEditFinished,
    required this.enableShaders,
    required this.playback,
    required this.shaderRevision,
    required this.displayScale,
    required this.fallbackCustomShader,
    required this.onShaderStatus,
  });

  final _DesignLayer layer;
  final GraphicsComponentDefinition? component;
  final Map<String, GraphicsComponentDefinition> componentDefinitions;
  final _DesignLayer? shaderOwner;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDoubleSelect;
  final GestureTapDownCallback onSecondaryTapDown;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final bool editingText;
  final TextEditingController inlineEditor;
  final FocusNode textEditFocus;
  final void Function({required bool cancel}) onTextEditFinished;
  final bool enableShaders;
  final PlaybackController playback;
  final int shaderRevision;
  final double displayScale;
  final String fallbackCustomShader;
  final ValueChanged<GpuShaderCompileStatus> onShaderStatus;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: layer.position.dx,
      top: layer.position.dy,
      width: layer.size.width,
      height: layer.size.height,
      child: Transform.rotate(
        angle: layer.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: editingText
                  ? _inlineTextEditor()
                  : _LayerGesture(
                      key: ValueKey('layer-gesture-${layer.id}'),
                      doubleSelectable: layer.kind == _LayerKind.text,
                      onSelect: onSelect,
                      onDoubleSelect: onDoubleSelect,
                      onSecondaryTapDown: onSecondaryTapDown,
                      onMove: (delta) =>
                          onMove(_rotateOffset(delta, layer.rotation)),
                      onMoveEnd: onMoveEnd,
                      child: KeyedSubtree(
                        key: ValueKey('layer-body-${layer.id}'),
                        child: KeyedSubtree(
                          key: ValueKey(
                            'shader-owner-${layer.id}-${shaderOwner?.id ?? 'none'}',
                          ),
                          child: _shaderLayer(_filteredLayer()),
                        ),
                      ),
                    ),
            ),
            if (selected)
              const Positioned.fill(
                child: IgnorePointer(
                  child: SizedBox(key: Key('selected-layer-body')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inlineTextEditor() => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          onTextEditFinished(cancel: false),
      const SingleActivator(LogicalKeyboardKey.enter): _insertNewline,
      const SingleActivator(LogicalKeyboardKey.enter, shift: true):
          _insertNewline,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): _insertNewline,
      const SingleActivator(LogicalKeyboardKey.backspace): _deleteBackward,
      const SingleActivator(LogicalKeyboardKey.delete): _deleteForward,
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          onTextEditFinished(cancel: true),
    },
    child: Stack(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: EditableText(
            key: Key('inline-text-${layer.id}'),
            controller: inlineEditor,
            focusNode: textEditFocus,
            style: _textStyle,
            cursorColor: _accent,
            backgroundCursorColor: Colors.white24,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            maxLines: null,
            selectionColor: _accent.withValues(alpha: 0.28),
            onTapOutside: (_) => onTextEditFinished(cancel: false),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: _accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _insertNewline() {
    final value = inlineEditor.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, '\n');
    inlineEditor.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  void _deleteBackward() {
    final value = inlineEditor.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    if (!selection.isCollapsed) {
      _replaceTextSelection(value, selection, '');
      return;
    }
    if (selection.start == 0) return;
    final previous = value.text.substring(0, selection.start).characters.last;
    _replaceTextSelection(
      value,
      TextSelection(
        baseOffset: selection.start - previous.length,
        extentOffset: selection.start,
      ),
      '',
    );
  }

  void _deleteForward() {
    final value = inlineEditor.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    if (!selection.isCollapsed) {
      _replaceTextSelection(value, selection, '');
      return;
    }
    if (selection.end == value.text.length) return;
    final next = value.text.substring(selection.end).characters.first;
    _replaceTextSelection(
      value,
      TextSelection(
        baseOffset: selection.end,
        extentOffset: selection.end + next.length,
      ),
      '',
    );
  }

  void _replaceTextSelection(
    TextEditingValue value,
    TextSelection selection,
    String replacement,
  ) {
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    inlineEditor.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
  }

  Widget _shaderLayer(Widget child) {
    final owner = shaderOwner;
    if (!enableShaders || owner == null) return child;
    final effect = owner.shaderEffect;
    final source = effect == _CanvasEffect.custom
        ? (owner.properties['appliedCustomShader'] as String? ??
              fallbackCustomShader)
        : _effectSource(effect);
    return GpuShaderSampler(
      key: ValueKey('layer-shader-${layer.id}-${owner.id}'),
      fragmentSource: source,
      paused: playback.paused,
      timeScale: playback.speed,
      interactive: false,
      capturePixelRatio: 1.25,
      rasterScale: (displayScale * 4).round().clamp(2, 8) / 4,
      inputColor: layer.color,
      initialCompilingFallback: child,
      compilingOverlay: _ShaderCompilingOverlay(displayScale: displayScale),
      compilationRevision: shaderRevision,
      onCompileStatus: effect == _CanvasEffect.custom && owner.id == layer.id
          ? onShaderStatus
          : null,
      child: child,
    );
  }

  TextStyle get _textStyle => TextStyle(
    color: layer.color,
    fontSize: ((layer.properties['fontSize'] as num?) ?? 18).toDouble(),
    height: 1.04,
    fontWeight: layer.properties['bold'] == true
        ? FontWeight.w700
        : FontWeight.w500,
    fontStyle: layer.properties['italic'] == true
        ? FontStyle.italic
        : FontStyle.normal,
    fontFamily: layer.properties['fontFamily'] as String?,
  );

  Widget _filteredLayer() {
    final child = switch (layer.kind) {
      _LayerKind.rectangle => DecoratedBox(
        decoration: BoxDecoration(
          color: layer.color,
          borderRadius: BorderRadius.circular(layer.borderRadius),
        ),
      ),
      _LayerKind.ellipse => ClipOval(child: ColoredBox(color: layer.color)),
      _LayerKind.line => CustomPaint(
        painter: _LinePainter(
          color: layer.color,
          strokeWidth: ((layer.properties['strokeWidth'] as num?) ?? 3)
              .toDouble(),
          roundCap: layer.properties['strokeCap'] != 'butt',
        ),
      ),
      _LayerKind.text => Align(
        alignment: Alignment.centerLeft,
        child: Text(layer.text!, style: _textStyle),
      ),
      _LayerKind.image => ClipRRect(
        borderRadius: BorderRadius.circular(layer.borderRadius),
        child: _imageLayer(),
      ),
      _LayerKind.component => switch (component?.properties['renderer']) {
        'hero-card' => _HeroCardComponent(layer: layer),
        'mobile-shell' => const _MobileShellComponent(),
        'mobile-feature-card' => _MobileFeatureCardComponent(layer: layer),
        _ => _UnknownComponent(
          layer: layer,
          component: component,
          definitions: componentDefinitions,
        ),
      },
    };
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_filterMatrix(layer.filter)),
      child: child,
    );
  }

  Widget _imageLayer() {
    final source = layer.imageSource;
    if (source == null) return const ColoredBox(color: Colors.black12);
    final fit = layer.properties['fit'] == 'contain'
        ? BoxFit.contain
        : BoxFit.cover;
    final colorFilter = layer.properties['tintWithLayerColor'] == true
        ? ColorFilter.mode(layer.color, BlendMode.srcIn)
        : null;
    if (source.type == 'embedded') {
      final bytes = base64Decode(source.data!);
      if (source.mimeType == 'image/svg+xml') {
        try {
          return SvgPicture.string(
            utf8.decode(bytes),
            fit: fit,
            colorFilter: colorFilter,
          );
        } on FormatException {
          return const _InvalidImageLayer(label: 'Invalid SVG');
        }
      }
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }
    final uri = source.uriValue!;
    if (uri.startsWith('asset:')) {
      final asset = uri.substring('asset:'.length);
      if (source.mimeType == 'image/svg+xml' || asset.endsWith('.svg')) {
        return SvgPicture.asset(asset, fit: fit, colorFilter: colorFilter);
      }
      return Image.asset(asset, fit: fit);
    }
    if (source.mimeType == 'image/svg+xml' || uri.endsWith('.svg')) {
      return SvgPicture.network(uri, fit: fit, colorFilter: colorFilter);
    }
    return Image.network(uri, fit: fit);
  }
}

class _InvalidImageLayer extends StatelessWidget {
  const _InvalidImageLayer({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black12,
    child: Center(child: Text(label, style: const TextStyle(fontSize: 10))),
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.color,
    required this.strokeWidth,
    required this.roundCap,
  });

  final Color color;
  final double strokeWidth;
  final bool roundCap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth.clamp(1, size.height)
      ..strokeCap = roundCap ? StrokeCap.round : StrokeCap.butt;
    final y = size.height / 2;
    canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.roundCap != roundCap;
}

class _LayerGesture extends StatefulWidget {
  const _LayerGesture({
    super.key,
    required this.doubleSelectable,
    required this.onSelect,
    required this.onDoubleSelect,
    required this.onSecondaryTapDown,
    required this.onMove,
    required this.onMoveEnd,
    required this.child,
  });

  final bool doubleSelectable;
  final VoidCallback onSelect;
  final VoidCallback onDoubleSelect;
  final GestureTapDownCallback onSecondaryTapDown;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final Widget child;

  @override
  State<_LayerGesture> createState() => _LayerGestureState();
}

class _LayerGestureState extends State<_LayerGesture> {
  bool _movingLayer = false;

  bool get _spacePan =>
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (event.buttons & kPrimaryButton == 0 || _spacePan) return;
      widget.onSelect();
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onSelect,
      onDoubleTap: widget.doubleSelectable ? widget.onDoubleSelect : null,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      onPanStart: (details) {
        _movingLayer = details.kind != PointerDeviceKind.trackpad && !_spacePan;
        if (_movingLayer) widget.onSelect();
      },
      onPanUpdate: (details) {
        if (_movingLayer) widget.onMove(details.delta);
      },
      onPanEnd: (_) {
        if (_movingLayer) widget.onMoveEnd();
        _movingLayer = false;
      },
      onPanCancel: () {
        if (_movingLayer) widget.onMoveEnd();
        _movingLayer = false;
      },
      child: widget.child,
    ),
  );
}

class _SelectionOverlay extends StatefulWidget {
  const _SelectionOverlay({
    super.key,
    required this.layer,
    required this.displayScale,
    required this.onResize,
    required this.onResizeEnd,
    required this.onRotate,
    required this.onRotateEnd,
  });

  final _DesignLayer layer;
  final double displayScale;
  final void Function(_ResizeHandle, Offset) onResize;
  final VoidCallback onResizeEnd;
  final ValueChanged<double> onRotate;
  final VoidCallback onRotateEnd;

  @override
  State<_SelectionOverlay> createState() => _SelectionOverlayState();
}

class _SelectionOverlayState extends State<_SelectionOverlay> {
  Offset? _rotationCenter;
  double? _rotationPointerAngle;
  double? _rotationStartAngle;
  bool _resizingWithPointer = false;
  bool _rotatingWithPointer = false;

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final margin = 34 / widget.displayScale;
    final controlSize = 20 / widget.displayScale;
    final overlaySize = Size(
      layer.size.width + margin * 2,
      layer.size.height + margin * 2,
    );
    return Positioned(
      left: layer.position.dx - margin,
      top: layer.position.dy - margin,
      width: overlaySize.width,
      height: overlaySize.height,
      child: Transform.rotate(
        angle: layer.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: margin,
              top: margin,
              width: layer.size.width,
              height: layer.size.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _accent,
                      width: 1.6 / widget.displayScale,
                    ),
                  ),
                ),
              ),
            ),
            for (final handle in _ResizeHandle.values)
              _positionedResizeControl(handle, layer.size),
            Positioned(
              left: margin + layer.size.width / 2 - controlSize / 2,
              top: 0,
              width: controlSize,
              height: margin,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  key: const Key('rotate-handle'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _startRotation,
                  onPanUpdate: _updateRotation,
                  onPanEnd: (_) {
                    if (_rotatingWithPointer) widget.onRotateEnd();
                    _rotatingWithPointer = false;
                  },
                  onPanCancel: () => _rotatingWithPointer = false,
                  child: Column(
                    children: [
                      _Handle(round: true, displayScale: widget.displayScale),
                      Expanded(
                        child: SizedBox(
                          width: 1 / widget.displayScale,
                          child: const ColoredBox(color: _accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionedResizeControl(_ResizeHandle handle, Size size) {
    final margin = 34 / widget.displayScale;
    final controlSize = 20 / widget.displayScale;
    final center = switch (handle) {
      _ResizeHandle.topLeft => Offset(margin, margin),
      _ResizeHandle.top => Offset(margin + size.width / 2, margin),
      _ResizeHandle.topRight => Offset(margin + size.width, margin),
      _ResizeHandle.right => Offset(
        margin + size.width,
        margin + size.height / 2,
      ),
      _ResizeHandle.bottomRight => Offset(
        margin + size.width,
        margin + size.height,
      ),
      _ResizeHandle.bottom => Offset(
        margin + size.width / 2,
        margin + size.height,
      ),
      _ResizeHandle.bottomLeft => Offset(margin, margin + size.height),
      _ResizeHandle.left => Offset(margin, margin + size.height / 2),
    };
    return Positioned(
      left: center.dx - controlSize / 2,
      top: center.dy - controlSize / 2,
      width: controlSize,
      height: controlSize,
      child: MouseRegion(
        cursor: _cursorFor(handle),
        child: GestureDetector(
          key: ValueKey('resize-handle-${handle.name}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details) =>
              _resizingWithPointer = details.kind != PointerDeviceKind.trackpad,
          onPanUpdate: (details) {
            if (_resizingWithPointer) {
              widget.onResize(handle, details.delta);
            }
          },
          onPanEnd: (_) {
            if (_resizingWithPointer) widget.onResizeEnd();
            _resizingWithPointer = false;
          },
          onPanCancel: () => _resizingWithPointer = false,
          child: Center(child: _Handle(displayScale: widget.displayScale)),
        ),
      ),
    );
  }

  void _startRotation(DragStartDetails details) {
    _rotatingWithPointer = details.kind != PointerDeviceKind.trackpad;
    if (!_rotatingWithPointer) return;
    final box = context.findRenderObject()! as RenderBox;
    _rotationCenter = box.localToGlobal(box.size.center(Offset.zero));
    _rotationPointerAngle = _angleFromCenter(details.globalPosition);
    _rotationStartAngle = widget.layer.rotation;
  }

  void _updateRotation(DragUpdateDetails details) {
    if (!_rotatingWithPointer) return;
    final pointerStart = _rotationPointerAngle;
    final rotationStart = _rotationStartAngle;
    if (pointerStart == null || rotationStart == null) return;
    widget.onRotate(
      rotationStart + _angleFromCenter(details.globalPosition) - pointerStart,
    );
  }

  double _angleFromCenter(Offset position) {
    final delta = position - _rotationCenter!;
    return math.atan2(delta.dy, delta.dx);
  }

  MouseCursor _cursorFor(_ResizeHandle handle) => switch (handle) {
    _ResizeHandle.topLeft ||
    _ResizeHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    _ResizeHandle.topRight ||
    _ResizeHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    _ResizeHandle.top ||
    _ResizeHandle.bottom => SystemMouseCursors.resizeUpDown,
    _ResizeHandle.left ||
    _ResizeHandle.right => SystemMouseCursors.resizeLeftRight,
  };
}

class _ComponentSlotEditorOverlay extends StatefulWidget {
  const _ComponentSlotEditorOverlay({
    required this.instance,
    required this.definition,
    required this.displayScale,
    required this.selectedSlot,
    required this.onSelect,
    required this.onUpdate,
    required this.onEditEnd,
    required this.onAccept,
    required this.onSecondaryTapDown,
  });

  final _DesignLayer instance;
  final GraphicsComponentDefinition definition;
  final double displayScale;
  final String? selectedSlot;
  final ValueChanged<String> onSelect;
  final void Function(String, GraphicsComponentSlotFrame) onUpdate;
  final VoidCallback onEditEnd;
  final void Function(String, String) onAccept;
  final void Function(String, TapDownDetails) onSecondaryTapDown;

  @override
  State<_ComponentSlotEditorOverlay> createState() =>
      _ComponentSlotEditorOverlayState();
}

class _ComponentSlotEditorOverlayState
    extends State<_ComponentSlotEditorOverlay> {
  _DesignLayer get instance => widget.instance;
  GraphicsComponentDefinition get definition => widget.definition;
  double get displayScale => widget.displayScale;
  String? get selectedSlot => widget.selectedSlot;
  ValueChanged<String> get onSelect => widget.onSelect;
  void Function(String, GraphicsComponentSlotFrame) get onUpdate =>
      widget.onUpdate;
  VoidCallback get onEditEnd => widget.onEditEnd;
  void Function(String, String) get onAccept => widget.onAccept;
  void Function(String, TapDownDetails) get onSecondaryTapDown =>
      widget.onSecondaryTapDown;
  final Map<String, GraphicsComponentSlotFrame> _dragStartFrames = {};
  final Map<String, Offset> _dragStartPositions = {};

  @override
  Widget build(BuildContext context) {
    final definitionWidth = definition.width ?? instance.size.width;
    final definitionHeight = definition.height ?? instance.size.height;
    final sx = instance.size.width / definitionWidth;
    final sy = instance.size.height / definitionHeight;
    return Positioned(
      left: instance.position.dx,
      top: instance.position.dy,
      width: instance.size.width,
      height: instance.size.height,
      child: Transform.rotate(
        angle: instance.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.04),
                    border: Border.all(
                      color: _accent,
                      width: 1.5 / displayScale,
                    ),
                  ),
                ),
              ),
            ),
            for (final entry in definition.slotFrames.entries)
              Positioned(
                left: entry.value.x * sx,
                top: entry.value.y * sy,
                width: entry.value.width * sx,
                height: entry.value.height * sy,
                child: DragTarget<String>(
                  key: Key('component-slot-${entry.key}'),
                  onWillAcceptWithDetails: (details) =>
                      details.data != instance.id,
                  onAcceptWithDetails: (details) =>
                      onAccept(entry.key, details.data),
                  builder: (context, candidates, rejected) {
                    final selected = selectedSlot == entry.key;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelect(entry.key),
                      onSecondaryTapDown: (details) =>
                          onSecondaryTapDown(entry.key, details),
                      onPanStart: (details) {
                        if (details.kind == PointerDeviceKind.trackpad) return;
                        _dragStartFrames[entry.key] = entry.value;
                        _dragStartPositions[entry.key] = details.globalPosition;
                      },
                      onPanUpdate: (details) {
                        final startFrame = _dragStartFrames[entry.key];
                        final startPosition = _dragStartPositions[entry.key];
                        if (startFrame == null || startPosition == null) return;
                        onSelect(entry.key);
                        final screenDelta =
                            details.globalPosition - startPosition;
                        onUpdate(
                          entry.key,
                          GraphicsComponentSlotFrame(
                            x:
                                startFrame.x +
                                screenDelta.dx / displayScale / sx,
                            y:
                                startFrame.y +
                                screenDelta.dy / displayScale / sy,
                            width: startFrame.width,
                            height: startFrame.height,
                          ),
                        );
                      },
                      onPanEnd: (_) {
                        final edited =
                            _dragStartFrames.remove(entry.key) != null;
                        _dragStartPositions.remove(entry.key);
                        if (edited) onEditEnd();
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _accent.withValues(
                            alpha: candidates.isNotEmpty ? 0.30 : 0.13,
                          ),
                          border: Border.all(
                            color: selected ? Colors.white : _accent,
                            width: (selected ? 2 : 1) / displayScale,
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(5 / displayScale),
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10 / displayScale,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Positioned(
                              right: -6 / displayScale,
                              bottom: -6 / displayScale,
                              width: 18 / displayScale,
                              height: 18 / displayScale,
                              child: GestureDetector(
                                key: Key('component-slot-resize-${entry.key}'),
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  if (details.kind ==
                                      PointerDeviceKind.trackpad) {
                                    return;
                                  }
                                  _dragStartFrames['resize:${entry.key}'] =
                                      entry.value;
                                  _dragStartPositions['resize:${entry.key}'] =
                                      details.globalPosition;
                                },
                                onPanUpdate: (details) {
                                  final key = 'resize:${entry.key}';
                                  final startFrame = _dragStartFrames[key];
                                  final startPosition =
                                      _dragStartPositions[key];
                                  if (startFrame == null ||
                                      startPosition == null) {
                                    return;
                                  }
                                  final screenDelta =
                                      details.globalPosition - startPosition;
                                  onUpdate(
                                    entry.key,
                                    GraphicsComponentSlotFrame(
                                      x: startFrame.x,
                                      y: startFrame.y,
                                      width: math.max(
                                        24,
                                        startFrame.width +
                                            screenDelta.dx / displayScale / sx,
                                      ),
                                      height: math.max(
                                        24,
                                        startFrame.height +
                                            screenDelta.dy / displayScale / sy,
                                      ),
                                    ),
                                  );
                                },
                                onPanEnd: (_) {
                                  final edited =
                                      _dragStartFrames.remove(
                                        'resize:${entry.key}',
                                      ) !=
                                      null;
                                  _dragStartPositions.remove(
                                    'resize:${entry.key}',
                                  );
                                  if (edited) onEditEnd();
                                },
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnknownComponent extends StatelessWidget {
  const _UnknownComponent({
    required this.layer,
    required this.component,
    required this.definitions,
  });

  final _DesignLayer layer;
  final GraphicsComponentDefinition? component;
  final Map<String, GraphicsComponentDefinition> definitions;

  @override
  Widget build(BuildContext context) {
    final component = this.component;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: layer.color,
        border: Border.all(color: Colors.white38),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final definitionWidth = component?.width ?? constraints.maxWidth;
          final definitionHeight = component?.height ?? constraints.maxHeight;
          final sx = constraints.maxWidth / definitionWidth;
          final sy = constraints.maxHeight / definitionHeight;
          return Stack(
            children: [
              Center(
                child: Text(
                  component?.name ?? layer.componentId ?? 'Unknown component',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              if (component != null)
                for (final entry in component.slotFrames.entries)
                  if (layer.slots[entry.key] case final referencedId?)
                    Positioned(
                      key: Key('component-slot-reference-${entry.key}'),
                      left: entry.value.x * sx,
                      top: entry.value.y * sy,
                      width: entry.value.width * sx,
                      height: entry.value.height * sy,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            definitions[referencedId]?.name ?? referencedId,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCardComponent extends StatelessWidget {
  const _HeroCardComponent({required this.layer});

  final _DesignLayer layer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: layer.color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: 390,
          height: 292,
          child: Padding(
            padding: const EdgeInsets.all(38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'COMPONENT',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.widgets_outlined, color: Colors.white54),
                  ],
                ),
                const Spacer(),
                _renderSlot(layer.slots['header']),
                const SizedBox(height: 18),
                _renderSlot(layer.slots['body']),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderSlot(String? componentId) => switch (componentId) {
    'title-block' => const Text(
      'Make ideas\nmove.',
      style: TextStyle(
        color: Colors.white,
        fontSize: 39,
        height: 1.04,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
    ),
    'badge' => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFF785A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'NEW COMPONENT',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    ),
    'subtitle' => const Text(
      'A live, editable canvas',
      style: TextStyle(
        color: Color(0xFFDAD6FF),
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    'action' => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Open project →',
        style: TextStyle(
          color: Color(0xFF252525),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    null => const SizedBox.shrink(),
    _ => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        componentId,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ),
  };
}

class _MobileShellComponent extends StatelessWidget {
  const _MobileShellComponent();

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.fill,
    child: SizedBox(
      width: 320,
      height: 504,
      child: Stack(
        children: [
          _card(
            left: 16,
            top: 16,
            width: 288,
            height: 54,
            color: Colors.white,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(18, 7, 18, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good morning',
                    style: TextStyle(
                      color: Color(0xFF1D1C22),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Your workspace, at a glance',
                    style: TextStyle(color: Color(0xFF77747F), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          _summaryCard(
            left: 16,
            title: 'Focus',
            copy: 'Lorem ipsum dolor sit amet.',
            color: const Color(0xFFFFD76A),
            textColor: const Color(0xFF27231A),
          ),
          _summaryCard(
            left: 166,
            title: 'Progress',
            copy: 'Lorem ipsum dolor sit amet.',
            color: const Color(0xFFB8DED7),
            textColor: const Color(0xFF16322D),
          ),
          _card(
            left: 16,
            top: 346,
            width: 288,
            height: 70,
            color: Colors.white,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(18, 11, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent activity',
                    style: TextStyle(
                      color: Color(0xFF34313A),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Lorem ipsum dolor sit amet, consectetur.',
                    style: TextStyle(color: Color(0xFF77747F), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          _card(
            left: 16,
            top: 428,
            width: 288,
            height: 60,
            radius: 24,
            color: const Color(0xFF201E26),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home', active: true),
                _NavItem(icon: Icons.search_rounded, label: 'Search'),
                _NavItem(icon: Icons.bookmark_outline_rounded, label: 'Saved'),
                _NavItem(icon: Icons.person_outline_rounded, label: 'Me'),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _summaryCard({
    required double left,
    required String title,
    required String copy,
    required Color color,
    required Color textColor,
  }) => _card(
    left: left,
    top: 230,
    width: 138,
    height: 104,
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(copy, style: TextStyle(color: textColor, fontSize: 10)),
        ],
      ),
    ),
  );

  static Widget _card({
    required double left,
    required double top,
    required double width,
    required double height,
    required Color color,
    required Widget child,
    double radius = 20,
  }) => Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    ),
  );
}

class _MobileFeatureCardComponent extends StatelessWidget {
  const _MobileFeatureCardComponent({required this.layer});

  final _DesignLayer layer;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: layer.color,
      borderRadius: BorderRadius.circular(26),
    ),
    child: const Padding(
      padding: EdgeInsets.fromLTRB(18, 13, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FEATURED',
            style: TextStyle(
              color: Color(0xFFDAD5FF),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Build better habits',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          Spacer(),
          Text(
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
            style: TextStyle(color: Color(0xFFE8E5FF), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 16, color: active ? Colors.white : Colors.white54),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontSize: 8,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.unit, required this.displayScale});

  final double unit;
  final double displayScale;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFF625E56).withValues(alpha: 0.10)
      ..strokeWidth = 0.65 / displayScale;
    final major = Paint()
      ..color = const Color(0xFF625E56).withValues(alpha: 0.17)
      ..strokeWidth = 0.85 / displayScale;
    var index = 0;
    for (var x = 0.0; x <= size.width; x += unit, index++) {
      final paint = index % 4 == 0 ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    index = 0;
    for (var y = 0.0; y <= size.height; y += unit, index++) {
      final paint = index % 4 == 0 ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.unit != unit || oldDelegate.displayScale != displayScale;
}

class _AlignmentGuidePainter extends CustomPainter {
  const _AlignmentGuidePainter({
    required this.guides,
    required this.displayScale,
  });

  final List<_AlignmentGuide> guides;
  final double displayScale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accent.withValues(alpha: 0.68)
      ..strokeWidth = 1 / displayScale;
    for (final guide in guides) {
      switch (guide.axis) {
        case _GuideAxis.horizontal:
          canvas.drawLine(
            Offset(0, guide.position),
            Offset(size.width, guide.position),
            paint,
          );
        case _GuideAxis.vertical:
          canvas.drawLine(
            Offset(guide.position, 0),
            Offset(guide.position, size.height),
            paint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_AlignmentGuidePainter oldDelegate) =>
      oldDelegate.displayScale != displayScale ||
      !_sameGuides(oldDelegate.guides, guides);

  bool _sameGuides(List<_AlignmentGuide> a, List<_AlignmentGuide> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].axis != b[index].axis ||
          a[index].position != b[index].position) {
        return false;
      }
    }
    return true;
  }
}

class _Handle extends StatelessWidget {
  const _Handle({this.round = false, this.displayScale = 1});

  final bool round;
  final double displayScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12 / displayScale,
      height: 12 / displayScale,
      transform: Matrix4.translationValues(0, 0, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        border: Border.all(color: _accent, width: 1.5 / displayScale),
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    required this.layer,
    required this.depth,
    required this.selected,
    required this.canContainChildren,
    required this.canAccept,
    required this.onAccept,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.renaming,
    required this.renameController,
    required this.renameFocus,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
  });

  final _DesignLayer layer;
  final int depth;
  final bool selected;
  final bool canContainChildren;
  final ValueChanged<String> onAccept;
  final bool Function(String) canAccept;
  final VoidCallback onTap;
  final GestureTapDownCallback onSecondaryTapDown;
  final bool renaming;
  final TextEditingController renameController;
  final FocusNode renameFocus;
  final ValueChanged<String> onRenameSubmitted;
  final VoidCallback onRenameCancelled;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          canContainChildren && canAccept(details.data),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) => Padding(
        padding: EdgeInsets.only(left: depth * 14.0),
        child: Draggable<String>(
          key: ValueKey('layer-drag-${layer.id}'),
          data: layer.id,
          feedback: Material(
            color: _panelHi,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 160,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  layer.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _tile(candidates)),
          child: _tile(candidates),
        ),
      ),
    );
  }

  Widget _tile(List<String?> candidates) {
    final accepting = candidates.isNotEmpty;
    return Material(
      color: accepting
          ? _accent.withValues(alpha: 0.22)
          : selected
          ? _panelHi
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: accepting ? _accent : Colors.transparent),
      ),
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              if (depth > 0) ...[
                const Icon(
                  Icons.subdirectory_arrow_right,
                  size: 11,
                  color: _muted,
                ),
                const SizedBox(width: 3),
              ],
              Icon(_icon, size: 14, color: selected ? _accent : _muted),
              const SizedBox(width: 8),
              Expanded(
                child: renaming
                    ? CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.escape):
                              onRenameCancelled,
                          const SingleActivator(LogicalKeyboardKey.enter): () =>
                              onRenameSubmitted(renameController.text),
                        },
                        child: TextField(
                          key: Key('rename-layer-${layer.id}'),
                          controller: renameController,
                          focusNode: renameFocus,
                          autofocus: true,
                          selectAllOnFocus: true,
                          onSubmitted: onRenameSubmitted,
                          onTapOutside: (_) =>
                              onRenameSubmitted(renameController.text),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 4,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      )
                    : Text(
                        layer.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white : _muted,
                          fontSize: 11,
                        ),
                      ),
              ),
              if (!renaming) ...[
                if (canContainChildren)
                  const Icon(
                    Icons.folder_open_outlined,
                    size: 13,
                    color: _muted,
                  )
                else
                  const Icon(Icons.drag_indicator, size: 13, color: _muted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (layer.kind) {
    _LayerKind.rectangle => Icons.crop_square,
    _LayerKind.ellipse => Icons.circle_outlined,
    _LayerKind.line => Icons.horizontal_rule_rounded,
    _LayerKind.text => Icons.title,
    _LayerKind.image => Icons.image_outlined,
    _LayerKind.component => Icons.widgets_outlined,
  };
}

class _LayerDropZone extends StatelessWidget {
  const _LayerDropZone({
    super.key,
    required this.depth,
    required this.onAccept,
  });

  final int depth;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => true,
    onAcceptWithDetails: (details) => onAccept(details.data),
    builder: (context, candidates, rejected) => SizedBox(
      height: candidates.isEmpty ? 4 : 8,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 14.0 + 8, right: 8),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: candidates.isEmpty ? 1 : 2,
            color: candidates.isEmpty ? Colors.transparent : _accent,
          ),
        ),
      ),
    ),
  );
}

class _ComponentSlotPicker extends StatelessWidget {
  const _ComponentSlotPicker({
    super.key,
    required this.label,
    required this.value,
    required this.allowedComponents,
    required this.definitions,
    required this.excludedComponentId,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> allowedComponents;
  final Map<String, GraphicsComponentDefinition> definitions;
  final String? excludedComponentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final componentIds = allowedComponents.isEmpty
        ? definitions.keys
        : allowedComponents;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: value,
            dropdownColor: _menuSurface,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _fieldDecoration(),
            items: [
              const DropdownMenuItem(value: null, child: Text('Empty')),
              for (final id in componentIds)
                if (id != excludedComponentId && definitions.containsKey(id))
                  DropdownMenuItem(
                    value: id,
                    child: Text(definitions[id]?.name ?? id),
                  ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 9.5,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _ShaderCompilingOverlay extends StatelessWidget {
  const _ShaderCompilingOverlay({required this.displayScale});

  final double displayScale;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 150 || constraints.maxHeight < 90;
      return Align(
        alignment: Alignment.topRight,
        child: Transform.scale(
          scale: 1 / displayScale,
          alignment: Alignment.topRight,
          child: Container(
            key: const Key('shader-compiling-overlay'),
            margin: const EdgeInsets.all(10),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xDD202020),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 7),
                  const Text(
                    'Compiling shader',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ShaderStatusText extends StatelessWidget {
  const _ShaderStatusText({required this.status});

  final GpuShaderCompileStatus? status;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return const Text(
        'Edit the fragment source, then compile.',
        style: TextStyle(color: _muted, fontSize: 9.5),
      );
    }
    return switch (status.phase) {
      GpuShaderCompilePhase.compiling => const Text(
        'Compiling with impellerc…',
        key: Key('shader-compile-status'),
        style: TextStyle(color: _muted, fontSize: 9.5),
      ),
      GpuShaderCompilePhase.succeeded => Text(
        'Compiled in ${status.elapsedMs} ms',
        key: const Key('shader-compile-status'),
        style: const TextStyle(color: Color(0xFF76B889), fontSize: 9.5),
      ),
      GpuShaderCompilePhase.failed => Text(
        status.errors ?? 'Compilation failed',
        key: const Key('shader-compile-status'),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFFF8870),
          fontFamily: 'monospace',
          fontSize: 9,
          height: 1.3,
        ),
      ),
    };
  }
}

class _PropertyValue extends StatelessWidget {
  const _PropertyValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _shell,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10.5)),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration() => const InputDecoration(
  filled: true,
  fillColor: _shell,
  isDense: true,
  contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 9),
  border: OutlineInputBorder(
    borderSide: BorderSide(color: _line),
    borderRadius: BorderRadius.all(Radius.circular(6)),
  ),
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(color: _line),
    borderRadius: BorderRadius.all(Radius.circular(6)),
  ),
);

String _filterName(_LayerFilter filter) => switch (filter) {
  _LayerFilter.none => 'None',
  _LayerFilter.mono => 'Monochrome',
  _LayerFilter.sepia => 'Sepia',
  _LayerFilter.warm => 'Warm contrast',
};

String _effectName(_CanvasEffect effect) => switch (effect) {
  _CanvasEffect.none => 'None',
  _CanvasEffect.paper => 'Paper grain · GLSL',
  _CanvasEffect.halftone => 'Halftone · GLSL',
  _CanvasEffect.ripple => 'Ripple · GLSL',
  _CanvasEffect.custom => 'Custom GLSL…',
};

List<double> _filterMatrix(_LayerFilter filter) => switch (filter) {
  _LayerFilter.none => const <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  _LayerFilter.mono => const <double>[
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  _LayerFilter.sepia => const <double>[
    .393,
    .769,
    .189,
    0,
    0,
    .349,
    .686,
    .168,
    0,
    0,
    .272,
    .534,
    .131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  _LayerFilter.warm => const <double>[
    1.12,
    .04,
    0,
    0,
    7,
    0,
    1.02,
    0,
    0,
    1,
    0,
    0,
    .86,
    0,
    -3,
    0,
    0,
    0,
    1,
    0,
  ],
};

const _shaderHeader = '''
uniform FragInfo {
  vec2 resolution;
  vec2 pointer;
  float time;
  float param0; float param1; float param2; float param3;
} u;
uniform sampler2D u_child;
in vec2 v_uv;
out vec4 frag_color;
''';

const _homeIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="#000" d="M3 11.2 12 4l9 7.2v8.3a.5.5 0 0 1-.5.5H15v-6H9v6H3.5a.5.5 0 0 1-.5-.5z"/>
</svg>
''';

const _searchIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="#000" d="M10.5 4a6.5 6.5 0 1 0 3.98 11.64L20 21.16 21.16 20l-5.52-5.52A6.5 6.5 0 0 0 10.5 4m0 2a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9"/>
</svg>
''';

const _savedIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="#000" d="M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1m1 2v12.55l5-2.86 5 2.86V5z"/>
</svg>
''';

const _profileIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="#000" d="M12 3a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9m0 11c4.42 0 8 2.24 8 5v2H4v-2c0-2.76 3.58-5 8-5"/>
</svg>
''';

GraphicsImageSource _embeddedSvg(String source) => GraphicsImageSource.embedded(
  mimeType: 'image/svg+xml',
  data: base64Encode(utf8.encode(source)),
);

String _effectSource(_CanvasEffect effect) => switch (effect) {
  _CanvasEffect.none =>
    '$_shaderHeader\nvoid main() { frag_color = texture(u_child, vec2(v_uv.x, 1.0 - v_uv.y)); }',
  _CanvasEffect.paper =>
    '''
$_shaderHeader
float noise(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  vec4 c = texture(u_child, uv);
  float grain = noise(uv * u.resolution + floor(u.time * 8.0)) - 0.5;
  c.rgb += grain * 0.055 * c.a;
  frag_color = c;
}
''',
  _CanvasEffect.halftone =>
    '''
$_shaderHeader
void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  vec2 aspect = vec2(u.resolution.x / u.resolution.y, 1.0);
  vec2 grid = uv * aspect * 120.0;
  vec2 sampleUv = (floor(grid) + 0.5) / 120.0 / aspect;
  vec4 c = texture(u_child, sampleUv);
  float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
  float dotMask = smoothstep((1.0 - lum) * 0.55 + 0.05, (1.0 - lum) * 0.55 - 0.08, length(fract(grid) - 0.5));
  frag_color = vec4(mix(vec3(0.96, 0.94, 0.90), vec3(0.10), dotMask) * c.a, c.a);
}
''',
  _CanvasEffect.ripple =>
    '''
$_shaderHeader
void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  vec2 pointer = vec2(u.pointer.x, 1.0 - u.pointer.y);
  vec2 d = uv - pointer;
  float distanceToPointer = length(d);
  float wave = sin(distanceToPointer * 55.0 - u.time * 5.0) * exp(-distanceToPointer * 8.0);
  vec2 offset = normalize(d + vec2(0.0001)) * wave * 0.008;
  frag_color = texture(u_child, uv + offset);
}
''',
  _CanvasEffect.custom => throw StateError('Custom GLSL has editable source'),
};

/// Shader sources used by the editor, exposed so validation can compile the
/// same GLSL that the presentation selects at runtime.
@visibleForTesting
List<String> get graphicsEditorShaderSources => [
  _effectSource(_CanvasEffect.paper),
  _effectSource(_CanvasEffect.halftone),
  _effectSource(_CanvasEffect.ripple),
];

List<GraphicsComponentDefinition> _defaultComponentDefinitions() => [
  GraphicsComponentDefinition(
    id: 'mobile-shell',
    name: 'Mobile layout',
    width: 320,
    height: 504,
    properties: const {'renderer': 'mobile-shell'},
  ),
  GraphicsComponentDefinition(
    id: 'mobile-feature-card',
    name: 'Featured card',
    width: 288,
    height: 136,
    properties: const {'renderer': 'mobile-feature-card'},
  ),
  GraphicsComponentDefinition(
    id: 'hero-card',
    name: 'Hero card',
    width: 390,
    height: 292,
    slots: const {
      'header': ['title-block', 'badge'],
      'body': ['subtitle', 'action'],
    },
    properties: const {'renderer': 'hero-card'},
    slotFrames: const {
      'header': GraphicsComponentSlotFrame(
        x: 42,
        y: 48,
        width: 306,
        height: 82,
      ),
      'body': GraphicsComponentSlotFrame(x: 42, y: 146, width: 306, height: 92),
    },
  ),
  GraphicsComponentDefinition(id: 'title-block', name: 'Title block'),
  GraphicsComponentDefinition(id: 'badge', name: 'Badge component'),
  GraphicsComponentDefinition(id: 'subtitle', name: 'Subtitle component'),
  GraphicsComponentDefinition(id: 'action', name: 'Action component'),
];

T _enumByName<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw GraphicsDocumentFormatException('$path has unsupported value "$name".');
}

String _safeFileName(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
  return safe.isEmpty ? 'design-canvas' : safe;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) =>
    (jsonDecode(jsonEncode(source)) as Map).cast<String, Object?>();

Color? _parseHexColor(String source) {
  var value = source.trim().replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
