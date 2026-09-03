// ignore_for_file: file_names
import '../config.dart';
import '../slide_layouts.dart';

class Slide31 extends ClosingSlideLayout {
  Slide31({super.key})
    : super(
        route: '/the-capability-is-here',
        navigationTitle: 'The capability is here',
        title: 'The capability is here. The apps are up to us.',
        subtitle: 'Questions?',
        link: deckConfig.website,
        additionalLinks: const ['github.com/orestesgaolin/desktop'],
      );
}
