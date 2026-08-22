// Raymarched SDF playground: a twisting sphere/box morph with orbiting blobs
// melting into it (smooth-min), over a checkered floor. Soft shadows, AO,
// sky reflections, fog. Drag orbits the camera.
uniform FragInfo {
  vec2 resolution;  // viewport size in pixels
  vec2 pointer;     // pointer position, uv space (y up), 0..1
  float time;       // seconds
  float param0;     // camera yaw (radians, drag controlled)
  float param1;     // camera pitch offset (radians, drag controlled)
  float param2;
  float param3;
} u;

in vec2 v_uv;

out vec4 frag_color;

mat2 rot2(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}

float sd_sphere(vec3 p, float r) {
  return length(p) - r;
}

float sd_round_box(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float hero(vec3 p) {
  p.y -= 0.55 + 0.15 * sin(u.time * 0.8);
  p.xz = rot2(u.time * 0.3) * p.xz;
  // Gentle animated twist around Y.
  float tw = 0.55 * sin(u.time * 0.45);
  p.xz = rot2(p.y * tw) * p.xz;

  float m = 0.5 + 0.5 * sin(u.time * 0.6);
  float d = mix(sd_sphere(p, 1.0), sd_round_box(p, vec3(0.72), 0.14), m);

  // Three orbiting blobs melt in and out.
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float a = u.time * (0.7 + 0.17 * fi) + fi * 2.094395;
    vec3 c = vec3(cos(a) * 1.45, sin(a * 1.3) * 0.65, sin(a) * 1.45);
    d = smin(d, sd_sphere(p - c, 0.30), 0.45);
  }
  return d;
}

float map(vec3 p) {
  float floor_d = p.y + 1.1;
  return min(floor_d, hero(p));
}

vec3 calc_normal(vec3 p) {
  const vec2 e = vec2(1.0, -1.0) * 0.0007;
  return normalize(e.xyy * map(p + e.xyy) + e.yyx * map(p + e.yyx) +
                   e.yxy * map(p + e.yxy) + e.xxx * map(p + e.xxx));
}

float soft_shadow(vec3 ro, vec3 rd, float k) {
  float res = 1.0;
  float t = 0.02;
  for (int i = 0; i < 32; i++) {
    float h = map(ro + rd * t);
    if (h < 0.001) return 0.0;
    res = min(res, k * h / t);
    t += clamp(h, 0.02, 0.5);
    if (t > 12.0) break;
  }
  return clamp(res, 0.0, 1.0);
}

float calc_ao(vec3 p, vec3 n) {
  float occ = 0.0;
  float sca = 1.0;
  for (int i = 0; i < 5; i++) {
    float h = 0.02 + 0.11 * float(i);
    float d = map(p + n * h);
    occ += (h - d) * sca;
    sca *= 0.7;
  }
  return clamp(1.0 - 2.2 * occ, 0.0, 1.0);
}

vec3 sky(vec3 rd, vec3 sun) {
  float horizon = pow(1.0 - max(rd.y, 0.0), 3.0);
  vec3 col = mix(vec3(0.58, 0.63, 0.68), vec3(0.84, 0.82, 0.78), horizon);
  float s = max(dot(rd, sun), 0.0);
  col += vec3(1.0, 0.95, 0.85) * (pow(s, 24.0) * 0.10 + pow(s, 200.0) * 0.45);
  return col;
}

// Porcelain: a slow, subtle drift between warm white and pale grey-blue.
vec3 palette(float t) {
  return mix(vec3(0.90, 0.88, 0.84), vec3(0.70, 0.74, 0.77),
             0.5 + 0.5 * sin(6.2831853 * t));
}

void main() {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  vec2 sp = (v_uv - 0.5) * vec2(aspect, 1.0) * 2.0;

  // Orbit camera.
  float yaw = u.param0 + u.time * 0.12;
  float pitch = clamp(0.42 + u.param1, 0.08, 1.35);
  float dist = 5.0;
  vec3 target = vec3(0.0, 0.25, 0.0);
  vec3 ro = target + dist * vec3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw));
  vec3 fwd = normalize(target - ro);
  vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(right, fwd);
  vec3 rd = normalize(fwd * 1.6 + right * sp.x + up * sp.y);

  vec3 sun = normalize(vec3(0.55, 0.62, -0.42));

  // March.
  float t = 0.0;
  float d = 0.0;
  for (int i = 0; i < 96; i++) {
    d = map(ro + rd * t);
    if (d < 0.0008 * t || t > 40.0) break;
    t += d;
  }

  vec3 col;
  if (t > 40.0) {
    col = sky(rd, sun);
  } else {
    vec3 p = ro + rd * t;
    vec3 n = calc_normal(p);
    bool is_floor = hero(p) > 0.02;

    vec3 albedo;
    float gloss;
    if (is_floor) {
      float checker = mod(floor(p.x * 1.2) + floor(p.z * 1.2), 2.0);
      albedo = mix(vec3(0.62, 0.59, 0.54), vec3(0.72, 0.69, 0.63), checker);
      gloss = 0.08;
    } else {
      albedo = palette(p.y * 0.10 + u.time * 0.015);
      gloss = 0.30;
    }

    float sha = soft_shadow(p + n * 0.01, sun, 10.0);
    float ao = calc_ao(p, n);
    float diff = max(dot(n, sun), 0.0);
    float sky_amb = 0.5 + 0.5 * n.y;

    vec3 h = normalize(sun - rd);
    float spec = pow(max(dot(n, h), 0.0), 64.0);
    vec3 refl = reflect(rd, n);
    float fres = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

    col = albedo * (vec3(1.02, 0.99, 0.93) * diff * sha * 0.85 +
                    vec3(0.52, 0.55, 0.58) * sky_amb * ao);
    col += sky(refl, sun) * fres * gloss * ao * 0.8;
    col += vec3(1.0, 0.97, 0.90) * spec * sha * gloss * 0.9;

    // Distance fog toward the horizon color.
    float fog = 1.0 - exp(-0.0022 * t * t);
    col = mix(col, vec3(0.80, 0.79, 0.76), fog);
  }

  // Gentle rolloff.
  col = col / (1.0 + col * 0.25);
  col = pow(max(col, 0.0), vec3(0.92));

  frag_color = vec4(col, 1.0);
}
