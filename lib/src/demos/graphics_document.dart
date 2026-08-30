import 'dart:convert';

/// Stable, portable representation of a design-canvas document.
///
/// The schema keeps rendering properties open-ended while making geometry,
/// component references, and slots explicit enough to validate on import.
class GraphicsDocument {
  GraphicsDocument({
    required this.name,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.nodes,
    required this.components,
    this.canvasEffect = 'none',
    this.customShader = '',
    this.appliedCustomShader = '',
    Map<String, Object?>? metadata,
  }) : metadata = metadata ?? <String, Object?>{};

  static const int currentSchemaVersion = 1;
  static const int maximumNestingDepth = 32;

  final String name;
  final double canvasWidth;
  final double canvasHeight;
  final List<GraphicsDocumentNode> nodes;
  final List<GraphicsComponentDefinition> components;
  final String canvasEffect;
  final String customShader;
  final String appliedCustomShader;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'name': name,
    'canvas': {'width': canvasWidth, 'height': canvasHeight},
    'nodes': [for (final node in nodes) node.toJson()],
    'components': [for (final component in components) component.toJson()],
    'effects': {
      'canvas': canvasEffect,
      'customShader': customShader,
      'appliedCustomShader': appliedCustomShader,
    },
    'metadata': metadata,
  };

  String encode({bool pretty = true}) {
    final value = toJson();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
  }

  factory GraphicsDocument.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw GraphicsDocumentFormatException('Invalid JSON: ${error.message}');
    }
    return GraphicsDocument.fromJson(_objectMap(decoded, 'document'));
  }

  factory GraphicsDocument.fromJson(Map<String, Object?> root) {
    final version = _integer(root['schemaVersion'], 'schemaVersion');
    if (version != currentSchemaVersion) {
      throw GraphicsDocumentFormatException(
        'Unsupported schemaVersion $version; expected $currentSchemaVersion.',
      );
    }
    final canvas = _objectMap(root['canvas'], 'canvas');
    final effects = root['effects'] == null
        ? <String, Object?>{}
        : _objectMap(root['effects'], 'effects');
    final customShader = effects['customShader'] == null
        ? ''
        : _string(effects['customShader'], 'effects.customShader');
    final document = GraphicsDocument(
      name: _string(root['name'], 'name'),
      canvasWidth: _number(canvas['width'], 'canvas.width'),
      canvasHeight: _number(canvas['height'], 'canvas.height'),
      nodes: _objectList(root['nodes'], 'nodes').indexed
          .map(
            (entry) => GraphicsDocumentNode.fromJson(
              entry.$2,
              path: 'nodes[${entry.$1}]',
            ),
          )
          .toList(),
      components: _objectList(root['components'], 'components').indexed
          .map(
            (entry) => GraphicsComponentDefinition.fromJson(
              entry.$2,
              path: 'components[${entry.$1}]',
            ),
          )
          .toList(),
      canvasEffect: effects['canvas'] == null
          ? 'none'
          : _string(effects['canvas'], 'effects.canvas'),
      customShader: customShader,
      appliedCustomShader: effects['appliedCustomShader'] == null
          ? customShader
          : _string(
              effects['appliedCustomShader'],
              'effects.appliedCustomShader',
            ),
      metadata: root['metadata'] == null
          ? null
          : _objectMap(root['metadata'], 'metadata'),
    );
    document.validate();
    return document;
  }

  void validate() {
    if (name.trim().isEmpty) {
      throw const GraphicsDocumentFormatException('name must not be empty.');
    }
    if (!canvasWidth.isFinite ||
        !canvasHeight.isFinite ||
        canvasWidth <= 0 ||
        canvasHeight <= 0) {
      throw const GraphicsDocumentFormatException(
        'canvas dimensions must be positive finite numbers.',
      );
    }

    final nodeIds = <String>{};
    final nodesById = <String, GraphicsDocumentNode>{};
    for (final node in nodes) {
      if (!nodeIds.add(node.id)) {
        throw GraphicsDocumentFormatException(
          'Duplicate node id "${node.id}".',
        );
      }
      node.validate();
      nodesById[node.id] = node;
    }
    for (final node in nodes) {
      final parentId = node.parentId;
      if (parentId != null && !nodesById.containsKey(parentId)) {
        throw GraphicsDocumentFormatException(
          'Node "${node.id}" references unknown parent "$parentId".',
        );
      }
      final ancestry = <String>{node.id};
      var ancestorId = parentId;
      while (ancestorId != null) {
        if (!ancestry.add(ancestorId)) {
          throw GraphicsDocumentFormatException(
            'Node "${node.id}" has a cyclic parent relationship.',
          );
        }
        if (ancestry.length > maximumNestingDepth) {
          throw GraphicsDocumentFormatException(
            'Node "${node.id}" exceeds the maximum nesting depth of '
            '$maximumNestingDepth.',
          );
        }
        ancestorId = nodesById[ancestorId]?.parentId;
      }
    }

    final definitions = <String, GraphicsComponentDefinition>{};
    for (final component in components) {
      if (definitions.containsKey(component.id)) {
        throw GraphicsDocumentFormatException(
          'Duplicate component id "${component.id}".',
        );
      }
      component.validate();
      definitions[component.id] = component;
    }
    for (final node in nodes.where((node) => node.componentId != null)) {
      final definition = definitions[node.componentId];
      if (definition == null) {
        throw GraphicsDocumentFormatException(
          'Node "${node.id}" references unknown component '
          '"${node.componentId}".',
        );
      }
      for (final assignment in node.slots.entries) {
        final allowed = definition.slots[assignment.key];
        if (allowed == null) {
          throw GraphicsDocumentFormatException(
            'Component "${definition.id}" has no slot "${assignment.key}".',
          );
        }
        final assigned = assignment.value;
        if (assigned != null &&
            (!definitions.containsKey(assigned) ||
                (allowed.isNotEmpty && !allowed.contains(assigned)))) {
          throw GraphicsDocumentFormatException(
            'Slot "${assignment.key}" cannot contain component "$assigned".',
          );
        }
      }
    }
    for (final node in nodes.where((node) => node.parentSlot != null)) {
      final parent = nodesById[node.parentId];
      if (parent == null) {
        throw GraphicsDocumentFormatException(
          'Node "${node.id}" assigns parentSlot without a parent.',
        );
      }
      final definition = definitions[parent.componentId];
      if (definition == null) {
        throw GraphicsDocumentFormatException(
          'Node "${node.id}" assigns parentSlot "${node.parentSlot}" to '
          'non-component parent "${parent.id}".',
        );
      }
      final slot = node.parentSlot!;
      if (!definition.slots.containsKey(slot) &&
          !definition.slotFrames.containsKey(slot)) {
        throw GraphicsDocumentFormatException(
          'Component "${definition.id}" has no slot "$slot" for child '
          'node "${node.id}".',
        );
      }
    }
  }
}

