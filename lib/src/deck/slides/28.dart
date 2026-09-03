// ignore_for_file: file_names
import '../asset_video.dart';
import '../slide_layouts.dart';

class Slide28 extends VideoSlideLayout {
  Slide28({super.key})
    : super(
        route: '/hidden-gem',
        navigationTitle: 'Flutter desktop as a development tool',
        title: 'Flutter desktop as a development tool',
        label: 'Visible',
        body: 'A purpose-built macOS shell gives the team personas, expanded views, a component browser, and hot reload without an emulator.',
        videoBuilder: (context) =>
            const AssetVideo(asset: 'assets/flutter_visible_macos.mp4'),
      );
}
