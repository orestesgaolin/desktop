import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../../palette.dart';
import '../page.dart';
import '../poll_qr_code.dart';
import '../vote_marquee.dart';

const _pollEndpoint = String.fromEnvironment('POLL_RESULTS_URL');
const _pollIntervalSeconds = int.fromEnvironment(
  'POLL_RESULTS_INTERVAL_SECONDS',
  defaultValue: 2,
);
final _pollInterval = Duration(seconds: math.max(1, _pollIntervalSeconds));

/// A live, data-driven audience poll.
///
/// The slide polls [POLL_RESULTS_URL] while it is mounted. With no endpoint it
/// uses an animated local feed, so the deck remains useful during rehearsal.
class Slide2 extends FlutterDeckSlideWidget {
  const Slide2({super.key})
    : super(
        configuration: const FlutterDeckSlideConfiguration(
          route: '/daily-desktop-apps',
          title: 'How many Flutter desktop apps do you use every day?',
          speakerNotes: '',
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FlutterDeckSlide.custom(
      builder: (context) => const _PollResultsView(),
    );
  }
}

class PollSnapshot {
  const PollSnapshot({required this.title, required this.options});

  factory PollSnapshot.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Poll response must be a JSON object.');
    }

    final title = (json['title'] ?? json['question'])?.toString().trim();
    final rawOptions = json['options'] ?? json['results'] ?? json['answers'];
    if (title == null || title.isEmpty || rawOptions is! List) {
      throw const FormatException(
        'Poll response needs a title and an options array.',
      );
    }

    final options = <PollOption>[];
    for (final item in rawOptions) {
      if (item is! Map) continue;
      final label =
          (item['label'] ?? item['title'] ?? item['option'] ?? item['answer'])
              ?.toString()
              .trim();
      final rawVotes = item['votes'] ?? item['count'] ?? item['value'];
      final votes = rawVotes is num
          ? rawVotes.toInt()
          : int.tryParse('$rawVotes');
      if (label == null || label.isEmpty || votes == null) continue;
      options.add(PollOption(label: label, votes: math.max(0, votes)));
    }

    if (options.isEmpty) {
      throw const FormatException('Poll response contains no valid options.');
    }
    return PollSnapshot(title: title, options: options);
  }

  final String title;
  final List<PollOption> options;

  int get totalVotes => options.fold(0, (sum, option) => sum + option.votes);
}

class PollOption {
  const PollOption({required this.label, required this.votes});

  final String label;
  final int votes;
}

class _PollResultsView extends StatefulWidget {
  const _PollResultsView();

  @override
  State<_PollResultsView> createState() => _PollResultsViewState();
}

class _PollResultsViewState extends State<_PollResultsView> {
  static const _qrOnlyDuration = Duration(seconds: 12);
  static const _demoTitle =
      'How many Flutter desktop apps do you use every day?';
  static const _demoLabels = ['None', 'One', 'Two or three', 'More than three'];

  final _random = math.Random();
  HttpClient? _client;
  Timer? _timer;
  Timer? _qrTimer;
  PollSnapshot? _snapshot;
  Object? _lastError;
  bool _fetching = false;
  bool _showResults = false;
  var _demoVotes = <int>[42, 18, 7, 2];

  bool get _isDemo => _pollEndpoint.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    if (!_isDemo) {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    }
    unawaited(_refresh(initial: true));
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
    _qrTimer = Timer(_qrOnlyDuration, () {
      if (mounted) setState(() => _showResults = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _qrTimer?.cancel();
    _client?.close(force: true);
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final next = _isDemo
          ? await _nextDemoSnapshot(initial: initial)
          : await _fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = next;
        _lastError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _lastError = error);
    } finally {
      _fetching = false;
    }
  }

  Future<PollSnapshot> _nextDemoSnapshot({required bool initial}) async {
    if (initial) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } else {
      final option = _random.nextInt(_demoVotes.length);
      final increment = 1 + _random.nextInt(3);
      _demoVotes = [..._demoVotes]..[option] += increment;
    }
    return PollSnapshot(
      title: _demoTitle,
      options: [
        for (var index = 0; index < _demoLabels.length; index++)
          PollOption(label: _demoLabels[index], votes: _demoVotes[index]),
      ],
    );
  }

  Future<PollSnapshot> _fetchSnapshot() async {
    final endpoint = Uri.parse(_pollEndpoint);
    final request = await _client!.getUrl(endpoint);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Poll endpoint returned HTTP ${response.statusCode}.',
        uri: endpoint,
      );
    }
    return PollSnapshot.fromJson(jsonDecode(body));
  }

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);
    return SlidePage(
      label: 'Audience pulse',
      child: Column(
        children: [
          Expanded(
            child: _PollStage(
              showResults: _showResults,
              snapshot: _snapshot,
              error: _lastError,
              isDemo: _isDemo,
              scale: s,
            ),
          ),
          if (pollVoteLinkLabel.isNotEmpty) ...[
            SizedBox(height: 18 * s),
            VoteMarquee(scale: s),
          ],
        ],
      ),
    );
  }
}

