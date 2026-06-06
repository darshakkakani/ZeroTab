import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── ZeroTab Brand Colors ────────────────────────────────────────
const _kViolet     = Color(0xFF7B2FFE); // electric violet — "the struggle"
const _kCyan       = Color(0xFF00CFDE); // intelligence cyan — "the freedom"
const _kDeepViolet = Color(0xFF1C0A42); // deep bg center
const _kVoidBlack  = Color(0xFF060C1A); // near-black bg edge

/// ZeroTab "Escape Orbit" — the official brand mark.
///
/// ═══ THE STORY ══════════════════════════════════════════════════
///  The circle  = Zero (the name, the starting point of every
///                wealth journey)
///  Bold Z      = You — the user at the center of it all
///  Glowing dot = Your wealth — finally in motion
///  Comet trail = The journey — every rupee tracked, every step lit
///  Gap in ring = The escape — breaking free from financial zero
/// ════════════════════════════════════════════════════════════════
///
/// Three layers of meaning — novice sees a logo, designer sees a
/// system, and everyone remembers it.
class ZeroTabLogo extends StatelessWidget {
  final double size;

  /// Set false when placing on a dark background that you control.
  /// Set true (default) for the launcher icon / standalone use.
  final bool showBackground;

  const ZeroTabLogo({
    super.key,
    required this.size,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _EscapeOrbitPainter(showBackground: showBackground),
        ),
      );
}

// ── Painter ─────────────────────────────────────────────────────

