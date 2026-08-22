// 2D metaballs with a glossy gel look, analytic iso-surface antialiasing,
// electric teal -> violet -> magenta palette and a faint outer glow.
//
// All params are neutral at 0.0 so the shader looks correct with unset uniforms:
//   param0: iso threshold offset   (+-0.5)
//   param1: outer glow gain        (+-1.0)
//   param2: animation speed offset (+-0.6)
//   param3: specular sharpness     (+-1.0)
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
const float EPS = 1.0e-5;

// Quiet stoneware ramp: dusty blue -> sage -> clay -> warm sand core.
// t is a compressed measure of how deep inside the blob we are (0 edge, 1 core).
vec3 gelPalette(float t) {
  t = clamp(t, 0.0, 1.0);
  vec3 blue = vec3(0.420, 0.520, 0.600);
  vec3 sage = vec3(0.560, 0.630, 0.530);
  vec3 clay = vec3(0.760, 0.580, 0.460);
  vec3 sand = vec3(0.870, 0.810, 0.700);
  vec3 core = vec3(0.930, 0.890, 0.810);

  vec3 c = mix(blue, sage, smoothstep(0.00, 0.34, t));
  c = mix(c, clay, smoothstep(0.28, 0.62, t));
  c = mix(c, sand, smoothstep(0.58, 0.86, t));
  c = mix(c, core, smoothstep(0.88, 1.00, t));
  return c;
}

// Hex dot lattice, used at very low contrast to give the void some texture.
// Standard two-offset-lattice trick: the nearer of two rectangular lattices
// staggered by half a cell forms a hexagonal arrangement.
float hexDots(vec2 p) {
  vec2 s = vec2(1.0, 1.7320508);
  vec2 a = mod(p, s) - s * 0.5;
  vec2 b = mod(p - s * 0.5, s) - s * 0.5;
  vec2 g = (dot(a, a) < dot(b, b)) ? a : b;
  return smoothstep(0.30, 0.10, length(g));
}

void main() {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0);

  // One pixel measured in p-space; drives the analytic edge antialiasing.
  float px = 1.0 / max(u.resolution.y, 1.0);

  float t = u.time * (1.0 + clamp(u.param2, -0.9, 2.0) * 0.6);

  // Keep the orbits inside the viewport on both portrait and landscape.
  float ampX = 0.32 * max(aspect, 0.75);
  float ampY = 0.34;

  float field = 0.0;
  vec2 grad = vec2(0.0);

  // Six lissajous-orbiting balls with index-derived frequencies and phases.
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float ph = fi * (TAU / 6.0);

    float fx = 0.29 + fi * 0.047;
    float fy = 0.25 + fi * 0.053;

    vec2 c = vec2(
      ampX * (0.74 * sin(t * fx * 2.0 + ph * 1.7) +
              0.26 * cos(t * fy * 3.1 - ph * 0.9)),
      ampY * (0.74 * cos(t * fy * 2.0 + ph * 1.3) +
              0.26 * sin(t * fx * 3.7 + ph * 2.1))
    );

    float r = 0.075 + 0.045 * (fi / 5.0) +
              0.018 * sin(t * (0.7 + 0.11 * fi) + ph * 2.3);

    vec2 d = p - c;
    float d2 = dot(d, d) + EPS;
    float r2 = r * r;

    field += r2 / d2;
    grad += -2.0 * r2 * d / (d2 * d2);
  }

  // Seventh ball tracks the pointer.
  {
    vec2 c = (u.pointer - 0.5) * vec2(aspect, 1.0);
    float r = 0.10;
    vec2 d = p - c;
    float d2 = dot(d, d) + EPS;
    float r2 = r * r;
    field += r2 / d2;
    grad += -2.0 * r2 * d / (d2 * d2);
  }

  float threshold = 1.0 + clamp(u.param0, -0.8, 2.0) * 0.5;

  // ---- iso-surface mask -------------------------------------------------
  // The field gradient converts a pixel of screen space into field units, so
  // the smoothstep band is exactly one pixel wide everywhere on the contour.
  float gLen = length(grad);
  float aa = max(gLen * px * 1.2, 1.0e-4);
  float mask = smoothstep(threshold - aa, threshold + aa, field);

  // ---- fake 2D normal ---------------------------------------------------
  // Depth inside the blob, compressed so it saturates near ball centres.
  float depth = 1.0 - 1.0 / (1.0 + max(field - threshold, 0.0) * 0.85);
  // Flat at the core, steeply sloped at the rim -> dome shading.
  float tilt = 1.0 - depth;
  vec2 outward = -grad / max(gLen, 1.0e-5);
  vec3 n = normalize(vec3(outward * tilt * 1.45, 1.0));

  // Slowly rotating light.
  float la = t * 0.35;
  vec3 lightDir = normalize(vec3(cos(la) * 0.78, sin(la) * 0.58, 0.72));
  vec3 viewDir = vec3(0.0, 0.0, 1.0);
  vec3 halfDir = normalize(lightDir + viewDir);

  float ndl = clamp(dot(n, lightDir), 0.0, 1.0);
  float shininess = 46.0 + clamp(u.param3, -0.9, 2.0) * 30.0;
  float spec = pow(clamp(dot(n, halfDir), 0.0, 1.0), shininess);
  // Broad sheen under the tight highlight.
  float sheen = pow(clamp(dot(n, halfDir), 0.0, 1.0), 6.0) * 0.16;
  // Rim / fresnel term brightens the silhouette.
  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.6);

  vec3 gel = gelPalette(depth);
  vec3 inside = gel * (0.72 + 0.32 * ndl);
  inside += gel * sheen * 0.5;
  inside += vec3(1.00, 0.99, 0.96) * spec * 0.20;
  inside += vec3(0.95, 0.93, 0.88) * rim * 0.10;
  // Gentle lift so thick regions read as soft matte volume.
  inside += gel * depth * 0.10;

  // ---- background: warm paper with a soft contact shadow ----------------
  vec3 bg = vec3(0.937, 0.925, 0.902);

  // Barely visible dot lattice, slightly darker than the paper.
  float dots = hexDots(p * 30.0);
  bg -= vec3(0.030, 0.028, 0.026) * dots * 0.5;

  // The field falloff becomes a soft shadow under the blobs.
  float gf = clamp(field / max(threshold, 1.0e-3), 0.0, 1.0);
  float shade = gf * gf * gf * (1.0 + clamp(u.param1, -0.9, 3.0));
  vec3 outside = bg - vec3(0.16, 0.15, 0.14) * shade * 0.55;

  vec3 col = mix(outside, inside, mask);

  // Fine ink contour right on the iso-surface.
  float ringX = (field - threshold) / (aa * 3.5);
  float ring = exp(-ringX * ringX);
  col = mix(col, vec3(0.24, 0.25, 0.26), ring * 0.22);

  // The faintest vignette.
  vec2 vd = v_uv - 0.5;
  col *= 1.0 - 0.10 * dot(vd, vd);

  col = pow(max(col, vec3(0.0)), vec3(0.97));

  frag_color = vec4(col, 1.0);
}