/// Serialized snapshot history for one design document.
///
/// States use compact JSON internally. Committing after undo removes the redo
/// branch, and the oldest states are discarded when [limit] is reached.
class GraphicsDocumentHistory {
  GraphicsDocumentHistory(GraphicsDocument initial, {this.limit = defaultLimit})
    : assert(limit > 0) {
    initial.validate();
    _states.add(initial.encode(pretty: false));
  }

  GraphicsDocumentHistory._({required this.limit});

  static const int currentHistoryVersion = 1;
  static const int defaultLimit = 1000;
  static const String fileFormat = 'gpu-design-history';

  final int limit;
  final List<String> _states = [];
  int _currentIndex = 0;

  int get length => _states.length;
  int get currentIndex => _currentIndex;
  bool get canUndo => _currentIndex > 0;
  bool get canRedo => _currentIndex + 1 < _states.length;
  GraphicsDocument get current => _decodeState(_currentIndex);

  bool commit(GraphicsDocument document) {
    document.validate();
    final encoded = document.encode(pretty: false);
    if (_states[_currentIndex] == encoded) return false;
    if (canRedo) {
      _states.removeRange(_currentIndex + 1, _states.length);
    }
    _states.add(encoded);
    if (_states.length > limit) {
      _states.removeRange(0, _states.length - limit);
    }
    _currentIndex = _states.length - 1;
    return true;
  }

