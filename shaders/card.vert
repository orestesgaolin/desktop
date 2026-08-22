// Textured quad for widget-snapshot cards in the 3D carousel.
uniform VertInfo {
  mat4 mvp;
} vinfo;

in vec2 position;  // unit quad corners, [-1, 1]
in vec2 uv;

out vec2 v_uv;

void main() {
  gl_Position = vinfo.mvp * vec4(position, 0.0, 1.0);
  v_uv = uv;
}
