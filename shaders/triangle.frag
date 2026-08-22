// Hue-cycling interpolated vertex colors.
uniform FragInfo {
  float time;
} finfo;

in vec3 v_color;
in vec2 v_pos;

out vec4 frag_color;

// Rotate hue by angle `a` (YIQ-space rotation).
vec3 hue_shift(vec3 color, float a) {
  const vec3 k = vec3(0.57735);
  float c = cos(a);
  return color * c + cross(k, color) * sin(a) + k * dot(k, color) * (1.0 - c);
}

void main() {
  vec3 col = hue_shift(v_color, finfo.time * 0.6);
  // Subtle radial shimmer from the centroid.
  float r = length(v_pos);
  col *= 0.92 + 0.16 * sin(r * 9.0 - finfo.time * 3.0);
  frag_color = vec4(pow(max(col, 0.0), vec3(0.9)), 1.0);
}
