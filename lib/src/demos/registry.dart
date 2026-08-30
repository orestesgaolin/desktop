import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cube.dart';
import 'demo.dart';
import 'fullscreen.dart';
import 'particles.dart';
import 'scene_fox.dart';
import 'scene_playground.dart';
import 'scratch.dart';
import 'triangle.dart';
import 'widget_fx.dart';
import 'widget_stage.dart';

List<GpuDemo> buildDemos() {
  return <GpuDemo>[
    TriangleDemo(),
    CubeDemo(),
    ParticlesDemo(),
    _raymarch(),
    _ocean(),
    _metaballs(),
    _plasma(),
    _mandelbrot(),
    WidgetStageDemo(),
    WidgetFxDemo(),
    ScenePlaygroundDemo(),
    SceneFoxDemo(),
    buildScratchDemo(),
  ];
}

FullscreenDemo _raymarch() {
  var yaw = 0.6;
  var pitch = 0.0;
  return FullscreenDemo(
    name: 'SDF Raymarch',
    subtitle: 'Signed distance fields, soft shadows',
    hint: 'drag to orbit',
    icon: Icons.brightness_low,
    shaderName: 'RaymarchFragment',
    fragmentAsset: 'shaders/raymarch.frag',
    onFrame: (frame, params) {
      yaw -= frame.dragDelta.dx * 0.008;
      pitch = (pitch + frame.dragDelta.dy * 0.006).clamp(-0.30, 0.85);
      params[0] = yaw;
      params[1] = pitch;
    },
  );
}

FullscreenDemo _ocean() {
  var yaw = 0.0;
  var pitch = 0.0;
  return FullscreenDemo(
    name: 'Nordic Sea',
    subtitle: 'Raymarched wave heightfield',
    hint: 'drag to look around',
    icon: Icons.waves,
    shaderName: 'OceanFragment',
    fragmentAsset: 'shaders/ocean.frag',
    onFrame: (frame, params) {
      yaw -= frame.dragDelta.dx * 0.005;
      pitch = (pitch - frame.dragDelta.dy * 0.003).clamp(-0.22, 0.22);
      params[0] = yaw;
      params[1] = pitch;
    },
  );
}

FullscreenDemo _metaballs() {
  return FullscreenDemo(
    name: 'Metaballs',
    subtitle: 'Analytic 2D iso-surface',
    hint: 'move the pointer — one ball is yours',
    icon: Icons.bubble_chart,
    shaderName: 'MetaballsFragment',
    fragmentAsset: 'shaders/metaballs.frag',
  );
}

FullscreenDemo _plasma() {
  return FullscreenDemo(
    name: 'Plasma',
    subtitle: 'Domain-warped colour field',
    hint: 'pointer stirs the field',
    icon: Icons.waves_outlined,
    shaderName: 'PlasmaFragment',
    fragmentAsset: 'shaders/plasma.frag',
  );
}

FullscreenDemo _mandelbrot() {
  var cx = -0.66;
  var cy = 0.0;
  var halfH = 1.25;
  return FullscreenDemo(
    name: 'Mandelbrot',
    subtitle: 'Smooth escape-time fractal',
    hint: 'drag to pan · scroll to zoom',
    icon: Icons.all_inclusive,
    shaderName: 'MandelbrotFragment',
    fragmentAsset: 'shaders/mandelbrot.frag',
    onFrame: (frame, params) {
      final h = frame.sizeLogical.height;
      if (h > 0) {
        final scale = 2 * halfH / h;
        cx -= frame.dragDelta.dx * scale;
        cy += frame.dragDelta.dy * scale;
      }
      if (frame.scrollDelta != 0) {
        // Zoom anchored at the pointer position.
        final aspect = frame.aspect;
        final ax = (frame.pointerUv.dx - 0.5) * 2 * aspect;
        final ay = (frame.pointerUv.dy - 0.5) * 2;
        final px = cx + ax * halfH;
        final py = cy + ay * halfH;
        halfH = (halfH * math.exp(frame.scrollDelta * 0.0016)).clamp(
          3.0e-5,
          2.2,
        );
        cx = px - ax * halfH;
        cy = py - ay * halfH;
      }
      params[0] = cx;
      params[1] = cy;
      params[2] = halfH;
    },
  );
}
