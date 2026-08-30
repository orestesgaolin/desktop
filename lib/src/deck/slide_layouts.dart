import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../palette.dart';
import 'page.dart';

/// Opening slide with presentation metadata and an optional subtitle.
class TitleSlideLayout extends FlutterDeckSlideWidget {
  TitleSlideLayout({
    super.key,
    required String route,
    required this.title,
    required this.details,
    this.subtitle,
    String speakerNotes = '',
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: title,
           speakerNotes: speakerNotes,
         ),
       );

  final String title;
  final String details;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        showNumber: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (details.trim().isNotEmpty) ...[
              Text(details.toUpperCase(), style: PageText.label(s)),
              SizedBox(height: 28 * s),
            ],
            Text(title, style: PageText.display(s)),
            SizedBox(height: 34 * s),
            Container(width: 90 * s, height: 1.4, color: clay),
            if (subtitle?.trim().isNotEmpty ?? false) ...[
              SizedBox(height: 30 * s),
              SizedBox(
                width: 720 * s,
                child: Text(subtitle!, style: PageText.lead(s)),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// A single audience-facing title, useful while the talk's content is being
/// written and for deliberate section turns in the finished deck.
class TitleOnlySlideLayout extends FlutterDeckSlideWidget {
  TitleOnlySlideLayout({
    super.key,
    required String route,
    required this.title,
    this.label,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: title,
         ),
       );

  final String title;
  final String? label;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 1100 * s,
            child: Text(title, style: PageText.title(s)),
          ),
        ),
      );
    },
  );
}

/// A near-full-slide frame for a still image, an MP4 player, or any other
/// media widget. Playback remains owned by the supplied builder.
class ImmersiveMediaSlideLayout extends FlutterDeckSlideWidget {
  ImmersiveMediaSlideLayout({
    super.key,
    required String route,
    required this.title,
    this.label,
    this.mediaBuilder,
    this.aspectRatio = 16 / 9,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: title,
         ),
       );

  final String title;
  final String? label;
  final WidgetBuilder? mediaBuilder;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: PageText.title(s)),
            if (mediaBuilder != null) ...[
              SizedBox(height: 28 * s),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10 * s),
                      child: mediaBuilder!(context),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Title and progressively revealed bullet points.
class BulletPointsSlideLayout extends FlutterDeckSlideWidget {
  BulletPointsSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.title,
    required this.items,
    this.label,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
           steps: items.isEmpty ? 1 : items.length,
         ),
       );

  final String? label;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.trim().isNotEmpty) ...[
              SizedBox(
                width: 980 * s,
                child: Text(title, style: PageText.title(s)),
              ),
              SizedBox(height: 48 * s),
            ],
            if (items.isNotEmpty)
              Expanded(
                child: FlutterDeckSlideStepsBuilder(
                  builder: (context, step) => SizedBox(
                    width: 900 * s,
                    child: PageBullets(items: items.take(step).toList()),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// A narrative block paired with an image or other still visual.
class ContentImageSlideLayout extends FlutterDeckSlideWidget {
  ContentImageSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.title,
    required this.body,
    this.label,
    this.imageBuilder,
    this.imageOnLeft = false,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
         ),
       );

  final String? label;
  final String title;
  final String body;
  final WidgetBuilder? imageBuilder;
  final bool imageOnLeft;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      final content = _NarrativeContent(title: title, body: body, scale: s);
      final image = imageBuilder?.call(context);

      return SlidePage(
        label: label,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: imageOnLeft
              ? _mediaColumns(image, content, s)
              : _mediaColumns(content, image, s),
        ),
      );
    },
  );
}

/// A narrative block paired with a video player or animated media widget.
class VideoSlideLayout extends FlutterDeckSlideWidget {
  VideoSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.title,
    required this.body,
    this.label,
    this.videoBuilder,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
         ),
       );

  final String? label;
  final String title;
  final String body;
  final WidgetBuilder? videoBuilder;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.trim().isNotEmpty) ...[
              Text(title, style: PageText.title(s)),
              SizedBox(height: 24 * s),
            ],
            if (body.trim().isNotEmpty) ...[
              SizedBox(
                width: 860 * s,
                child: Text(body, style: PageText.body(s)),
              ),
              SizedBox(height: 32 * s),
            ],
            if (videoBuilder != null)
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: videoBuilder!(context),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// One large statement with optional supporting copy.
class StatementSlideLayout extends FlutterDeckSlideWidget {
  StatementSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.statement,
    this.supportingText,
    this.label,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
         ),
       );

  final String? label;
  final String statement;
  final String? supportingText;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (statement.trim().isNotEmpty)
              SizedBox(
                width: 1040 * s,
                child: Text(statement, style: PageText.display(s)),
              ),
            if (supportingText?.trim().isNotEmpty ?? false) ...[
              SizedBox(height: 32 * s),
              SizedBox(
                width: 720 * s,
                child: Text(supportingText!, style: PageText.body(s)),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// A quotation and attribution.
class QuoteSlideLayout extends FlutterDeckSlideWidget {
  QuoteSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.quote,
    required this.attribution,
    this.label,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
         ),
       );

  final String? label;
  final String quote;
  final String attribution;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (quote.trim().isNotEmpty)
              SizedBox(
                width: 1040 * s,
                child: Text(
                  '“$quote”',
                  style: PageText.title(s).copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            if (attribution.trim().isNotEmpty) ...[
              SizedBox(height: 36 * s),
              Text(attribution, style: PageText.label(s).copyWith(color: clay)),
            ],
          ],
        ),
      );
    },
  );
}

