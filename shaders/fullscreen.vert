// Fullscreen triangle vertex shader shared by all 2D shader-art demos.
// Expects 3 vertices: (-1,-1), (3,-1), (-1,3).
in vec2 position;

out vec2 v_uv;

void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  // uv in [0,1] across the visible viewport, y pointing up on screen.
  v_uv = position * 0.5 + 0.5;
}
