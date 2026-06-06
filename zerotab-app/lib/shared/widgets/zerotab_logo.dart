import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── ZeroTab Brand Colors ────────────────────────────────────────
const kZtViolet     = Color(0xFF7B2FFE);
const kZtCyan       = Color(0xFF00CFDE);
const kZtDeepBg     = Color(0xFF0E0820);
const kZtVoidBlack  = Color(0xFF060C1A);

/// ZeroTab "Escape Orbit" — Variation 2 (refined).
///
/// O (orbit ring) as hero. Z at medium-bold weight, floating
/// inside with breathing room. Pure white Z. Smaller gap (~18°).
class ZeroTabLogo extends StatelessWidget {
  final double size;
  final bool   showBackground;

  const ZeroTabLogo({
    super.key,
    required this.size,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width:  size,
        height: size,
        child:  CustomPaint(
          painter: ZeroTabLogoPainter(showBackground: showBackground),
        ),
      );
}

/// Exposed so the splash screen painter can embed it directly.
class ZeroTabLogoPainter extends CustomPainter {
  final bool showBackground;
  const ZeroTabLogoPainter({this.showBackground = true});

  // ── ring geometry (shared with splash animation) ────────────
  static const escapeAngle = -math.pi / 2 + math.pi / 5.5; // 1 o'clock (top-right)
  static const gapHalf     = math.pi / 10.0;   // ~18° gap
  static const arcStart    = escapeAngle + gapHalf;
  static const arcSweep    = math.pi * 2 - gapHalf * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;

    if (showBackground) drawBackground(canvas, w, h, cx, cy);

    final ringR = w * 0.350;
    drawRing(canvas, cx, cy, ringR, w, progress: 1.0);
    drawDotOnRing(canvas, cx, cy, ringR, w,
        angle: escapeAngle, glowRadius: w * 0.055, alpha: 1.0);
    drawGhostDot(canvas, cx, cy, ringR, w, alpha: 0.30);
    drawZ(canvas, cx, cy, w, opacity: 1.0, scale: 1.0);
  }

  // ── background squircle ──────────────────────────────────────
  static void drawBackground(
      Canvas canvas, double w, double h, double cx, double cy) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.22),
      ),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.12, -0.20),
          radius: 0.95,
          colors: const [kZtDeepBg, kZtVoidBlack],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // Glass border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.013, h * 0.013, w * 0.974, h * 0.974),
        Radius.circular(w * 0.210),
      ),
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = w * 0.007
        ..color       = kZtViolet.withValues(alpha: 0.18),
    );
  }

  // ── orbit ring ───────────────────────────────────────────────
  static void drawRing(
    Canvas canvas, double cx, double cy, double ringR, double w,
    {double progress = 1.0}) {
    final segs = (160 * progress).toInt().clamp(1, 160);
    final sw   = w / 220.0;

    for (int i = 0; i < segs; i++) {
      final t         = i / 160;
      final angle     = arcStart + arcSweep * t;
      final nextAngle = arcStart + arcSweep * (i + 1) / 160;
      final far       = math.sin(math.pi * t);
      final opacity   = (1.0 - far * 0.80).clamp(0.20, 1.0);
      final stroke    = ((3.4 - 1.8 * far).clamp(1.6, 3.4)) * sw;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: ringR),
        angle,
        nextAngle - angle + 0.008,
        false,
        Paint()
          ..color       = Color.lerp(kZtViolet, kZtCyan, t)!
                              .withValues(alpha: opacity)
          ..strokeWidth = stroke
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round,
      );
    }
  }

  // ── dot (escaping or travelling) ────────────────────────────
  static void drawDotOnRing(
    Canvas canvas, double cx, double cy, double ringR, double w,
    {required double angle, required double glowRadius, double alpha = 1.0}) {
    final x = cx + ringR * 0.93 * math.cos(angle);
    final y = cy + ringR * 0.93 * math.sin(angle);

    canvas.drawCircle(Offset(x, y), glowRadius * 3.4,
        Paint()
          ..color      = kZtCyan.withValues(alpha: 0.08 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(Offset(x, y), glowRadius * 1.9,
        Paint()
          ..color      = kZtCyan.withValues(alpha: 0.22 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(Offset(x, y), glowRadius,
        Paint()..color = Color.lerp(Colors.white, kZtCyan, 0.08)!
                             .withValues(alpha: alpha));
  }

  // ── ghost micro-dot (7 o'clock) ──────────────────────────────
  static void drawGhostDot(
    Canvas canvas, double cx, double cy, double ringR, double w,
    {double alpha = 0.30}) {
    const a = math.pi / 2 + math.pi / 5.5; // 7 o'clock (mirrors 1 o'clock escape)
    canvas.drawCircle(
      Offset(cx + ringR * 0.87 * math.cos(a),
             cy + ringR * 0.87 * math.sin(a)),
      w * 0.022,
      Paint()..color = kZtCyan.withValues(alpha: alpha),
    );
  }

  // ── Z mark — medium-bold, white, floating ───────────────────
  static void drawZ(
    Canvas canvas, double cx, double cy, double w,
    {double opacity = 1.0, double scale = 1.0}) {
    if (opacity <= 0 || scale <= 0) return;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-2.8 * math.pi / 180); // lean 2.8° forward
    canvas.scale(scale, scale);
    canvas.translate(-cx, -cy);

    // Variation 2: smaller Z, breathing room inside ring
    final hs  = w * 0.118; // half-span — 40% of ring interior
    final bh  = w * 0.078; // medium-bold bar height
    final zL  = cx - hs, zR = cx + hs;
    final zT  = cy - hs, zB = cy + hs;

    final fill = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    // Top bar — clean horizontal, no slope
    canvas.drawRect(Rect.fromLTRB(zL, zT, zR, zT + bh), fill);

    // Bottom bar
    canvas.drawRect(Rect.fromLTRB(zL, zB - bh, zR, zB), fill);

    // Diagonal — exact rotated rectangle
    final dx = zL - zR, dy = (zB - bh) - (zT + bh);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.atan2(dy, dx));
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width:  math.sqrt(dx * dx + dy * dy),
        height: bh * 1.10,
      ),
      fill,
    );
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ZeroTabLogoPainter old) =>
      old.showBackground != showBackground;
}
