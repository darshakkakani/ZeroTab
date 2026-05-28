import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
//  ZTLogo — premium geometric Z mark
//
//  Usage:
//    ZTLogo(size: 48)                           // accent gradient fill
//    ZTLogo(size: 32, style: ZTLogoStyle.mono)  // flat single color
//    ZTLogo(size: 24, style: ZTLogoStyle.outline) // stroke only
//    ZTLogoFull(size: 40)                       // mark + "ZeroTab" wordmark
// ─────────────────────────────────────────────────────────────

enum ZTLogoStyle { gradient, mono, outline }

class ZTLogo extends StatelessWidget {
  final double     size;
  final ZTLogoStyle style;
  final Color?     color;

  const ZTLogo({
    super.key,
    this.size   = 40,
    this.style  = ZTLogoStyle.gradient,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  size,
      height: size,
      child:  CustomPaint(
        painter: _ZMarkPainter(style: style, color: color),
      ),
    );
  }
}

// ── Logo + wordmark combo ─────────────────────────────────────

class ZTLogoFull extends StatelessWidget {
  final double markSize;
  final Color? color;

  const ZTLogoFull({super.key, this.markSize = 36, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ZTLogo(size: markSize, style: ZTLogoStyle.gradient, color: color),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ZeroTab',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: markSize * 0.48,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: AppColors.text,
                height: 1.0,
              ),
            ),
            Text(
              'Finance OS',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: markSize * 0.25,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.4,
                color: AppColors.text3,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Painter ───────────────────────────────────────────────────

class _ZMarkPainter extends CustomPainter {
  final ZTLogoStyle style;
  final Color?      color;

  const _ZMarkPainter({required this.style, this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Background circle ─────────────────────────────────────
    final bgPaint = Paint()..style = PaintingStyle.fill;

    if (style == ZTLogoStyle.gradient) {
      bgPaint.shader = const LinearGradient(
        colors: [Color(0xFF1A1040), Color(0xFF0C0920)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    } else {
      bgPaint.color = color?.withOpacity(0.08) ?? AppColors.bg3;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.26),
      ),
      bgPaint,
    );

    // ── Border for gradient style ─────────────────────────────
    if (style == ZTLogoStyle.gradient) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..color = const Color(0xFF7B5FFF).withOpacity(0.30);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            w * 0.015, h * 0.015,
            w * 0.970, h * 0.970,
          ),
          Radius.circular(w * 0.245),
        ),
        borderPaint,
      );
    }

    // ── Z mark geometry ───────────────────────────────────────
    // The Z is constructed from 3 precision segments:
    //   1. Top horizontal bar (full width, slight rightward taper)
    //   2. Diagonal stroke (top-right → bottom-left, bold)
    //   3. Bottom horizontal bar (full width, slight leftward taper)
    // Inspired by high-end brand geometry (clean angles, optically balanced)

    final pad = w * 0.22;

    final topLeft     = Offset(pad,         h * 0.22);
    final topRight    = Offset(w - pad,      h * 0.22);
    final botLeft     = Offset(pad,          h * 0.78);
    final botRight    = Offset(w - pad,      h * 0.78);
    final diagStart   = Offset(w - pad,      h * 0.32); // just below top bar
    final diagEnd     = Offset(pad,          h * 0.68); // just above bottom bar

    final strokeW = w * 0.105;

    Paint markPaint() {
      final p = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round;

      if (style == ZTLogoStyle.gradient) {
        p.shader = const LinearGradient(
          colors: [Color(0xFFB59FFF), Color(0xFF7B5FFF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      } else {
        p.color = color ?? AppColors.accent;
      }
      return p;
    }

    final p = markPaint();

    // Top bar
    canvas.drawLine(topLeft, topRight, p);
    // Diagonal
    canvas.drawLine(diagStart, diagEnd, p);
    // Bottom bar
    canvas.drawLine(botLeft, botRight, p);

    // ── Optional: small accent dot at diagonal midpoint ───────
    if (style == ZTLogoStyle.gradient) {
      final midX = (diagStart.dx + diagEnd.dx) / 2;
      final midY = (diagStart.dy + diagEnd.dy) / 2;
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF9B7FFF).withOpacity(0.55);
      canvas.drawCircle(Offset(midX, midY), w * 0.045, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_ZMarkPainter old) =>
      old.style != style || old.color != color;
}

// ── Animated logo for splash / loading ───────────────────────

class ZTLogoAnimated extends StatefulWidget {
  final double size;
  const ZTLogoAnimated({super.key, this.size = 80});

  @override
  State<ZTLogoAnimated> createState() => _ZTLogoAnimatedState();
}

class _ZTLogoAnimatedState extends State<ZTLogoAnimated>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale   = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: 0.7 + (_scale.value * 0.3),
          child: ZTLogo(size: widget.size, style: ZTLogoStyle.gradient),
        ),
      ),
    );
  }
}
