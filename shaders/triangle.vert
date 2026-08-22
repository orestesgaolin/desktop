// Hello triangle: rotation + breathing scale animated on the GPU.
uniform VertInfo {
  float time;
  float aspect;  // width / height
} vinfo;

in vec2 position;
in vec3 color;

out vec3 v_color;
out vec2 v_pos;

void main() {
  float a = vinfo.time * 0.5;
  float c = cos(a);
  float s = sin(a);
  vec2 p = mat2(c, -s, s, c) * position;
  p *= 0.9 + 0.08 * sin(vinfo.time * 1.7);
  p.x /= vinfo.aspect;
  gl_Position = vec4(p, 0.0, 1.0);
  v_color = color;
  v_pos = position;
}
