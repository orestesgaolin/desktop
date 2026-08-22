import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:marionette_flutter/marionette_flutter.dart';

import 'src/demos/demo.dart';
import 'src/demos/live.dart';
import 'src/demos/registry.dart';
import 'src/frame.dart';
import 'src/gpu_kit.dart';
import 'src/live_editor.dart';
import 'src/surface_view.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const GpuPlaygroundApp());
}

const _bg = Color(0xFF0A0C11);
const _panel = Color(0xFF10131B);
const _panelHi = Color(0xFF1A1F2C);
const _accent = Color(0xFF22D3EE);
const _accent2 = Color(0xFFA78BFA);
const _textDim = Color(0xFF8A93A6);

class GpuPlaygroundApp extends StatelessWidget {
  const GpuPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPU Playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
          surface: _panel,
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          thumbSize: WidgetStatePropertyAll(Size(14, 14)),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
        ),
      ),
      home: const BootstrapScreen(),
    );
  }
}

/// Loads the shader bundle before showing the gallery, with a useful error
/// screen if the GPU context or bundle is unavailable.
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late final Future<gpu.ShaderLibrary> _library = loadShaderLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<gpu.ShaderLibrary>(
      future: _library,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gpp_bad_outlined, size: 44),
                    const SizedBox(height: 16),
                    Text('Flutter GPU is unavailable',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    SelectableText(
                      '${snapshot.error}\n\n'
                      'This app needs the Impeller renderer and the '
                      '"$kShaderBundlePath" asset built by hook/build.dart '
                      '(requires: flutter config --enable-native-assets, '
                      'Flutter master channel).',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textDim, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return HomeShell(library: snapshot.data!);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.library});

  final gpu.ShaderLibrary library;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final List<GpuDemo> _demos = buildDemos();
  final PlaybackController _playback = PlaybackController();
  int _selected = 0;

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = _demos[_selected];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            demos: _demos,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(demo: demo, playback: _playback),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              4, 0, demo is LiveShaderDemo ? 12 : 14, 14),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const ColoredBox(color: Colors.black),
                                GpuSurfaceView(
                                  demo: demo,
                                  playback: _playback,
                                  library: widget.library,
                                ),
                                if (demo.hint.isNotEmpty)
                                  Positioned(
                                    left: 14,
                                    bottom: 12,
                                    child: _HintChip(text: demo.hint),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (demo is LiveShaderDemo) LiveEditorPanel(demo: demo),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.demos,
    required this.selected,
    required this.onSelect,
  });

  final List<GpuDemo> demos;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      color: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_accent, _accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.memory,
                      size: 20, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GPU Playground',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('Flutter GPU · Impeller',
                        style: TextStyle(fontSize: 11, color: _textDim)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: demos.length,
              itemBuilder: (context, i) => _DemoTile(
                demo: demos[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'All pixels on this screen are rendered by '
              'package:flutter_gpu render passes.',
              style: TextStyle(fontSize: 10.5, color: _textDim, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({
    required this.demo,
    required this.selected,
    required this.onTap,
  });

  final GpuDemo demo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? _panelHi : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? _accent.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(demo.icon,
                    size: 18, color: selected ? _accent : _textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(demo.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                      Text(demo.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5, color: _textDim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.demo, required this.playback});

  final GpuDemo demo;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(demo.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(demo.subtitle,
                      style: const TextStyle(fontSize: 11, color: _textDim)),
                ],
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: playback.stats,
              builder: (context, stats, _) => Text(
                stats,
                style: const TextStyle(
                  fontSize: 12,
                  color: _accent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
            ListenableBuilder(
              listenable: playback,
              builder: (context, _) => Row(
                children: [
                  SegmentedButton<double>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 10.5)),
                    ),
                    segments: const [
                      ButtonSegment(value: 0.5, label: Text('50%')),
                      ButtonSegment(value: 0.75, label: Text('75%')),
                      ButtonSegment(value: 1.0, label: Text('100%')),
                    ],
                    selected: {playback.renderScale},
                    onSelectionChanged: (s) => playback.renderScale = s.first,
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.speed, size: 15, color: _textDim),
                  SizedBox(
                    width: 110,
                    child: Slider(
                      value: playback.speed,
                      min: 0,
                      max: 2.5,
                      onChanged: (v) => playback.speed = v,
                    ),
                  ),
                  IconButton(
                    tooltip: playback.paused ? 'Play' : 'Pause',
                    onPressed: () => playback.paused = !playback.paused,
                    icon: Icon(
                      playback.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: Colors.white70)),
    );
  }
}
