// ignore_for_file: file_names
import '../slide_layouts.dart';

class Slide14 extends BulletPointsSlideLayout {
  Slide14({super.key})
    : super(
        route: '/desktop-gaps',
        navigationTitle: "It's still not perfect",
        title: "It's still not perfect",
        label: 'Desktop today',
        items: const [
          'Accessibility is still in progress, especially for AI-agent computer use.',
          'IME support is far from perfect and still relies on platform channels.',
          'Occasional rendering and windowing glitches remain.',
          'Platform-specific APIs still require separate implementation work.',
        ],
      );
}
