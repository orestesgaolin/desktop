// ignore_for_file: file_names
import 'package:flutter/widgets.dart';

import '../slide_layouts.dart';

class Slide22 extends ImmersiveMediaSlideLayout {
  Slide22({super.key})
    : super(
        route: '/desktop-apps-grid',
        title: 'Popular Flutter desktop apps are mostly utilities',
        label: 'Where are the apps?',
        aspectRatio: 2024 / 1424,
        mediaBuilder: (context) =>
            Image.asset('assets/images/localsend.png', fit: BoxFit.contain),
      );
}
