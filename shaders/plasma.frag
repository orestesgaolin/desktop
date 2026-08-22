// Classic oldschool plasma with domain warping and palette cycling.
uniform FragInfo {
  vec2 resolution;  // viewport size in pixels
  vec2 pointer;     // pointer position, uv space (y up), 0..1
  float time;       // seconds
  float param0;
  float param1;
  float param2;
  float param3;
} u;

in vec2 v_uv;

out vec4 frag_color;

// Cosine palette (Inigo Quilez style).
vec3 palette(float t) {
  vec3 a = vec3(0.52, 0.45, 0.61);
  vec3 b = vec3(0.40, 0.42, 0.31);
  vec3 c = vec3(1.00, 1.00, 1.00);
  vec3 d = vec3(0.00, 0.33, 0.67);
  return a + b * cos(6.2831853 * (c * t + d));
}

void main() {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0) * 6.0;
  float t = u.time * 0.6;

  // Domain warp.
  vec2 q = p;
  q += 0.8 * vec2(sin(p.y * 1.3 + t), cos(p.x * 1.1 - t * 0.8));
  q += 0.4 * vec2(sin(q.y * 2.7 - t * 1.7), sin(q.x * 2.3 + t * 1.2));

  // Layered plasma waves.
  float v = 0.0;
  v += sin(q.x * 1.4 + t);
  v += sin((q.y + t) * 1.1);
  v += sin((q.x + q.y) * 0.9 + t * 1.4);
  float r = length(q - vec2(sin(t * 0.7) * 2.0, cos(t * 0.9) * 2.0));
  v += sin(r * 1.8 - t * 2.0);
  v *= 0.25;

  // Pointer adds a local ripple.
  vec2 m = (u.pointer - 0.5) * vec2(aspect, 1.0) * 6.0;
  float dm = length(p - m);
  v += 0.35 * sin(dm * 4.0 - t * 4.0) * exp(-dm * 0.7);

  vec3 col = palette(v * 0.9 + t * 0.05);
  // Gentle vignette.
  float vig = 1.0 - 0.35 * dot(v_uv - 0.5, v_uv - 0.5) * 2.4;
  col *= vig;

  frag_color = vec4(col, 1.0);
}
