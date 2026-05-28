import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';

// ════════════════════════════════════════════════════════════
//  PhoneOtpScreen
// ════════════════════════════════════════════════════════════
class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrls  = List.generate(8, (_) => TextEditingController());
  final _otpFocus  = List.generate(8, (_) => FocusNode());

  bool    _otpSent    = false;
  bool    _loading    = false;
  int     _resendSecs = 30;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  // ── OTP flow ─────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        data: {'type': 'email'},
      );
      setState(() { _otpSent = true; _loading = false; });
      _startResendTimer();
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _verifyOtp() async {
    final otp   = _otpCtrls.map((c) => c.text).join();
    final email = _emailCtrl.text.trim();
    if (otp.length != 8) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email, token: otp, type: OtpType.email,
      );
      if (res.session != null && mounted) {
        try {
          await api.post(ApiConstants.userRegister, data: {'email': email});
        } catch (_) {}
        try {
          final accountsRes = await api.get(ApiConstants.accounts);
          final accounts = accountsRes.data as List? ?? [];
          if (mounted) context.go(accounts.isEmpty ? '/connect' : '/home');
        } catch (_) {
          if (mounted) context.go('/connect');
        }
      }
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startResendTimer() {
    setState(() => _resendSecs = 30);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendSecs--);
      return _resendSecs > 0;
    });
  }

  void _onOtpDigitChanged(String val, int index) {
    if (val.length == 1 && index < 7) _otpFocus[index + 1].requestFocus();
    if (val.isEmpty && index > 0)     _otpFocus[index - 1].requestFocus();
    final full = _otpCtrls.map((c) => c.text).join();
    if (full.length == 8) _verifyOtp();
  }

  // ── Gradient button ───────────────────────────────────────
  Widget _gradientButton({required VoidCallback? onTap, required Widget child}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 180),
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
            boxShadow: enabled
                ? [BoxShadow(
                    color: const Color(0xFF7B5FFF).withOpacity(0.38),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )]
                : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: Stack(children: [
        // ── Background: top-centre purple haze ──────────────
        Positioned(
          top: -120, left: 0, right: 0,
          child: Container(
            height: 400,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 0.95,
                colors: [
                  const Color(0xFF7B5FFF).withOpacity(0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // ── Background: bottom-left accent glow ─────────────
        Positioned(
          bottom: -90, left: -70,
          child: Container(
            height: 300, width: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF3B2FA0).withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // ── Content ─────────────────────────────────────────
        SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24, 0, 24,
                MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // ── Premium 3D illustration ───────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(begin: 0.72, end: 1.0).animate(
                          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: _otpSent
                          ? const _OtpIllustration(key: ValueKey('otp'))
                          : const _EmailIllustration(key: ValueKey('email')),
                    ),
                    const SizedBox(height: 26),

                    // ── Title ─────────────────────────────────
                    Text(
                      _otpSent ? 'Verify OTP' : 'Sign in to ZeroTab',
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.9,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _otpSent
                          ? 'We sent an 8-digit code to\n${_emailCtrl.text}'
                          : 'Enter your email — we\'ll send a\none-time code to verify',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text2,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── Email input ───────────────────────────
                    if (!_otpSent) ...[
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF100E22),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border2),
                        ),
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'your@email.com',
                            hintStyle: TextStyle(
                              fontFamily: 'DMSans',
                              color: AppColors.text3,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: AppColors.text3,
                              size: 20,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          ),
                          onSubmitted: (_) => _sendOtp(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: AppColors.red.withOpacity(0.2)),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: AppColors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),

                      _gradientButton(
                        onTap: _loading ? null : _sendOtp,
                        child: _loading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                            : const Text('Send OTP', style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.2)),
                      ),

                    ] else ...[
                      // ── OTP digit boxes ─────────────────────
                      LayoutBuilder(
                        builder: (ctx2, c2) {
                          final boxW =
                              ((c2.maxWidth - 7 * 6) / 8).clamp(30.0, 42.0);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(8, (i) => Padding(
                              padding: EdgeInsets.only(right: i < 7 ? 6 : 0),
                              child: SizedBox(
                                width: boxW,
                                child: _OtpDigitBox(
                                  controller: _otpCtrls[i],
                                  focusNode: _otpFocus[i],
                                  onChanged: (v) => _onOtpDigitChanged(v, i),
                                ),
                              ),
                            )),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      if (_resendSecs > 0)
                        RichText(
                          text: TextSpan(children: [
                            const TextSpan(
                              text: 'Resend in  ',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 13,
                                color: AppColors.text3,
                              ),
                            ),
                            TextSpan(
                              text: '0:${_resendSecs.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontFamily: 'DMMono',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text2,
                              ),
                            ),
                          ]),
                        )
                      else
                        GestureDetector(
                          onTap: _sendOtp,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: AppColors.accent.withOpacity(0.2)),
                            ),
                            child: const Text('Resend OTP', style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.accent2,
                            )),
                          ),
                        ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: AppColors.red.withOpacity(0.2)),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 13,
                              color: AppColors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      _gradientButton(
                        onTap: _loading ? null : _verifyOtp,
                        child: _loading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                            : const Text('Verify & Continue', style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.2)),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ── Privacy footnote ──────────────────────
                    const Text(
                      'By continuing you agree to our Terms & Privacy Policy.'
                      '\nYour data stays private — always.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        color: AppColors.text3,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  Email Illustration  — pre-OTP state
//  Premium 3D floating envelope with @ symbol, pulse rings,
//  orbital particles, ground shadow and glassmorphic specular.
// ════════════════════════════════════════════════════════════
class _EmailIllustration extends StatefulWidget {
  const _EmailIllustration({super.key});

  @override
  State<_EmailIllustration> createState() => _EmailIllustrationState();
}

class _EmailIllustrationState extends State<_EmailIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
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
      builder: (_, __) => CustomPaint(
        painter: _EmailPainter(_ctrl.value),
        size: const Size(160, 160),
      ),
    );
  }
}

