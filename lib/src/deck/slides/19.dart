// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../demos/scene_playground.dart';
import '../../frame.dart';
import '../../gallery.dart';

class Slide19 extends FlutterDeckSlideWidget {
  const Slide19({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/flutter-scene',
          title: 'flutter_scene',
          showProgress: false,
          transition: FlutterDeckTransition.fade(),
          speakerNotes:
              'A separate flutter_scene demo: a retained 3D scene with PBR '
              'materials, lighting, shadows, post-processing, and an '
              'interactive Flutter widget inside the scene. This is the first '
              'cut if the talk is running long.',
        ),
      );

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) =>
        Theme(data: galleryTheme(), child: const _FlutterSceneSlideBody()),
  );
}

class _FlutterSceneSlideBody extends StatefulWidget {
  const _FlutterSceneSlideBody();

  @override
  State<_FlutterSceneSlideBody> createState() => _FlutterSceneSlideBodyState();
}

class _FlutterSceneSlideBodyState extends State<_FlutterSceneSlideBody> {
  final PlaybackController _playback = PlaybackController();
  final ScenePlaygroundDemo _demo = ScenePlaygroundDemo();

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _demo.buildView(context, _playback),
      const Positioned(
        top: 28,
        left: 32,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xCC252A28),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                'flutter_scene',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
