// Raymarched stylized ocean at golden hour.
//
// A choppy sine heightfield is intersected with a fixed-step scan plus binary
// refinement, then shaded with a Schlick fresnel blend of a golden-hour sky
// gradient against a deep teal water body, a two-lobe sun glint, crest foam
// and distance fog.
//
// param0 = camera yaw (radians, drag horizontally)
// param1 = camera pitch offset (radians, small, drag vertically)
// param2 / param3 = unused.
uniform FragInfo {
  vec2 resolution;  // viewport size in pixels
  vec2 pointer;     // pointer position, uv space (y up), 0..1
  float time;       // seconds
  float param0;     // camera yaw in radians (drag-controlled from Dart)
  float param1;     // camera pitch offset in radians (drag-controlled, small)
  float param2;
  float param3;
} u;

in vec2 v_uv;

out vec4 frag_color;

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

const float EYE_HEIGHT   = 3.5;
const float BASE_PITCH   = -0.085;      // slight downward tilt
const float TAN_HALF_FOV = 0.5773503;   // tan(30 deg) -> 60 deg vertical FOV

// Heightfield: 5 octaves, freq x1.9 and amp x0.45 per octave.
const float BASE_AMP  = 0.6;
const float BASE_FREQ = 0.16;
const float AMP_GAIN  = 0.45;
const float W_MEAN    = 0.18;   // mean of the sharpened wave term, keeps h ~ zero mean
const float H_MAX     =  0.95;  // conservative bounds of the heightfield
const float H_MIN     = -0.30;

// 1.9 * rotation by ~33 degrees, column-major.
const mat2 OCT_STEP = mat2(1.5943, 1.0336, -1.0336, 1.5943);

const int   MARCH_STEPS  = 64;
const int   REFINE_STEPS = 6;   // 64 + 6 = 70 heightfield evaluations worst case
const float T_MAX        = 60.0;

// Sun sits at a fixed world azimuth so dragging the yaw sweeps it into view.
const float SUN_AZIMUTH   = 0.62;
const float SUN_ELEVATION = 0.055;

const vec3 SKY_ZENITH  = vec3(0.340, 0.400, 0.470);  // pale slate
const vec3 SKY_TEAL    = vec3(0.520, 0.570, 0.600);  // grey mid band
const vec3 SKY_HORIZON = vec3(0.880, 0.830, 0.730);  // pale gold haze
const vec3 SUN_TINT    = vec3(1.000, 0.930, 0.790);
const vec3 WATER_DEEP  = vec3(0.055, 0.085, 0.095);
const vec3 WATER_CREST = vec3(0.150, 0.205, 0.205);

// ---------------------------------------------------------------------------
// Hash / value noise (used only for foam breakup and output dither)
// ---------------------------------------------------------------------------

