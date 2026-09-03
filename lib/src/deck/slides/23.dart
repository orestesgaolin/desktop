// ignore_for_file: file_names
import 'package:flutter/widgets.dart';

import '../slide_layouts.dart';

class Slide23 extends ImmersiveMediaSlideLayout {
  Slide23({super.key})
    : super(
        route: '/opencode',
        title: 'OpenCode moved from Tauri to Electron',
        label: 'Where are the apps?',
        aspectRatio: 1850 / 1204,
        mediaBuilder: (context) => Image.asset(
          'assets/images/tauri-open-code.png',
          fit: BoxFit.contain,
        ),
      );
}