/// Minimal closing slide with optional supporting copy.
class ClosingSlideLayout extends FlutterDeckSlideWidget {
  ClosingSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.title,
    this.subtitle,
    this.link,
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
         ),
       );

  final String title;
  final String? subtitle;
  final String? link;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        showNumber: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (title.trim().isNotEmpty)
              Text(title, style: PageText.display(s)),
            if (title.trim().isNotEmpty) ...[
              SizedBox(height: 28 * s),
              Container(width: 90 * s, height: 1.4, color: spruce),
            ],
            if (subtitle?.trim().isNotEmpty ?? false) ...[
              SizedBox(height: 26 * s),
              Text(subtitle!, style: PageText.lead(s)),
            ],
            if (link?.trim().isNotEmpty ?? false) ...[
              SizedBox(height: 18 * s),
              Text(
                link!,
                style: PageText.title(s)
                    .copyWith(color: clay, fontSize: 34 * s),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// A compact reference list designed to remain legible in a photograph.
class SourcesSlideLayout extends FlutterDeckSlideWidget {
  SourcesSlideLayout({
    super.key,
    required String route,
    required String navigationTitle,
    required this.title,
    required this.website,
    required this.sources,
    this.label = 'References',
  }) : super(
         configuration: FlutterDeckSlideConfiguration(
           route: route,
           title: navigationTitle,
           speakerNotes:
               '[Sources]\n${sources.map((source) => '- ${source.url}').join('\n')}',
         ),
       );

  final String? label;
  final String title;
  final String website;
  final List<SourceReference> sources;

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      final split = (sources.length / 2).ceil();
      final columns = [
        sources.take(split).toList(),
        sources.skip(split).toList(),
      ];

      return SlidePage(
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(title, style: PageText.title(s))),
                if (website.trim().isNotEmpty)
                  Text(website, style: PageText.lead(s).copyWith(color: clay)),
              ],
            ),
            SizedBox(height: 42 * s),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var columnIndex = 0;
                    columnIndex < columns.length;
                    columnIndex++
                  ) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var rowIndex = 0;
                            rowIndex < columns[columnIndex].length;
                            rowIndex++
                          )
                            _SourceEntry(
                              number: columnIndex * split + rowIndex + 1,
                              source: columns[columnIndex][rowIndex],
                              scale: s,
                            ),
                        ],
                      ),
                    ),
                    if (columnIndex == 0) SizedBox(width: 70 * s),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class SourceReference {
  const SourceReference({required this.title, required this.url});

  final String title;
  final String url;
}

class _SourceEntry extends StatelessWidget {
  const _SourceEntry({
    required this.number,
    required this.source,
    required this.scale,
  });

  final int number;
  final SourceReference source;
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 18 * scale),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34 * scale,
          child: Text(
            number.toString().padLeft(2, '0'),
            style: PageText.label(scale).copyWith(color: clay),
          ),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.title,
                style: TextStyle(
                  color: ink,
                  fontSize: 18 * scale,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6 * scale),
              Text(
                source.url,
                style: TextStyle(
                  color: textDim,
                  fontSize: 16 * scale,
                  height: 1.28,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NarrativeContent extends StatelessWidget {
  const _NarrativeContent({
    required this.title,
    required this.body,
    required this.scale,
  });

  final String title;
  final String body;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (title.trim().isNotEmpty) Text(title, style: PageText.title(scale)),
      if (title.trim().isNotEmpty && body.trim().isNotEmpty)
        SizedBox(height: 28 * scale),
      if (body.trim().isNotEmpty) Text(body, style: PageText.body(scale)),
    ],
  );
}

List<Widget> _mediaColumns(Widget? left, Widget? right, double scale) => [
  Expanded(flex: 5, child: left ?? const SizedBox.shrink()),
  SizedBox(width: 64 * scale),
  Expanded(flex: 5, child: right ?? const SizedBox.shrink()),
];
