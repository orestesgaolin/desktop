// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../code_snippet.dart';
import '../page.dart';

class Slide9 extends FlutterDeckSlideWidget {
  const Slide9({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/windowing-api',
          title: 'How to - windowing API',
          steps: 4,
          speakerNotes:
              'Step 1: unlike a conventional Flutter app, this calls '
              'runWidget rather than runApp. The root owns the complete set '
              'of views. Step 2: construct the regular main window. Step 3: '
              'create a dialog controller with the main window as its parent. '
              'Step 4: expose both controllers as Window widgets in one '
              'ViewCollection. A production app should also use a controller '
              'delegate to remove the dialog when its native window is '
              'destroyed. The examples assume flutter config '
              '--enable-windowing has already been run.\n\n'
              '[Sources]\n'
              '- https://flutter.dev/blog/desktop-windowing-apis\n'
              '- https://flutter.dev/to/windowing-example',
        ),
      );

  static const _steps = <_WindowingCodeStep>[
    _WindowingCodeStep(
      title: 'Replace runApp with a window-owning root',
      code: '''void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(const MyWindows());
}''',
    ),
    _WindowingCodeStep(
      title: 'Create the main window',
      code: '''late final mainWindow = WindowController(
  size: const Size(1280, 800),
  title: 'My app',
);

DialogWindowController? dialog;''',
    ),
    _WindowingCodeStep(
      title: 'Open a dialog window',
      code: '''void openDialog() {
  setState(() {
    dialog = DialogWindowController(
      parent: mainWindow,
      size: const Size(480, 320),
    );
  });
}''',
    ),
    _WindowingCodeStep(
      title: 'Render every window in one widget tree',
      code: '''Widget build(BuildContext context) => ViewCollection(
  views: [
    Window(
      controller: mainWindow,
      child: MyApp(onOpenDialog: openDialog),
    ),
    if (dialog case final controller?)
      DialogWindow(
        controller: controller,
        child: const SettingsDialog(),
      ),
  ],
);''',
    ),
  ];

  @override
  Widget build(BuildContext context) => FlutterDeckSlide.custom(
    builder: (context) => FlutterDeckSlideStepsBuilder(
      builder: (context, step) {
        final s = SlidePage.scaleOf(context);
        final index = (step - 1).clamp(0, _steps.length - 1);
        final current = _steps[index];
        return XpSlideFrame(
          title: 'Flutter Desktop — Windowing API',
          child: SlidePage(
            label: 'Windowing · API',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(current.title, style: PageText.title(s)),
                SizedBox(height: 22 * s),
                Row(
                  children: [
                    Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: PageText.label(s).copyWith(color: clay),
                    ),
                    SizedBox(width: 18 * s),
                    Expanded(
                      child: Text(
                        current.title,
                        style: PageText.lead(s)
                            .copyWith(color: ink, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${index + 1} / ${_steps.length}',
                      style: PageText.footer(s),
                    ),
                  ],
                ),
                SizedBox(height: 22 * s),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.025, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: DecoratedBox(
                      key: ValueKey(index),
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(18 * s),
                        border: Border.all(
                          color: spruce.withValues(alpha: .28),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(34 * s),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DartCodeSnippet(
                            code: current.code,
                            style: TextStyle(
                              color: paper,
                              fontFamily: 'Menlo',
                              fontSize: 22 * s,
                              height: 1.42,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10 * s),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Source: flutter.dev/blog/desktop-windowing-apis',
                    style: PageText.footer(s),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _WindowingCodeStep {
  const _WindowingCodeStep({required this.title, required this.code});

  final String title;
  final String code;
}
