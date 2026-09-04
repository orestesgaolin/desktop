import 'package:flutter/material.dart';
import 'package:flutter_deck/flutter_deck.dart';

import '../palette.dart';
import 'config.dart';

/// Windows XP-inspired outer chrome for selected slides.
///
/// The content keeps the deck's existing type scale and spacing. This widget
/// only supplies the recognizable application frame, so media and code remain
/// readable at presentation distance.
class XpSlideFrame extends StatelessWidget {
  const XpSlideFrame({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = SlidePage.scaleOf(context);

    return Padding(
      padding: EdgeInsets.all(18 * s),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFECE9D8),
          border: Border.all(color: const Color(0xFF0054E3), width: 3 * s),
          borderRadius: BorderRadius.circular(8 * s),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003C74).withValues(alpha: .28),
              blurRadius: 18 * s,
              offset: Offset(5 * s, 8 * s),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5 * s),
          child: Column(
            children: [
              _XpTitleBar(title: title, scale: s),
              Expanded(
                child: ColoredBox(color: const Color(0xFFF8F8F4), child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XpTitleBar extends StatelessWidget {
  const _XpTitleBar({required this.title, required this.scale});

  final String title;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    height: 38 * scale,
    padding: EdgeInsets.fromLTRB(10 * scale, 0, 5 * scale, 0),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF5AA2F5),
          Color(0xFF245EDB),
          Color(0xFF0C51CA),
          Color(0xFF003C74),
        ],
        stops: [0, .2, .78, 1],
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Tahoma',
              fontSize: 14 * scale,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Color(0xFF0F368B), offset: Offset(1, 1)),
              ],
            ),
          ),
        ),
        ExcludeSemantics(
          child: Row(
            children: [
              _XpWindowButton(action: _XpWindowAction.minimize, scale: scale),
              SizedBox(width: 2 * scale),
              _XpWindowButton(action: _XpWindowAction.maximize, scale: scale),
              SizedBox(width: 2 * scale),
              _XpWindowButton(action: _XpWindowAction.close, scale: scale),
            ],
          ),
        ),
      ],
    ),
  );
}

class _XpWindowButton extends StatelessWidget {
  const _XpWindowButton({required this.action, required this.scale});

  final _XpWindowAction action;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    width: 29 * scale,
    height: 28 * scale,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-.55, -.65),
        radius: 1.15,
        colors: action == _XpWindowAction.close
            ? const [Color(0xFFF6A184), Color(0xFFD65335), Color(0xFFB73822)]
            : const [Color(0xFF8EB7EF), Color(0xFF477CC9), Color(0xFF28549D)],
        stops: const [0, .58, 1],
      ),
      border: Border.all(color: Colors.white, width: 2 * scale),
      borderRadius: BorderRadius.circular(5.5 * scale),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF143E83),
          offset: Offset(1.5 * scale, 1.5 * scale),
        ),
      ],
    ),
    child: _XpWindowGlyph(action: action, scale: scale),
  );
}

enum _XpWindowAction { minimize, maximize, close }

class _XpWindowGlyph extends StatelessWidget {
  const _XpWindowGlyph({required this.action, required this.scale});

  final _XpWindowAction action;
  final double scale;

  @override
  Widget build(BuildContext context) => switch (action) {
    _XpWindowAction.minimize => Align(
      alignment: const Alignment(0, .58),
      child: Container(
        width: 12 * scale,
        height: 3 * scale,
        color: Colors.white,
      ),
    ),
    _XpWindowAction.maximize => Container(
      width: 13 * scale,
      height: 12 * scale,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2.2 * scale),
      ),
    ),
    _XpWindowAction.close => SizedBox.square(
      dimension: 19 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final angle in [-.785398, .785398])
            Transform.rotate(
              angle: angle,
              child: Container(
                width: 21 * scale,
                height: 3.2 * scale,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(.8 * scale),
                ),
              ),
            ),
        ],
      ),
    ),
  };
}

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
                Text(deckConfig.footerText, style: PageText.footer(s)),
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
    fontFamily: deckFontFamily,
    fontSize: 82 * s,
    height: 1.05,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.6 * s,
    color: ink,
  );

  static TextStyle title(double s) => TextStyle(
    fontFamily: deckFontFamily,
    fontSize: 52 * s,
    height: 1.12,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.8 * s,
    color: ink,
  );

  static TextStyle lead(double s) => TextStyle(
    fontFamily: deckFontFamily,
    fontSize: 26 * s,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: ink.withValues(alpha: 0.78),
  );

  static TextStyle body(double s) => TextStyle(
    fontFamily: deckFontFamily,
    fontSize: 19 * s,
    height: 1.72,
    fontWeight: FontWeight.w400,
    color: ink.withValues(alpha: 0.70),
  );

  static TextStyle label(double s) => TextStyle(
    fontFamily: deckFontFamily,
    fontSize: 12.5 * s,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.6 * s,
    color: spruce,
  );

  static TextStyle footer(double s) => TextStyle(
    fontFamily: deckFontFamily,
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
                  child: Text(
                    item,
                    style: PageText.lead(s)
                        .copyWith(fontSize: 23 * s, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