  GraphicsDocument? undo() {
    if (!canUndo) return null;
    _currentIndex--;
    return current;
  }

  GraphicsDocument? redo() {
    if (!canRedo) return null;
    _currentIndex++;
    return current;
  }

  GraphicsDocument jumpTo(int index) {
    _checkIndex(index);
    _currentIndex = index;
    return current;
  }

  /// Resolves any ordered state sequence without changing the history cursor.
  /// Indices may be reordered or repeated for non-linear playback.
  List<GraphicsDocument> sequence(Iterable<int> indices) => [
    for (final index in indices) _decodeState(_checkedIndex(index)),
  ];

  String encode({bool pretty = true}) {
    final value = <String, Object?>{
      'fileFormat': fileFormat,
      'historyVersion': currentHistoryVersion,
      'currentIndex': _currentIndex,
      'states': [for (final state in _states) jsonDecode(state)],
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
  }

  /// Decodes a history archive or imports a legacy single-state document.
  factory GraphicsDocumentHistory.decode(
    String source, {
    int limit = defaultLimit,
  }) {
    if (limit <= 0) {
      throw const GraphicsDocumentFormatException(
        'History limit must be positive.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw GraphicsDocumentFormatException('Invalid JSON: ${error.message}');
    }
    final root = _objectMap(decoded, 'document');
    if (root['fileFormat'] == null) {
      return GraphicsDocumentHistory(
        GraphicsDocument.fromJson(root),
        limit: limit,
      );
    }
    final format = _string(root['fileFormat'], 'fileFormat');
    if (format != fileFormat) {
      throw GraphicsDocumentFormatException(
        'Unsupported fileFormat "$format".',
      );
    }
    final version = _integer(root['historyVersion'], 'historyVersion');
    if (version != currentHistoryVersion) {
      throw GraphicsDocumentFormatException(
        'Unsupported historyVersion $version; expected '
        '$currentHistoryVersion.',
      );
    }
    final rawStates = _objectList(root['states'], 'states');
    if (rawStates.isEmpty) {
      throw const GraphicsDocumentFormatException(
        'History must contain at least one state.',
      );
    }
    if (rawStates.length > limit) {
      throw GraphicsDocumentFormatException(
        'History contains ${rawStates.length} states; maximum is $limit.',
      );
    }
    final currentIndex = _integer(root['currentIndex'], 'currentIndex');
    if (currentIndex < 0 || currentIndex >= rawStates.length) {
      throw const GraphicsDocumentFormatException(
        'currentIndex is outside the history state range.',
      );
    }
    final history = GraphicsDocumentHistory._(limit: limit);
    for (final state in rawStates) {
      history._states.add(
        GraphicsDocument.fromJson(state).encode(pretty: false),
      );
    }
    history._currentIndex = currentIndex;
    return history;
  }

  GraphicsDocument _decodeState(int index) =>
      GraphicsDocument.decode(_states[index]);

  int _checkedIndex(int index) {
    _checkIndex(index);
    return index;
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= _states.length) {
      throw RangeError.index(index, _states, 'index');
    }
  }
}

class GraphicsDocumentNode {
  GraphicsDocumentNode({
    required this.id,
    required this.name,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.color,
    this.rotation = 0,
    this.borderRadius = 0,
    this.filter = 'none',
    this.text,
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
  String kind;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  double borderRadius;
  int color;
  String filter;
  String? text;
  GraphicsImageSource? imageSource;
  String? componentId;
  String? parentId;
  String? parentSlot;
  final Map<String, String?> slots;
  final Map<String, Object?> properties;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'frame': {'x': x, 'y': y, 'width': width, 'height': height},
    'rotation': rotation,
    if (borderRadius != 0) 'borderRadius': borderRadius,
    'color': '#${color.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    'filter': filter,
    if (text != null) 'text': text,
    if (imageSource != null) 'imageSource': imageSource!.toJson(),
    if (componentId != null) 'componentId': componentId,
    if (parentId != null) 'parentId': parentId,
    if (parentSlot != null) 'parentSlot': parentSlot,
    if (slots.isNotEmpty) 'slots': slots,
    if (properties.isNotEmpty) 'properties': properties,
  };

  factory GraphicsDocumentNode.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final frame = _objectMap(json['frame'], '$path.frame');
    return GraphicsDocumentNode(
      id: _string(json['id'], '$path.id'),
      name: _string(json['name'], '$path.name'),
      kind: _string(json['kind'], '$path.kind'),
      x: _number(frame['x'], '$path.frame.x'),
      y: _number(frame['y'], '$path.frame.y'),
      width: _number(frame['width'], '$path.frame.width'),
      height: _number(frame['height'], '$path.frame.height'),
      rotation: json['rotation'] == null
          ? 0
          : _number(json['rotation'], '$path.rotation'),
      borderRadius: json['borderRadius'] == null
          ? 0
          : _number(json['borderRadius'], '$path.borderRadius'),
      color: _color(json['color'], '$path.color'),
      filter: json['filter'] == null
          ? 'none'
          : _string(json['filter'], '$path.filter'),
      text: json['text'] == null ? null : _string(json['text'], '$path.text'),
      imageSource: json['imageSource'] == null
          ? null
          : GraphicsImageSource.fromJson(
              _objectMap(json['imageSource'], '$path.imageSource'),
              path: '$path.imageSource',
            ),
      componentId: json['componentId'] == null
          ? null
          : _string(json['componentId'], '$path.componentId'),
      parentId: json['parentId'] == null
          ? null
          : _string(json['parentId'], '$path.parentId'),
      parentSlot: json['parentSlot'] == null
          ? null
          : _string(json['parentSlot'], '$path.parentSlot'),
      slots: json['slots'] == null
          ? null
          : _nullableStringMap(json['slots'], '$path.slots'),
      properties: json['properties'] == null
          ? null
          : _objectMap(json['properties'], '$path.properties'),
    );
  }

