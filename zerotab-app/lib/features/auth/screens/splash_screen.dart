import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/zt_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Main logo entrance
  late AnimationController _logoCtrl;
  late Animation<double>    _logoScale;
  late Animation<double>    _logoFade;

  // Tagline reveal — delayed after logo settles
  late AnimationController _taglineCtrl;
  late Animation<double>    _taglineFade;

  // Radial ring pulse expanding outward from logo
  late AnimationController _ringCtrl;
  late Animation<double>    _ringScale;
  late Animation<double>    _ringFade;

  @override
  void initState() {
    super.initState();

    // Logo: spring scale 0.82 → 1.0 over 420ms
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);

    // Ring: starts at logo settle, expands outward
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ringScale = Tween<double>(begin: 0.0, end: 2.4).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut),
    );
    _ringFade = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut),
    );

    // Tagline: fades in 200ms after logo settles
    _taglineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _taglineFade = CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut);

    // Choreography
    _logoCtrl.forward().then((_) {
      _ringCtrl.forward();
      _taglineCtrl.forward();
    });

    _navigate();
  }

  Future<void> _navigate() async {
    // 200ms — just enough for the logo animation to breathe.
    // The GoRouter redirect handles auth check; splash just kicks it off.
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    context.go(session != null ? '/home' : '/onboard');
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _ringCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Stack(
        children: [
          // ── Subtle geometric mesh lines (background texture) ──
          Positioned.fill(child: _MeshLines()),

          // ── Main content ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo mark with ring pulse
                SizedBox(
                  width: 160, height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ring expanding outward
                      AnimatedBuilder(
                        animation: _ringCtrl,
                        builder: (_, __) => Opacity(
                          opacity: _ringFade.value,
                          child: Transform.scale(
                            scale: _ringScale.value,
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.accent,
                                  width: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Logo mark — ZTLogo geometric Z
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer glow halo
                              Container(
                                width: 96, height: 96,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.45),
                                      blurRadius: 52,
                                      spreadRadius: 4,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                              ),
                              // Logo tile
                              ZTLogo(
                                size: 80,
                                style: ZTLogoStyle.gradient,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Brand name
                FadeTransition(
                  opacity: _logoFade,
                  child: const Text(
                    'ZeroTab',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0,
                      color: AppColors.text,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Tagline — delayed fade
                FadeTransition(
                  opacity: _taglineFade,
                  child: const Text(
                    'YOUR WEALTH, FINALLY LEGIBLE',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.8,
                      color: AppColors.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Version string — bottom right, DM Mono ──
          Positioned(
            bottom: 32, right: 24,
            child: FadeTransition(
              opacity: _taglineFade,
              child: const Text(
                'v1.0.0',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 11,
                  color: AppColors.text3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subtle mesh line background ───────────────────────────

class _MeshLines extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MeshPainter(),
    );
  }
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x087B5FFF)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // 6 radiating lines from center
    const angles = [0.0, 60.0, 120.0, 180.0, 240.0, 300.0];
    for (final deg in angles) {
      final rad = deg * math.pi / 180;
      final dx = cx + size.width * 0.65 * math.cos(rad);
      final dy = cy + size.height * 0.65 * math.sin(rad);
      canvas.drawLine(Offset(cx, cy), Offset(dx, dy), paint);
    }

    // Concentric subtle rings
    for (final r in [80.0, 160.0, 260.0]) {
      canvas.drawCircle(
        Offset(cx, cy), r,
        paint..color = const Color(0x057B5FFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
