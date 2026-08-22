uniform VertInfo {
  mat4 mvp;
  mat4 model;
} vinfo;

in vec3 position;
in vec3 normal;

out vec3 v_normal;  // world space
out vec3 v_world;
out vec3 v_local;

void main() {
  gl_Position = vinfo.mvp * vec4(position, 1.0);
  v_normal = mat3(vinfo.model) * normal;
  v_world = (vinfo.model * vec4(position, 1.0)).xyz;
  v_local = position;
}
