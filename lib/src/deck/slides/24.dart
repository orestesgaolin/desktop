// ignore_for_file: file_names
import 'package:flutter/material.dart';

import '../../palette.dart';
import '../asset_video.dart';
import '../page.dart';
import '../slide_layouts.dart';

class Slide24 extends ImmersiveMediaSlideLayout {
  Slide24({super.key})
    : super(
        route: '/engine-experiments',
        title: 'Flutter Zero and Flocker',
        label: 'Engine experiments',
        aspectRatio: 16 / 7.2,
        speakerNotes:
            'Flutter Zero is by Matej Knopp. Flocker is by Jesse Ezell. '
            'Flocker is a fork of Flutter\'s web engine, not a fork of Flutter.',
        mediaBuilder: (context) {
          final s = SlidePage.scaleOf(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 330 * s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panel,
                    border: Border.all(color: panelHi),
                    borderRadius: BorderRadius.circular(10 * s),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(26 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flutter Zero',
                          style: PageText.lead(s)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8 * s),
                        Text('Matej Knopp', style: PageText.label(s)),
                        SizedBox(height: 20 * s),
                        Text(
                          'Flutter UI without the Flutter engine.',
                          style: PageText.body(s),
                        ),
                        const Spacer(),
                        Divider(color: panelHi),
                        SizedBox(height: 18 * s),
                        Text(
                          'Flocker',
                          style: PageText.lead(s)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8 * s),
                        Text('Jesse Ezell', style: PageText.label(s)),
                        SizedBox(height: 20 * s),
                        Text(
                          'A Skia-based fork of Flutter\'s web engine.',
                          style: PageText.body(s),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 18 * s),
              Expanded(
                child: Column(
                  children: [
                    Flexible(
                      flex: 2,
                      child: Image.asset(
                        'assets/images/flocker-post-text.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: 12 * s),
                    const Expanded(
                      flex: 5,
                      child: AssetVideo(asset: 'assets/flocker-video.mp4'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}
