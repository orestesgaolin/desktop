# State of Flutter Desktop

Source for the **State of Flutter Desktop in 2026** presentation from
Flutter & Friends 2026.

The presentation is a macOS Flutter application built with
[flutter_deck](https://pub.dev/packages/flutter_deck). It includes live
desktop-windowing examples, Flutter GPU shaders, `flutter_scene`, an
interactive design editor, videos, and audience polling.

Presentation sources and external references are collected at
[roszkowski.dev/desktop](https://roszkowski.dev/desktop).

## Requirements

- macOS
- Flutter on the `master` channel, pinned through FVM in `.fvmrc`
- Flutter's experimental desktop-windowing feature
- Xcode command-line tools

## Run

```sh
fvm use master
fvm flutter config --enable-windowing
fvm flutter run -d macos
```

The poll uses simulated results by default. See
[Implementation notes](docs/implementation.md#live-poll) to connect the
presentation to a live result endpoint.

## Controls

- Left and Right move through slides and slide steps.
- `⌘.` opens the slide drawer.
- Interactive demo slides accept pointer and keyboard input.
- Videos start muted and loop. Click a video to pause or resume it.

## Presentation structure

| Slides | Subject |
| --- | --- |
| 1–4 | Introduction, audience question, desktop screenshot, and the 2020 talk |
| 5–7 | Flutter desktop timeline and Canonical's Ubuntu work |
| 8–13 | Window types, windowing API, shared state, browser tabs, panels, and frameless windows |
| 14–17 | 3D transition, Flutter GPU shaders, and `flutter_scene` |
| 18–19 | Design-editor demo |
| 20–25 | Desktop applications, engine experiments, and current platform issues |
| 26–27 | Flutter desktop as a development tool at Visible |
| 28 | Sources |
| 29 | Closing and questions |

The optional audience poll is slide 2. Disable it with `showAudiencePoll` in
`lib/src/deck/slides.dart` when preparing a version without audience voting.

## Repository map

- `lib/src/deck/`: deck configuration, shared layouts, and numbered slides
- `lib/src/demos/`: GPU and editor demos
- `lib/src/flyover/`: procedural landscape and camera flight
- `shaders/`: GLSL sources compiled by the live shader compiler
- `assets/`: presentation images and videos
- `macos/`: desktop runner and native window integration
- `docs/implementation.md`: architecture, demo behavior, and implementation notes

## More information

- [Implementation notes](docs/implementation.md)
- [Flutter desktop windowing APIs](https://flutter.dev/blog/desktop-windowing-apis)
- [Flutter GPU documentation](https://github.com/flutter/flutter/blob/master/engine/src/flutter/docs/impeller/Flutter-GPU.md)
- [Public presentation repository](https://github.com/orestesgaolin/desktop)
