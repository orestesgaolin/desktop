// Shades a widget snapshot (premultiplied alpha) on the carousel: backside
// dimming, a cyan edge glow on front-facing cards, and a floor-reflection
// fade. All output stays premultiplied for one-oneMinusSourceAlpha blending.
uniform FragInfo {
  float facing;      // 0 (facing away) .. 1 (facing the camera)
  float reflection;  // 0 = the card, 1 = its mirrored floor reflection
  float time;
} finfo;

uniform sampler2D card_tex;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 tex = texture(card_tex, v_uv);

  float bright = mix(0.55, 1.0, finfo.facing);
  vec3 col = tex.rgb * bright;
  float alpha = tex.a;

  if (finfo.reflection > 0.5) {
    // v_uv.y == 1 is the card's top edge; on the mirrored quad that edge sits
    // farthest from the floor, so fade toward it.
    float fade = 0.26 * pow(1.0 - v_uv.y, 1.8);
    col *= fade;
    alpha *= fade;
  }

  frag_color = vec4(col, alpha);
}
