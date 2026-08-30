import '../config.dart';
import '../slide_layouts.dart';

/// The opening slide.
class Slide1 extends TitleSlideLayout {
  Slide1({super.key})
    : super(
        route: '/title',
        title: deckConfig.title,
        details: deckConfig.titleDetails,
      );
}

// ignore_for_file: file_names
