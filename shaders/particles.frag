// Soft gaussian star sprite, rendered with additive blending.
in vec2 v_quad;
in vec4 v_color;

out vec4 frag_color;

void main() {
  float d2 = dot(v_quad, v_quad);
  float g = exp(-d2 * 5.0) + 0.14 * exp(-d2 * 1.6);
  g *= 1.0 - smoothstep(0.75, 1.0, d2);
  frag_color = vec4(v_color.rgb * (v_color.a * g), 0.0);
}
