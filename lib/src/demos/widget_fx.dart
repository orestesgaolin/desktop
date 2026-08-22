import 'package:flutter/material.dart';

import '../frame.dart';
import '../gpu_widgets.dart';
import 'demo.dart';

const _ink = Color(0xFF2C2E31);
const _dim = Color(0xFF8B8578);
const _accent = Color(0xFF4F6F6A);

/// GpuShaderSampler in action: a real, interactive widget with a Flutter GPU
/// fragment shader applied over it, flutter_shaders' AnimatedSampler style.
/// The child is captured through flutter_scene's WidgetTexture and stays
/// fully interactive — input is forwarded through the effect.
class WidgetFxDemo extends WidgetHostedDemo {
  @override
  String get name => 'Widget FX';
  @override
  String get subtitle => 'GpuShaderSampler over a live widget';
  @override
  String get hint => 'pick an effect — the card keeps working underneath';
  @override
  IconData get icon => Icons.auto_fix_high;

  @override
  Widget buildView(BuildContext context, PlaybackController playback) {
    return _FxView(key: ObjectKey(this), playback: playback);
  }
}

const String _kFragHeader = '''
uniform FragInfo {
  vec2 resolution;
  vec2 pointer;     // uv space, y up
  float time;
  float param0; float param1; float param2; float param3;
} u;

uniform sampler2D u_child;

in vec2 v_uv;

out vec4 frag_color;
''';

/// Identity: proves capture fidelity (and keeps child state when selected).
const String _kFxNone = '''
$_kFragHeader
void main() {
  frag_color = texture(u_child, vec2(v_uv.x, 1.0 - v_uv.y));
}
''';

/// Gentle water ripple emanating from the pointer. param0 = intensity.
const String _kFxRipple = '''
$_kFragHeader
void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  vec2 pt = vec2(u.pointer.x, 1.0 - u.pointer.y);
  vec2 asp = vec2(u.resolution.x / u.resolution.y, 1.0);
  vec2 d = (uv - pt) * asp;
  float dist = length(d);
  float wave = sin(dist * 46.0 - u.time * 4.2) * exp(-dist * 3.6);
  vec2 dir = d / max(dist, 1.0e-4);
  vec2 offset = dir * wave * 0.011 * (0.15 + u.param0) / asp;
  vec4 c = texture(u_child, uv + offset);
  c.rgb *= 1.0 + wave * 0.10 * (0.15 + u.param0);
  frag_color = c;
}
''';

/// Ink halftone print: the child re-screened as dots on its own alpha.
/// param0 = dot size bias.
const String _kFxHalftone = '''
$_kFragHeader
void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  float cells = mix(90.0, 44.0, clamp(u.param0, 0.0, 1.0));
  vec2 asp = vec2(u.resolution.x / u.resolution.y, 1.0);
  vec2 g = uv * asp * cells;
  vec2 cell = (floor(g) + 0.5) / cells / asp;
  vec4 s = texture(u_child, cell);
  float a = max(s.a, 1.0e-4);
  float lum = dot(s.rgb / a, vec3(0.299, 0.587, 0.114));
  float radius = (1.0 - lum) * 0.58 + 0.04;
  float d = length(fract(g) - 0.5);
  float dotMask = smoothstep(radius, radius - 0.14, d);
  // Ink dots over faint paper, masked by the child's own alpha.
  vec3 ink = vec3(0.173, 0.180, 0.192);
  vec3 paper = vec3(0.965, 0.955, 0.935);
  vec3 col = mix(paper, ink, dotMask);
  frag_color = vec4(col * s.a, s.a);
}
''';

/// Frosted glass: jittered multi-tap blur with a cool tint.
/// param0 = frost strength.
const String _kFxFrost = '''
$_kFragHeader
vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453) - 0.5;
}

void main() {
  vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
  float amount = (0.004 + 0.016 * clamp(u.param0, 0.0, 1.0));
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 6; i++) {
    vec2 j = hash2(uv * u.resolution.xy + float(i) * 17.31) * amount;
    acc += texture(u_child, uv + j);
  }
  vec4 c = acc / 6.0;
  // Cool, slightly lifted tint.
  c.rgb = mix(c.rgb, vec3(0.80, 0.84, 0.86) * c.a, 0.14);
  frag_color = c;
}
''';

class _Effect {
  const _Effect(this.name, this.source);
  final String name;
  final String source;
}

const List<_Effect> _effects = [
  _Effect('None', _kFxNone),
  _Effect('Ripple', _kFxRipple),
  _Effect('Halftone', _kFxHalftone),
  _Effect('Frost', _kFxFrost),
];

class _FxView extends StatefulWidget {
  const _FxView({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<_FxView> createState() => _FxViewState();
}

class _FxViewState extends State<_FxView> {
  int _effect = 1;
  double _intensity = 0.6;
  double _fps = 0;
  int _statTicks = 0;

  void _onTick(double rawDt) {
    if (rawDt > 0) {
      _fps = _fps == 0 ? 1 / rawDt : _fps * 0.95 + (1 / rawDt) * 0.05;
    }
    if (++_statTicks >= 20) {
      _statTicks = 0;
      widget.playback.stats.value = '${_fps.round()} fps · GpuShaderSampler';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEFECE6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _effects.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(_effects[i].name,
                          style: const TextStyle(fontSize: 12)),
                      selected: _effect == i,
                      selectedColor: _accent.withValues(alpha: 0.16),
                      onSelected: (_) => setState(() => _effect = i),
                    ),
                  ),
                const SizedBox(width: 16),
                const Icon(Icons.opacity, size: 15, color: _dim),
                SizedBox(
                  width: 130,
                  child: Slider(
                    value: _intensity,
                    onChanged: (v) => setState(() => _intensity = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 420,
                height: 290,
                child: ListenableBuilder(
                  listenable: widget.playback,
                  builder: (context, _) => GpuShaderSampler(
                    fragmentSource: _effects[_effect].source,
                    paused: widget.playback.paused,
                    timeScale: widget.playback.speed,
                    onParams: (params) => params[0] = _intensity,
                    onTick: _onTick,
                    child: const Center(child: _FxCard()),
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 18),
            child: Text(
              'The card is a real widget, captured by flutter_scene\'s '
              'WidgetTexture and redrawn through a runtime-compiled Flutter '
              'GPU fragment shader. Pointer input is forwarded, so it works '
              'under any effect.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _dim, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live subject: state, animation, and controls all keep running while
/// an effect re-renders it.
class _FxCard extends StatefulWidget {
  const _FxCard();

  @override
  State<_FxCard> createState() => _FxCardState();
}

class _FxCardState extends State<_FxCard> {
  int _taps = 0;
  bool _enabled = true;
  double _amount = 0.4;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x212C2E31)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A2C2E31), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_accent, Color(0xFFC6947A)]),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.spa, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fjällen',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _ink)),
                    Text('a real, live widget',
                        style: TextStyle(fontSize: 11, color: _dim)),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                activeThumbColor: _accent,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Amount',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _ink)),
              Expanded(
                child: Slider(
                  value: _amount,
                  activeColor: _accent,
                  onChanged:
                      _enabled ? (v) => setState(() => _amount = v) : null,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: _amount,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                  backgroundColor: const Color(0x142C2E31),
                  color: _accent,
                ),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: () => setState(() => _taps++),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('Taps: $_taps',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
