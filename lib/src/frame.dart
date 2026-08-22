import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Per-frame data handed to a demo's render method.
class FrameContext {
  FrameContext({
    required this.transients,
    required this.time,
    required this.dt,
    required this.widthPx,
    required this.heightPx,
    required this.sizeLogical,
    required this.pointerUv,
    required this.pointerDown,
    required this.dragDelta,
    required this.scrollDelta,
    this.tapUv,
  });

  /// Per-frame bump allocator for uniform/vertex data. Reset by the surface
  /// view at the start of every frame.
  final gpu.HostBuffer transients;

  /// Demo time in seconds (scaled by playback speed, frozen while paused).
  final double time;

  /// Scaled delta time for this frame in seconds.
  final double dt;

  /// Render target size in physical pixels.
  final int widthPx;
  final int heightPx;

  /// Viewport size in logical pixels (for pointer-space math).
  final Size sizeLogical;

  double get aspect => heightPx == 0 ? 1 : widthPx / heightPx;

  /// Pointer position in uv space ([0,1] x [0,1], y pointing up).
  final Offset pointerUv;
  final bool pointerDown;

  /// Drag movement (logical px) accumulated since the previous frame.
  final Offset dragDelta;

  /// Scroll wheel movement accumulated since the previous frame.
  final double scrollDelta;

  /// Position of a completed tap (press + release with little movement)
  /// since the previous frame, in uv space (y up). Null if none.
  final Offset? tapUv;
}

/// Shared playback/quality state between the toolbar UI and the surface view.
class PlaybackController extends ChangeNotifier {
  bool _paused = false;
  double _speed = 1.0;
  double _renderScale = 1.0;

  bool get paused => _paused;
  set paused(bool value) {
    if (value == _paused) return;
    _paused = value;
    notifyListeners();
  }

  double get speed => _speed;
  set speed(double value) {
    if (value == _speed) return;
    _speed = value;
    notifyListeners();
  }

  /// Multiplier on top of the device pixel ratio (1.0 = native).
  double get renderScale => _renderScale;
  set renderScale(double value) {
    if (value == _renderScale) return;
    _renderScale = value;
    notifyListeners();
  }

  /// Live stats line (`<fps> fps · <w>x<h>`), written by the surface view.
  final ValueNotifier<String> stats = ValueNotifier<String>('· · ·');
}