class _EscapeOrbitPainter extends CustomPainter {
  final bool showBackground;
  const _EscapeOrbitPainter({required this.showBackground});

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── 1. Background ────────────────────────────────────────────
    if (showBackground) {
      // Rounded-square for launcher icons, circle for in-app use
      final bgPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.25),
          radius: 0.92,
          colors: const [_kDeepViolet, _kVoidBlack],
        ).createShader(Rect.fromLTWH(0, 0, w, h));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          Radius.circular(w * 0.22), // squircle — works for both launcher + splash
        ),
        bgPaint,
      );

      // Subtle inner glow border — premium glass edge
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.012, h * 0.012, w * 0.976, h * 0.976),
          Radius.circular(w * 0.21),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.008
          ..color = _kViolet.withValues(alpha: 0.22),
      );
    }

    // ── 2. Escape Orbit Ring — comet trail effect ────────────────
    //
    //  Gap = ~40° at the 1 o'clock position (the escape point).
    //  Arc starts just past the gap and sweeps ~320° clockwise.
    //  Color interpolates: violet at arc start → cyan at arc end.
    //  Opacity fades: full at both ends (near gap) → 18% at center.
    //  Stroke tapers: thick at both ends → thin at center.
    //  Result: ring looks like a living comet orbiting the Z.

    final ringR = w * 0.345;

    // Escape angle = 1 o'clock = -π/2 - π/5.5 ≈ -122°
    const escapeAngle = -math.pi / 2 - math.pi / 5.5;
    const gapHalf     = math.pi / 8.0;   // ~22.5° each side of gap
    const arcStart    = escapeAngle + gapHalf;
    const arcSweep    = math.pi * 2 - gapHalf * 2;
    const segs        = 160;

    for (int i = 0; i < segs; i++) {
      final t         = i / segs;
      final angle     = arcStart + arcSweep * t;
      final nextAngle = arcStart + arcSweep * (i + 1) / segs;

      // sin curve: 0 at ends (near gap/dot), peaks at 1 at opposite side
      final far     = math.sin(math.pi * t);
      final opacity = (1.0 - far * 0.82).clamp(0.18, 1.0);
      final sw      = ((3.6 - 2.0 * far).clamp(1.6, 3.6)) * (w / 220.0);

      final color = Color.lerp(_kViolet, _kCyan, t)!
          .withValues(alpha: opacity);

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: ringR),
        angle,
        nextAngle - angle + 0.01, // tiny overlap prevents hairline gaps
        false,
        Paint()
          ..color       = color
          ..strokeWidth = sw
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round,
      );
    }

    // ── 3. Escaping Dot — the wealth breaking free ───────────────
    //
    //  Sits exactly at the gap opening. 3-layer bloom glow +
    //  a bright white-cyan core. This is the hero detail —
    //  it's what draws the eye first.

    final dotX = cx + ringR * 0.92 * math.cos(escapeAngle);
    final dotY = cy + ringR * 0.92 * math.sin(escapeAngle);
    final dotR = w * 0.055;

    // Layer 1 — wide soft outer bloom
    canvas.drawCircle(
      Offset(dotX, dotY), dotR * 3.6,
      Paint()
        ..color      = _kCyan.withValues(alpha: 0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Layer 2 — tighter mid glow
    canvas.drawCircle(
      Offset(dotX, dotY), dotR * 2.0,
      Paint()
        ..color      = _kCyan.withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Layer 3 — bright core (near-white, faint cyan warmth)
    canvas.drawCircle(
      Offset(dotX, dotY), dotR,
      Paint()..color = const Color(0xFFF2FFFF),
    );

    // ── 4. Ghost Micro-Dot — orbital counterweight at 7 o'clock ──
    //
    //  This is the detail only designers notice on second look.
    //  It creates visual balance and subconsciously reads as
    //  "another body in orbit" — reinforcing the orbit metaphor.

    const ghostAngle = math.pi / 2 + math.pi / 4.2;
    final ghostX = cx + ringR * 0.86 * math.cos(ghostAngle);
    final ghostY = cy + ringR * 0.86 * math.sin(ghostAngle);
    canvas.drawCircle(
      Offset(ghostX, ghostY), w * 0.022,
      Paint()..color = _kCyan.withValues(alpha: 0.32),
    );

    // ── 5. Bold Z — leaning 3° forward into the future ───────────
    //
    //  White-near Z with very faint ascending slope on bars.
    //  Diagonal computed via exact geometry — no approximations.
    //  Shadow beneath for depth against the dark background.

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-3.0 * math.pi / 180.0); // 3° lean: subconscious momentum
    canvas.translate(-cx, -cy);
    _paintZ(canvas, cx, cy, w);
    canvas.restore();
  }

  void _paintZ(Canvas canvas, double cx, double cy, double w) {
    final hs = w * 0.168; // half-span: Z fits inside the orbit ring
    final bh = w * 0.105; // bar height: optically balanced proportion

    final zL = cx - hs;
    final zR = cx + hs;
    final zT = cy - hs;
    final zB = cy + hs;

    // Subtle drop shadow — gives the Z lift off the background
    final shadow = Paint()
      ..color      = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.025);

    // Clean white fill — near-white with barely-there cyan warmth
    final fill = Paint()
      ..color = const Color(0xFFF0FBFF)
      ..style = PaintingStyle.fill;

    // ── Top bar — very subtle ascending slope (right 0.8% higher) ──
    // This micro-slope is invisible consciously but makes the Z feel
    // dynamic and "leaning into the future."
    final slope = w * 0.007;
    final topBar = Path()
      ..moveTo(zL, zT)
      ..lineTo(zR, zT - slope)
      ..lineTo(zR, zT - slope + bh)
      ..lineTo(zL, zT + bh)
      ..close();

    // ── Bottom bar — mirrored slope ──────────────────────────────
    final botBar = Path()
      ..moveTo(zL, zB - bh)
      ..lineTo(zR, zB - bh - slope)
      ..lineTo(zR, zB - slope)
      ..lineTo(zL, zB)
      ..close();

    // ── Diagonal — mathematically precise rotated rectangle ──────
    // Direction: from (zR, zT+bh) → (zL, zB-bh)
    final dx       = zL - zR;
    final dy       = (zB - bh) - (zT + bh);
    final diagLen  = math.sqrt(dx * dx + dy * dy);
    final diagAngle = math.atan2(dy, dx);

    // Draw shadow first, then fill on top
    for (final paint in [shadow, fill]) {
      // Diagonal
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(diagAngle);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width:  diagLen,
          height: bh * 1.06,
        ),
        paint,
      );
      canvas.restore();

      // Top and bottom bars
      canvas.drawPath(topBar, paint);
      canvas.drawPath(botBar, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EscapeOrbitPainter old) =>
      old.showBackground != showBackground;
}