  void validate() {
    if (id.trim().isEmpty || name.trim().isEmpty || kind.trim().isEmpty) {
      throw const GraphicsDocumentFormatException(
        'Node id, name, and kind must not be empty.',
      );
    }
    if (parentSlot != null && parentSlot!.trim().isEmpty) {
      throw GraphicsDocumentFormatException(
        'Node "$id" has an empty parentSlot.',
      );
    }
    if (![
          x,
          y,
          width,
          height,
          rotation,
          borderRadius,
        ].every((value) => value.isFinite) ||
        width <= 0 ||
        height <= 0 ||
        borderRadius < 0) {
      throw GraphicsDocumentFormatException('Node "$id" has invalid geometry.');
    }
    if (kind == 'image' && imageSource == null) {
      throw GraphicsDocumentFormatException(
        'Image node "$id" must define imageSource.',
      );
    }
    if (kind != 'image' && imageSource != null) {
      throw GraphicsDocumentFormatException(
        'Node "$id" defines imageSource but kind is "$kind".',
      );
    }
    imageSource?.validate(nodeId: id);
  }
}

/// Portable image content for an image node.
///
/// Imported local files should use [embedded] so documents remain movable.
/// [uri] is for stable HTTP(S) or application-asset references.
class GraphicsImageSource {
  const GraphicsImageSource.embedded({
    required this.mimeType,
    required this.data,
  }) : type = 'embedded',
       uriValue = null;

  const GraphicsImageSource.uri({required String uri, this.mimeType})
    : type = 'uri',
      uriValue = uri,
      data = null;

  final String type;
  final String? uriValue;
  final String? mimeType;

  /// Base64-encoded bytes when [type] is `embedded`.
  final String? data;

  Map<String, Object?> toJson() => switch (type) {
    'embedded' => {
      'type': type,
      'mimeType': mimeType,
      'encoding': 'base64',
      'data': data,
    },
    'uri' => {
      'type': type,
      'uri': uriValue,
      if (mimeType != null) 'mimeType': mimeType,
    },
    _ => {'type': type},
  };

