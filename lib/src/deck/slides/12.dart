// ignore_for_file: file_names
import '../slide_layouts.dart';

class Slide12 extends TitleOnlySlideLayout {
  Slide12({super.key})
    : super(
        route: '/detachable-panels',
        title: 'Panels can detach into native windows',
        label: 'Windowing demo',
        link: 'roszkowski.dev/panel',
      );
}
