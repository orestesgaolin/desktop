// Matte ceramic cube: muted per-axis face tints, thin grout seams, soft
// key light with a restrained specular and a whisper of rim.
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
    tint = vec3(0.78, 0.58, 0.46);  // clay X faces
  } else if (anrm.y > anrm.z) {
    fc = v_local.zx;
    tint = vec3(0.58, 0.66, 0.54);  // sage Y faces
  } else {
    fc = v_local.xy;
    tint = vec3(0.47, 0.57, 0.66);  // dusty blue Z faces
  }

  // Thin grout seams, antialiased with derivatives.
  vec2 gcoord = fc * 2.0;
  vec2 g = abs(fract(gcoord + 0.5) - 0.5) / max(fwidth(gcoord), vec2(1e-4));
  float seam = 1.0 - min(min(g.x, g.y) / 3.0, 1.0);

  // Slightly darker border at the face edges.
  vec2 e2 = abs(fc);
  float border = smoothstep(0.90, 1.0, max(e2.x, e2.y));

  float diff = max(dot(n, l), 0.0);
  vec3 h = normalize(l + vdir);
  float spec = pow(max(dot(n, h), 0.0), 24.0);
  float rim = pow(1.0 - max(dot(n, vdir), 0.0), 3.0);

  vec3 col = tint * (0.78 + 0.26 * diff);
  col = mix(col, col * 0.72, seam * 0.7);
  col = mix(col, col * 0.86, border);
  col += vec3(1.0, 0.98, 0.94) * spec * 0.12;
  col += vec3(1.0) * rim * 0.05;

  frag_color = vec4(col, 1.0);
}
