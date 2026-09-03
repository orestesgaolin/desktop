// ignore_for_file: file_names
import 'package:flutter/widgets.dart';

import '../slide_layouts.dart';

class Slide29 extends ImmersiveMediaSlideLayout {
  Slide29({super.key})
    : super(
        route: '/visible-linux-agent',
        title: 'Visible’s app in a Linux sandbox',
        label: 'Visible demo',
        aspectRatio: 1694 / 1716,
        mediaBuilder: (context) =>
            Image.asset('assets/images/vix-slack.png', fit: BoxFit.contain),
      );
}
