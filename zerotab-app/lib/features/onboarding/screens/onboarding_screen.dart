import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/zt_card.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  int _page = 0;

  static const _slideCount = 3;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _next() {
    if (_page < _slideCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Stack(children: [
        // ── Ambient gradient glow (top-center) ─────────────────
        Positioned(
          top: -60, left: -60, right: -60,
          child: Container(
            height: 360,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 0.9,
                colors: [
                  const Color(0xFF7B5FFF).withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // ── Top bar: skip only ───────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => context.go('/login'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Page view ──────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [
                    _SlideValue(),
                    _SlideTrust(),
                    _SlideAI(),
                  ],
                ),
              ),

              // ── Dot progress + CTA ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: Column(
                  children: [
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slideCount, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width:  active ? 22 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? AppColors.accent : AppColors.bg4,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Premium gradient CTA button
                    GestureDetector(
                      onTap: _next,
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9B7FFF), Color(0xFF5B40CC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B5FFF).withOpacity(0.38),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _page < _slideCount - 1 ? 'Continue' : 'Get started',
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// SLIDE 1 — Value: "Your complete financial picture"
// ══════════════════════════════════════════════════════════

class _SlideValue extends StatelessWidget {
  const _SlideValue();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),

          SizedBox(
            height: 210,
            child: _NetworkHubIllustration(),
          ),

          const SizedBox(height: 36),

          const Text(
            'Your complete\nfinancial picture',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Banks, credit cards, loans and investments — connected securely via RBI\'s Account Aggregator.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium financial constellation illustration (slide 1) ─

class _NetworkHubIllustration extends StatefulWidget {
  @override
  State<_NetworkHubIllustration> createState() => _NetworkHubIllustrationState();
}

class _NetworkHubIllustrationState extends State<_NetworkHubIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Continuous forward — data always flows outward from hub
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(
      painter: _NetworkPainter(_ctrl.value),
      size: const Size(double.infinity, 210),
    ),
  );
}

class _NetworkPainter extends CustomPainter {
  final double t;
  _NetworkPainter(this.t);

  // ── Icon drawing methods ─────────────────────────────────

  // Banks — greek temple columns
  void _drawBank(Canvas canvas, Offset c, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Pediment (triangle roof)
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 7,   c.dy - 1)
        ..lineTo(c.dx,       c.dy - 7)
        ..lineTo(c.dx + 7,   c.dy - 1),
      p,
    );
    // Cap line
    canvas.drawLine(Offset(c.dx - 7, c.dy - 1), Offset(c.dx + 7, c.dy - 1), p);
    // Three columns
    for (final ox in [-4.5, 0.0, 4.5]) {
      canvas.drawLine(
        Offset(c.dx + ox, c.dy - 0.5),
        Offset(c.dx + ox, c.dy + 4.5),
        p,
      );
    }
    // Base
    canvas.drawLine(Offset(c.dx - 7, c.dy + 5), Offset(c.dx + 7, c.dy + 5), p);
  }

  // Cards — credit card outline with chip & stripe
  void _drawCard(Canvas canvas, Offset c, Color col) {
    // Card body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 15, height: 10.5),
        const Radius.circular(1.8),
      ),
      Paint()..color = col..strokeWidth = 1.3..style = PaintingStyle.stroke,
    );
    // Mag stripe (top area, thick)
    canvas.drawLine(
      Offset(c.dx - 7.5, c.dy - 1.5),
      Offset(c.dx + 7.5, c.dy - 1.5),
      Paint()
        ..color = col.withOpacity(0.60)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.butt,
    );
    // Chip square
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(c.dx - 3, c.dy + 2), width: 4, height: 3),
        const Radius.circular(0.6),
      ),
      Paint()..color = col.withOpacity(0.70)..strokeWidth = 1.0..style = PaintingStyle.stroke,
    );
  }

  // Loans — house silhouette
  void _drawHouse(Canvas canvas, Offset c, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Roof
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 7,   c.dy)
        ..lineTo(c.dx,       c.dy - 7)
        ..lineTo(c.dx + 7,   c.dy),
      p,
    );
    // Body walls
    canvas.drawRect(
      Rect.fromLTRB(c.dx - 5.5, c.dy, c.dx + 5.5, c.dy + 6.5),
      p,
    );
    // Door
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(c.dx - 1.5, c.dy + 2.5, c.dx + 1.5, c.dy + 6.5),
        const Radius.circular(1),
      ),
      p,
    );
  }

  // Invest — three ascending bar chart
  void _drawChart(Canvas canvas, Offset c, Color col) {
    final data = [
      (dx: -4.5, h: 4.0),
      (dx:  0.0, h: 6.5),
      (dx:  4.5, h: 9.0),
    ];
    const baseY = 5.0;
    for (final bar in data) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            c.dx + bar.dx - 1.6,
            c.dy + baseY - bar.h,
            c.dx + bar.dx + 1.6,
            c.dy + baseY,
          ),
          const Radius.circular(0.8),
        ),
        Paint()..color = col.withOpacity(0.85)..style = PaintingStyle.fill,
      );
    }
    // Upward arrow above tallest bar
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + 4.5,  c.dy + baseY - 9.8)
        ..lineTo(c.dx + 2.5,  c.dy + baseY - 7.8)
        ..moveTo(c.dx + 4.5,  c.dy + baseY - 9.8)
        ..lineTo(c.dx + 6.5,  c.dy + baseY - 7.8),
      Paint()
        ..color = col
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height * 0.46;

    const purple = Color(0xFF7B5FFF);
    const teal   = Color(0xFF00C896);
    const gold   = Color(0xFFFFAA00);
    const blue   = Color(0xFF3B8BFF);
    const violet = Color(0xFF9B7FFF);

    // Satellite definitions: [position, color, icon enum]
    final sats = [
      (pos: Offset(cx - 92, cy - 52), color: purple, label: 'Banks',  idx: 0),
      (pos: Offset(cx + 92, cy - 52), color: teal,   label: 'Cards',  idx: 1),
      (pos: Offset(cx - 76, cy + 60), color: gold,   label: 'Loans',  idx: 2),
      (pos: Offset(cx + 76, cy + 60), color: blue,   label: 'Invest', idx: 3),
    ];

    // ── 1. Wide ambient radial glow (atmosphere) ─────────
    canvas.drawCircle(
      Offset(cx, cy), 115,
      Paint()
        ..color = purple.withOpacity(0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 52),
    );

    // ── 2. Faint orbital path rings ───────────────────────
    for (final r in [68.0, 108.0]) {
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = Colors.white.withOpacity(0.035)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }

    // ── 3. Connection lines + traveling pulses ────────────
    for (int i = 0; i < sats.length; i++) {
      final sat    = sats[i];
      final color  = sat.color;
      final sdx    = sat.pos.dx - cx;
      final sdy    = sat.pos.dy - cy;
      final len    = math.sqrt(sdx * sdx + sdy * sdy);
      final ux     = sdx / len;
      final uy     = sdy / len;
      const hubR   = 26.0;
      const satR   = 16.0;

      // Connection glow (thick blur behind line)
      canvas.drawLine(
        Offset(cx + ux * hubR, cy + uy * hubR),
        Offset(sat.pos.dx - ux * satR, sat.pos.dy - uy * satR),
        Paint()
          ..color = color.withOpacity(0.14)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      // Gradient dotted line (bright at hub → dim at satellite)
      for (double d = hubR + 4; d < len - satR - 4; d += 5.5) {
        final progress = (d - hubR) / (len - hubR - satR);
        final opacity  = 0.65 * (1.0 - progress * 0.72);
        canvas.drawCircle(
          Offset(cx + ux * d, cy + uy * d),
          0.9,
          Paint()..color = color.withOpacity(opacity),
        );
      }

      // Traveling data packet (direction: hub → satellite)
      final phasedT  = (t + i * 0.25) % 1.0;
      final pStart   = hubR + 6;
      final pEnd     = len - satR - 8;
      final pd       = pStart + phasedT * (pEnd - pStart);
      // Glow behind packet
      canvas.drawCircle(
        Offset(cx + ux * pd, cy + uy * pd), 5.5,
        Paint()
          ..color = color.withOpacity(0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Packet body
      canvas.drawCircle(
        Offset(cx + ux * pd, cy + uy * pd), 3.0,
        Paint()..color = color.withOpacity(0.90),
      );
      // Bright white core
      canvas.drawCircle(
        Offset(cx + ux * pd, cy + uy * pd), 1.2,
        Paint()..color = Colors.white.withOpacity(0.95),
      );
    }

    // ── 4. Satellite nodes (back-to-front layering) ───────
    for (final sat in sats) {
      final color   = sat.color;
      final p       = sat.pos;
      final bounds  = Rect.fromCenter(center: p, width: 34, height: 34);

      // Outer glow halo
      canvas.drawCircle(
        p, 20,
        Paint()
          ..color = color.withOpacity(0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );

      // Node body — dark sphere gradient (3D light: top-left = lighter)
      canvas.drawCircle(
        p, 15,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.5, -0.55),
            radius: 1.0,
            colors: const [Color(0xFF1E1A42), Color(0xFF0B091F)],
          ).createShader(bounds),
      );

      // Rim border
      canvas.drawCircle(
        p, 15,
        Paint()
          ..color = color.withOpacity(0.48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Specular arc highlight (top-left bevel — 3D glass effect)
      canvas.drawArc(
        Rect.fromCenter(center: p, width: 24, height: 24),
        -2.5, 1.5, false,
        Paint()
          ..color = Colors.white.withOpacity(0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Icon
      switch (sat.idx) {
        case 0: _drawBank(canvas, p, color); break;
        case 1: _drawCard(canvas, p, color); break;
        case 2: _drawHouse(canvas, p, color); break;
        case 3: _drawChart(canvas, p, color); break;
      }

      // Label below node
      final lp = TextPainter(
        text: TextSpan(
          text: sat.label,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: AppColors.text3.withOpacity(0.80),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lp.paint(canvas, Offset(p.dx - lp.width / 2, p.dy + 19));
    }

    // ── 5. Central hub ────────────────────────────────────

    final hubBounds = Rect.fromCenter(center: Offset(cx, cy), width: 52, height: 52);

    // Breathing outer glow
    final glowR = 30.0 + 3.0 * math.sin(t * math.pi * 2);
    canvas.drawCircle(
      Offset(cx, cy), glowR,
      Paint()
        ..color = violet.withOpacity(0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );

    // Hub drop shadow (elevation)
    canvas.drawCircle(
      Offset(cx, cy + 5), 26,
      Paint()
        ..color = Colors.black.withOpacity(0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Outer orbit ring (thin, animated dash)
    canvas.drawCircle(
      Offset(cx, cy), 30,
      Paint()
        ..color = purple.withOpacity(0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    // Hub sphere body — radial gradient: bright purple top-left → deep indigo bottom-right
    canvas.drawCircle(
      Offset(cx, cy), 26,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.60),
          radius: 1.0,
          colors: const [
            Color(0xFFA08BFF),
            Color(0xFF7B5FFF),
            Color(0xFF3D1E9E),
            Color(0xFF1A0A4E),
          ],
          stops: [0.0, 0.35, 0.70, 1.0],
        ).createShader(hubBounds),
    );

    // Hub rim border
    canvas.drawCircle(
      Offset(cx, cy), 26,
      Paint()
        ..color = purple.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Glassmorphism specular sheen (top-left)
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: 26)));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 8, cy - 10), width: 30, height: 16),
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.20), Colors.transparent],
        ).createShader(Rect.fromCenter(center: Offset(cx - 8, cy - 10), width: 30, height: 16)),
    );
    canvas.restore();

    // Z lettermark — drawn as path segments (not text renderer)
    final zGlowPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    final zCrispPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final zPath = Path()
      ..moveTo(cx - 8.5, cy - 8)   // top-left
      ..lineTo(cx + 8.5, cy - 8)   // top-right  (top bar)
      ..lineTo(cx - 8.5, cy + 8)   // bottom-left (diagonal)
      ..lineTo(cx + 8.5, cy + 8);  // bottom-right (bottom bar)

    canvas.drawPath(zPath, zGlowPaint);  // glow pass
    canvas.drawPath(zPath, zCrispPaint); // crisp pass

    // Specular dot (brightest point of the sphere — top-left of hub)
    canvas.drawCircle(
      Offset(cx - 8, cy - 8), 3.5,
      Paint()..color = Colors.white.withOpacity(0.45),
    );
  }

  @override
  bool shouldRepaint(_NetworkPainter old) => old.t != t;
}

// ══════════════════════════════════════════════════════════
// SLIDE 2 — Trust: "Read-only access. No exceptions."
// ══════════════════════════════════════════════════════════

class _SlideTrust extends StatelessWidget {
  const _SlideTrust();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),

          SizedBox(
            height: 210,
            child: _ShieldIllustration(),
          ),

          const SizedBox(height: 36),

          const Text(
            'Read-only access.\nNo exceptions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'We read your data the same way your CA does — with your explicit permission, revoked anytime.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          ...[
            'No password ever stored',
            'Consent revocable anytime',
            'Powered by Finvu AA · RBI licensed',
          ].map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TrustRow(text: t),
          )),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  final String text;
  const _TrustRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded, size: 12, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium 3D Shield illustration ───────────────────────

