import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// A selectable Dart snippet using Flutter's TextMate-based highlighter.
class DartCodeSnippet extends StatelessWidget {
  const DartCodeSnippet({super.key, required this.code, required this.style});

  final String code;
  final TextStyle style;

  static final Future<Highlighter> _highlighter = _loadHighlighter();

  static Future<Highlighter> _loadHighlighter() async {
    await Highlighter.initialize(['dart']);
    final theme = await HighlighterTheme.loadDarkTheme();
    return Highlighter(language: 'dart', theme: theme);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Highlighter>(
    future: _highlighter,
    builder: (context, snapshot) {
      final highlighter = snapshot.data;
      if (highlighter == null) {
        return SelectableText(code, style: style);
      }
      return SelectableText.rich(highlighter.highlight(code), style: style);
    },
  );
}

/// A small Swift highlighter for the native snippets used by the window demo.
class SwiftCodeSnippet extends StatelessWidget {
  const SwiftCodeSnippet({super.key, required this.code, required this.style});

  final String code;
  final TextStyle style;

  static final _token = RegExp(
    r'//.*|"(?:\\.|[^"\\])*"|\b(?:class|else|false|func|guard|if|in|let|nil|private|return|self|true|var|weak)\b|\b\d+(?:\.\d+)?\b|\b[A-Z][A-Za-z0-9_]*\b',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _token.allMatches(code)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: code.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      spans.add(TextSpan(text: token, style: _styleFor(token)));
      cursor = match.end;
    }
    if (cursor < code.length) {
      spans.add(TextSpan(text: code.substring(cursor)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  TextStyle _styleFor(String token) {
    if (token.startsWith('//')) {
      return const TextStyle(color: Color(0xFF6A9955));
    }
    if (token.startsWith('"')) {
      return const TextStyle(color: Color(0xFFC3E88D));
    }
    if (RegExp(r'^\d').hasMatch(token)) {
      return const TextStyle(color: Color(0xFFF78C6C));
    }
    if (RegExp(r'^[A-Z]').hasMatch(token)) {
      return const TextStyle(color: Color(0xFF82AAFF));
    }
    return const TextStyle(color: Color(0xFFC792EA));
  }
}