class _EmailPainter extends CustomPainter {
  final double t;
  _EmailPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; // 80

    // Floating vertical offset (gentle bob)
    final float = 4.0 * math.sin(t * 2 * math.pi);

    // Envelope geometry
    const eL = 16.0;
    const eR = 144.0;
    const eW = eR - eL; // 128
    const eH = 56.0;
    final eT = 46.0 + float;
    final eB = eT + eH;
    final eCy = eT + eH / 2;

    final eRect  = Rect.fromLTRB(eL, eT, eR, eB);
    final eRRect = RRect.fromRectAndRadius(eRect, const Radius.circular(10));

    // ── 1. Ground shadow (scales as envelope rises/falls) ─────────────
    final shadowPulse = 1.0 - 0.10 * (math.sin(t * 2 * math.pi) * 0.5 + 0.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, 114.0),
        width: 92 * shadowPulse,
        height: 9 * shadowPulse,
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // ── 2. Wide ambient purple halo ────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, eCy),
      70,
      Paint()
        ..color = const Color(0xFF7B5FFF).withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );

    // ── 3. Offset teal accent glow (adds colour richness) ─────────────
    canvas.drawCircle(
      Offset(cx + 20, eCy - 16),
      42,
      Paint()
        ..color = const Color(0xFF3BB8FF).withOpacity(0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // ── 4. Three expanding pulse rings ────────────────────────────────
    for (int i = 0; i < 3; i++) {
      final phase = (t + i * 0.3333) % 1.0;
      final r     = 44.0 + phase * 36.0;
      final alpha = (1.0 - phase) * 0.19;
      canvas.drawCircle(
        Offset(cx, eCy),
        r,
        Paint()
          ..color = const Color(0xFF7B5FFF).withOpacity(alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }

    // ── 5. Orbital micro-particles (elliptical path) ───────────────────
    for (int i = 0; i < 8; i++) {
      final angle  = (2 * math.pi * i / 8) + t * 2 * math.pi * 0.20;
      const orbitX = 60.0;
      const orbitY = 34.0;
      final px = cx      + orbitX * math.cos(angle);
      final py = eCy + orbitY * math.sin(angle);
      // skip if point is inside the envelope body
      final inside = px > eL + 3 && px < eR - 3 && py > eT + 2 && py < eB - 2;
      if (!inside) {
        final bright = 0.40 + 0.60 *
            (math.sin(t * 2 * math.pi * 2.2 + i * 0.85) * 0.5 + 0.5);
        canvas.drawCircle(
          Offset(px, py),
          2.0,
          Paint()..color =
              const Color(0xFF9D8FFF).withOpacity(0.30 + 0.65 * bright),
        );
      }
    }

    // ── 6. Envelope drop shadow ────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(eRect.translate(0, 10), const Radius.circular(10)),
      Paint()
        ..color = Colors.black.withOpacity(0.52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // ── 7. Envelope body — 3-stop LinearGradient (lit top-left) ───────
    canvas.drawRRect(
      eRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C1F72), Color(0xFF150D3E), Color(0xFF070414)],
          stops: [0.0, 0.48, 1.0],
        ).createShader(eRect),
    );

    // ── 8. Inner specular oval (surface lit top-left) ──────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(eL + 26, eT + 13),
        width: 40,
        height: 18,
      ),
      Paint()
        ..color = Colors.white.withOpacity(0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // ── 9. Rim glow ────────────────────────────────────────────────────
    canvas.drawRRect(
      eRRect,
      Paint()
        ..color = const Color(0xFF7B5FFF).withOpacity(0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── 10. Crisp 1px border ───────────────────────────────────────────
    canvas.drawRRect(
      eRRect,
      Paint()
        ..color = const Color(0xFF7B5FFF).withOpacity(0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ── 11. Flap (V-fold pointing down into envelope) ──────────────────
    // Flap peak depth breathes subtly with animation
    final flapDepth = 23.0 + 2.5 * math.sin(t * 2 * math.pi);
    final flapPeakY = eT + flapDepth;

    final flapPath = Path()
      ..moveTo(eL, eT)
      ..lineTo(cx, flapPeakY)
      ..lineTo(eR, eT);

    canvas.save();
    canvas.clipRRect(eRRect);

    // Flap fill — slightly lighter purple
    canvas.drawPath(
      flapPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF3D2895),
            const Color(0xFF1F1362),
          ],
        ).createShader(Rect.fromLTWH(eL, eT, eW, flapDepth + 4)),
    );

    // Fold crease specular highlight
    canvas.drawPath(
      Path()
        ..moveTo(eL + 5,  eT + 1.0)
        ..lineTo(cx - 6,  flapPeakY - 4)
        ..lineTo(cx + 6,  flapPeakY - 4)
        ..lineTo(eR - 5,  eT + 1.0),
      Paint()
        ..color = Colors.white.withOpacity(0.16)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Flap edge crease
    canvas.drawPath(
      flapPath,
      Paint()
        ..color = const Color(0xFF7B5FFF).withOpacity(0.28)
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();

    // ── 12. @ symbol — glow pass then crisp pass ───────────────────────
    final atCx = cx;
    final atCy = eT + 36.0; // below flap crease, vertical centre of body
    const atR  = 10.5;

    // Glow layer
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, 7),
    );
    _drawAt(canvas, Offset(atCx, atCy), atR,
        const Color(0xFF9D8FFF).withOpacity(0.65));
    canvas.restore();

    // Crisp layer
    _drawAt(canvas, Offset(atCx, atCy), atR, Colors.white.withOpacity(0.90));

    // ── 13. Top-left corner specular dot ──────────────────────────────
    canvas.drawCircle(
      Offset(eL + 7, eT + 7),
      4.5,
      Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // ── 14. Travelling data-packet particles (right edge → right) ──────
    // 3 small dots shoot outward from the right edge of the envelope,
    // suggesting an email being dispatched.
    for (int i = 0; i < 3; i++) {
      final phase = (t + i * 0.333) % 1.0;
      final px = eR + 4 + phase * 28;
      final py = eCy + (i - 1) * 8.0;
      final alpha = (1.0 - phase) * 0.70;
      // glow
      canvas.drawCircle(
        Offset(px, py),
        3.5,
        Paint()
          ..color = const Color(0xFF7B5FFF).withOpacity(alpha * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // body
      canvas.drawCircle(
        Offset(px, py),
        2.0,
        Paint()..color = const Color(0xFFB8A6FF).withOpacity(alpha),
      );
      // white core
      canvas.drawCircle(
        Offset(px, py),
        0.9,
        Paint()..color = Colors.white.withOpacity(alpha),
      );
    }
  }

  /// Draws an "@" symbol using canvas arcs centred at [c] with outer
  /// radius [r] in the given [color].
  void _drawAt(Canvas canvas, Offset c, double r, Color color) {
    final sw = (r * 0.155).clamp(1.4, 2.8);
    final p  = Paint()
      ..color      = color
      ..strokeWidth = sw
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // Inner "a" ring
    canvas.drawCircle(c, r * 0.44, p);

    // Outer arc (~270°, open gap on right side)
    canvas.drawArc(
      Rect.fromCenter(center: c, width: r * 2, height: r * 2),
      math.pi * 0.50,       // start at 6 o'clock
      -(math.pi * 1.55),    // sweep 279° counter-clockwise → ends ~3 o'clock
      false,
      p,
    );

    // Tail: short vertical line on right completing the @
    canvas.drawLine(
      Offset(c.dx + r, c.dy - r * 0.30),
      Offset(c.dx + r, c.dy + r * 0.70),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _EmailPainter old) => old.t != t;
}

// ════════════════════════════════════════════════════════════
//  OTP Illustration  — post-OTP-sent state
//  Premium 3D floating shield with teal glow, pulse rings,
//  breathing checkmark and glassmorphic specular.
// ════════════════════════════════════════════════════════════
class _OtpIllustration extends StatefulWidget {
  const _OtpIllustration({super.key});

  @override
  State<_OtpIllustration> createState() => _OtpIllustrationState();
}

class _OtpIllustrationState extends State<_OtpIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
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
      builder: (_, __) => CustomPaint(
        painter: _OtpPainter(_ctrl.value),
        size: const Size(160, 160),
      ),
    );
  }
}

class _OtpPainter extends CustomPainter {
  final double t;
  _OtpPainter(this.t);

  // Flat-top shield with curved bottom tapering to a point.
  Path _shieldPath(double l, double top, double r, double b, double cx) {
    return Path()
      ..moveTo(l, top)
      ..lineTo(r, top)
      ..lineTo(r, top + (b - top) * 0.58)
      ..quadraticBezierTo(r, b, cx, b)
      ..quadraticBezierTo(l, b, l, top + (b - top) * 0.58)
      ..close();
  }

  void _drawShield(Canvas canvas, double l, double top, double r, double b,
      double cx, Paint paint) {
    canvas.drawPath(_shieldPath(l, top, r, b, cx), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx  = size.width / 2; // 80
    final float = 4.0 * math.sin(t * 2 * math.pi);
    final cy  = size.height / 2 + float; // ~80 + float

    // Shield geometry
    const sHalfW = 40.0;
    const sH     = 86.0;
    final sL = cx - sHalfW;
    final sR = cx + sHalfW;
    final sT = cy - sH * 0.50;
    final sB = sT + sH;

    // ── 1. Ground shadow ──────────────────────────────────────────────
    final ss = 1.0 - 0.10 * (math.sin(t * 2 * math.pi) * 0.5 + 0.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, 118.0),
        width: 72 * ss,
        height: 9 * ss,
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // ── 2. Wide ambient teal halo ─────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      70,
      Paint()
        ..color = const Color(0xFF00C9B1).withOpacity(0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );

    // ── 3. Secondary accent glow (off-centre, adds depth) ─────────────
    canvas.drawCircle(
      Offset(cx - 18, cy - 14),
      40,
      Paint()
        ..color = const Color(0xFF7B5FFF).withOpacity(0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    // ── 4. Three expanding teal pulse rings ───────────────────────────
    for (int i = 0; i < 3; i++) {
      final phase = (t + i * 0.3333) % 1.0;
      final r     = 42.0 + phase * 36.0;
      final alpha = (1.0 - phase) * 0.19;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = const Color(0xFF00C9B1).withOpacity(alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }

    // ── 5. Orbital micro-particles ────────────────────────────────────
    for (int i = 0; i < 6; i++) {
      final angle  = (2 * math.pi * i / 6) + t * 2 * math.pi * 0.18;
      const rx = 58.0, ry = 34.0;
      final px = cx + rx * math.cos(angle);
      final py = cy + ry * math.sin(angle);
      // skip if inside shield bounding box
      final inside = px > sL + 4 && px < sR - 4 && py > sT && py < sB;
      if (!inside && px > 2 && px < 158 && py > 2 && py < 158) {
        final bright = 0.40 + 0.60 *
            (math.sin(t * 2 * math.pi * 2.0 + i * 1.05) * 0.5 + 0.5);
        canvas.drawCircle(
          Offset(px, py),
          2.0,
          Paint()..color =
              const Color(0xFF00C9B1).withOpacity(0.28 + 0.65 * bright),
        );
      }
    }

    // ── 6. Shield drop shadow ─────────────────────────────────────────
    _drawShield(canvas, sL, sT + 10, sR, sB + 10, cx,
        Paint()
          ..color = Colors.black.withOpacity(0.52)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));

    // ── 7. Shield body — 3-stop gradient (lit top-left) ───────────────
    _drawShield(canvas, sL, sT, sR, sB, cx,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              Color(0xFF0E3D3A),
              Color(0xFF082424),
              Color(0xFF030F10),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromLTRB(sL, sT, sR, sB)));

    // ── 8. Inner specular oval (surface lit top-left) ──────────────────
    canvas.save();
    canvas.clipPath(_shieldPath(sL, sT, sR, sB, cx));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(sL + 20, sT + 13),
        width: 34,
        height: 15,
      ),
      Paint()
        ..color = Colors.white.withOpacity(0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();

    // ── 9. Rim glow ───────────────────────────────────────────────────
    _drawShield(canvas, sL, sT, sR, sB, cx,
        Paint()
          ..color = const Color(0xFF00C9B1).withOpacity(0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // ── 10. Crisp border ──────────────────────────────────────────────
    _drawShield(canvas, sL, sT, sR, sB, cx,
        Paint()
          ..color = const Color(0xFF00C9B1).withOpacity(0.68)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // ── 11. Inner concentric shield ring ──────────────────────────────
    _drawShield(canvas, sL + 8, sT + 8, sR - 8, sB - 10, cx,
        Paint()
          ..color = const Color(0xFF00C9B1).withOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // ── 12. Breathing centre glow ─────────────────────────────────────
    final breathe = 0.55 + 0.45 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(
      Offset(cx, cy + 2),
      18,
      Paint()
        ..color = const Color(0xFF00C9B1).withOpacity(0.08 * breathe)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── 13. Checkmark — glow pass then crisp pass ─────────────────────
    // The checkmark pulses subtly (opacity breathes)
    final checkAlpha = 0.62 + 0.38 * math.sin(t * 2 * math.pi);

    final checkPath = Path()
      ..moveTo(cx - 14, cy + 4)
      ..lineTo(cx - 2,  cy + 16)
      ..lineTo(cx + 18, cy - 12);

    // Glow
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = const Color(0xFF00C9B1).withOpacity(checkAlpha * 0.35)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Crisp white outline
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white.withOpacity(checkAlpha * 0.30)
        ..strokeWidth = 5.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Crisp teal stroke
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = const Color(0xFF00C9B1).withOpacity(checkAlpha)
        ..strokeWidth = 3.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── 14. Top-left corner specular dot ──────────────────────────────
    canvas.drawCircle(
      Offset(sL + 6, sT + 7),
      4.0,
      Paint()
        ..color = Colors.white.withOpacity(0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _OtpPainter old) => old.t != t;
}

// ════════════════════════════════════════════════════════════
//  OTP digit box
// ════════════════════════════════════════════════════════════
class _OtpDigitBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final ValueChanged<String>  onChanged;

  const _OtpDigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  State<_OtpDigitBox> createState() => _OtpDigitBoxState();
}

class _OtpDigitBoxState extends State<_OtpDigitBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (widget.controller.text.isNotEmpty) {
      _ctrl.forward().then((_) => _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        height: 52,
        child: TextField(
          controller:   widget.controller,
          focusNode:    widget.focusNode,
          textAlign:    TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: const TextStyle(
            fontFamily:  'DMMono',
            fontSize:    20,
            fontWeight:  FontWeight.w500,
            color:       AppColors.accent2,
            letterSpacing: 0,
          ),
          decoration: InputDecoration(
            filled:    true,
            fillColor: AppColors.bg3,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppColors.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(
                color: AppColors.accent, width: 1.5),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
