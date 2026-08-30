import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_playground/src/demos/graphics_document.dart';

void main() {
  GraphicsDocument fixture() => GraphicsDocument(
    name: 'Reusable layout',
    canvasWidth: 1280,
    canvasHeight: 720,
    canvasEffect: 'custom',
    customShader: 'void main() { /* saved GLSL */ }',
    appliedCustomShader: 'void main() { /* last good GLSL */ }',
    metadata: const {
      'author': 'integration-test',
      'extensions': {'futureProperty': true},
    },
    components: [
      GraphicsComponentDefinition(
        id: 'card',
        name: 'Card',
        width: 560,
        height: 320,
        slots: const {
          'header': ['heading', 'badge'],
          'body': ['copy'],
        },
        properties: const {'renderer': 'card-v1'},
      ),
      GraphicsComponentDefinition(id: 'heading', name: 'Heading'),
      GraphicsComponentDefinition(id: 'badge', name: 'Badge'),
      GraphicsComponentDefinition(id: 'copy', name: 'Copy'),
    ],
    nodes: [
      GraphicsDocumentNode(
        id: 'hero-instance',
        name: 'Hero',
        kind: 'component',
        x: 120,
        y: 80,
        width: 560,
        height: 320,
        rotation: 0.125,
        color: 0xFF5244B9,
        filter: 'warm',
        componentId: 'card',
        slots: const {'header': 'heading', 'body': 'copy'},
        properties: const {
          'opacity': 0.8,
          'custom': {'blendMode': 'screen'},
        },
      ),
      GraphicsDocumentNode(
        id: 'free-text',
        name: 'Caption',
        kind: 'text',
        x: 20,
        y: 640,
        width: 260,
        height: 42,
        color: 0xFF202020,
        text: 'Serialized text',
      ),
    ],
  );

  test('round trips generic nodes, components, slots, and shader state', () {
    final source = fixture();
    final decoded = GraphicsDocument.decode(source.encode());

    expect(jsonDecode(decoded.encode()), jsonDecode(source.encode()));
    expect(decoded.nodes.first.slots['header'], 'heading');
    expect(decoded.nodes.first.properties['custom'], {'blendMode': 'screen'});
    expect(decoded.customShader, contains('saved GLSL'));
    expect(decoded.appliedCustomShader, contains('last good GLSL'));
  });

  test(
    'round trips edited content, frame shaders, duplicates, and layer order',
    () {
      final document = fixture();
      final hero = document.nodes.first;
      final caption = document.nodes.last;

      hero.name = 'Renamed frame';
      hero.color = 0xFF12ABEF;
      hero.properties.addAll({
        'shaderEffect': 'custom',
        'customShader': 'void main() { /* edited frame GLSL */ }',
        'appliedCustomShader': 'void main() { /* compiled frame GLSL */ }',
      });
      caption
        ..name = 'Renamed caption'
        ..text = 'Edited inline copy'
        ..color = 0x80443322;
      document.nodes
        ..insert(
          1,
          GraphicsDocumentNode(
            id: 'free-text-copy',
            name: '${caption.name} copy',
            kind: caption.kind,
            x: caption.x + 16,
            y: caption.y + 16,
            width: caption.width,
            height: caption.height,
            color: caption.color,
            text: caption.text,
          ),
        )
        ..add(document.nodes.removeAt(0));

      final decoded = GraphicsDocument.decode(document.encode());

      expect(decoded.nodes.map((node) => node.id), [
        'free-text-copy',
        'free-text',
        'hero-instance',
      ]);
      expect(decoded.nodes[1].name, 'Renamed caption');
      expect(decoded.nodes[1].text, 'Edited inline copy');
      expect(decoded.nodes[1].color, 0x80443322);
      expect(decoded.nodes.last.name, 'Renamed frame');
      expect(decoded.nodes.last.color, 0xFF12ABEF);
      expect(
        decoded.nodes.last.properties,
        containsPair('shaderEffect', 'custom'),
      );
      expect(
        decoded.nodes.last.properties,
        containsPair('customShader', 'void main() { /* edited frame GLSL */ }'),
      );
      expect(
        decoded.nodes.last.properties,
        containsPair(
          'appliedCustomShader',
          'void main() { /* compiled frame GLSL */ }',
        ),
      );
    },
  );

  test('round trips image sources and rectangle border radius', () {
    final document = fixture();
    document.nodes.first.borderRadius = 18;
    document.nodes.addAll([
      GraphicsDocumentNode(
        id: 'embedded-image',
        name: 'Embedded image',
        kind: 'image',
        x: 40,
        y: 60,
        width: 320,
        height: 180,
        borderRadius: 12,
        color: 0xFFFFFFFF,
        imageSource: const GraphicsImageSource.embedded(
          mimeType: 'image/png',
          data: 'iVBORw0KGgo=',
        ),
      ),
      GraphicsDocumentNode(
        id: 'remote-image',
        name: 'Remote image',
        kind: 'image',
        x: 400,
        y: 60,
        width: 320,
        height: 180,
        color: 0xFFFFFFFF,
        imageSource: const GraphicsImageSource.uri(
          uri: 'https://assets.example.com/photo.webp',
          mimeType: 'image/webp',
        ),
      ),
      GraphicsDocumentNode(
        id: 'embedded-svg',
        name: 'Vector icon',
        kind: 'image',
        x: 40,
        y: 280,
        width: 48,
        height: 48,
        color: 0xFF252525,
        imageSource: GraphicsImageSource.embedded(
          mimeType: 'image/svg+xml',
          data: base64Encode(
            utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h8v8z"/></svg>',
            ),
          ),
        ),
        properties: const {'fit': 'contain', 'tintWithLayerColor': true},
      ),
      GraphicsDocumentNode(
        id: 'line',
        name: 'Divider',
        kind: 'line',
        x: 120,
        y: 300,
        width: 240,
        height: 20,
        rotation: 0.25,
        color: 0xFF252525,
        properties: const {'strokeWidth': 2.5, 'strokeCap': 'round'},
      ),
    ]);

    final decoded = GraphicsDocument.decode(document.encode());

    expect(decoded.nodes.first.borderRadius, 18);
    expect(decoded.nodes[1].borderRadius, 0);
    expect(decoded.nodes[2].borderRadius, 12);
    expect(decoded.nodes[2].imageSource!.type, 'embedded');
    expect(decoded.nodes[2].imageSource!.mimeType, 'image/png');
    expect(decoded.nodes[2].imageSource!.data, 'iVBORw0KGgo=');
    expect(decoded.nodes[3].imageSource!.type, 'uri');
    expect(
      decoded.nodes[3].imageSource!.uriValue,
      'https://assets.example.com/photo.webp',
    );
    expect(decoded.nodes[4].imageSource!.mimeType, 'image/svg+xml');
    expect(
      utf8.decode(base64Decode(decoded.nodes[4].imageSource!.data!)),
      contains('<path'),
    );
    expect(decoded.nodes[4].properties['fit'], 'contain');
    expect(decoded.nodes[5].kind, 'line');
    expect(decoded.nodes[5].rotation, 0.25);
    expect(decoded.nodes[5].properties['strokeWidth'], 2.5);
    expect(decoded.nodes[5].properties['strokeCap'], 'round');
  });

  test('rejects invalid image sources and negative border radius', () {
    Map<String, Object?> imageNodeJson() => GraphicsDocumentNode(
      id: 'image',
      name: 'Image',
      kind: 'image',
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      color: 0xFFFFFFFF,
      imageSource: const GraphicsImageSource.embedded(
        mimeType: 'image/png',
        data: 'iVBORw0KGgo=',
      ),
    ).toJson();

    final missingSource = fixture().toJson();
    (missingSource['nodes']! as List).add(
      {...imageNodeJson()}..remove('imageSource'),
    );
    expect(
      () => GraphicsDocument.decode(jsonEncode(missingSource)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('must define imageSource'),
        ),
      ),
    );

    final invalidBase64 = fixture().toJson();
    final invalidBase64Node = imageNodeJson();
    (invalidBase64Node['imageSource']! as Map)['data'] = 'not base64!';
    (invalidBase64['nodes']! as List).add(invalidBase64Node);
    expect(
      () => GraphicsDocument.decode(jsonEncode(invalidBase64)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('invalid base64 image data'),
        ),
      ),
    );

    final unstableUri = fixture().toJson();
    final unstableUriNode = imageNodeJson();
    unstableUriNode['imageSource'] = {
      'type': 'uri',
      'uri': 'file:///Users/example/photo.png',
    };
    (unstableUri['nodes']! as List).add(unstableUriNode);
    expect(
      () => GraphicsDocument.decode(jsonEncode(unstableUri)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('stable HTTP(S) or asset URI'),
        ),
      ),
    );

    final negativeRadius = fixture().toJson();
    ((negativeRadius['nodes']! as List).first as Map)['borderRadius'] = -1;
    expect(
      () => GraphicsDocument.decode(jsonEncode(negativeRadius)),
      throwsA(isA<GraphicsDocumentFormatException>()),
    );
  });

  test(
    'saves and reimports a document file without semantic changes',
    () async {
      final directory = await Directory.systemTemp.createTemp('gpu-doc-test-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/layout.gpudoc';
      final encoded = '${fixture().encode()}\n';

      await XFile.fromData(
        Uint8List.fromList(utf8.encode(encoded)),
        mimeType: 'application/json',
        name: 'layout.gpudoc',
      ).saveTo(path);

      final imported = GraphicsDocument.decode(await File(path).readAsString());
      expect(imported.name, 'Reusable layout');
      expect(imported.nodes.map((node) => node.id), [
        'hero-instance',
        'free-text',
      ]);
    },
  );

  test('round trips positioned component slots and slotted frame content', () {
    final document = fixture();
    final component = document.components.first;
    component.slotFrames.addAll(const {
      'media': GraphicsComponentSlotFrame(
        x: 24,
        y: 32,
        width: 220,
        height: 140,
      ),
    });
    document.nodes.add(
      GraphicsDocumentNode(
        id: 'media-frame',
        name: 'Media frame',
        kind: 'rectangle',
        x: 0,
        y: 0,
        width: 220,
        height: 140,
        color: 0xFF112233,
        parentId: 'hero-instance',
        parentSlot: 'media',
      ),
    );

    final decoded = GraphicsDocument.decode(document.encode());

    final decodedSlot = decoded.components.first.slotFrames['media']!;
    expect(decoded.components.first.width, 560);
    expect(decoded.components.first.height, 320);
    expect(
      [decodedSlot.x, decodedSlot.y, decodedSlot.width, decodedSlot.height],
      [24, 32, 220, 140],
    );
    expect(decoded.nodes.last.parentId, 'hero-instance');
    expect(decoded.nodes.last.parentSlot, 'media');
  });

  test('imports legacy components without positioned slots', () {
    final legacy = fixture().toJson();
    for (final component in legacy['components']! as List) {
      (component as Map)
        ..remove('frame')
        ..remove('slotFrames');
    }

    final decoded = GraphicsDocument.decode(jsonEncode(legacy));

    expect(decoded.components.every((item) => item.slotFrames.isEmpty), isTrue);
    expect(decoded.components.every((item) => item.width == null), isTrue);
  });

  test('rejects invalid positioned slots and invalid slotted parents', () {
    final invalidFrame = fixture().toJson();
    ((invalidFrame['components']! as List).first as Map)['slotFrames'] = {
      'media': {'x': 0, 'y': 0, 'width': 0, 'height': 100},
    };
    expect(
      () => GraphicsDocument.decode(jsonEncode(invalidFrame)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('slot "media" has invalid geometry'),
        ),
      ),
    );

    final invalidParent = fixture();
    invalidParent.nodes.add(
      GraphicsDocumentNode(
        id: 'invalid-slotted-frame',
        name: 'Invalid slotted frame',
        kind: 'rectangle',
        x: 0,
        y: 0,
        width: 20,
        height: 20,
        color: 0xFFFFFFFF,
        parentId: 'free-text',
        parentSlot: 'header',
      ),
    );
    expect(
      () => GraphicsDocument.decode(invalidParent.encode()),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('non-component parent "free-text"'),
        ),
      ),
    );
  });

  test('rejects unsupported versions without accepting partial content', () {
    final json = jsonDecode(fixture().encode()) as Map<String, Object?>;
    json['schemaVersion'] = 99;

    expect(
      () => GraphicsDocument.decode(jsonEncode(json)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported schemaVersion 99'),
        ),
      ),
    );
  });

  test('rejects invalid geometry and slot assignments with useful paths', () {
    final invalidGeometry = jsonDecode(fixture().encode()) as Map;
    (invalidGeometry['nodes'] as List).first['frame']['width'] = -4;
    expect(
      () => GraphicsDocument.decode(jsonEncode(invalidGeometry)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('invalid geometry'),
        ),
      ),
    );

    final invalidSlot = jsonDecode(fixture().encode()) as Map;
    (invalidSlot['nodes'] as List).first['slots']['header'] = 'copy';
    expect(
      () => GraphicsDocument.decode(jsonEncode(invalidSlot)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('cannot contain component "copy"'),
        ),
      ),
    );
  });

  test('round trips hierarchy and rejects missing or cyclic parents', () {
    final nested = fixture();
    nested.nodes.last.parentId = nested.nodes.first.id;
    final decoded = GraphicsDocument.decode(nested.encode());
    expect(decoded.nodes.last.parentId, 'hero-instance');

    final missingParent = jsonDecode(nested.encode()) as Map;
    (missingParent['nodes'] as List).last['parentId'] = 'missing';
    expect(
      () => GraphicsDocument.decode(jsonEncode(missingParent)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('unknown parent'),
        ),
      ),
    );

    final cycle = jsonDecode(nested.encode()) as Map;
    (cycle['nodes'] as List).first['parentId'] = 'free-text';
    expect(
      () => GraphicsDocument.decode(jsonEncode(cycle)),
      throwsA(
        isA<GraphicsDocumentFormatException>().having(
          (error) => error.message,
          'message',
          contains('cyclic parent relationship'),
        ),
      ),
    );
  });

  group('serialized document history', () {
    GraphicsDocument at(double x) {
      final document = fixture();
      document.nodes.first.x = x;
      return document;
    }

    test('undoes, redoes, branches, and deduplicates complete states', () {
      final history = GraphicsDocumentHistory(at(0));
      expect(history.commit(at(10)), isTrue);
      expect(history.commit(at(20)), isTrue);
      expect(history.commit(at(20)), isFalse);

      expect(history.undo()!.nodes.first.x, 10);
      expect(history.canRedo, isTrue);
      expect(history.commit(at(15)), isTrue);
      expect(history.canRedo, isFalse);
      expect(history.length, 3);
      expect(history.undo()!.nodes.first.x, 10);
      expect(history.redo()!.nodes.first.x, 15);
    });

    test('caps history and keeps snapshots independent from mutable input', () {
      final source = at(0);
      final history = GraphicsDocumentHistory(source, limit: 3);
      source.nodes.first.x = 999;
      expect(history.current.nodes.first.x, 0);

      for (var x = 1; x <= 4; x++) {
        history.commit(at(x.toDouble()));
      }
      expect(history.length, 3);
      expect(history.current.nodes.first.x, 4);
      expect(history.undo()!.nodes.first.x, 3);
      expect(history.undo()!.nodes.first.x, 2);
      expect(history.canUndo, isFalse);
    });

    test('round trips cursor and resolves arbitrary playback order', () {
      final history = GraphicsDocumentHistory(at(0))
        ..commit(at(10))
        ..commit(at(20));
      history.undo();

      final imported = GraphicsDocumentHistory.decode(history.encode());
      expect(imported.length, 3);
      expect(imported.currentIndex, 1);
      expect(imported.current.nodes.first.x, 10);
      expect(imported.sequence([2, 0, 2]).map((state) => state.nodes.first.x), [
        20,
        0,
        20,
      ]);
      expect(imported.currentIndex, 1);
    });

    test('saves and imports the complete history archive file', () async {
      final history = GraphicsDocumentHistory(at(0))
        ..commit(at(10))
        ..commit(at(20));
      history.undo();
      final directory = await Directory.systemTemp.createTemp(
        'gpu-history-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/history.gpudoc';

      await XFile.fromData(
        Uint8List.fromList(utf8.encode(history.encode())),
        mimeType: 'application/json',
        name: 'history.gpudoc',
      ).saveTo(path);

      final imported = GraphicsDocumentHistory.decode(
        await File(path).readAsString(),
      );
      expect(imported.length, 3);
      expect(imported.currentIndex, 1);
      expect(imported.undo()!.nodes.first.x, 0);
      expect(imported.redo()!.nodes.first.x, 10);
      expect(imported.redo()!.nodes.first.x, 20);
    });

    test('imports a legacy single-state document', () {
      final history = GraphicsDocumentHistory.decode(fixture().encode());
      expect(history.length, 1);
      expect(history.current.name, 'Reusable layout');
    });
  });
}
