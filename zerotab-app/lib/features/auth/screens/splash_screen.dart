import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/zerotab_logo.dart';

// ════════════════════════════════════════════════════════════════
//  ZeroTab Splash — "Escape from Zero" story animation
//
//  THE STORY:
//   1. DARKNESS       — empty void (the financial unknown)
//   2. RING FORMS     — the Zero, the debt trap, forms around you
//   3. Z AWAKENS      — you appear at the center
//   4. THE BURDEN     — ring pulses/constricts (debt pressing in)
//   5. THE RUN        — your wealth dot races along the ring
//   6. THE ESCAPE     — dot BURSTS through the gap — FREEDOM
//   7. SETTLE         — logo lands in final state, name reveals
// ════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers (one per story beat) ───────────────
  late AnimationController _ringCtrl;    // ring draws in
  late AnimationController _zCtrl;       // Z appears
  late AnimationController _pulseCtrl;   // ring constricts (burden)
  late AnimationController _dotCtrl;     // dot travels + escapes
  late AnimationController _burstCtrl;   // escape flash
  late AnimationController _flyCtrl;     // dot floats free
  late AnimationController _nameCtrl;    // brand name + tagline

  // Animated values
  late Animation<double> _ringDraw;
  late Animation<double> _ringPulse;
  late Animation<double> _zScale;
  late Animation<double> _zFade;
  late Animation<double> _dotTravel;
  late Animation<double> _burstGlow;
  late Animation<double> _flyProgress;
  late Animation<double> _nameFade;
  late Animation<double> _taglineFade;
  late Animation<Offset> _nameSlide;

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    _runStory();
    _navigate();
  }

  void _buildAnimations() {
    // Ring draws: 500ms
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _ringDraw = CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut);

    // Z appears: 350ms spring
    _zCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _zScale = Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _zCtrl, curve: Curves.easeOutBack));
    _zFade = CurvedAnimation(parent: _zCtrl, curve: Curves.easeIn);

    // Ring pulse — burden (300ms, repeat 1.5x then settle)
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _ringPulse = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.028), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.028, end: 0.985), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.985, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Dot travels along ring (700ms, ease-in = acceleration)
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _dotTravel =
        CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInCubic);

    // Burst at escape point (280ms)
    _burstCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _burstGlow = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 65),
    ]).animate(CurvedAnimation(parent: _burstCtrl, curve: Curves.easeOut));

    // Dot flies free (500ms)
    _flyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _flyProgress =
        CurvedAnimation(parent: _flyCtrl, curve: Curves.easeOutCubic);

    // Name + tagline reveal (450ms)
    _nameCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _nameFade    = CurvedAnimation(parent: _nameCtrl, curve: Curves.easeOut);
    _taglineFade = CurvedAnimation(
        parent: _nameCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut));
    _nameSlide = Tween<Offset>(
            begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(parent: _nameCtrl, curve: Curves.easeOut));
  }

  // ── Choreography ─────────────────────────────────────────────
  Future<void> _runStory() async {
    // Phase 1: Darkness (300ms pause)
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Phase 2: Ring forms
    _ringCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 440));
    if (!mounted) return;

    // Phase 3: Z awakens
    _zCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // Phase 4: The burden (ring pulses)
    _pulseCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;

    // Phase 5: The run — dot races around ring
    _dotCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 580));
    if (!mounted) return;

    // Phase 6: Burst + fly free (dot exits the ring)
    _burstCtrl.forward();
    _flyCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    // Phase 7: Brand name reveals
    _nameCtrl.forward();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    context.go(session != null ? '/home' : '/onboard');
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _zCtrl.dispose();
    _pulseCtrl.dispose();
    _dotCtrl.dispose();
    _burstCtrl.dispose();
    _flyCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kZtVoidBlack,
      body: Stack(
        children: [
          // Subtle mesh background
          Positioned.fill(child: _MeshLines()),

          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Animated logo ─────────────────────────────
                SizedBox(
                  width: 200, height: 200,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _ringCtrl, _zCtrl, _pulseCtrl,
                      _dotCtrl, _burstCtrl, _flyCtrl,
                    ]),
                    builder: (_, __) => CustomPaint(
                      painter: _StoryPainter(
                        ringDraw:    _ringDraw.value,
                        ringPulse:   _ringCtrl.isAnimating ||
                                     _ringCtrl.isCompleted
                            ? _ringPulse.value : 1.0,
                        zScale:     _zCtrl.isAnimating || _zCtrl.isCompleted
                            ? _zScale.value : 0.0,
                        zFade:      _zCtrl.isAnimating || _zCtrl.isCompleted
                            ? _zFade.value : 0.0,
                        dotTravel:  _dotTravel.value,
                        dotActive:  _dotCtrl.isAnimating || _dotCtrl.isCompleted,
                        burstGlow:  _burstGlow.value,
                        flyProgress: _flyProgress.value,
                        flyActive:  _flyCtrl.isAnimating || _flyCtrl.isCompleted,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Brand name ────────────────────────────────
                FadeTransition(
                  opacity: _nameFade,
                  child: SlideTransition(
                    position: _nameSlide,
                    child: const Text(
                      'ZeroTab',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Tagline ───────────────────────────────────
                FadeTransition(
                  opacity: _taglineFade,
                  child: const Text(
                    'YOUR WEALTH, FINALLY LEGIBLE',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2.0,
                      color: AppColors.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Version
          Positioned(
            bottom: 32, right: 24,
            child: FadeTransition(
              opacity: _nameFade,
              child: const Text('v1.0.0',
                  style: TextStyle(
                      fontFamily: 'DMMono', fontSize: 11,
                      color: AppColors.text3)),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Story Painter — draws each frame of the escape animation
// ════════════════════════════════════════════════════════════════

class _StoryPainter extends CustomPainter {
  final double ringDraw;
  final double ringPulse;
  final double zScale;
  final double zFade;
  final double dotTravel;
  final bool   dotActive;
  final double burstGlow;
  final double flyProgress;
  final bool   flyActive;

  const _StoryPainter({
    required this.ringDraw,
    required this.ringPulse,
    required this.zScale,
    required this.zFade,
    required this.dotTravel,
    required this.dotActive,
    required this.burstGlow,
    required this.flyProgress,
    required this.flyActive,
  });

  // Dot travels from ghost (7 o'clock) clockwise to escape (11 o'clock)
  static const _ghostAngle  = math.pi / 2 + math.pi / 4.2;  // 7 o'clock
  static const _escapeAngle = ZeroTabLogoPainter.escapeAngle; // 11 o'clock
  // Clockwise: increase angle (add 2π to escape so it's > ghost)
  static const _escapeFull  = _escapeAngle + math.pi * 2;    // same point, +360°
  static const _travelSweep = _escapeFull - _ghostAngle;     // ~104° clockwise

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final ringR = w * 0.350;

    // ── 1. Ring (forms progressively) ───────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(ringPulse, ringPulse);
    canvas.translate(-cx, -cy);

    ZeroTabLogoPainter.drawRing(canvas, cx, cy, ringR, w,
        progress: ringDraw);

    canvas.restore();

    // ── 2. Ghost dot at 7 o'clock (before dot starts moving) ────
    if (ringDraw > 0.8 && !dotActive) {
      ZeroTabLogoPainter.drawGhostDot(canvas, cx, cy, ringR, w,
          alpha: ((ringDraw - 0.8) / 0.2).clamp(0.0, 0.35));
    }

    // ── 3. Z appears (spring scale + fade) ──────────────────────
    ZeroTabLogoPainter.drawZ(canvas, cx, cy, w,
        opacity: zFade, scale: zScale);

    // ── 4. Travelling dot ────────────────────────────────────────
    if (dotActive && dotTravel < 1.0) {
      final angle = _ghostAngle + _travelSweep * dotTravel;
      final dotR  = w * 0.048 + w * 0.012 * dotTravel; // grows as it accelerates

      // Speed trail — 5 ghost dots behind current position
      for (int i = 1; i <= 5; i++) {
        final trailT = (dotTravel - i * 0.04).clamp(0.0, 1.0);
        final trailAngle = _ghostAngle + _travelSweep * trailT;
        final trailAlpha = (1 - i * 0.18) * dotTravel;
        final trailR     = dotR * (1 - i * 0.12);
        if (trailAlpha > 0) {
          canvas.drawCircle(
            Offset(cx + ringR * 0.93 * math.cos(trailAngle),
                   cy + ringR * 0.93 * math.sin(trailAngle)),
            trailR.clamp(1.0, dotR),
            Paint()
              ..color      = kZtCyan.withValues(alpha: trailAlpha * 0.35)
              ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal, 3 + i.toDouble()),
          );
        }
      }

      ZeroTabLogoPainter.drawDotOnRing(
          canvas, cx, cy, ringR, w,
          angle: angle, glowRadius: dotR, alpha: 1.0);
    }

    // ── 5. Burst flash at escape point ───────────────────────────
    if (burstGlow > 0) {
      final ex = cx + ringR * 0.93 * math.cos(_escapeAngle);
      final ey = cy + ringR * 0.93 * math.sin(_escapeAngle);

      // Shockwave ring expanding outward
      canvas.drawCircle(
        Offset(ex, ey),
        w * 0.08 + w * 0.18 * burstGlow,
        Paint()
          ..color      = kZtCyan.withValues(alpha: burstGlow * 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..style      = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      // Core white flash
      canvas.drawCircle(
        Offset(ex, ey),
        w * 0.055 + w * 0.04 * burstGlow,
        Paint()
          ..color      = Colors.white.withValues(alpha: burstGlow * 0.90)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * burstGlow),
      );
    }

    // ── 6. Escaped dot floating upward ────────────────────────────
    if (flyActive && flyProgress > 0) {
      final ex = cx + ringR * 0.93 * math.cos(_escapeAngle);
      final ey = cy + ringR * 0.93 * math.sin(_escapeAngle);

      // Dot floats up and slightly right, fading out
      final flyX = ex + w * 0.08 * flyProgress;
      final flyY = ey - w * 0.22 * flyProgress;
      final alpha = (1.0 - flyProgress * 0.85).clamp(0.0, 1.0);
      final dotR  = w * 0.055 * (1.0 - flyProgress * 0.4);

      canvas.drawCircle(Offset(flyX, flyY), dotR * 2.0,
          Paint()
            ..color      = kZtCyan.withValues(alpha: alpha * 0.20)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(flyX, flyY), dotR,
          Paint()..color = Colors.white.withValues(alpha: alpha));

      // Show static dot at escape gap once dot has flown away
      if (flyProgress > 0.5) {
        final settled = ((flyProgress - 0.5) / 0.5).clamp(0.0, 1.0);
        ZeroTabLogoPainter.drawDotOnRing(
            canvas, cx, cy, ringR, w,
            angle: _escapeAngle,
            glowRadius: w * 0.048,
            alpha: settled * 0.85);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StoryPainter old) => true;
}

// ── Subtle mesh lines background ─────────────────────────────────

class _MeshLines extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _MeshPainter());
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color       = const Color(0x067B5FFF)
      ..strokeWidth = 0.5
      ..style       = PaintingStyle.stroke;

    final cx = size.width / 2, cy = size.height / 2;

    for (final deg in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]) {
      final rad = deg * math.pi / 180;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + size.width  * 0.65 * math.cos(rad),
               cy + size.height * 0.65 * math.sin(rad)),
        p,
      );
    }

    for (final r in [80.0, 160.0, 260.0]) {
      canvas.drawCircle(Offset(cx, cy), r,
          p..color = const Color(0x047B5FFF));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
