// ignore_for_file: file_names
import 'package:flutter/material.dart';

import '../../palette.dart';
import '../asset_video.dart';
import '../page.dart';
import '../slide_layouts.dart';

class Slide28 extends ImmersiveMediaSlideLayout {
  Slide28({super.key})
    : super(
        route: '/visible-linux-agent',
        title: 'Visible’s app in a Linux sandbox',
        label: 'Visible demo',
        aspectRatio: 2.12,
        speakerNotes:
            'The screenshot and muted recording show the Linux sandbox '
            'workflow and its result in Slack.\n\n'
            '[Sources]\n'
            '- User-provided asset: assets/images/vix-slack.png\n'
            '- User-provided asset: assets/vix-slack.mp4',
        mediaBuilder: (context) {
          final s = SlidePage.scaleOf(context);
          return Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panel,
                    border: Border.all(color: panelHi),
                  ),
                  child: Image.asset(
                    'assets/images/vix-slack.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(width: 18 * s),
              const Expanded(
                child: AssetVideo(
                  asset: 'assets/vix-slack.mp4',
                  fit: BoxFit.contain,
                ),
              ),
            ],
          );
        },
      );
}
