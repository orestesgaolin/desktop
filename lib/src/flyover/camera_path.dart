import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'world.dart';

/// One frame of the flight: where the camera is, what it looks at, which way
/// is up (the bank), and how wide the lens is.
class CameraShot {
  const CameraShot({
    required this.position,
    required this.target,
    required this.up,
    required this.fovY,
  });

  final vm.Vector3 position;
  final vm.Vector3 target;
  final vm.Vector3 up;
  final double fovY;

  PerspectiveCamera toCamera() => PerspectiveCamera(
        position: position,
        target: target,
        up: up,
        fovRadiansY: fovY,
        fovNear: 0.5,
        fovFar: 900,
      );
}

/// The camera choreography for the flyover: dock A → up over the forest →
/// down across the lake → up the plateau → parked square on dock B.
///
/// The control points are a Catmull-Rom spline, re-parametrised by arc length
/// so the camera holds a steady speed regardless of how far apart the
/// waypoints are. A pacing curve on top of that eases out of the first dock
/// and into the last one.
///
/// The two ends are computed from the viewport [aspect]: a dock panel has to
/// cover the whole frame, and how far back that is depends on the display's
/// shape.
class FlightPath {
  FlightPath({required this.aspect}) {
    _controls = _controlPoints(Landmarks.dockDistance(aspect));
    _buildArcTable();
    _buildRollTable();
  }

  final double aspect;

  /// Wall-clock length of the flight.
  static const Duration duration = Duration(milliseconds: 20000);

  /// Lens width at the fastest part of the cruise. Wider than the dock lens,
  /// which is what makes the middle of the flight feel quick.
  static const double _cruiseFovY = 64 * math.pi / 180;

  late final List<vm.Vector3> _controls;
  late final List<double> _arc; // cumulative length at each table sample
  late final List<double> _param; // spline parameter at each table sample
  late final List<double> _roll; // baked bank angle, sampled in u

  /// Arc-length table resolution. The camera reads its position through this
  /// table, so a coarse one shows up as a shiver in the bank (which is derived
  /// from how the heading changes) long before it is visible in the motion.
  static const int _samples = 1400;
  static const int _rollSamples = 320;

  List<vm.Vector3> _controlPoints(double dock) {
    final a = Landmarks.dockA;
    final b = Landmarks.dockB;
    return <vm.Vector3>[
      vm.Vector3(a.x, a.y, a.z - dock), //  parked on the monolith
      vm.Vector3(2, 19, a.z - dock - 26), //  pull straight back
      vm.Vector3(22, 26, -42), //  climb and swing right
      vm.Vector3(40, 28, -6), //  arc around the monolith
      vm.Vector3(32, 22, 38), //  out over the treetops
      vm.Vector3(10, 14, 68), //  bank left, dropping
      vm.Vector3(-12, 7, 96), //  low across the lake
      vm.Vector3(-26, 9, 122), //  the far shore
      vm.Vector3(-14, 22, 138), //  up the plateau edge
      vm.Vector3(-2, 20, 154), //  swing onto the axis
      vm.Vector3(b.x, b.y, b.z - dock), //  parked on the pavilion panel
    ];
  }

  // ------------------------------------------------------------------ curve

  /// Catmull-Rom through the control points. [s] runs 0..segments.
  vm.Vector3 _spline(double s) {
    final n = _controls.length;
    final maxS = (n - 1).toDouble();
    final clamped = s.clamp(0.0, maxS);
    final i = clamped.floor().clamp(0, n - 2);
    final t = clamped - i;

    // Reflect the endpoints so the curve leaves and arrives in a straight
    // line — the docks must be approached square-on.
    vm.Vector3 at(int k) {
      if (k < 0) return _controls[0] * 2 - _controls[1];
      if (k > n - 1) return _controls[n - 1] * 2 - _controls[n - 2];
      return _controls[k];
    }

    final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    final t2 = t * t;
    final t3 = t2 * t;
    return (p1 * 2.0 +
            (p2 - p0) * t +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) *
        0.5;
  }

  void _buildArcTable() {
    final maxS = (_controls.length - 1).toDouble();
    _arc = List<double>.filled(_samples, 0);
    _param = List<double>.filled(_samples, 0);
    var previous = _spline(0);
    var length = 0.0;
    for (var i = 0; i < _samples; i++) {
      final s = maxS * i / (_samples - 1);
      final point = _spline(s);
      length += (point - previous).length;
      previous = point;
      _arc[i] = length;
      _param[i] = s;
    }
  }

