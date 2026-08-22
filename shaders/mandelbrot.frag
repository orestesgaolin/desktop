// Interactive Mandelbrot set with smooth (continuous) escape-time coloring.
// param0/param1 = view center in the complex plane, param2 = view half-height
// (zoom: smaller = deeper), param3 = unused.
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

const float TAU = 6.28318530718;
const int MAX_ITER = 300;
const float BAILOUT = 256.0;          // large bailout keeps the smooth term smooth
const float BAILOUT_SQ = 65536.0;     // BAILOUT * BAILOUT

// Cosine palette (Inigo Quilez style): a + b * cos(TAU * (c * t + d)).
// Tuned for a deep-space look: dark blues/violets in the slow-escape halo,
// warm gold/orange on the fast-escaping filaments near the boundary.
vec3 palette(float t) {
  vec3 a = vec3(0.34, 0.26, 0.44);
  vec3 b = vec3(0.42, 0.36, 0.46);
  vec3 c = vec3(1.00, 0.94, 0.78);
  vec3 d = vec3(0.08, 0.52, 0.86);
  return a + b * cos(TAU * (c * t + d));
}

// Cheap per-pixel hash in [0,1), used as sub-quantum dither noise.
float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  float halfHeight = max(abs(u.param2), 1e-7);

  // uv (y up) -> complex plane, aspect corrected, centered on (param0, param1).
  vec2 uv = (v_uv - 0.5) * 2.0;                       // [-1, 1]
  vec2 c = vec2(u.param0, u.param1) +
           vec2(uv.x * aspect, uv.y) * halfHeight;

  vec2 z = vec2(0.0);
  float m2 = 0.0;
  float iter = 0.0;
  bool escaped = false;

  for (int i = 0; i < MAX_ITER; i++) {
    // z = z^2 + c
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
    m2 = dot(z, z);
    if (m2 > BAILOUT_SQ) {
      iter = float(i) + 1.0;
      escaped = true;
      break;
    }
  }

  vec3 col;
  if (!escaped) {
    // Interior: near-black with a faint blue tint.
    col = vec3(0.008, 0.011, 0.026);
  } else {
    // Continuous (smooth) iteration count -> no banding between bands.
    float sn = iter - log2(log2(max(m2, 1.0001))) + 4.0;

    // Compress the iteration axis so deep zooms keep colour variety.
    float t = sqrt(max(sn, 0.0)) * 0.075 + u.time * 0.02;
    col = palette(t);

    // Warm the very tightly-bound filaments, darken the fast escapes so the
    // exterior falls off into deep space.
    float boundary = clamp(sn / 90.0, 0.0, 1.0);
    col = mix(col * vec3(1.35, 0.95, 0.45), col, boundary);
    col *= mix(0.22, 1.0, pow(clamp(sn / 22.0, 0.0, 1.0), 0.65));

    // Slight glow tied to the escape radius for a soft, plasma-like edge.
    float glow = clamp(log2(log2(max(m2, 1.0001))) * 0.5, 0.0, 1.0);
    col += vec3(0.05, 0.03, 0.10) * (1.0 - glow);
  }

  // Gentle vignette.
  vec2 vc = v_uv - 0.5;
  col *= 1.0 - 0.30 * dot(vc, vc) * 2.4;

  // Sub-LSB dither kills residual 8-bit banding in the smooth gradients.
  float dither = (hash21(gl_FragCoord.xy) - 0.5) / 255.0;
  col = clamp(col + dither, 0.0, 1.0);

  frag_color = vec4(col, 1.0);
}
