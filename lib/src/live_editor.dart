import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demos/live.dart';
import 'live_compiler.dart';

const _panelBg = Color(0xFF0D1017);
const _editorBg = Color(0xFF0A0D13);
const _dim = Color(0xFF8A93A6);
const _accent = Color(0xFF22D3EE);
const _errorRed = Color(0xFFF87171);
const _okGreen = Color(0xFF4ADE80);

/// Side panel with the GLSL source editor, Run button (cmd+enter), and the
/// impellerc error console. Compiles through [LiveShaderCompiler] and swaps
/// the result into [LiveShaderDemo].
class LiveEditorPanel extends StatefulWidget {
  const LiveEditorPanel({super.key, required this.demo});

  final LiveShaderDemo demo;

  @override
  State<LiveEditorPanel> createState() => _LiveEditorPanelState();
}

class _LiveEditorPanelState extends State<LiveEditorPanel> {
  static final LiveShaderCompiler _compiler = LiveShaderCompiler();

  late final TextEditingController _controller =
      TextEditingController(text: widget.demo.source);
  final FocusNode _editorFocus = FocusNode();

  bool _compiling = false;
  String? _errors;
  String _status = '';

  @override
  void initState() {
    super.initState();
    if (!widget.demo.hasCompiledOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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

    final source = _controller.text;
    widget.demo.source = source;
    try {
      final result = await _compiler.compile(source);
      if (!mounted) return;
      if (result.ok) {
        await widget.demo.apply(result.bytes!);
        _status = 'compiled in ${result.elapsedMs} ms';
      } else {
        _errors = result.errors;
        _status = '';
      }
    } catch (e) {
      if (!mounted) return;
      _errors = '$e';
      _status = '';
    } finally {
      if (mounted) setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _run,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _run,
      },
      child: Container(
        width: 460,
        margin: const EdgeInsets.fromLTRB(0, 0, 14, 14),
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'fragment shader · impellerc',
                      style: TextStyle(fontSize: 11, color: _dim),
                    ),
                  ),
                  if (_status.isNotEmpty && _errors == null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 11,
                          color: _compiling ? _dim : _okGreen,
                        ),
                      ),
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
                  controller: _controller,
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
                  onChanged: (text) => widget.demo.source = text,
                ),
              ),
            ),
            if (_errors != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0E12),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(13)),
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
