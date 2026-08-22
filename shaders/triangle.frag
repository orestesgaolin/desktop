// Interpolated vertex colors with a slow, quiet breathing.
uniform FragInfo {
  float time;
} finfo;

in vec3 v_color;
in vec2 v_pos;

out vec4 frag_color;

void main() {
  vec3 col = v_color;
  float r = length(v_pos);
  col *= 0.96 + 0.05 * sin(finfo.time * 0.8 - r * 2.6);
  frag_color = vec4(col, 1.0);
}
