// Neon "tron" cube: per-axis face tint, pulsing grid lines, glowing edges,
// blinn-phong key light + rim.
uniform FragInfo {
  vec4 light_dir;   // xyz: direction TO the light, normalized
  vec4 camera_pos;  // xyz
  float time;
} finfo;

in vec3 v_normal;
in vec3 v_world;
in vec3 v_local;

out vec4 frag_color;

void main() {
  vec3 n = normalize(v_normal);
  vec3 vdir = normalize(finfo.camera_pos.xyz - v_world);
  vec3 l = normalize(finfo.light_dir.xyz);

  // Face-local 2D coordinates (tangential axes of the face being shaded).
  vec3 anrm = abs(n);
  vec2 fc;
  vec3 tint;
  if (anrm.x > anrm.y && anrm.x > anrm.z) {
    fc = v_local.yz;
    tint = vec3(1.0, 0.30, 0.62);   // magenta X faces
  } else if (anrm.y > anrm.z) {
    fc = v_local.zx;
    tint = vec3(0.25, 0.90, 1.00);  // cyan Y faces
  } else {
    fc = v_local.xy;
    tint = vec3(1.00, 0.62, 0.25);  // amber Z faces
  }

  // Glowing border of each face.
  vec2 e2 = abs(fc);
  float edge = max(e2.x, e2.y);
  float glow_edge = smoothstep(0.80, 0.98, edge);

  // Animated inner grid (antialiased with derivatives).
  vec2 gcoord = fc * 2.0;
  vec2 g = abs(fract(gcoord + 0.5) - 0.5) / max(fwidth(gcoord), vec2(1e-4));
  float grid_line = 1.0 - min(min(g.x, g.y), 1.0);
  float pulse = 0.5 + 0.5 * sin(finfo.time * 2.0 - (fc.x + fc.y) * 2.2);

  float diff = max(dot(n, l), 0.0);
  vec3 h = normalize(l + vdir);
  float spec = pow(max(dot(n, h), 0.0), 48.0);
  float rim = pow(1.0 - max(dot(n, vdir), 0.0), 3.0);

  vec3 col = vec3(0.05, 0.06, 0.09) * (0.35 + 0.85 * diff);
  col += tint * grid_line * (0.20 + 0.45 * pulse);
  col += tint * glow_edge * (0.85 + 0.40 * pulse);
  col += vec3(1.0) * spec * 0.55;
  col += tint * rim * 0.35;

  frag_color = vec4(col, 1.0);
}
