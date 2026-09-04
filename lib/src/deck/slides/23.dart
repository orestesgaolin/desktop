// ignore_for_file: file_names
import 'package:flutter/widgets.dart';

import '../slide_layouts.dart';

class Slide23 extends ImmersiveMediaSlideLayout {
  Slide23({super.key})
    : super(
        route: '/desktop-apps-grid',
        title: 'Popular Flutter desktop apps are mostly utilities',
        label: 'Where are the apps?',
        aspectRatio: 16 / 7,
        mediaBuilder: (context) => Row(
          children: [
            Expanded(
              child: Image.asset(
                'assets/images/localsend.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Image.asset(
                'assets/images/rust-desk.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      );
}
