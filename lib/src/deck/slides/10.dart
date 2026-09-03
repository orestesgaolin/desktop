// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid_core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../palette.dart';
import '../config.dart';
import '../page.dart';

class Slide10 extends FlutterDeckSlideWidget {
  const Slide10({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/one-widget-tree',
          title: 'Single widget tree',
          speakerNotes:
              'All windows remain part of one widget tree. A provider above '
              'the window boundary remains available to widgets rendered in '
              'each native window, so existing state management keeps '
              'working. Solid lines show the widget tree; dotted arrows show '
              'each widget resolving the shared provider through its '
              'InheritedWidget lookup.\n\n'
              '[Sources]\n'
              '- https://flutter.dev/blog/desktop-windowing-apis\n'
              '- Diagram rendered with the local mermaid_flutter package.',
        ),
      );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: 'Windowing · 2026',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Single widget tree', style: PageText.title(s)),
            SizedBox(height: 38 * s),
            const Expanded(child: _SharedWidgetTreeDiagram()),
            SizedBox(height: 12 * s),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Source: https://flutter.dev/blog/desktop-windowing-apis; Mermaid: package:mermaid_flutter',
                style: PageText.footer(s),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SharedWidgetTreeDiagram extends StatelessWidget {
  const _SharedWidgetTreeDiagram();

  static const _source = '''
flowchart BT
  P[Shared provider]:::provider
  A[Widget]:::widget --- WA[Window A]:::window --- P
  B[Widget]:::widget --- WB[Window B]:::window --- P
  C[Widget]:::widget --- WC[Window C]:::window --- P

  A -.-> P
  B -.-> P
  C -.-> P

  classDef provider fill:#4F6F6A,stroke:#4F6F6A,color:#F5F3EE,stroke-width:2px
  classDef window fill:#F5F3EE,stroke:#4F6F6A,color:#2C2E31,stroke-width:2px
  classDef widget fill:#E8E4DB,stroke:#C6947A,color:#2C2E31,stroke-width:2px
''';

  static final _theme = mermaid_core.MermaidTheme.defaultTheme.copyWith(
    background: mermaid_core.Color(paper.toARGB32()),
    primaryColor: mermaid_core.Color(panel.toARGB32()),
    primaryTextColor: mermaid_core.Color(ink.toARGB32()),
    primaryBorderColor: mermaid_core.Color(spruce.toARGB32()),
    secondaryColor: mermaid_core.Color(panelHi.toARGB32()),
    lineColor: mermaid_core.Color(spruce.toARGB32()),
    arrowheadColor: mermaid_core.Color(spruce.toARGB32()),
    textColor: mermaid_core.Color(ink.toARGB32()),
    nodeBorder: mermaid_core.Color(spruce.toARGB32()),
    mainBkg: mermaid_core.Color(panel.toARGB32()),
    clusterBkg: mermaid_core.Color(panel.toARGB32()),
    clusterBorder: mermaid_core.Color(spruce.toARGB32()),
    titleColor: mermaid_core.Color(ink.toARGB32()),
    edgeLabelBackground: mermaid_core.Color(paper.toARGB32()),
    fontFamily: deckFontFamily,
    fontSize: 24,
  );

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 42 * s, vertical: 18 * s),
      child: Column(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: MermaidDiagram(
                source: _source,
                theme: _theme,
                keepLastGoodSceneOnError: false,
              ),
            ),
          ),
          SizedBox(height: 10 * s),
          Text(
            '······→  InheritedWidget lookup',
            style: PageText.body(
              s,
            ).copyWith(color: spruce, fontSize: 18 * s, letterSpacing: .4 * s),
          ),
        ],
      ),
    );
  }
}
