import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gpu_playground/src/demos/graphics_editor.dart';
import 'package:gpu_playground/src/frame.dart';

void main() {
  testWidgets('creates and transforms content in the design canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(GraphicsEditorView),
      matchesGoldenFile('goldens/graphics_editor_initial.png'),
    );

    expect(find.text('21 objects'), findsOneWidget);
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Build better habits'), findsOneWidget);
    expect(find.textContaining('Lorem ipsum'), findsNWidgets(4));
    expect(find.textContaining('Home'), findsOneWidget);
    expect(find.text('Paper grain · GLSL'), findsOneWidget);
    expect(find.byKey(const Key('frame-shader-scope')), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(4));
    expect(find.text('Activity divider'), findsOneWidget);
    expect(find.text('Header photo'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Build better habits')).style?.fontSize,
      16,
    );
    expect(
      tester
          .widget<Text>(find.text('Your workspace, at a glance'))
          .style
          ?.fontSize,
      10,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '30/30',
    );

    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.pump();
    expect(find.text('22 objects'), findsOneWidget);
    expect(find.byKey(const Key('undo-document')), findsOneWidget);
    expect(find.byKey(const Key('redo-document')), findsOneWidget);
    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(find.text('21 objects'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redo-document')));
    await tester.pump();
    expect(find.text('22 objects'), findsOneWidget);
    for (final handle in const [
      'topLeft',
      'top',
      'topRight',
      'right',
      'bottomRight',
      'bottom',
      'bottomLeft',
      'left',
    ]) {
      expect(find.byKey(Key('resize-handle-$handle')), findsOneWidget);
    }
    expect(find.byKey(const Key('rotate-handle')), findsOneWidget);

    String propertyValue(Key key) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .last
        .data!;
    final xBefore = propertyValue(const Key('x-value'));
    final yBefore = propertyValue(const Key('y-value'));
    final moveGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('selected-layer-body'))),
    );
    await moveGesture.moveBy(const Offset(30, 20));
    await tester.pump();
    await moveGesture.moveBy(const Offset(50, 35));
    await tester.pump();
    expect(propertyValue(const Key('x-value')), isNot(xBefore));
    expect(propertyValue(const Key('y-value')), isNot(yBefore));
    expect(propertyValue(const Key('x-value')), '408');
    expect(propertyValue(const Key('y-value')), '260');
    await moveGesture.moveBy(const Offset(-29, 0));
    await tester.pump();
    expect(find.byKey(const Key('alignment-guides')), findsOneWidget);
    expect(propertyValue(const Key('x-value')), '384');
    await expectLater(
      find.byType(GraphicsEditorView),
      matchesGoldenFile('goldens/graphics_editor_alignment_guides.png'),
    );
    await moveGesture.up();
    await tester.pump();
    expect(find.byKey(const Key('alignment-guides')), findsNothing);

    final widthBeforeFreeResize = propertyValue(const Key('width-value'));
    final heightBeforeFreeResize = propertyValue(const Key('height-value'));
    await tester.drag(
      find.byKey(const Key('resize-handle-right')),
      const Offset(35, 0),
    );
    await tester.pump();

    expect(
      propertyValue(const Key('width-value')),
      isNot(widthBeforeFreeResize),
    );
    expect(propertyValue(const Key('height-value')), heightBeforeFreeResize);

    double numericProperty(Key key) => double.parse(propertyValue(key));
    final ratioBefore =
        numericProperty(const Key('width-value')) /
        numericProperty(const Key('height-value'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.drag(
      find.byKey(const Key('resize-handle-bottomRight')),
      const Offset(42, 9),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    final ratioAfter =
        numericProperty(const Key('width-value')) /
        numericProperty(const Key('height-value'));
    expect(ratioAfter, closeTo(ratioBefore, 0.03));

    final rotationBefore = tester
        .widget<Text>(find.byKey(const Key('rotation-value')))
        .data;
    await tester.drag(
      find.byKey(const Key('rotate-handle')),
      const Offset(28, 0),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('rotation-value'))).data,
      isNot(rotationBefore),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.drag(
      find.byKey(const Key('rotate-handle')),
      const Offset(-36, 18),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    final snappedDegrees = int.parse(
      tester
          .widget<Text>(find.byKey(const Key('rotation-value')))
          .data!
          .replaceFirst('°', ''),
    );
    expect(snappedDegrees % 45, 0);

    expect(find.byKey(const Key('faint-grid')), findsNothing);
    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.pump();
    expect(find.byKey(const Key('faint-grid')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('canvas-zoom')),
      const Offset(300, 0),
    );
    await tester.pump();
    expect(find.text('800%'), findsOneWidget);
    final positionBeforePan = propertyValue(const Key('x-value'));

    final historyBeforeGridChange = tester
        .widget<Text>(find.byKey(const Key('history-position')))
        .data;
    await tester.tap(find.byKey(const Key('grid-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16 px').last);
    await tester.pumpAndSettle();
    expect(find.text('16 px'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      isNot(historyBeforeGridChange),
    );
    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(find.text('8 px'), findsOneWidget);
    final transformBeforePan = tester
        .widget<Transform>(find.byKey(const Key('canvas-viewport')))
        .transform
        .storage
        .toList();
    final panGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('canvas-input'))),
      buttons: kMiddleMouseButton,
    );
    await panGesture.moveBy(const Offset(70, 45));
    await panGesture.up();
    await tester.pump();
    expect(
      tester
          .widget<Transform>(find.byKey(const Key('canvas-viewport')))
          .transform
          .storage
          .toList(),
      isNot(equals(transformBeforePan)),
    );
    expect(propertyValue(const Key('x-value')), positionBeforePan);

    final historyPositionBeforePlayback = tester
        .widget<Text>(find.byKey(const Key('history-position')))
        .data;
    await tester.tap(find.byKey(const Key('play-history')));
    await tester.pump();
    expect(find.text('0 objects'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      startsWith('1/'),
    );
    await tester.tap(find.byKey(const Key('play-history')));
    await tester.pump();
    expect(find.text('22 objects'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      historyPositionBeforePlayback,
    );

    await tester.enterText(
      find.byKey(const Key('design-prompt')),
      'Draw a pink component with a title and subtitle',
    );
    await tester.tap(find.byKey(const Key('generate-design')));
    await tester.pump();

    expect(find.text('21 objects'), findsOneWidget);
    expect(find.text('Featured card'), findsWidgets);

    await tester.tap(find.byKey(const Key('canvas-effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom GLSL…').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-shader-source')), findsOneWidget);
    expect(find.byKey(const Key('compile-custom-shader')), findsOneWidget);
  });

  testWidgets('autoplays the serialized starter construction states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final transformBefore = tester
        .widget<Transform>(find.byKey(const Key('canvas-viewport')))
        .transform
        .storage
        .toList();
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '30/30',
    );

    await tester.tap(find.byKey(const Key('play-history')));
    await tester.pump();
    expect(find.text('0 objects'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '1/30',
    );

    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('1 objects'), findsOneWidget);
    expect(find.text('Phone frame'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '2/30',
    );

    await tester.tap(find.byKey(const Key('play-history')));
    await tester.pump();
    expect(find.text('21 objects'), findsOneWidget);
    expect(find.text('Header photo'), findsOneWidget);
    expect(find.text('Paper grain · GLSL'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '30/30',
    );
    expect(
      tester
          .widget<Transform>(find.byKey(const Key('canvas-viewport')))
          .transform
          .storage
          .toList(),
      transformBefore,
    );

    await tester.tap(find.byKey(const Key('play-history')));
    for (var step = 0; step < 30; step++) {
      await tester.pump(const Duration(milliseconds: 240));
    }
    expect(find.text('21 objects'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      '30/30',
    );
  });

  testWidgets('groups layers, moves descendants, and detaches them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.tap(find.byTooltip('Text'));
    await tester.pump();

    final textLayer = find.byKey(const Key('layer-drag-node-5'));
    final rectangleLayer = find.byKey(const Key('layer-drag-node-4'));
    await tester.dragFrom(
      tester.getCenter(textLayer),
      tester.getCenter(rectangleLayer) - tester.getCenter(textLayer),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inside Rectangle'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(find.byKey(const Key('selected-layer-parent')), findsNothing);
    await tester.tap(find.byKey(const Key('redo-document')));
    await tester.pump();
    expect(find.text('Inside Rectangle'), findsOneWidget);

    await tester.tap(rectangleLayer);
    await tester.pump();
    await tester.timedDrag(
      find.byKey(const Key('layer-body-node-4')),
      const Offset(70, 50),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    final textBody = find.byKey(const Key('layer-body-node-5'));
    await tester.tap(textBody);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(textBody);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inline-text-node-5')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('inline-text-node-5')),
      'Edited nested text',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Edited nested text'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Text',
    );
    String propertyValue(Key key) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .last
        .data!;
    final nestedX = propertyValue(const Key('x-value'));
    final nestedY = propertyValue(const Key('y-value'));
    expect(nestedX, isNot('330'));
    expect(nestedY, isNot('210'));

    final rootDrop = find.byKey(const Key('layer-drop-above-node-4'));
    await tester.dragFrom(
      tester.getCenter(textLayer),
      tester.getCenter(rootDrop) - tester.getCenter(textLayer),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-layer-parent')), findsNothing);

    await tester.tap(rectangleLayer);
    await tester.pump();
    final selectedRectangleBody = find.byKey(const Key('selected-layer-body'));
    final selectedRectangleBounds = tester.getRect(selectedRectangleBody);
    await tester.timedDragFrom(
      Offset(
        selectedRectangleBounds.center.dx,
        selectedRectangleBounds.bottom - 10,
      ),
      const Offset(-28, 24),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.tap(textBody);
    await tester.pump(const Duration(milliseconds: 500));
    expect(propertyValue(const Key('x-value')), nestedX);
    expect(propertyValue(const Key('y-value')), nestedY);
  });

  testWidgets('rotates grouped descendants around the parent center', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.tap(find.byTooltip('Text'));
    await tester.pump();
    final rectangleTile = find.byKey(const Key('layer-drag-node-4'));
    final textTile = find.byKey(const Key('layer-drag-node-5'));
    await tester.dragFrom(
      tester.getCenter(textTile),
      tester.getCenter(rectangleTile) - tester.getCenter(textTile),
    );
    await tester.pumpAndSettle();

    String propertyValue(Key key) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .last
        .data!;
    final childXBefore = propertyValue(const Key('x-value'));
    final childYBefore = propertyValue(const Key('y-value'));

    await tester.tap(rectangleTile);
    await tester.pump();
    final rotationSlider = find.byKey(const Key('layer-rotation'));
    final sliderRect = tester.getRect(rotationSlider);
    await tester.tapAt(
      Offset(sliderRect.left + sliderRect.width * 0.75, sliderRect.center.dy),
    );
    await tester.pump();

    await tester.tap(textTile);
    await tester.pump(const Duration(milliseconds: 400));
    final childRotation = int.parse(
      tester
          .widget<Text>(find.byKey(const Key('rotation-value')))
          .data!
          .replaceFirst('°', ''),
    );
    expect(childRotation, inInclusiveRange(60, 120));
    expect(propertyValue(const Key('x-value')), isNot(childXBefore));
    expect(propertyValue(const Key('y-value')), isNot(childYBefore));
    expect(find.text('Inside Rectangle'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('rotation-value'))).data,
      '0°',
    );
    expect(propertyValue(const Key('x-value')), childXBefore);
    expect(propertyValue(const Key('y-value')), childYBefore);

    await tester.tap(find.byKey(const Key('redo-document')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('rotation-value'))).data,
      isNot('0°'),
    );
  });

  testWidgets('keeps pointer, canvas, and layers in one viewport transform', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unselected = find.byKey(const Key('layer-body-node-1'));
    final dragStart = tester.getCenter(unselected);
    final gesture = await tester.startGesture(dragStart);
    await gesture.moveBy(const Offset(20, 12));
    await tester.pump();
    await gesture.moveBy(const Offset(32, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final draggedCenter = tester.getCenter(
      find.byKey(const Key('selected-layer-body')),
    );
    expect((draggedCenter - dragStart).dx, closeTo(52, 1));
    expect((draggedCenter - dragStart).dy, closeTo(32, 1));

    final artboardBefore = tester.getRect(find.byKey(const Key('artboard')));
    final layerBefore = tester.getRect(
      find.byKey(const Key('selected-layer-body')),
    );
    final focalPoint = layerBefore.center;
    final pointer = TestPointer(96, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(focalPoint));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -140)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final artboardAfter = tester.getRect(find.byKey(const Key('artboard')));
    final layerAfter = tester.getRect(
      find.byKey(const Key('selected-layer-body')),
    );
    expect(layerAfter.center.dx, closeTo(focalPoint.dx, 1));
    expect(layerAfter.center.dy, closeTo(focalPoint.dy, 1));
    expect(
      layerAfter.width / layerBefore.width,
      closeTo(artboardAfter.width / artboardBefore.width, 0.001),
    );
  });

  testWidgets('edits multiline text without changing its preview layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Text'));
    await tester.pump();
    final textBody = find.byKey(const Key('layer-body-node-4'));
    await tester.tap(textBody);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(textBody);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('inline-text-node-4'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Line one');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<EditableText>(field).controller.text, 'Line one\n');
    expect(find.text('22 objects'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(tester.widget<EditableText>(field).controller.text, 'Line one');
    expect(find.text('22 objects'), findsOneWidget);

    await tester.enterText(field, 'Line one\nLine two');
    await tester.pump();
    final editable = field;
    final editableRect = tester.getRect(editable);
    final editingStyle = tester.widget<EditableText>(editable).style;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    final renderedText = find.descendant(
      of: find.byKey(const Key('layer-body-node-4')),
      matching: find.text('Line one\nLine two'),
    );
    expect(renderedText, findsOneWidget);
    final renderedRect = tester.getRect(renderedText);
    expect(renderedRect.left, closeTo(editableRect.left, 0.5));
    expect(renderedRect.top, closeTo(editableRect.top, 0.5));
    expect(renderedRect.height, closeTo(editableRect.height, 0.5));
    expect(tester.widget<Text>(renderedText).style, editingStyle);

    await tester.tap(renderedText);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(renderedText);
    await tester.pumpAndSettle();
    final emptyField = find.byKey(const Key('inline-text-node-4'));
    await tester.enterText(emptyField, '');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('layer-body-node-4')),
              matching: find.byType(Text),
            ),
          )
          .single
          .data,
      '',
    );
  });

  testWidgets('selects nested text before editing and changes its font', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textBody = find.byKey(
      const ValueKey('layer-body-starter-feature-title'),
    );
    await tester.tap(textBody);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('inline-text-starter-feature-title')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Featured title',
    );
    expect(find.byKey(const Key('text-font-family')), findsOneWidget);
    expect(find.text('Bold'), findsNothing);
    expect(find.text('Italic'), findsNothing);
    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.byTooltip('Italic'), findsOneWidget);

    await tester.tap(find.byKey(const Key('text-font-family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Georgia').last);
    await tester.pumpAndSettle();
    expect(find.text('Georgia'), findsOneWidget);

    final renderedText = find.descendant(
      of: textBody,
      matching: find.text('Build better habits'),
    );
    expect(
      tester.widget<Text>(renderedText).style?.fontWeight,
      FontWeight.w700,
    );
    await tester.tap(find.byKey(const Key('text-bold')));
    await tester.pump();
    expect(
      tester.widget<Text>(renderedText).style?.fontWeight,
      FontWeight.w500,
    );
    await tester.tap(find.byKey(const Key('text-bold')));

    final fontSizeSlider = find.byKey(const Key('text-font-size'));
    final fontSizeBounds = tester.getRect(fontSizeSlider);
    await tester.tapAt(
      Offset(
        fontSizeBounds.left + fontSizeBounds.width * 0.45,
        fontSizeBounds.center.dy,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('text-italic')));
    await tester.pump();

    final renderedStyle = tester.widget<Text>(renderedText).style!;
    expect(renderedStyle.fontFamily, 'Georgia');
    expect(renderedStyle.fontSize, greaterThan(18));
    expect(renderedStyle.fontWeight, FontWeight.w700);
    expect(renderedStyle.fontStyle, FontStyle.italic);

    await tester.tap(textBody);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(textBody);
    await tester.pumpAndSettle();
    final inlineEditor = find.byKey(
      const Key('inline-text-starter-feature-title'),
    );
    expect(inlineEditor, findsOneWidget);
    final editorStyle = tester.widget<EditableText>(inlineEditor).style;
    expect(editorStyle.fontFamily, 'Georgia');
    expect(editorStyle.fontSize, renderedStyle.fontSize);
    expect(editorStyle.fontWeight, FontWeight.w700);
    expect(editorStyle.fontStyle, FontStyle.italic);
  });

  testWidgets('selects the exact nested frame on a direct click', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final focusCard = find.byKey(const Key('layer-body-starter-card-focus'));
    final bounds = tester.getRect(focusCard);
    await tester.tapAt(Offset(bounds.right - 5, bounds.bottom - 5));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Focus card',
    );
    expect(find.text('Inside Phone frame'), findsOneWidget);
  });

  testWidgets('undoes a resize with Command-Z', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final progressCard = find.byKey(
      const Key('layer-body-starter-card-progress'),
    );
    final cardBounds = tester.getRect(progressCard);
    await tester.tapAt(Offset(cardBounds.right - 5, cardBounds.bottom - 5));
    await tester.pump();

    String widthValue() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('width-value')),
            matching: find.byType(Text),
          ),
        )
        .last
        .data!;

    final widthBefore = widthValue();
    await tester.drag(
      find.byKey(const Key('resize-handle-right')),
      const Offset(48, 0),
    );
    await tester.pump();
    final widthAfterResize = widthValue();
    expect(widthAfterResize, isNot(widthBefore));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(widthValue(), widthBefore);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Progress card',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(widthValue(), widthAfterResize);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Progress card',
    );
  });

  testWidgets('can apply a frame shader to its descendants', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shader-owner-starter-feature-title-none')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('frame-shader-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frame + children').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shader-owner-starter-feature-title-node-3')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(
      find.byKey(const Key('shader-owner-starter-feature-title-none')),
      findsOneWidget,
    );
  });

  testWidgets('moves a rotated layer in canvas coordinates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.pump();
    final rotationSlider = find.byKey(const Key('layer-rotation'));
    final sliderRect = tester.getRect(rotationSlider);
    await tester.tapAt(
      Offset(sliderRect.left + sliderRect.width * 0.75, sliderRect.center.dy),
    );
    await tester.pump();
    final rotation = int.parse(
      tester
          .widget<Text>(find.byKey(const Key('rotation-value')))
          .data!
          .replaceFirst('°', ''),
    );
    expect(rotation, inInclusiveRange(60, 120));

    int propertyValue(Key key) => int.parse(
      tester
          .widgetList<Text>(
            find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          )
          .last
          .data!,
    );
    final xBefore = propertyValue(const Key('x-value'));
    final yBefore = propertyValue(const Key('y-value'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('selected-layer-body'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final xAfter = propertyValue(const Key('x-value'));
    final yAfter = propertyValue(const Key('y-value'));
    expect(xAfter - xBefore, greaterThan(50));
    expect((yAfter - yBefore).abs(), lessThanOrEqualTo(8));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('adds and resizes a line as a document layer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-line')));
    await tester.pump();
    expect(find.text('22 objects'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Line',
    );
    expect(find.byKey(const Key('line-stroke-width')), findsOneWidget);
    expect(find.byKey(const Key('layer-body-node-4')), findsOneWidget);

    String widthValue() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('width-value')),
            matching: find.byType(Text),
          ),
        )
        .last
        .data!;

    expect(widthValue(), '180');
    await tester.dragFrom(
      tester.getCenter(find.byKey(const Key('resize-handle-right'))) -
          const Offset(2, 0),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(widthValue(), '220');

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(widthValue(), '180');
    await tester.tap(find.byKey(const Key('redo-document')));
    await tester.pump();
    expect(widthValue(), '220');
  });

  testWidgets('preserves viewport zoom and pan across undo and redo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('zoom-in')));
    await tester.tap(find.byKey(const Key('zoom-in')));
    final panGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('canvas-input'))),
      buttons: kMiddleMouseButton,
    );
    await panGesture.moveBy(const Offset(48, 32));
    await panGesture.up();
    await tester.pump();

    List<double> viewportTransform() => tester
        .widget<Transform>(find.byKey(const Key('canvas-viewport')))
        .transform
        .storage
        .toList();

    expect(find.text('150%'), findsOneWidget);
    final expectedTransform = viewportTransform();
    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    expect(viewportTransform(), expectedTransform);

    await tester.tap(find.byKey(const Key('redo-document')));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    expect(viewportTransform(), expectedTransform);
  });

  testWidgets(
    'edits layers through menus, clipboard, colors, and viewport input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = PlaybackController();
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 1400,
            height: 850,
            child: GraphicsEditorView(playback: playback, enableShaders: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Text'));
      await tester.pump();
      expect(find.text('22 objects'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('layer-body-node-4')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('23 objects'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('layer-drag-node-5')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      final rename = find.byKey(const Key('rename-layer-node-5'));
      expect(rename, findsOneWidget);
      await tester.enterText(rename, 'Callout copy');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Callout copy'), findsWidgets);

      await tester.tap(find.byKey(const Key('custom-color')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('custom-color-hex')),
        '#FF12ABEF',
      );
      await tester.tap(find.byKey(const Key('apply-custom-color')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('frame-effect')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('frame-effect')),
          matching: find.text('None'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paper grain · GLSL').last);
      await tester.pumpAndSettle();
      expect(find.text('Paper grain · GLSL'), findsOneWidget);

      final zoomBefore = find.text('100%');
      expect(zoomBefore, findsOneWidget);
      final pointer = TestPointer(88, PointerDeviceKind.mouse);
      final focalPoint = tester.getCenter(
        find.byKey(const Key('canvas-input')),
      );
      await tester.sendEventToBinding(pointer.hover(focalPoint));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(find.text('100%'), findsNothing);

      final trackpad = TestPointer(89, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(focalPoint));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(focalPoint, scale: 1.25),
      );
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();
      expect(find.byKey(const Key('faint-grid')), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('layer-drag-node-4')),
        tester.getCenter(find.byKey(const Key('layer-drop-above-node-5'))) -
            tester.getCenter(find.byKey(const Key('layer-drag-node-4'))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const Key('layer-drag-node-4'))).dy,
        lessThan(
          tester.getCenter(find.byKey(const Key('layer-drag-node-5'))).dy,
        ),
      );

      await tester.tap(
        find.byKey(const Key('layer-drag-node-5')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('22 objects'), findsOneWidget);
    },
  );

  testWidgets('selects an unselected layer on pointer down and moves it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unselected = find.byKey(const Key('layer-body-node-1'));
    final start = tester.getCenter(unselected);
    final gesture = await tester.startGesture(start);
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Phone frame',
    );
    expect(find.byKey(const Key('selected-layer-body')), findsOneWidget);

    await gesture.moveBy(const Offset(52, 32));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final end = tester.getCenter(find.byKey(const Key('selected-layer-body')));
    expect(end.dx - start.dx, closeTo(52, 1));
    expect(end.dy - start.dy, closeTo(32, 1));
  });

  testWidgets('focuses a selected layer and fits the complete canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('layer-drag-node-2')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus selection'));
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byKey(const Key('canvas-input')));
    final focused = tester.getRect(
      find.byKey(const Key('selected-layer-body')),
    );
    expect(focused.center.dx, closeTo(viewport.center.dx, 1));
    expect(focused.center.dy, closeTo(viewport.center.dy, 1));

    await tester.tap(find.byKey(const Key('fit-canvas')));
    await tester.pumpAndSettle();
    final artboard = tester.getRect(find.byKey(const Key('artboard')));
    expect(artboard.center.dx, closeTo(viewport.center.dx, 1));
    expect(artboard.center.dy, closeTo(viewport.center.dy, 1));
    expect(viewport.inflate(0.5).contains(artboard.topLeft), isTrue);
    expect(viewport.inflate(0.5).contains(artboard.bottomRight), isTrue);
  });

  testWidgets('moves overlapping layers to the back and front', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-rectangle')));
    await tester.tap(find.byTooltip('Text'));
    await tester.pump();

    final overlap = tester.getCenter(
      find.byKey(const Key('selected-layer-body')),
    );
    await tester.tap(
      find.byKey(const Key('layer-body-node-5')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to back'));
    await tester.pumpAndSettle();
    await tester.tapAt(overlap);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Rectangle',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('layer-drag-node-5')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const Key('layers-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(
      find.byKey(const Key('layer-drag-node-5')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to front'));
    await tester.pumpAndSettle();
    await tester.tapAt(overlap);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Text',
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    await tester.tapAt(overlap);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      'Rectangle',
    );
  });

  testWidgets('autofocuses rename and records one rename state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text'));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('layer-drag-node-4')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    final rename = find.byKey(const Key('rename-layer-node-4'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: rename, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    final historyBefore = tester
        .widget<Text>(find.byKey(const Key('history-position')))
        .data!;

    await tester.enterText(rename, 'Callout');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(rename, findsNothing);
    expect(find.text('Callout'), findsWidgets);
    final historyAfter = tester
        .widget<Text>(find.byKey(const Key('history-position')))
        .data!;
    final beforeIndex = int.parse(historyBefore.split('/').first);
    final afterIndex = int.parse(historyAfter.split('/').first);
    expect(afterIndex, beforeIndex + 1);
  });

  testWidgets('pans with Space-primary drag and middle-button drag', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final input = tester.getRect(find.byKey(const Key('canvas-input')));
    final pointerStart = input.topLeft + const Offset(12, 12);
    var artboard = tester.getRect(find.byKey(const Key('artboard')));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final spaceGesture = await tester.startGesture(
      pointerStart,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await spaceGesture.moveBy(const Offset(44, 26));
    await tester.pump();
    await spaceGesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    var moved = tester.getRect(find.byKey(const Key('artboard')));
    expect(moved.center.dx - artboard.center.dx, closeTo(44, 1));
    expect(moved.center.dy - artboard.center.dy, closeTo(26, 1));

    await tester.tap(find.byKey(const Key('fit-canvas')));
    await tester.pump();
    artboard = tester.getRect(find.byKey(const Key('artboard')));
    final middleGesture = await tester.startGesture(
      pointerStart,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middleGesture.moveBy(const Offset(-36, 30));
    await tester.pump();
    await middleGesture.up();
    await tester.pump();
    moved = tester.getRect(find.byKey(const Key('artboard')));
    expect(moved.center.dx - artboard.center.dx, closeTo(-36, 1));
    expect(moved.center.dy - artboard.center.dy, closeTo(30, 1));
  });

  testWidgets('trackpad pan does not select or move a canvas layer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final transformBefore = tester
        .widget<Transform>(find.byKey(const Key('canvas-viewport')))
        .transform
        .storage
        .toList();
    final historyBefore = tester
        .widget<Text>(find.byKey(const Key('history-position')))
        .data;
    final selectedBefore = tester
        .widget<Text>(find.byKey(const Key('selected-layer-name')))
        .data;
    final progressCard = find.byKey(
      const Key('layer-body-starter-card-progress'),
    );
    final artboard = find.byKey(const Key('artboard'));
    final layerOffsetBefore =
        tester.getTopLeft(progressCard) - tester.getTopLeft(artboard);
    final focalPoint = tester.getCenter(progressCard);
    final trackpad = TestPointer(109, PointerDeviceKind.trackpad);

    await tester.sendEventToBinding(trackpad.panZoomStart(focalPoint));
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(focalPoint, pan: const Offset(64, 36)),
    );
    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await tester.pump();

    expect(
      tester
          .widget<Transform>(find.byKey(const Key('canvas-viewport')))
          .transform
          .storage
          .toList(),
      isNot(transformBefore),
    );
    final layerOffsetAfter =
        tester.getTopLeft(progressCard) - tester.getTopLeft(artboard);
    expect(layerOffsetAfter.dx, closeTo(layerOffsetBefore.dx, 0.01));
    expect(layerOffsetAfter.dy, closeTo(layerOffsetBefore.dy, 0.01));
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-layer-name'))).data,
      selectedBefore,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('history-position'))).data,
      historyBefore,
    );
  });

  testWidgets('defines a component slot and accepts a layer into it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-component')));
    await tester.pumpAndSettle();
    expect(find.text('COMPONENT EDITOR'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-component-slot')));
    await tester.pump();
    final slot = find.byKey(const Key('component-slot-slot-1'));
    expect(slot, findsOneWidget);

    final slotBefore = tester.getRect(slot);
    await tester.drag(slot, const Offset(24, 16));
    await tester.pump();
    final slotDelta = tester.getRect(slot).topLeft - slotBefore.topLeft;
    expect(slotDelta.dx, greaterThan(0));
    expect(slotDelta.dy, greaterThan(0));

    final customComponentCount = find
        .text('Custom component')
        .evaluate()
        .length;
    await tester.tap(find.byKey(const Key('slot-1-slot')));
    await tester.pumpAndSettle();
    expect(
      find.text('Custom component').evaluate().length,
      customComponentCount,
    );
    await tester.tap(find.text('Badge component').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('component-slot-reference-slot-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('component-slot-row-slot-1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(GraphicsEditorView),
      matchesGoldenFile(
        'goldens/graphics_editor_component_slot_context_menu.png',
      ),
    );
    await tester.tap(find.text('Delete slot'));
    await tester.pumpAndSettle();
    expect(slot, findsNothing);
    expect(
      find.byKey(const Key('component-slot-reference-slot-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('layer-drag-node-4')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit component'));
    await tester.pumpAndSettle();
    expect(slot, findsOneWidget);
    expect(
      find.byKey(const Key('component-slot-reference-slot-1')),
      findsOneWidget,
    );

    final layerTile = find.byKey(const Key('layer-drag-node-1'));
    await tester.dragFrom(
      tester.getCenter(layerTile),
      tester.getCenter(slot) - tester.getCenter(layerTile),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inside Custom component'), findsOneWidget);

    await tester.tap(slot, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete slot'));
    await tester.pumpAndSettle();
    expect(slot, findsNothing);
    expect(find.byKey(const Key('selected-layer-parent')), findsNothing);

    await tester.tap(find.byKey(const Key('undo-document')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('layer-drag-node-1')));
    await tester.pump();
    expect(find.text('Inside Custom component'), findsOneWidget);
  });

  testWidgets('shows progress while a custom shader compile is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 850,
          child: GraphicsEditorView(playback: playback, enableShaders: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('canvas-effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom GLSL…').last);
    await tester.pumpAndSettle();

    final compileButton = find.byKey(const Key('compile-custom-shader'));
    await tester.ensureVisible(compileButton);
    await tester.pumpAndSettle();
    await tester.tap(compileButton);
    await tester.pump();

    expect(
      find.descendant(
        of: compileButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shader-compile-status')), findsOneWidget);
    expect(find.text('Compiling with impellerc…'), findsOneWidget);
    expect(tester.widget<FilledButton>(compileButton).onPressed, isNull);
  });
}
