// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../page.dart';

class Slide7 extends FlutterDeckSlideWidget {
  const Slide7({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/canonical-ubuntu-installer',
          title: 'Canonical was already shipping\ndesktop apps in Flutter',
          preloadImages: {
            'assets/images/ubuntu-flutter-installer.jpg',
            'assets/images/lukas-ubuntu.png',
          },
          speakerNotes:
              'Canonical used Flutter for Ubuntu desktop software before the '
              'new windowing work, including the Ubuntu installer. This is '
              'the concrete product context for the 2024 partnership with '
              'Google.\n\n'
              '[Sources]\n'
              '- https://ubuntu.com/blog/flutter-and-ubuntu-so-far\n'
              '- https://ubuntu.com/blog/how-we-designed-the-new-ubuntu-desktop-installer\n'
              '- https://flutter.dev/blog/desktop-windowing-apis\n'
              '- User-provided asset: assets/images/lukas-ubuntu.png',
        ),
      );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) {
      final s = SlidePage.scaleOf(context);
      return SlidePage(
        label: 'Timeline · Canonical',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Canonical was already shipping desktop apps in Flutter',
              style: PageText.title(s),
            ),
            SizedBox(height: 28 * s),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18 * s),
                      child: ColoredBox(
                        color: panel,
                        child: Image.asset(
                          'assets/images/ubuntu-flutter-installer.jpg',
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 18 * s),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18 * s),
                      child: ColoredBox(
                        color: panel,
                        child: Image.asset(
                          'assets/images/lukas-ubuntu.png',
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10 * s),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Sources: ubuntu.com/blog/flutter-and-ubuntu-so-far; Lukas Klingsbo',
                style: PageText.footer(s),
              ),
            ),
          ],
        ),
      );
    },
  );
}
