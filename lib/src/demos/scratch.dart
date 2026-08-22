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

// Muted tones on paper: dusty blue, sage, clay, sand, ink.
vec3 tone(int i) {
  if (i == 0) return vec3(0.42, 0.53, 0.62);
  if (i == 1) return vec3(0.56, 0.63, 0.53);
  if (i == 2) return vec3(0.76, 0.58, 0.46);
  if (i == 3) return vec3(0.84, 0.77, 0.63);
  return vec3(0.24, 0.26, 0.29);
}

void main() {
  float aspect = u.resolution.x / u.resolution.y;
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0);
  vec2 m = (u.pointer - 0.5) * vec2(aspect, 1.0);

  vec3 col = vec3(0.937, 0.925, 0.902);  // warm paper
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    vec2 q = p;
    q.x += 0.22 * sin(u.time * 0.35 + fi * 1.7);
    q.y += 0.22 * cos(u.time * 0.45 + fi * 2.3);
    float d = abs(length(q) - 0.22 - 0.06 * fi);
    float line = smoothstep(0.018, 0.004, d);
    col = mix(col, tone(i), line * 0.75);
  }
  // The pointer carries a small ink dot.
  float dm = length(p - m);
  col = mix(col, vec3(0.24, 0.26, 0.29), smoothstep(0.030, 0.012, dm) * 0.6);

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