class _ShieldIllustration extends StatefulWidget {
  @override
  State<_ShieldIllustration> createState() => _ShieldIllustrationState();
}

class _ShieldIllustrationState extends State<_ShieldIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(
      painter: _ShieldPainter3D(_ctrl.value),
      size: const Size(double.infinity, 210),
    ),
  );
}

class _ShieldPainter3D extends CustomPainter {
  final double t;
  _ShieldPainter3D(this.t);

  // Classic heraldic shield shape — wider shoulders, curved sides, pointed tip
  Path _shieldPath(double cx, double cy, double w, double h) {
    final path = Path();
    final top    = cy - h * 0.50;
    final bottom = cy + h * 0.50;
    final left   = cx - w * 0.50;
    final right  = cx + w * 0.50;
    final shoulderY = top + h * 0.16;
    final waistY    = cy + h * 0.06;

    path.moveTo(cx, top);
    path.lineTo(right, shoulderY);
    path.lineTo(right, waistY);
    // right curve to bottom point
    path.cubicTo(
      right,       cy + h * 0.35,
      cx + w * 0.25, bottom - h * 0.04,
      cx,          bottom,
    );
    // left curve from bottom point
    path.cubicTo(
      cx - w * 0.25, bottom - h * 0.04,
      left,        cy + h * 0.35,
      left,        waistY,
    );
    path.lineTo(left, shoulderY);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.46;
    const teal    = Color(0xFF00C896);
    const tealDim = Color(0xFF009970);

    // ── 1. Deep ambient halo (far background glow) ────────
    canvas.drawCircle(
      Offset(cx, cy), 96,
      Paint()
        ..color = teal.withOpacity(0.055)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 44),
    );

