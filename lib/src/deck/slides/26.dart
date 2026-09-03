// ignore_for_file: file_names
import 'package:flutter/material.dart';

import '../asset_video.dart';
import '../slide_layouts.dart';

class Slide26 extends ImmersiveMediaSlideLayout {
  Slide26({super.key})
    : super(
        route: '/flocker',
        title: 'Flocker: a Skia-based Flutter web-engine fork',
        label: 'Engine experiments · Jesse Ezell',
        aspectRatio: 1.72,
        mediaBuilder: (context) => Column(
          children: [
            Flexible(
              flex: 2,
              child: Image.asset(
                'assets/images/flocker-post-text.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 14),
            const Expanded(
              flex: 5,
              child: AssetVideo(asset: 'assets/flocker-video.mp4'),
            ),
          ],
        ),
      );
}
