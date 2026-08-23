import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../palette.dart';
import 'camera_path.dart';
import 'world.dart';

/// The 3D layer behind the flyover slide.
///
/// While [playing] is false the camera is parked head-on against the monolith
/// and a paper wash covers the whole frame, so the slide reads as any other
/// slide in the deck. Setting [playing] runs the flight: the wash lifts, the
/// camera pulls back to reveal that the "page" was a panel standing in a
/// landscape, flies over the forest and the lake to the pavilion, and settles
/// square against the second panel — where the wash returns, handing off
/// invisibly to the next slide.
class FlyoverView extends StatefulWidget {
  const FlyoverView({
    super.key,
    required this.playing,
    this.dockOverlay,
  });

  /// Whether the flight is running. False parks the camera back on dock A.
  final bool playing;

  /// Slide content drawn on the paper wash while docked. It fades out as soon
  /// as the flight starts.
  final Widget? dockOverlay;

  @override
  State<FlyoverView> createState() => _FlyoverViewState();
}

class _FlyoverViewState extends State<FlyoverView>
    with SingleTickerProviderStateMixin {
  final FlyoverWorld _world = FlyoverWorld.instance;

  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: FlightPath.duration,
  );

  FlightPath? _path;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ready = _world.isReady;
    if (!_ready) {
      _world.ready.then((_) {
        if (mounted) setState(() => _ready = true);
      });
    }
    if (widget.playing) _flight.forward();
  }

  @override
  void didUpdateWidget(FlyoverView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _flight.forward(from: 0);
    } else {
      _flight.value = 0;
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  /// A path is tied to the viewport shape, because the dock distance is. Only
  /// rebuild it when the shape actually moves.
  FlightPath _pathFor(double aspect) {
    final path = _path;
    if (path != null && (path.aspect - aspect).abs() < 0.01) return path;
    return _path = FlightPath(aspect: aspect);
  }

  /// Opacity of the paper wash: opaque while docked, gone through the flight,
  /// back at the landing so the next slide can take over unnoticed.
  double _wash(double t) => math.max(
        1 - _smoothstep(0.008, 0.070, t),
        _smoothstep(0.945, 1.0, t),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = constraints.hasBoundedHeight && constraints.maxHeight > 0
            ? constraints.maxWidth / constraints.maxHeight
            : 16 / 9;
        final path = _pathFor(aspect);

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: paper),
            if (_ready)
              SceneView(
                _world.scene,
                // Not `warmUp: true`: it gates the view behind a reveal that
                // never fires here, leaving the slide blank. Nothing is lost —
                // the view mounts on step 1 behind the opaque wash, so the
                // pipelines are warm well before the flight starts.
                cameraBuilder: (_) => path.shotAt(_flight.value).toCamera(),
              ),
            AnimatedBuilder(
              animation: _flight,
              builder: (context, _) {
                final t = _flight.value;
                final wash = _wash(t);
                final content = 1 - _smoothstep(0.0, 0.028, t);
                return IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (wash > 0)
                        Opacity(
                          opacity: wash,
                          child: const ColoredBox(color: paper),
                        ),
                      if (widget.dockOverlay != null && content > 0)
                        Opacity(opacity: content, child: widget.dockOverlay),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