  factory GraphicsImageSource.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final type = _string(json['type'], '$path.type');
    return switch (type) {
      'embedded' => GraphicsImageSource.embedded(
        mimeType: _string(json['mimeType'], '$path.mimeType'),
        data: _embeddedImageData(json, path),
      ),
      'uri' => GraphicsImageSource.uri(
        uri: _string(json['uri'], '$path.uri'),
        mimeType: json['mimeType'] == null
            ? null
            : _string(json['mimeType'], '$path.mimeType'),
      ),
      _ => throw GraphicsDocumentFormatException(
        '$path.type has unsupported value "$type".',
      ),
    };
  }

  void validate({required String nodeId}) {
    if (mimeType != null &&
        (!mimeType!.startsWith('image/') || mimeType!.length <= 6)) {
      throw GraphicsDocumentFormatException(
        'Image node "$nodeId" has invalid image MIME type "$mimeType".',
      );
    }
    switch (type) {
      case 'embedded':
        if (mimeType == null || data == null || data!.isEmpty) {
          throw GraphicsDocumentFormatException(
            'Image node "$nodeId" has incomplete embedded image data.',
          );
        }
        try {
          base64Decode(base64.normalize(data!));
        } on FormatException {
          throw GraphicsDocumentFormatException(
            'Image node "$nodeId" has invalid base64 image data.',
          );
        }
      case 'uri':
        final parsed = Uri.tryParse(uriValue ?? '');
        if (parsed == null ||
            !parsed.hasScheme ||
            !const {'http', 'https', 'asset'}.contains(parsed.scheme) ||
            (parsed.scheme != 'asset' && parsed.host.isEmpty) ||
            (parsed.scheme == 'asset' && parsed.path.isEmpty)) {
          throw GraphicsDocumentFormatException(
            'Image node "$nodeId" must use a stable HTTP(S) or asset URI.',
          );
        }
      default:
        throw GraphicsDocumentFormatException(
          'Image node "$nodeId" has unsupported source type "$type".',
        );
    }
  }
}

String _embeddedImageData(Map<String, Object?> json, String path) {
  final encoding = _string(json['encoding'], '$path.encoding');
  if (encoding != 'base64') {
    throw GraphicsDocumentFormatException(
      '$path.encoding has unsupported value "$encoding".',
    );
  }
  return _string(json['data'], '$path.data');
}

class GraphicsComponentDefinition {
  GraphicsComponentDefinition({
    required this.id,
    required this.name,
    this.width,
    this.height,
    Map<String, List<String>>? slots,
    Map<String, GraphicsComponentSlotFrame>? slotFrames,
    Map<String, Object?>? properties,
  }) : slots = {
         for (final entry in (slots ?? const <String, List<String>>{}).entries)
           entry.key: List<String>.of(entry.value),
       },
       slotFrames = Map<String, GraphicsComponentSlotFrame>.of(
         slotFrames ?? const {},
       ),
       properties = Map<String, Object?>.of(properties ?? const {});

