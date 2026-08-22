import 'package:flutter/material.dart';

import 'fullscreen.dart';

/// The starting source for the scratchpad tile: glowing neon orbit rings
/// plus a light that follows the pointer.
const String kScratchTemplate = '''
// Live GLSL, ShaderToy style. Edit and press Run (cmd+enter).
// Contract: this FragInfo block (members are optional), `in vec2 v_uv`
// with y up, and an opaque `out vec4 frag_color`.
uniform FragInfo {
  vec2 resolution;  // viewport in pixels
  vec2 pointer;     // pointer, uv space (y up)
  float time;       // seconds (respects the speed slider)
  float param0; float param1; float param2; float param3;
} u;

in vec2 v_uv;
out vec4 frag_color;

vec3 palette(float t) {
  return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void main() {
  float aspect = u.resolution.x / u.resolution.y;
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0);
  vec2 m = (u.pointer - 0.5) * vec2(aspect, 1.0);

  vec3 col = vec3(0.0);
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    vec2 q = p;
    q.x += 0.30 * sin(u.time * 0.7 + fi * 1.7);
    q.y += 0.30 * cos(u.time * 0.9 + fi * 2.3);
    float d = abs(length(q) - 0.24 - 0.05 * fi) + 0.012;
    col += palette(fi * 0.19 + u.time * 0.08) * (0.010 / d);
  }
  col += vec3(0.85, 0.95, 1.0) * (0.02 / (length(p - m) + 0.03));

  frag_color = vec4(col, 1.0);
}
''';

/// A blank-canvas fullscreen demo seeded with [kScratchTemplate]. With the
/// runtime-compilation architecture this needs no special machinery — it is
/// an ordinary [FullscreenDemo] whose fragment source is inline instead of
/// an asset.
FullscreenDemo buildScratchDemo() {
  return FullscreenDemo(
    name: 'Live Editor',
    subtitle: 'Scratchpad, start from the template',
    hint: 'edit the GLSL on the right · cmd+enter runs it',
    icon: Icons.code,
    shaderName: 'ScratchFragment',
    fragmentSource: kScratchTemplate,
    editorByDefault: true,
  );
}
