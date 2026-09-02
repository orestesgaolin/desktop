import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../palette.dart';

const pollVoteUrl = String.fromEnvironment(
  'POLL_VOTE_URL',
  defaultValue: 'https://roszkowski.dev/vote',
);
const pollVoteLabel = String.fromEnvironment(
  'POLL_VOTE_LABEL',
  defaultValue: 'roszkowski.dev/vote',
);

String get pollVoteLinkLabel {
  if (pollVoteLabel.trim().isNotEmpty) return pollVoteLabel.trim();
  if (pollVoteUrl.trim().isEmpty) return '';
  final uri = Uri.tryParse(pollVoteUrl.trim());
  if (uri == null || uri.host.isEmpty) return pollVoteUrl.trim();
  final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/$'), '');
  return '${uri.host}$path';
}

class VoteMarquee extends StatefulWidget {
  const VoteMarquee({super.key, required this.scale});

  final double scale;

  @override
  State<VoteMarquee> createState() => _VoteMarqueeState();
}

class _VoteMarqueeState extends State<VoteMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 18 * widget.scale,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5 * widget.scale,
      color: paper,
    );
    final phrase = 'VOTE NOW  ↗  $pollVoteLinkLabel      ';

    return Semantics(
      label: 'Vote at ${pollVoteUrl.trim()}',
      child: Container(
        height: 54 * widget.scale,
        color: spruce,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final phrasePainter = TextPainter(
                text: TextSpan(text: phrase, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              final repetitions = math.max(
                2,
                (constraints.maxWidth / phrasePainter.width).ceil(),
              );
              final segment = List.filled(repetitions, phrase).join();
              final segmentPainter = TextPainter(
                text: TextSpan(text: segment, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              final segmentWidth = segmentPainter.width;

              Widget copy(double left) => Positioned(
                left: left,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      segment,
                      maxLines: 1,
                      softWrap: false,
                      style: style,
                    ),
                  ),
                ),
              );

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final offset = _controller.value * segmentWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [copy(-offset), copy(segmentWidth - offset)],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