  /// The point [u] of the way along the curve *by distance*, `u` in 0..1.
  vm.Vector3 pointAt(double u) {
    final want = _arc.last * u.clamp(0.0, 1.0);
    var lo = 0, hi = _samples - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_arc[mid] < want) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return _spline(_param[0]);
    final a = _arc[lo - 1], b = _arc[lo];
    final f = b > a ? (want - a) / (b - a) : 0.0;
    return _spline(_param[lo - 1] + (_param[lo] - _param[lo - 1]) * f);
  }

  // ------------------------------------------------------------------- bank

  /// Bakes the bank angle once, from how fast the heading turns.
  ///
  /// Deriving the bank per frame from a second difference of sampled positions
  /// reads as a shiver: the arc-length table is piecewise linear, so its
  /// curvature is mostly sampling noise. Turn *rate* is a first difference —
  /// far better behaved — and smoothing the baked curve removes what is left.
  /// What the frame reads is then a fixed table.
  void _buildRollTable() {
    final heading = List<double>.filled(_rollSamples, 0);
    var previous = 0.0;
    for (var i = 0; i < _rollSamples; i++) {
      final u = i / (_rollSamples - 1);
      final ahead = pointAt(u + 0.006);
      final behind = pointAt(u - 0.006);
      var angle = math.atan2(ahead.x - behind.x, ahead.z - behind.z);
      // Unwrap, so a heading crossing ±π does not read as a violent turn.
      if (i > 0) {
        while (angle - previous > math.pi) {
          angle -= 2 * math.pi;
        }
        while (previous - angle > math.pi) {
          angle += 2 * math.pi;
        }
      }
      previous = angle;
      heading[i] = angle;
    }

    final du = 1 / (_rollSamples - 1);
    var roll = List<double>.generate(_rollSamples, (i) {
      final lo = math.max(i - 1, 0);
      final hi = math.min(i + 1, _rollSamples - 1);
      final span = (hi - lo) * du;
      final rate = span > 0 ? (heading[hi] - heading[lo]) / span : 0.0;
      return (rate * 0.05).clamp(-0.38, 0.38);
    });

    // Three box passes: enough to take the last of the sampling grain out
    // without flattening the real turns.
    for (var pass = 0; pass < 3; pass++) {
      roll = List<double>.generate(_rollSamples, (i) {
        var sum = 0.0;
        var count = 0;
        for (var k = -3; k <= 3; k++) {
          final j = i + k;
          if (j < 0 || j >= _rollSamples) continue;
          sum += roll[j];
          count++;
        }
        return sum / count;
      });
    }
    _roll = roll;
  }

  double _rollAt(double u) {
    final x = u.clamp(0.0, 1.0) * (_rollSamples - 1);
    final i = x.floor().clamp(0, _rollSamples - 2);
    return _roll[i] + (_roll[i + 1] - _roll[i]) * (x - i);
  }

  // ------------------------------------------------------------------ shots

  /// Maps the animation's linear 0..1 onto distance along the curve: a slow
  /// reveal out of dock A, a quick cruise, a long settle into dock B.
  static double pace(double x) {
    final c = x.clamp(0.0, 1.0);
    final smoother = c * c * c * (c * (c * 6 - 15) + 10);
    return 0.30 * c + 0.70 * smoother;
  }

  /// A slow, deterministic wander — the camera ship is hand-flown, not on
  /// rails. Two detuned sines per axis, so the loop never reads as periodic.
  /// [seconds] is wall-clock into the flight, so the wobble does not speed up
  /// where the path does.
  static vm.Vector3 _wander(double seconds, double phase, double gain) {
    return vm.Vector3(
      math.sin(seconds * 0.61 + phase) * 0.62 +
          math.sin(seconds * 1.43 + phase * 2.1) * 0.24,
      math.sin(seconds * 0.47 + phase + 2.2) * 0.48 +
          math.sin(seconds * 1.19 + phase * 1.7) * 0.19,
      math.sin(seconds * 0.53 + phase + 4.0) * 0.40,
    )..scale(gain);
  }

  /// The camera at animation position [x] (0 = parked on dock A, 1 = parked on
  /// dock B).
  CameraShot shotAt(double x) {
    final u = pace(x);
    final position = pointAt(u);

    // Weights that pin the ends: the docks must be framed exactly, the middle
    // is free to look wherever the flight is going.
    final onA = 1 - _smoothstep(0.0, 0.13, u);
    final onB = _smoothstep(0.68, 0.97, u);
    final level = math.max(onA, onB);

    // Aim along the path's heading but at a fixed downward pitch, the way a
    // camera ship is flown. Following the spline's own tangent would point the
    // lens at the sky wherever the path climbs; pinning it to the ground below
    // would lose the horizon. The pitch opens with altitude, so the high pass
    // over the forest looks down and the low run across the lake looks out.
    final lookahead = pointAt(u + 0.055);
    final heading = vm.Vector3(
      lookahead.x - position.x,
      0,
      lookahead.z - position.z,
    );
    final reach = math.max(heading.length, 1e-3);
    final under = math.max(
      FlyoverWorld.instance.terrainHeight(position.x, position.z),
      FlyoverWorld.waterLevel,
    );
    final altitude = math.max(position.y - under, 0.0);
    final pitch = (0.10 + altitude / 70 * 0.45).clamp(0.10, 0.40);
    var target = position + heading - vm.Vector3(0, reach * math.tan(pitch), 0);
    target = _mix3(target, Landmarks.dockA, onA);
    target = _mix3(target, Landmarks.dockB, onB);

    // The hand-flown wander, faded out at both docks so the panels still frame
    // exactly. The aim wanders further than the body, which is what makes it
    // read as a camera operator rather than as turbulence.
    final seconds = x * duration.inMilliseconds / 1000;
    final gain = 1 - level;
    position.add(_wander(seconds, 0, gain));
    target.add(_wander(seconds, 1.9, gain * 2.4));

    final forward = target - position;
    if (forward.length2 > 1e-6) forward.normalize();
    final up = vm.Quaternion.axisAngle(forward, _rollAt(u) * gain)
        .rotate(vm.Vector3(0, 1, 0));

    // The lens widens through the cruise and returns to the dock lens at both
    // ends, so the panels still frame exactly.
    final open = _smoothstep(0.03, 0.20, u) * (1 - _smoothstep(0.78, 0.97, u));
    final fov = Landmarks.dockFovY + (_cruiseFovY - Landmarks.dockFovY) * open;

    return CameraShot(position: position, target: target, up: up, fovY: fov);
  }
}

vm.Vector3 _mix3(vm.Vector3 a, vm.Vector3 b, double t) => a + (b - a) * t;

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
