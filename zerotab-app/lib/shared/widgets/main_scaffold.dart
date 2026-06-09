import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import 'ai_brain_icon.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _tabs = [
    _TabItem(label: 'Home',   route: '/home'),
    _TabItem(label: 'Spend',  route: '/transactions'),
    _TabItem(label: 'Invest', route: '/investments'),
    _TabItem(label: 'Debt',   route: '/debt'),
    _TabItem(label: 'More',   route: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location     = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t.route));

    final isOnChat = location.startsWith('/chat');

    return Scaffold(
      body: Stack(
        children: [
          child,
          // ── AI chat FAB — bottom-right on ALL pages (except chat) ──
          if (!isOnChat)
            Positioned(
              bottom: 16,
              right: 16,
              child: _AiChatFab(onTap: () => context.go('/chat')),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xF4121020),
          border: Border(
              top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = i == currentIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => context.go(_tabs[i].route),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Custom SVG icon — no emoji, no Material icon
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CustomPaint(
                            painter: _NavIconPainter(
                              index: i,
                              active: active,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabs[i].label,
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: active
                                ? AppColors.accent2
                                : AppColors.text3,
                          ),
                        ),
                        // Active dot indicator
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: active ? 14 : 0,
                          height: 2,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final String route;
  const _TabItem({required this.label, required this.route});
}

// ── Custom SVG nav icons — 1.5px stroke, rounded linecap ─

class _NavIconPainter extends CustomPainter {
  final int index;
  final bool active;
  const _NavIconPainter({required this.index, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final color = active ? AppColors.accent2 : AppColors.text3;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (index) {
      case 0: // Home — house outline
        _drawHome(canvas, paint, w, h);
        break;
      case 1: // Spend — card with line
        _drawCard(canvas, paint, w, h);
        break;
      case 2: // Invest — rising bar chart
        _drawChart(canvas, paint, w, h);
        break;
      case 3: // Debt — shield with %
        _drawShield(canvas, paint, w, h);
        break;
      case 4: // More — 2×2 grid
        _drawGrid(canvas, paint, w, h);
        break;
    }
  }

  void _drawHome(Canvas canvas, Paint p, double w, double h) {
    // Roof
    final roof = Path()
      ..moveTo(w * 0.08, h * 0.52)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.92, h * 0.52);
    canvas.drawPath(roof, p);
    // Walls + base
    final walls = Path()
      ..moveTo(w * 0.18, h * 0.52)
      ..lineTo(w * 0.18, h * 0.92)
      ..lineTo(w * 0.82, h * 0.92)
      ..lineTo(w * 0.82, h * 0.52);
    canvas.drawPath(walls, p);
    // Door
    final door = Path()
      ..moveTo(w * 0.40, h * 0.92)
      ..lineTo(w * 0.40, h * 0.68)
      ..arcToPoint(Offset(w * 0.60, h * 0.68),
          radius: Radius.circular(w * 0.10), clockwise: false)
      ..lineTo(w * 0.60, h * 0.92);
    canvas.drawPath(door, p);
  }

  void _drawCard(Canvas canvas, Paint p, double w, double h) {
    // Card body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.20, w * 0.88, h * 0.60),
        Radius.circular(w * 0.12),
      ),
      p,
    );
    // Magnetic stripe
    canvas.drawLine(
      Offset(w * 0.06, h * 0.46),
      Offset(w * 0.94, h * 0.46),
      p..strokeWidth = 2.0,
    );
    // Chip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.57, w * 0.22, h * 0.15),
        const Radius.circular(2),
      ),
      p..strokeWidth = 1.5,
    );
  }

  void _drawChart(Canvas canvas, Paint p, double w, double h) {
    // 3 ascending bars
    final bars = [
      [w * 0.14, h * 0.92, h * 0.55],
      [w * 0.44, h * 0.92, h * 0.28],
      [w * 0.74, h * 0.92, h * 0.08],
    ];
    for (final b in bars) {
      canvas.drawLine(
        Offset(b[0], b[1]),
        Offset(b[0], b[2]),
        p..strokeWidth = 5.0..strokeCap = StrokeCap.round,
      );
    }
    // Baseline
    canvas.drawLine(
      Offset(w * 0.06, h * 0.92),
      Offset(w * 0.94, h * 0.92),
      p..strokeWidth = 1.5..strokeCap = StrokeCap.round,
    );
    // Trend line
    final trend = Path()
      ..moveTo(w * 0.14, h * 0.55)
      ..lineTo(w * 0.44, h * 0.28)
      ..lineTo(w * 0.74, h * 0.08);
    canvas.drawPath(trend, p..strokeWidth = 1.2..strokeCap = StrokeCap.round);
  }

  void _drawShield(Canvas canvas, Paint p, double w, double h) {
    final shield = Path()
      ..moveTo(w * 0.50, h * 0.06)
      ..lineTo(w * 0.90, h * 0.22)
      ..lineTo(w * 0.90, h * 0.56)
      ..quadraticBezierTo(w * 0.90, h * 0.86, w * 0.50, h * 0.94)
      ..quadraticBezierTo(w * 0.10, h * 0.86, w * 0.10, h * 0.56)
      ..lineTo(w * 0.10, h * 0.22)
      ..close();
    canvas.drawPath(shield, p..strokeWidth = 1.5);
    // % symbol inside
    canvas.drawCircle(Offset(w * 0.36, h * 0.44), w * 0.06,
        p..strokeWidth = 1.2);
    canvas.drawCircle(Offset(w * 0.64, h * 0.64), w * 0.06,
        p..strokeWidth = 1.2);
    canvas.drawLine(
        Offset(w * 0.66, h * 0.38), Offset(w * 0.34, h * 0.70), p);
  }

  void _drawGrid(Canvas canvas, Paint p, double w, double h) {
    // 2×2 grid of rounded squares
    final positions = [
      Rect.fromLTWH(w * 0.08, h * 0.08, w * 0.36, h * 0.36),
      Rect.fromLTWH(w * 0.56, h * 0.08, w * 0.36, h * 0.36),
      Rect.fromLTWH(w * 0.08, h * 0.56, w * 0.36, h * 0.36),
      Rect.fromLTWH(w * 0.56, h * 0.56, w * 0.36, h * 0.36),
    ];
    for (final r in positions) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        p..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_NavIconPainter old) =>
      old.active != active || old.index != index;
}

// ── AI Chat FAB — bottom-right on all pages ──────────────────────

class _AiChatFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AiChatFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          // Deep dark radial shell — near-black violet core fading to dark navy
          gradient: const RadialGradient(
            center: Alignment(-0.2, -0.3),
            radius: 1.0,
            colors: [
              Color(0xFF1C0A4A), // deep violet center
              Color(0xFF070D1F), // near-black navy edge
            ],
          ),
          shape: BoxShape.circle,
          // Subtle gradient border ring
          border: Border.all(
            color: AppColors.accent,
            width: 1.0,
          ),
          boxShadow: [
            // Outer violet glow
            const BoxShadow(
              color: Color(0x4D7B5FFF), // violet 30%
              blurRadius: 18,
              spreadRadius: 0,
              offset: Offset(0, 4),
            ),
            // Inner cyan halo
            const BoxShadow(
              color: Color(0x3300C4A8), // cyan 20%
              blurRadius: 8,
              spreadRadius: 0,
              offset: Offset(0, 0),
            ),
            // Base shadow for depth
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const AiBrainIcon(size: 28),
      ),
    );
  }
}
