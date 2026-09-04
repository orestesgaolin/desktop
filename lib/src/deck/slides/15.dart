// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../page.dart';

class Slide15 extends FlutterDeckSlideWidget {
  const Slide15({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/issues-in-progress',
          title: 'Sample of issues in progress',
          speakerNotes: '''Selected Flutter desktop issues:

Closest cross-desktop matches:
- https://github.com/flutter/flutter/issues/55427
- https://github.com/flutter/flutter/issues/182059
- https://github.com/flutter/flutter/issues/74255
- https://github.com/flutter/flutter/issues/67034

macOS:
- https://github.com/flutter/flutter/issues/189321
- https://github.com/flutter/flutter/issues/190075
- https://github.com/flutter/flutter/issues/191865
- https://github.com/flutter/flutter/issues/122133
- https://github.com/flutter/flutter/issues/112882

Windows:
- https://github.com/flutter/flutter/issues/186948
- https://github.com/flutter/flutter/issues/188270
- https://github.com/flutter/flutter/issues/130683
- https://github.com/flutter/flutter/issues/159630
- https://github.com/flutter/flutter/issues/151457

Linux:
- https://github.com/flutter/flutter/issues/191870
- https://github.com/flutter/flutter/issues/174762
- https://github.com/flutter/flutter/issues/185726
- https://github.com/flutter/flutter/issues/188966
- https://github.com/flutter/flutter/issues/127768
- https://github.com/flutter/flutter/issues/126329''',
        ),
      );

  static const _crossDesktop = _IssueGroup(
    title: 'Closest cross-desktop matches',
    issues: [
      _Issue(
        '55427',
        'Startup window flashes and jumps before the first frame.',
      ),
      _Issue('182059', 'Text fields lose focus after route navigation.'),
      _Issue('74255', 'Context menus do not look or behave natively.'),
      _Issue('67034', 'Desktop text appears heavier and blurrier.'),
    ],
  );

  static const _macOS = _IssueGroup(
    title: 'macOS',
    issues: [
      _Issue('189321', 'Multiple windows flicker and show artifacts.'),
      _Issue('190075', 'Empty Flutter scenes stall window resizing.'),
      _Issue('191865', 'Platform-view windows stall during resizing.'),
      _Issue('122133', 'Transparent windows leave shadow artifacts.'),
      _Issue('112882', 'Activation clicks incorrectly trigger controls.'),
    ],
  );

  static const _windows = _IssueGroup(
    title: 'Windows',
    issues: [
      _Issue('186948', 'A spawned window can remain transparent.'),
      _Issue('188270', 'Secondary window content becomes stretched.'),
      _Issue('130683', 'Frameless windows flicker after repositioning.'),
      _Issue('159630', 'FancyZones can restore a blank window.'),
      _Issue('151457', 'The app can permanently lose keyboard focus.'),
    ],
  );

  static const _linux = _IssueGroup(
    title: 'Linux',
    issues: [
      _Issue('191870', 'Empty frames leave stale content visible.'),
      _Issue('174762', 'Window resizing visibly stutters.'),
      _Issue('185726', 'Overlapping windows leave ghosting artifacts.'),
      _Issue('188966', 'Wayland with NVIDIA can show a black window.'),
      _Issue('127768', 'Fractional scaling changes text but not other UI.'),
      _Issue('126329', 'IME suggestions appear away from the caret.'),
    ],
  );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: 'Desktop today',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sample of issues in progress', style: PageText.title(s)),
            SizedBox(height: 28 * s),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _IssueColumn(
                      groups: const [_crossDesktop, _macOS],
                      scale: s,
                    ),
                  ),
                  SizedBox(width: 54 * s),
                  Expanded(
                    child: _IssueColumn(
                      groups: const [_windows, _linux],
                      scale: s,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _IssueColumn extends StatelessWidget {
  const _IssueColumn({required this.groups, required this.scale});

  final List<_IssueGroup> groups;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < groups.length; index++) ...[
        if (index > 0) SizedBox(height: 20 * scale),
        Text(groups[index].title, style: PageText.label(scale)),
        SizedBox(height: 9 * scale),
        for (final issue in groups[index].issues)
          Padding(
            padding: EdgeInsets.only(bottom: 6 * scale),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '#${issue.number}  ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: clay,
                    ),
                  ),
                  TextSpan(text: issue.description),
                ],
              ),
              style: PageText.body(scale).copyWith(
                color: ink.withValues(alpha: .82),
                fontSize: 14.5 * scale,
                height: 1.28,
              ),
            ),
          ),
      ],
    ],
  );
}

class _IssueGroup {
  const _IssueGroup({required this.title, required this.issues});

  final String title;
  final List<_Issue> issues;
}

class _Issue {
  const _Issue(this.number, this.description);

  final String number;
  final String description;
}
