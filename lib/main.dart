// Flutter's desktop windowing API is still experimental and intentionally
// lives in an internal library while it is developed on the main channel.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';

import 'src/deck/deck_app.dart';
import 'src/demos/browser_demo.dart';
import 'src/demos/edge_window_demo.dart';

class _MainWindowDelegate with WindowControllerDelegate {
  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}

void main() {
  // Windowing currently requires Flutter's binding to own the view lifecycle.
  // Marionette's custom debug binding assumes the traditional implicit view.
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(const _GpuPlaygroundWindows());
}

/// Keeps the presentation and every detached browser tab in one widget tree.
/// This is the state-sharing model provided by Flutter's windowing API: no
/// secondary engines, isolates, or message bridge are involved.
class _GpuPlaygroundWindows extends StatefulWidget {
  const _GpuPlaygroundWindows();

  @override
  State<_GpuPlaygroundWindows> createState() => _GpuPlaygroundWindowsState();
}

class _GpuPlaygroundWindowsState extends State<_GpuPlaygroundWindows> {
  late final WindowController _mainWindow;
  final BrowserWorkspace _browser = BrowserWorkspace.instance;
  final EdgeWindowDemo _edgeWindow = EdgeWindowDemo.instance;

  @override
  void initState() {
    super.initState();
    _mainWindow = WindowController(
      size: const Size(1280, 800),
      constraints: const BoxConstraints(minWidth: 960, minHeight: 640),
      title: 'Flutter GPU Playground',
      delegate: _MainWindowDelegate(),
    );
    _edgeWindow.attach(_mainWindow);
    if (const bool.fromEnvironment('EDGE_WINDOW_AUTOSTART')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _edgeWindow.open());
    }
    _browser.addListener(_windowsChanged);
    _edgeWindow.addListener(_windowsChanged);
  }

  void _windowsChanged() => setState(() {});

  @override
  void dispose() {
    _browser.removeListener(_windowsChanged);
    _edgeWindow.removeListener(_windowsChanged);
    _edgeWindow.close();
    _mainWindow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(
      views: <Widget>[
        Window(controller: _mainWindow, child: const PresentationApp()),
        if (_edgeWindow.window case final edgeWindow?)
          Window(
            key: const ValueKey('edge-window-demo'),
            controller: edgeWindow,
            child: const EdgeWindowView(),
          ),
        for (final detached in _browser.detachedTabs)
          Window(
            key: ValueKey('browser-window-${detached.tab.id}'),
            controller: detached.window,
            child: DetachedBrowserWindow(tab: detached.tab),
          ),
      ],
    );
  }
}
