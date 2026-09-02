import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../palette.dart';
import 'vote_marquee.dart';

class PollQrCode extends StatelessWidget {
  const PollQrCode({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(pollVoteUrl),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );

    return Semantics(
      label: 'Scan to vote at $pollVoteUrl',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12 * scale),
          border: Border.all(color: ink.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: 0.08),
              blurRadius: 28 * scale,
              offset: Offset(0, 10 * scale),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22 * scale,
            22 * scale,
            22 * scale,
            18 * scale,
          ),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: EdgeInsets.all(8 * scale),
                    child: CustomPaint(painter: _QrPainter(image)),
                  ),
                ),
              ),
              SizedBox(height: 12 * scale),
              Text(
                pollVoteLinkLabel,
                maxLines: 1,
                style: TextStyle(
                  color: spruce,
                  fontSize: 18 * scale,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3 * scale,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final moduleSize = side / image.moduleCount;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final paint = Paint()
      ..color = ink
      ..isAntiAlias = false;

    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (!image.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTRB(
            origin.dx + column * moduleSize,
            origin.dy + row * moduleSize,
            origin.dx + (column + 1) * moduleSize,
            origin.dy + (row + 1) * moduleSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => false;
}
