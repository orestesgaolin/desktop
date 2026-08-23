import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../palette.dart';

/// Shared chrome for every slide in the deck.
///
/// flutter_deck's own templates are deliberately not used: the deck has one
/// quiet Scandinavian layout — a wide left margin, a hairline rule, an
/// uppercase section label and a slide number in the corner — and every slide
/// is a variation on it.
///
/// Type scales with the window (the deck runs responsive, not letterboxed, so
/// the 3D slide and the gallery slide get real pixels), anchored on a 1440 pt
/// design width.
class SlidePage extends StatelessWidget {
  const SlidePage({
    super.key,
    required this.child,
    this.label,
    this.showNumber = true,
    this.padded = true,
  });

  final Widget child;

  /// Small uppercase section label above the content.
  final String? label;

  final bool showNumber;
  final bool padded;

  /// Type scale for the current window, clamped so a very small or very wide
  /// window still reads.
  static double scaleOf(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 1440).clamp(0.62, 1.7);

  @override
  Widget build(BuildContext context) {
    final s = scaleOf(context);
    final deck = context.flutterDeck;

    return Padding(
      padding: padded
          ? EdgeInsets.fromLTRB(112 * s, 84 * s, 112 * s, 64 * s)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!.toUpperCase(), style: PageText.label(s)),
            SizedBox(height: 10 * s),
            Container(width: 46 * s, height: 1.4, color: spruce),
            SizedBox(height: 34 * s),
          ],
          Expanded(child: child),
          if (showNumber) ...[
            SizedBox(height: 24 * s),
            Row(
              children: [
                Text('Lorem Ipsum · Flutter GPU', style: PageText.footer(s)),
                const Spacer(),
                Text(
                  '${deck.slideNumber.toString().padLeft(2, '0')}'
                  ' / ${deck.router.slides.length.toString().padLeft(2, '0')}',
                  style: PageText.footer(s),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The deck's type ramp. Every size is a multiple of the window scale so the
/// layout holds together from a laptop panel to a projector.
abstract final class PageText {
  static TextStyle display(double s) => TextStyle(
        fontSize: 82 * s,
        height: 1.05,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.6 * s,
        color: ink,
      );

  static TextStyle title(double s) => TextStyle(
        fontSize: 52 * s,
        height: 1.12,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.8 * s,
        color: ink,
      );

  static TextStyle lead(double s) => TextStyle(
        fontSize: 26 * s,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: ink.withValues(alpha: 0.78),
      );

  static TextStyle body(double s) => TextStyle(
        fontSize: 19 * s,
        height: 1.72,
        fontWeight: FontWeight.w400,
        color: ink.withValues(alpha: 0.70),
      );

  static TextStyle label(double s) => TextStyle(
        fontSize: 12.5 * s,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.6 * s,
        color: spruce,
      );

  static TextStyle footer(double s) => TextStyle(
        fontSize: 12.5 * s,
        letterSpacing: 0.6 * s,
        color: textDim,
      );
}

/// A bulleted list in the deck's voice: a hairline square marker, generous
/// leading, and no list punctuation.
class PageBullets extends StatelessWidget {
  const PageBullets({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: EdgeInsets.only(bottom: 22 * s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(top: 13 * s, right: 18 * s),
                  width: 7 * s,
                  height: 7 * s,
                  color: clay,
                ),
                Expanded(
                  child: Text(item, style: PageText.lead(s).copyWith(
                        fontSize: 23 * s,
                        height: 1.45,
                      )),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