class _PollStage extends StatelessWidget {
  const _PollStage({
    required this.showResults,
    required this.snapshot,
    required this.error,
    required this.isDemo,
    required this.scale,
  });

  final bool showResults;
  final PollSnapshot? snapshot;
  final Object? error;
  final bool isDemo;
  final double scale;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 850);
    const curve = Curves.easeInOutCubic;
    final qrWidth = (showResults ? 270 : 420) * scale;
    final qrHeight = (showResults ? 315 : 465) * scale;

    return Stack(
      children: [
        Positioned.fill(
          right: 320 * scale,
          child: IgnorePointer(
            ignoring: !showResults,
            child: AnimatedSlide(
              duration: duration,
              curve: curve,
              offset: showResults ? Offset.zero : const Offset(-0.04, 0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOut,
                opacity: showResults ? 1 : 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: snapshot == null
                      ? _PollLoadingState(error: error, scale: scale)
                      : _PollChart(
                          key: const ValueKey('poll-chart'),
                          snapshot: snapshot!,
                          isDemo: isDemo,
                          reconnecting: error != null,
                          scale: scale,
                        ),
                ),
              ),
            ),
          ),
        ),
        AnimatedAlign(
          duration: duration,
          curve: curve,
          alignment: showResults ? Alignment.centerRight : Alignment.center,
          child: AnimatedContainer(
            duration: duration,
            curve: curve,
            width: qrWidth,
            height: qrHeight,
            child: PollQrCode(scale: scale),
          ),
        ),
      ],
    );
  }
}

class _PollLoadingState extends StatelessWidget {
  const _PollLoadingState({required this.error, required this.scale});

  final Object? error;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          SizedBox(
            width: 28 * scale,
            height: 28 * scale,
            child: CircularProgressIndicator(
              strokeWidth: 1.8 * scale,
              color: error == null ? spruce : clay,
            ),
          ),
          SizedBox(width: 22 * scale),
          Text(
            error == null
                ? 'Waiting for the first votes…'
                : 'Reconnecting to the poll…',
            style: PageText.lead(scale),
          ),
        ],
      ),
    );
  }
}

class _PollChart extends StatelessWidget {
  const _PollChart({
    super.key,
    required this.snapshot,
    required this.isDemo,
    required this.reconnecting,
    required this.scale,
  });

  final PollSnapshot snapshot;
  final bool isDemo;
  final bool reconnecting;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalVotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                snapshot.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PageText.title(scale),
              ),
            ),
            SizedBox(width: 36 * scale),
            Padding(
              padding: EdgeInsets.only(bottom: 8 * scale),
              child: _PollStatus(
                total: total,
                isDemo: isDemo,
                reconnecting: reconnecting,
                scale: scale,
              ),
            ),
          ],
        ),
        SizedBox(height: 34 * scale),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final count = snapshot.options.length;
              final gap = 14 * scale;
              final naturalHeight = count == 0
                  ? constraints.maxHeight
                  : (constraints.maxHeight - gap * (count - 1)) / count;
              final rowHeight = naturalHeight.clamp(43 * scale, 74 * scale);
              return SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < count; index++) ...[
                      _PollBar(
                        option: snapshot.options[index],
                        total: total,
                        color: _barColors[index % _barColors.length],
                        height: rowHeight,
                        scale: scale,
                      ),
                      if (index != count - 1) SizedBox(height: gap),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PollStatus extends StatelessWidget {
  const _PollStatus({
    required this.total,
    required this.isDemo,
    required this.reconnecting,
    required this.scale,
  });

  final int total;
  final bool isDemo;
  final bool reconnecting;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final status = reconnecting ? 'RECONNECTING' : (isDemo ? 'DEMO' : 'LIVE');
    final color = reconnecting ? clay : spruce;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8 * scale,
          height: 8 * scale,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        SizedBox(width: 9 * scale),
        Text(
          '$status · $total ${total == 1 ? 'vote' : 'votes'}',
          style: PageText.label(scale)
              .copyWith(color: color, letterSpacing: 1.5 * scale),
        ),
      ],
    );
  }
}

class _PollBar extends StatelessWidget {
  const _PollBar({
    required this.option,
    required this.total,
    required this.color,
    required this.height,
    required this.scale,
  });

  final PollOption option;
  final int total;
  final Color color;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : option.votes / total;
    final percent = (fraction * 100).round();
    return Semantics(
      label: option.label,
      value: '${option.votes} votes, $percent percent',
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: 232 * scale,
              child: Text(
                option.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PageText.lead(scale)
                    .copyWith(fontSize: 20 * scale, height: 1.18),
              ),
            ),
            SizedBox(width: 24 * scale),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 25 * scale,
                      color: panelHi.withValues(alpha: 0.82),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Container(
                        width: constraints.maxWidth * value,
                        height: 25 * scale,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 22 * scale),
            SizedBox(
              width: 104 * scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Text(
                  '$percent% · ${option.votes}',
                  key: ValueKey(option.votes),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16 * scale,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: ink.withValues(alpha: 0.82),
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

const _barColors = [spruce, dustyBlue, sage, clay, sand];
// ignore_for_file: file_names
