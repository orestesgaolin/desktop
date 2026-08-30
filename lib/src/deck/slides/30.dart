import '../config.dart';
import '../slide_layouts.dart';

class Slide30 extends SourcesSlideLayout {
  Slide30({super.key})
    : super(
        route: '/sources',
        navigationTitle: 'Sources',
        title: 'Sources worth keeping.',
        website: deckConfig.website,
        sources: const [
          SourceReference(
            title: 'Flutter 1.12 · macOS alpha',
            url: 'flutter.dev/blog/announcing-flutter-1-12-what-a-year',
          ),
          SourceReference(
            title: 'Flutter 2 · desktop expansion',
            url: 'developers.googleblog.com/en/announcing-flutter-2',
          ),
          SourceReference(
            title: 'Flutter 3 · desktop stable',
            url: 'flutter.dev/blog/introducing-flutter-3',
          ),
          SourceReference(
            title: 'Flutter 3.16 · Impeller on macOS',
            url: 'docs.flutter.dev/release/release-notes/release-notes-3.16.0',
          ),
          SourceReference(
            title: 'Flutter 3.35 · merged desktop threads',
            url: 'docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads',
          ),
          SourceReference(
            title: 'Flutter 3.35 · multi-window engine',
            url: 'docs.flutter.dev/release/release-notes/release-notes-3.35.0',
          ),
          SourceReference(
            title: 'Flutter 3.47 · Impeller across desktop',
            url: 'docs.flutter.dev/release/release-notes/release-notes-3.47.0',
          ),
          SourceReference(
            title: 'Desktop Windowing API',
            url: 'flutter.dev/blog/desktop-windowing-apis',
          ),
        ],
      );
}

// ignore_for_file: file_names
