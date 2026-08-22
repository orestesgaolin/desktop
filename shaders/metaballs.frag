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

// Electric ramp: deep teal -> cyan -> violet -> hot magenta -> white core.
// t is a compressed measure of how deep inside the blob we are (0 edge, 1 core).
vec3 gelPalette(float t) {
  t = clamp(t, 0.0, 1.0);
  vec3 teal    = vec3(0.020, 0.310, 0.400);
  vec3 cyan    = vec3(0.110, 0.780, 0.880);
  vec3 violet  = vec3(0.420, 0.320, 0.960);
  vec3 magenta = vec3(0.980, 0.360, 0.820);
  vec3 core    = vec3(1.000, 0.880, 0.980);

  vec3 c = mix(teal, cyan, smoothstep(0.00, 0.34, t));
  c = mix(c, violet, smoothstep(0.28, 0.62, t));
  c = mix(c, magenta, smoothstep(0.58, 0.86, t));
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
  vec3 inside = gel * (0.46 + 0.62 * ndl);
  inside += gel * sheen;
  inside += vec3(0.90, 0.97, 1.00) * spec * 0.95;
  inside += mix(vec3(0.10, 0.85, 0.95), vec3(0.85, 0.35, 1.00), depth) * rim * 0.40;
  // Subsurface lift so thick regions read as translucent gel.
  inside += gel * depth * 0.22;

  // ---- background -------------------------------------------------------
  vec3 bg = vec3(0.0392, 0.0471, 0.0706);

  // Barely visible hex lattice.
  float dots = hexDots(p * 30.0);
  bg += vec3(0.055, 0.085, 0.130) * dots * 0.085;

  // Faint outer glow in the ball palette.
  float gf = clamp(field / max(threshold, 1.0e-3), 0.0, 1.0);
  float glow = gf * gf * gf * (1.0 + clamp(u.param1, -0.9, 3.0));
  vec3 glowCol = mix(vec3(0.06, 0.55, 0.72), vec3(0.62, 0.26, 0.92), gf);
  vec3 outside = bg + glowCol * glow * 0.85;

  vec3 col = mix(outside, inside, mask);

  // Crisp contour line right on the iso-surface.
  float ringX = (field - threshold) / (aa * 3.5);
  float ring = exp(-ringX * ringX);
  col += mix(vec3(0.30, 0.95, 1.00), vec3(0.95, 0.55, 1.00), depth) * ring * 0.30;

  // Gentle vignette keeps the corners deep.
  vec2 vd = v_uv - 0.5;
  col *= 1.0 - 0.55 * dot(vd, vd);

  // Filmic-ish rolloff so the cores bloom instead of clipping flat.
  col = col / (1.0 + col * 0.22);
  col = pow(max(col, vec3(0.0)), vec3(0.92));

  frag_color = vec4(col, 1.0);
}
