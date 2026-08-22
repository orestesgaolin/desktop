import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demos/demo.dart';

const _panelBg = Color(0xFF0D1017);
const _editorBg = Color(0xFF0A0D13);
const _dim = Color(0xFF8A93A6);
const _accent = Color(0xFF22D3EE);
const _errorRed = Color(0xFFF87171);
const _okGreen = Color(0xFF4ADE80);

/// GLSL editor for any demo's shader documents: one tab per stage, a Run
/// button (cmd+enter) that recompiles through impellerc and hot-swaps the
/// demo's pipelines, and an error console with impellerc line numbers.
class ShaderEditorPanel extends StatefulWidget {
  const ShaderEditorPanel({
    super.key,
    required this.demo,
    this.width = 460,
    this.margin = const EdgeInsets.fromLTRB(0, 0, 14, 14),
  });

  final GpuDemo demo;
  final double? width;
  final EdgeInsets margin;

  @override
  State<ShaderEditorPanel> createState() => _ShaderEditorPanelState();
}

class _ShaderEditorPanelState extends State<ShaderEditorPanel> {
  late List<TextEditingController> _controllers;
  final FocusNode _editorFocus = FocusNode();

  int _tab = 0;
  bool _compiling = false;
  String? _errors;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final doc in widget.demo.shaders)
        TextEditingController(text: doc.source),
    ];
    // Default to the fragment shader, which is usually the interesting one.
    final fragIndex =
        widget.demo.shaders.indexWhere((d) => d.stage == 'fragment');
    _tab = fragIndex < 0 ? 0 : fragIndex;

    // Sources may still be loading (first open of the demo); sync the
    // controllers once they arrive.
    if (!widget.demo.isReady) {
      widget.demo.ensureReady().whenComplete(() {
        if (!mounted) return;
        setState(() {
          for (var i = 0; i < _controllers.length; i++) {
            if (_controllers[i].text.isEmpty) {
              _controllers[i].text = widget.demo.shaders[i].source;
            }
          }
        });
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _editorFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_compiling) return;
    setState(() {
      _compiling = true;
      _errors = null;
      _status = 'compiling…';
    });

    for (var i = 0; i < _controllers.length; i++) {
      widget.demo.shaders[i].source = _controllers[i].text;
    }
    final stopwatch = Stopwatch()..start();
    String? error;
    try {
      error = await widget.demo.recompile();
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _errors = error;
      _status = error == null
          ? 'compiled in ${stopwatch.elapsedMilliseconds} ms'
          : '';
      _compiling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.demo.shaders;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _run,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _run,
      },
      child: Container(
        width: widget.width,
        margin: widget.margin,
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  for (var i = 0; i < docs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _TabChip(
                        label: docs[i].label,
                        selected: i == _tab,
                        onTap: () => setState(() => _tab = i),
                      ),
                    ),
                  Expanded(
                    child: _status.isNotEmpty && _errors == null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              _status,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _compiling ? _dim : _okGreen,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  FilledButton.icon(
                    onPressed: _compiling ? null : _run,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    icon: _compiling
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black54),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Run  ⌘⏎'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: _editorBg,
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: TextField(
                  key: ValueKey('doc-$_tab'),
                  controller: _controllers[_tab],
                  focusNode: _editorFocus,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  spellCheckConfiguration:
                      const SpellCheckConfiguration.disabled(),
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontFamilyFallback: ['Courier New', 'monospace'],
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFFD7DEE8),
                  ),
                  cursorColor: _accent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
            if (_errors != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0E12),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(13)),
                  border: Border(
                    top: BorderSide(color: _errorRed.withValues(alpha: 0.35)),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _errors!,
                    style: const TextStyle(
                      fontFamily: 'Menlo',
                      fontFamilyFallback: ['Courier New', 'monospace'],
                      fontSize: 11,
                      height: 1.5,
                      color: _errorRed,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _editorBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? _accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: const ['Courier New', 'monospace'],
            fontSize: 11,
            color: selected ? _accent : _dim,
          ),
        ),
      ),
    );
  }
}
