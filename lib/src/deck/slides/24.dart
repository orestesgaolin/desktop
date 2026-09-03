// ignore_for_file: file_names
import 'package:flutter/widgets.dart';

import '../slide_layouts.dart';

class Slide24 extends ContentImageSlideLayout {
  Slide24({super.key})
    : super(
        route: '/buzz',
        title: 'Buzz uses Flutter on mobile and Tauri on desktop',
        label: 'Where are the apps?',
        navigationTitle: 'Buzz',
        body: 'The desktop version is built with Tauri, which uses web technologies for the UI and Rust for the backend.',
        imageBuilder: (context) => Image(
          image: AssetImage('assets/images/buzz.png'),
          fit: BoxFit.contain,
        ),
      );
}
