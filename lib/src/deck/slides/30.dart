import '../config.dart';
import '../slide_layouts.dart';

class Slide30 extends SourcesSlideLayout {
  Slide30({super.key})
    : super(
        route: '/sources',
        navigationTitle: 'Sources',
        title: 'Sources',
        website: deckConfig.website,
        sources: const [
          SourceReference(
            title: 'Flutter 2 · desktop expansion',
            url: 'developers.googleblog.com/en/announcing-flutter-2',
          ),
          SourceReference(
            title: 'Flutter 3 · desktop stable',
            url: 'flutter.dev/blog/introducing-flutter-3',
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
            title: 'Flutter 3.44 · Canonical leads desktop',
            url: 'flutter.dev/blog/whats-new-in-flutter-3-44',
          ),
          SourceReference(
            title: 'Flutter 3.47 · Impeller across desktop',
            url: 'docs.flutter.dev/release/release-notes/release-notes-3.47.0',
          ),
          SourceReference(
            title: 'Desktop Windowing API',
            url: 'flutter.dev/blog/desktop-windowing-apis',
          ),
          SourceReference(
            title: 'Windowing example',
            url: 'flutter.dev/to/windowing-example',
          ),
          SourceReference(
            title: 'Ubuntu desktop installer',
            url: 'ubuntu.com/blog/flutter-and-ubuntu-so-far',
          ),
          SourceReference(
            title: 'Detachable panels',
            url: 'github.com/orestesgaolin/panel',
          ),
          SourceReference(
            title: 'Why OpenCode moved to Electron',
            url: 'dev.to/brendonovich/moving-opencode-desktop-to-electron-4hip',
          ),
          SourceReference(
            title: 'Jesse Ezell on Flocker',
            url: 'itsallwidgets.com/podcast/episodes/58/jesse-ezell',
          ),
          SourceReference(
            title: 'Flutter & Friends',
            url: 'flutterfriends.dev',
          ),
        ],
      );
}

// ignore_for_file: file_names