  final String id;
  final String name;
  final double? width;
  final double? height;
  final Map<String, List<String>> slots;
  final Map<String, GraphicsComponentSlotFrame> slotFrames;
  final Map<String, Object?> properties;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (width != null && height != null)
      'frame': {'width': width, 'height': height},
    'slots': slots,
    if (slotFrames.isNotEmpty)
      'slotFrames': {
        for (final entry in slotFrames.entries) entry.key: entry.value.toJson(),
      },
    if (properties.isNotEmpty) 'properties': properties,
  };

  factory GraphicsComponentDefinition.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) {
    final rawSlots = json['slots'] == null
        ? <String, Object?>{}
        : _objectMap(json['slots'], '$path.slots');
    final frame = json['frame'] == null
        ? null
        : _objectMap(json['frame'], '$path.frame');
    return GraphicsComponentDefinition(
      id: _string(json['id'], '$path.id'),
      name: _string(json['name'], '$path.name'),
      width: frame == null
          ? null
          : _number(frame['width'], '$path.frame.width'),
      height: frame == null
          ? null
          : _number(frame['height'], '$path.frame.height'),
      slots: {
        for (final entry in rawSlots.entries)
          entry.key: _stringList(entry.value, '$path.slots.${entry.key}'),
      },
      slotFrames: json['slotFrames'] == null
          ? null
          : {
              for (final entry in _objectMap(
                json['slotFrames'],
                '$path.slotFrames',
              ).entries)
                entry.key: GraphicsComponentSlotFrame.fromJson(
                  _objectMap(entry.value, '$path.slotFrames.${entry.key}'),
                  path: '$path.slotFrames.${entry.key}',
                ),
            },
      properties: json['properties'] == null
          ? null
          : _objectMap(json['properties'], '$path.properties'),
    );
  }

  void validate() {
    if ((width == null) != (height == null) ||
        (width != null &&
            (!width!.isFinite ||
                !height!.isFinite ||
                width! <= 0 ||
                height! <= 0))) {
      throw GraphicsDocumentFormatException(
        'Component "$id" frame must have positive finite width and height.',
      );
    }
    for (final entry in slotFrames.entries) {
      if (entry.key.trim().isEmpty) {
        throw GraphicsDocumentFormatException(
          'Component "$id" has an empty slot name.',
        );
      }
      entry.value.validate(componentId: id, slotName: entry.key);
    }
  }
}

/// A slot's frame in its component definition's local coordinate space.
class GraphicsComponentSlotFrame {
  const GraphicsComponentSlotFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory GraphicsComponentSlotFrame.fromJson(
    Map<String, Object?> json, {
    required String path,
  }) => GraphicsComponentSlotFrame(
    x: _number(json['x'], '$path.x'),
    y: _number(json['y'], '$path.y'),
    width: _number(json['width'], '$path.width'),
    height: _number(json['height'], '$path.height'),
  );

  void validate({required String componentId, required String slotName}) {
    if (![x, y, width, height].every((value) => value.isFinite) ||
        width <= 0 ||
        height <= 0) {
      throw GraphicsDocumentFormatException(
        'Component "$componentId" slot "$slotName" has invalid geometry.',
      );
    }
  }
}

class GraphicsDocumentFormatException implements FormatException {
  const GraphicsDocumentFormatException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'GraphicsDocumentFormatException: $message';
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw GraphicsDocumentFormatException('$path must be an object.');
  }
  return value.map((key, value) {
    if (key is! String) {
      throw GraphicsDocumentFormatException('$path keys must be strings.');
    }
    return MapEntry(key, value);
  });
}

List<Map<String, Object?>> _objectList(Object? value, String path) {
  if (value is! List) {
    throw GraphicsDocumentFormatException('$path must be an array.');
  }
  return [
    for (var i = 0; i < value.length; i++) _objectMap(value[i], '$path[$i]'),
  ];
}

String _string(Object? value, String path) {
  if (value is! String) {
    throw GraphicsDocumentFormatException('$path must be a string.');
  }
  return value;
}

int _integer(Object? value, String path) {
  if (value is! int) {
    throw GraphicsDocumentFormatException('$path must be an integer.');
  }
  return value;
}

double _number(Object? value, String path) {
  if (value is! num) {
    throw GraphicsDocumentFormatException('$path must be a number.');
  }
  return value.toDouble();
}

int _color(Object? value, String path) {
  if (value is int) return value;
  if (value is String && RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value)) {
    return int.parse(value.substring(1), radix: 16);
  }
  throw GraphicsDocumentFormatException(
    '$path must be an ARGB color such as #FF5244B9.',
  );
}

Map<String, String?> _nullableStringMap(Object? value, String path) {
  final map = _objectMap(value, path);
  return {
    for (final entry in map.entries)
      entry.key: entry.value == null
          ? null
          : _string(entry.value, '$path.${entry.key}'),
  };
}

List<String> _stringList(Object? value, String path) {
  if (value is! List) {
    throw GraphicsDocumentFormatException('$path must be an array.');
  }
  return [
    for (var i = 0; i < value.length; i++) _string(value[i], '$path[$i]'),
  ];
}
