import 'package:flutter/material.dart';

/// Premium AI icon — clean, bold, minimal.
/// A stylized "spark" / diamond starburst that reads as intelligence
/// at any size. Simple geometry, high visibility, unmistakably AI.
class AiBrainIcon extends StatelessWidget {
  final double size;
  final Color iconColor;
  const AiBrainIcon({
    super.key,
    required this.size,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AiSparkPainter(color: iconColor)),
    );
  }
}

class _AiSparkPainter extends CustomPainter {
  final Color color;
  const _AiSparkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // ── Main 4-point spark — bold diamond starburst ─────────
    // Vertical spike (tall & narrow)
    final spark = Path()
      ..moveTo(cx, h * 0.02)            // top point
      ..quadraticBezierTo(cx + w * 0.08, cy, cx, h * 0.98)   // right curve → bottom
      ..quadraticBezierTo(cx - w * 0.08, cy, cx, h * 0.02);  // left curve → top
    canvas.drawPath(spark, fill);

    // Horizontal spike (wide & narrow)
    final spark2 = Path()
      ..moveTo(w * 0.02, cy)            // left point
      ..quadraticBezierTo(cx, cy + h * 0.08, w * 0.98, cy)   // bottom curve → right
      ..quadraticBezierTo(cx, cy - h * 0.08, w * 0.02, cy);  // top curve → left
    canvas.drawPath(spark2, fill);

    // ── Centre dot — solid bright core ──────────────────────
    canvas.drawCircle(Offset(cx, cy), w * 0.09, fill);

    // ── Small secondary spark (top-right) — adds depth ──────
    final s2x = w * 0.78;
    final s2y = h * 0.22;
    final smallR = w * 0.12;

    final miniV = Path()
      ..moveTo(s2x, s2y - smallR)
      ..quadraticBezierTo(s2x + smallR * 0.25, s2y, s2x, s2y + smallR)
      ..quadraticBezierTo(s2x - smallR * 0.25, s2y, s2x, s2y - smallR);
    canvas.drawPath(miniV, fill);

    final miniH = Path()
      ..moveTo(s2x - smallR, s2y)
      ..quadraticBezierTo(s2x, s2y + smallR * 0.25, s2x + smallR, s2y)
      ..quadraticBezierTo(s2x, s2y - smallR * 0.25, s2x - smallR, s2y);
    canvas.drawPath(miniH, fill);

    canvas.drawCircle(Offset(s2x, s2y), w * 0.035, fill);
  }

  @override
  bool shouldRepaint(_AiSparkPainter old) => old.color != color;
}
