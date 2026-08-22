// Instanced spiral-galaxy particles. Each instance is a billboarded quad;
// its position, size, and color are derived on the GPU from a random seed.
uniform VertInfo {
  mat4 view_proj;
  vec4 cam_right;   // xyz: camera right vector (world space)
  vec4 cam_up;      // xyz: camera up vector (world space)
  float time;
  float size_scale;
} vinfo;

in vec2 corner;  // slot 0, per vertex: quad corner in [-1, 1]
in vec4 seed;    // slot 1, per instance: uniform randoms in [0, 1)

out vec2 v_quad;
out vec4 v_color;  // rgb = color, a = brightness

void main() {
  const float PI = 3.14159265359;

  float rr = pow(seed.x, 0.62);            // radial distribution, dense core
  float radius = mix(0.18, 9.5, rr);

  // Two spiral arms with angular scatter that widens with radius.
  float arm = floor(seed.y * 2.0);
  float base_ang = arm * PI + radius * 0.62;
  float scatter = (fract(seed.y * 2.0) - 0.5) * (0.5 + rr * 1.9);
  float speed = 0.9 / (0.35 + pow(radius, 0.9));  // differential rotation
  float ang = base_ang + scatter + vinfo.time * speed;

  // Thin disk that swells into a central bulge.
  float thick = mix(0.55, 0.07, smoothstep(0.0, 0.35, rr)) + rr * 0.05;
  float up = (seed.z - 0.5) * 2.0;
  float y = sign(up) * up * up * thick;

  vec3 world = vec3(cos(ang) * radius, y, sin(ang) * radius);

  // Star colors: quiet palette — warm cream core, pale ice arms, a few
  // soft aurora-green accents.
  vec3 c_core = vec3(1.00, 0.93, 0.78);
  vec3 c_arm = vec3(0.72, 0.79, 0.88);
  vec3 col = mix(c_core, c_arm, smoothstep(0.05, 0.55, rr));
  float w = fract(seed.w * 97.13);
  if (seed.w > 0.975 && rr > 0.3) {
    col = vec3(0.62, 0.78, 0.70);  // aurora accents
  } else if (seed.w < 0.02) {
    col = vec3(0.85, 0.90, 0.97);  // hot young stars
  }
  float bright = mix(0.38, 0.09, rr) * (0.45 + 0.85 * w);

  float size = vinfo.size_scale
      * mix(0.020, 0.080, pow(fract(seed.w * 7.31), 2.0))
      * (1.0 + 0.9 * (1.0 - rr));

  world += (vinfo.cam_right.xyz * corner.x + vinfo.cam_up.xyz * corner.y) * size;

  gl_Position = vinfo.view_proj * vec4(world, 1.0);
  v_quad = corner;
  v_color = vec4(col, bright);
}