    // ── 2. Three pulsing rings expanding outward ──────────
    for (int i = 0; i < 3; i++) {
      final phase = ((t * 0.9 + i * 0.33) % 1.0);
      final r     = 62.0 + phase * 36;
      final op    = (1.0 - phase) * 0.14;
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = teal.withOpacity(op)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // ── 3. Eight orbital particles (rotating) ────────────
    for (int i = 0; i < 8; i++) {
      final angle  = (i / 8) * 2 * math.pi + t * math.pi * 2 * 0.4;
      const orbit  = 78.0;
      final dx     = cx + orbit * math.cos(angle);
      final dy     = cy + orbit * math.sin(angle);
      final bright = 0.22 + 0.28 * (math.sin(angle * 2 + t * math.pi) * 0.5 + 0.5);
      canvas.drawCircle(
        Offset(dx, dy),
        i % 3 == 0 ? 2.8 : 1.6,
        Paint()..color = teal.withOpacity(bright),
      );
    }

    final shield = _shieldPath(cx, cy, 88.0, 104.0);
    final shBounds = Rect.fromCenter(center: Offset(cx, cy), width: 176, height: 208);

    // ── 4. Shield drop shadow (3D elevation) ──────────────
    canvas.drawPath(
      _shieldPath(cx, cy + 8, 88.0, 104.0),
      Paint()
        ..color = Colors.black.withOpacity(0.44)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // ── 5. Shield body — deep gradient (light top-left → dark bottom-right) ──
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.7, -1.0),
          end:   Alignment(0.6,  1.0),
          colors: [Color(0xFF1E1848), Color(0xFF110E30), Color(0xFF080612)],
          stops:  [0.0,              0.55,              1.0],
        ).createShader(shBounds),
    );

    // ── 6. Subtle inner face highlight (simulates curved surface) ──
    canvas.save();
    canvas.clipPath(shield);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 8, cy - 32), width: 62, height: 34),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.8,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCenter(center: Offset(cx - 8, cy - 32), width: 62, height: 34)),
    );
    canvas.restore();

    // ── 7. Teal rim glow (outer glow layer) ───────────────
    canvas.drawPath(
      shield,
      Paint()
        ..color = teal.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // ── 8. Teal border (crisp edge) ───────────────────────
    canvas.drawPath(
      shield,
      Paint()
        ..color = teal.withOpacity(0.60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // ── 9. Inner concentric ring (shield badge ring) ──────
    final innerShield = _shieldPath(cx, cy, 60.0, 72.0);
    canvas.drawPath(
      innerShield,
      Paint()
        ..color = teal.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── 10. Breathing center glow ─────────────────────────
    final glowR = 18.0 + 2.5 * math.sin(t * math.pi * 2);
    canvas.drawCircle(
      Offset(cx, cy - 2),
      glowR + 10,
      Paint()
        ..color = teal.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // ── 11. Checkmark — premium drawn with glow ───────────
    final checkPath = Path()
      ..moveTo(cx - 14, cy)
      ..lineTo(cx - 3,  cy + 13)
      ..lineTo(cx + 17, cy - 13);

    // Glow halo behind checkmark
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = teal.withOpacity(0.40)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Main crisp checkmark
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = teal
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Specular highlight on checkmark (thin white line over)
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── 12. Corner accent dots (decorative — 4 around shield) ──
    const dotPositions = [
      Offset(-50, -42), Offset(50, -42),
      Offset(-44,  34), Offset(44,  34),
    ];
    for (final dp in dotPositions) {
      canvas.drawCircle(
        Offset(cx + dp.dx, cy + dp.dy), 3.5,
        Paint()
          ..color = tealDim.withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        Offset(cx + dp.dx, cy + dp.dy), 1.8,
        Paint()..color = teal.withOpacity(0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_ShieldPainter3D old) => old.t != t;
}

// ══════════════════════════════════════════════════════════
// SLIDE 3 — AI: "Your AI CFO"
// ══════════════════════════════════════════════════════════

class _SlideAI extends StatelessWidget {
  const _SlideAI();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),

          SizedBox(
            height: 210,
            child: _AIBrainIllustration(),
          ),

          const SizedBox(height: 36),

          // Teal "AI CFO" eyebrow
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.teal.withOpacity(0.2)),
            ),
            child: const Text(
              'POWERED BY AI',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.teal,
                letterSpacing: 0.12,
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Meet your\nAI CFO',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Personalized financial insights every week — like having a private CFO who knows your spending better than you do.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium holographic neural chip illustration ──────────

class _AIBrainIllustration extends StatefulWidget {
  @override
  State<_AIBrainIllustration> createState() => _AIBrainIllustrationState();
}

class _AIBrainIllustrationState extends State<_AIBrainIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(
      painter: _AIChipPainter(_ctrl.value),
      size: const Size(double.infinity, 210),
    ),
  );
}

class _AIChipPainter extends CustomPainter {
  final double t;
  _AIChipPainter(this.t);

  // Build regular hexagon path
  Path _hex(double cx, double cy, double r, {double rotation = 0}) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + rotation;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    return path;
  }

  // Get hex vertex positions
  List<Offset> _hexPoints(double cx, double cy, double r, {double rotation = 0}) =>
    List.generate(6, (i) {
      final angle = i * math.pi / 3 + rotation;
      return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
    });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height * 0.46;

    // Color palette
    const blue   = Color(0xFF3B8BFF);
    const purple = Color(0xFF7B5FFF);
    const cyan   = Color(0xFF00D4FF);
    const teal   = Color(0xFF00C896);

    // ── 1. Wide ambient deep glow ──────────────────────────
    canvas.drawCircle(
      Offset(cx, cy), 100,
      Paint()
        ..color = blue.withOpacity(0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48),
    );
    canvas.drawCircle(
      Offset(cx, cy), 60,
      Paint()
        ..color = purple.withOpacity(0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    // ── 2. Three concentric pulsing rings ─────────────────
    for (int i = 0; i < 3; i++) {
      final phase = ((t + i * 0.33) % 1.0);
      final r     = 50.0 + phase * 42;
      final op    = (1.0 - phase) * 0.18;
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = cyan.withOpacity(op)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // ── 3. Six circuit arms + traveling pulse + satellite nodes ──
    final armColors    = [purple, teal, blue, cyan, purple, teal];
    final satellites   = _hexPoints(cx, cy, 72, rotation: math.pi / 6);
    // Insight labels on satellite nodes
    final nodeLabels   = ['₹', '%', '↑', '▣', '→', '≡'];

    for (int i = 0; i < 6; i++) {
      final sat   = satellites[i];
      final color = armColors[i];

      // Dashed arm line (simulated by drawing short segments)
      final dx = sat.dx - cx, dy = sat.dy - cy;
      final len = math.sqrt(dx * dx + dy * dy);
      final ux  = dx / len, uy = dy / len;

      for (double d = 8; d < len - 14; d += 8) {
        canvas.drawLine(
          Offset(cx + ux * d, cy + uy * d),
          Offset(cx + ux * (d + 4), cy + uy * (d + 4)),
          Paint()
            ..color = color.withOpacity(0.18)
            ..strokeWidth = 1.0,
        );
      }

      // Traveling data pulse dot along arm
      final pulseT = ((t * 1.3 + i * 0.166) % 1.0);
      final pd     = 14.0 + pulseT * (len - 28);
      canvas.drawCircle(
        Offset(cx + ux * pd, cy + uy * pd),
        2.8,
        Paint()
          ..color = color.withOpacity(0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // Satellite node — layered for 3D depth
      // Outer glow
      canvas.drawCircle(
        sat, 14,
        Paint()
          ..color = color.withOpacity(0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      // Body (dark with gradient feel)
      final satBounds = Rect.fromCenter(center: sat, width: 26, height: 26);
      canvas.drawCircle(
        sat, 12,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            radius: 1.0,
            colors: [
              const Color(0xFF1C1840),
              const Color(0xFF0A0818),
            ],
          ).createShader(satBounds),
      );
      // Rim border
      canvas.drawCircle(
        sat, 12,
        Paint()
          ..color = color.withOpacity(0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // Specular highlight on top-left
      canvas.drawArc(
        Rect.fromCenter(center: sat, width: 20, height: 20),
        -2.4, 1.4, false,
        Paint()
          ..color = Colors.white.withOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // Inner dot
      canvas.drawCircle(
        sat, 3.5,
        Paint()
          ..color = color.withOpacity(0.90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }

    // ── 4. Outer hex ring (slow rotation) ─────────────────
    canvas.drawPath(
      _hex(cx, cy, 50, rotation: t * math.pi / 6),
      Paint()
        ..color = purple.withOpacity(0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── 5. Main hex chip — drop shadow ────────────────────
    canvas.drawPath(
      _hex(cx, cy + 7, 34),
      Paint()
        ..color = Colors.black.withOpacity(0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // ── 6. Hex chip body — gradient (lit top-left) ────────
    final chipBounds = Rect.fromCenter(center: Offset(cx, cy), width: 68, height: 68);
    canvas.drawPath(
      _hex(cx, cy, 34),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.8, -1.0),
          end:   Alignment(0.7,  1.0),
          colors: [Color(0xFF201A50), Color(0xFF0E0A28), Color(0xFF060415)],
          stops:  [0.0,              0.55,              1.0],
        ).createShader(chipBounds),
    );

    // ── 7. Chip face inner specular ───────────────────────
    canvas.save();
    canvas.clipPath(_hex(cx, cy, 34));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 6, cy - 10), width: 36, height: 20),
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.09), Colors.transparent],
        ).createShader(Rect.fromCenter(center: Offset(cx - 6, cy - 10), width: 36, height: 20)),
    );
    canvas.restore();

    // ── 8. Animated sweep gradient border ─────────────────
    // Glow halo
    canvas.drawPath(
      _hex(cx, cy, 34),
      Paint()
        ..color = blue.withOpacity(0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Animated sweep border
    canvas.drawPath(
      _hex(cx, cy, 34),
      Paint()
        ..shader = SweepGradient(
          startAngle: t * 2 * math.pi,
          endAngle:   (t + 1) * 2 * math.pi,
          colors: const [
            Color(0xFF7B5FFF),
            Color(0xFF3B8BFF),
            Color(0xFF00D4FF),
            Color(0xFF00C896),
            Color(0xFF7B5FFF),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(chipBounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // ── 9. Inner hex ring ─────────────────────────────────
    canvas.drawPath(
      _hex(cx, cy, 22, rotation: -t * math.pi / 10),
      Paint()
        ..color = cyan.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    // ── 10. Core pulse (breathing glow) ───────────────────
    final pulseR = 10.0 + 2.0 * math.sin(t * math.pi * 2);
    canvas.drawCircle(
      Offset(cx, cy), pulseR + 10,
      Paint()
        ..color = cyan.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── 11. Core fill — radial gradient (energy core) ─────
    final coreBounds = Rect.fromCenter(center: Offset(cx, cy), width: 28, height: 28);
    canvas.drawCircle(
      Offset(cx, cy), pulseR,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFFAAE8FF),
            Color(0xFF3BB8FF),
            Color(0xFF1050CC),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(coreBounds),
    );

    // ── 12. Core specular dot (brightest point) ───────────
    canvas.drawCircle(
      Offset(cx - 2.5, cy - 2.5), 2.5,
      Paint()..color = Colors.white.withOpacity(0.60),
    );
  }

  @override
  bool shouldRepaint(_AIChipPainter old) => old.t != t;
}

// ── Unused legacy class kept for zero-warning compile ─────
class _LinearProgress extends StatelessWidget {
  final int current;
  final int total;
  const _LinearProgress({required this.current, required this.total});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