float hash21(vec2 p) {
  p = fract(p * vec2(233.34, 851.73));
  p += dot(p, p + 23.45);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = p - i;
  vec2 w = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// ---------------------------------------------------------------------------
// Heightfield
// ---------------------------------------------------------------------------

// Two crossing wave trains per octave. `1 - abs(sin)` puts the peak at the
// zero crossing, and squaring it narrows the peak into a crest while leaving a
// broad flat trough -- the classic chop silhouette.
float oceanHeight(vec2 p, int octaves) {
  vec2 q = p;
  float amp = BASE_AMP;
  float speed = 1.0;
  float h = 0.0;

  for (int i = 0; i < 5; i++) {
    if (i >= octaves) {
      break;
    }
    float phase = u.time * speed;
    float a = 1.0 - abs(sin(q.x * BASE_FREQ + phase));
    float b = 1.0 - abs(sin(q.y * BASE_FREQ * 1.27 - phase * 0.81 + 2.1));
    float w = a * 0.62 + b * 0.38;
    w *= w;                        // sharpen the crest
    h += (w - W_MEAN) * amp;

    q = OCT_STEP * q;              // rotate + scale coords => frequency x1.9
    amp *= AMP_GAIN;
    speed *= 1.28;
  }
  return h;
}

// Central differences, 4 octaves, epsilon widened with distance so the far
// field low-passes itself instead of aliasing.
vec3 oceanNormal(vec2 p, float dist) {
  float e = clamp(dist * 0.006, 0.02, 1.2);
  float hx = oceanHeight(p + vec2(e, 0.0), 4) - oceanHeight(p - vec2(e, 0.0), 4);
  float hz = oceanHeight(p + vec2(0.0, e), 4) - oceanHeight(p - vec2(0.0, e), 4);
  return normalize(vec3(-hx, 2.0 * e, -hz));
}

// ---------------------------------------------------------------------------
// Sky
// ---------------------------------------------------------------------------

vec3 sunDirection() {
  float ce = cos(SUN_ELEVATION);
  return normalize(vec3(sin(SUN_AZIMUTH) * ce, sin(SUN_ELEVATION), cos(SUN_AZIMUTH) * ce));
}

// Gradient + atmospheric glow, no disk.
vec3 skyDome(vec3 rd, vec3 sunDir) {
  float up = clamp(rd.y, 0.0, 1.0);

  // Warm orange at the horizon -> teal -> indigo overhead.
  vec3 col = mix(SKY_HORIZON, SKY_TEAL, smoothstep(0.0, 0.16, up));
  col = mix(col, SKY_ZENITH, smoothstep(0.10, 0.72, up));

  // Below-horizon rays (reflection lookups) keep the horizon colour.
  col = mix(SKY_HORIZON * 0.72, col, smoothstep(-0.05, 0.01, rd.y));

  float sd = max(dot(rd, sunDir), 0.0);
  col += SUN_TINT * 0.55 * pow(sd, 6.0);              // broad haze
  col += SUN_TINT * 1.10 * pow(sd, 90.0);             // tight bloom
  return col;
}

float sunDisk(vec3 rd, vec3 sunDir) {
  float sd = dot(rd, sunDir);
  return smoothstep(0.99950, 0.99978, sd);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  vec2 sc = (v_uv - 0.5) * 2.0;   // [-1,1], y up

  // Camera basis from yaw / pitch.
  float yaw = u.param0;
  float pitch = clamp(BASE_PITCH + u.param1, -0.55, 0.35);
  float cp = cos(pitch);
  vec3 fwd = vec3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp);
  vec3 right = vec3(cos(yaw), 0.0, -sin(yaw));
  vec3 upv = cross(fwd, right);

  vec3 ro = vec3(0.0, EYE_HEIGHT, 0.0);
  vec3 rd = normalize(fwd
                      + right * (sc.x * aspect * TAN_HALF_FOV)
                      + upv * (sc.y * TAN_HALF_FOV));

  vec3 sunDir = sunDirection();

  // Slab the ray against the heightfield bounds; everything above the horizon
  // (or too shallow to reach the water inside T_MAX) is pure sky.
  bool hit = false;
  float tHit = T_MAX;
  if (rd.y < -1e-4) {
    float invDown = 1.0 / (-rd.y);
    float t0 = (ro.y - H_MAX) * invDown;
    if (t0 < T_MAX) {
      float tEnd = min((ro.y - H_MIN) * invDown, T_MAX);
      t0 = max(t0, 0.0);
      float span = max(tEnd - t0, 0.0);

      // Scan with a mildly front-loaded step so the near field is finer.
      float tPrev = t0;
      for (int i = 1; i <= MARCH_STEPS; i++) {
        float s = float(i) / float(MARCH_STEPS);
        float t = t0 + span * (s * s * 0.55 + s * 0.45);
        float d = (ro.y + rd.y * t) - oceanHeight(ro.xz + rd.xz * t, 5);
        if (d < 0.0) {
          // Binary refinement across the sign change.
          float lo = tPrev;
          float hi = t;
          for (int k = 0; k < REFINE_STEPS; k++) {
            float mid = 0.5 * (lo + hi);
            float dm = (ro.y + rd.y * mid) - oceanHeight(ro.xz + rd.xz * mid, 5);
            if (dm < 0.0) {
              hi = mid;
            } else {
              lo = mid;
            }
          }
          tHit = 0.5 * (lo + hi);
          hit = true;
          break;
        }
        tPrev = t;
      }
    }
  }

  vec3 col;

  if (!hit) {
    col = skyDome(rd, sunDir) + SUN_TINT * 4.5 * sunDisk(rd, sunDir);
  } else {
    vec3 pos = ro + rd * tHit;
    vec3 n = oceanNormal(pos.xz, tHit);
    vec3 view = -rd;

    float h = oceanHeight(pos.xz, 4);
    float hn = clamp(h / 0.85, -0.4, 1.0);
    float steep = clamp((1.0 - n.y) * 7.0, 0.0, 1.0);

    // Body colour: deep teal troughs, lighter/greener crests.
    vec3 body = mix(WATER_DEEP, WATER_CREST, clamp(hn * 0.75 + steep * 0.35, 0.0, 1.0));
    body *= mix(0.72, 1.0, clamp(hn * 0.5 + 0.5, 0.0, 1.0));   // darken the depths

    // Sky reflection, kept above the horizon so grazing normals stay sane.
    vec3 refl = reflect(rd, n);
    refl.y = max(refl.y, 0.006);
    refl = normalize(refl);
    // No sun disk in the reflection -- a 1.5 deg disk sampled through a noisy
    // normal turns into fireflies. The specular lobe below covers it smoothly.
    vec3 reflCol = skyDome(refl, sunDir);

    // Schlick fresnel.
    float ndv = clamp(dot(n, view), 0.0, 1.0);
    float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
    fres = clamp(fres, 0.0, 1.0);

    col = mix(body, reflCol, fres);

    // Sun glint: a tight lobe plus a broader, hash-modulated glitter path.
    vec3 hv = normalize(sunDir + view);
    float ndh = max(dot(n, hv), 0.0);
    float tight = pow(ndh, 720.0);
    float broad = pow(ndh, 42.0);
    float sparkle = vnoise(pos.xz * 5.5 + vec2(u.time * 0.7, -u.time * 0.5));
    sparkle = smoothstep(0.35, 0.95, sparkle);
    col += SUN_TINT * (tight * 3.2 + broad * 0.55 * (0.35 + 0.65 * sparkle));

    // Foam on the sharpest crests, broken up by high-frequency noise.
    float crest = smoothstep(0.42, 0.80, hn) * (0.45 + 0.55 * steep);
    float fnoise = vnoise(pos.xz * 1.6 + vec2(u.time * 0.25, u.time * -0.18)) * 0.62
                 + vnoise(pos.xz * 4.7 - vec2(u.time * 0.55, u.time * 0.4)) * 0.38;
    float foam = crest * smoothstep(0.42, 0.78, fnoise);
    foam *= exp(-tHit * 0.055);   // fade out with distance
    col = mix(col, vec3(0.92, 0.88, 0.80), clamp(foam * 0.8, 0.0, 1.0));

    // Distance fog. Fading into skyDome() along the *view* ray makes the far
    // water meet the sky continuously, so the horizon needs no seam fixup.
    vec3 fogCol = skyDome(rd, sunDir) * 0.96;
    float fog = 1.0 - exp(-tHit * 0.030);
    fog = clamp(fog + smoothstep(0.90, 1.0, tHit / T_MAX) * 0.35, 0.0, 1.0);
    col = mix(col, fogCol, fog);
  }

  // Tonemap + gentle vignette.
  col = 1.0 - exp(-col * 1.25);
  float vig = 1.0 - 0.26 * dot(v_uv - 0.5, v_uv - 0.5) * 2.4;
  col *= vig;

  // Sub-LSB dither against banding in the sky gradient.
  col = clamp(col + (hash21(gl_FragCoord.xy) - 0.5) / 255.0, 0.0, 1.0);

  frag_color = vec4(col, 1.0);
}
