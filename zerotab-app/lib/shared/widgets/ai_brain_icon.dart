import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── ZeroTab AI Identity Colors ─────────────────────────────────
const _kViolet = Color(0xFF7B2FFE); // electric violet
const _kCyan   = Color(0xFF00CFDE); // intelligence cyan
const _kWhite  = Color(0xFFFFFFFF);

/// The "Intelligence Orb" — ZeroTab's AI identity mark.
///
/// Anatomy:
///  • Gradient arc ring  — violet→cyan, stroke thicker at top, thinner at bottom
///  • Primary dot        — white with cyan bloom, at 1 o'clock (inside the arc)
///  • Ghost micro-dot    — cyan 40%, at 7 o'clock (creates orbit balance)
///
/// This is a pure CustomPainter — zero dependencies, scales to any size.
class AiBrainIcon extends StatelessWidget {
  final double size;
  const AiBrainIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _OrbPainter()),
      );
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r  = w * 0.40; // arc radius

    // ── 1. Gradient arc ring ─────────────────────────────────────
    // We draw the arc in segments so we can fake a gradient stroke.
    // Each segment gets an interpolated color: violet at top → cyan at bottom.
    const segments = 120;
    const startAngle = -math.pi / 2; // start at 12 o'clock
    const sweep = math.pi * 2;

    for (int i = 0; i < segments; i++) {
      final t       = i / segments;
      final angle   = startAngle + sweep * t;

      // Stroke width tapers: thick at top (t≈0), thin at bottom (t≈0.5),
      // thick again at top wrap (t≈1) — creates a living, breathing feel.
      final strokeW = 2.8 - 1.2 * math.sin(math.pi * t);

      // Color interpolates violet → cyan → violet around the ring
      final color = Color.lerp(_kViolet, _kCyan, math.sin(math.pi * t))!;

      final paint = Paint()
        ..color       = color
        ..strokeWidth = strokeW
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round;

      final segSweep = sweep / segments + 0.002; // tiny overlap prevents gaps
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        angle,
        segSweep,
        false,
        paint,
      );
    }

    // ── 2. Primary dot — 1 o'clock position (inside arc) ────────
    // Angle: -60° from top = -π/2 - π/3
    const primaryAngle = -math.pi / 2 - math.pi / 3;
    final dotR   = r * 0.78; // slightly inside the arc ring
    final dotX   = cx + dotR * math.cos(primaryAngle);
    final dotY   = cy + dotR * math.sin(primaryAngle);
    final dotSize = w * 0.095;

    // Cyan bloom glow behind dot
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotSize * 2.2,
      Paint()
        ..color      = _kCyan.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Secondary soft glow ring
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotSize * 1.5,
      Paint()
        ..color      = _kCyan.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // White dot core
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotSize,
      Paint()..color = _kWhite,
    );

    // ── 3. Ghost micro-dot — 7 o'clock (orbital balance) ────────
    const ghostAngle = math.pi / 2 + math.pi / 6; // 7 o'clock
    final ghostR  = r * 0.75;
    final ghostX  = cx + ghostR * math.cos(ghostAngle);
    final ghostY  = cy + ghostR * math.sin(ghostAngle);
    final ghostSz = w * 0.045;

    canvas.drawCircle(
      Offset(ghostX, ghostY),
      ghostSz,
      Paint()..color = _kCyan.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
