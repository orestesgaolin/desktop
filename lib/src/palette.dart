import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart' as vm;

/// The quiet Scandinavian palette shared by the deck, the gallery chrome and
/// the 3D landscape.
///
/// The values are sRGB, the way Flutter wants them. flutter_scene wants linear
/// colour, so anything handed to a material goes through [linear] first.
const paper = Color(0xFFEFECE6); // warm paper
const panel = Color(0xFFF5F3EE);
const panelHi = Color(0xFFE8E4DB);
const ink = Color(0xFF2C2E31);
const textDim = Color(0xFF8B8578);

const spruce = Color(0xFF4F6F6A);
const clay = Color(0xFFC6947A);
const sage = Color(0xFF8CA185);
const dustyBlue = Color(0xFF6B879E);
const sand = Color(0xFFD4C29E);

/// sRGB → linear, the transfer function Impeller applies in reverse when it
/// resolves a frame. Materials take linear colour, so a palette entry pasted
/// straight into `baseColorFactor` renders too bright and too saturated.
double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// The linear RGBA a flutter_scene material needs for [color].
vm.Vector4 linear(Color color, {double alpha = 1.0}) => vm.Vector4(
      _toLinear(color.r),
      _toLinear(color.g),
      _toLinear(color.b),
      alpha,
    );

/// The linear RGB of [color], for the fields that take a bare `Vector3`
/// (sky colours, fog, light tint).
vm.Vector3 linear3(Color color) => vm.Vector3(
      _toLinear(color.r),
      _toLinear(color.g),
      _toLinear(color.b),
    );
