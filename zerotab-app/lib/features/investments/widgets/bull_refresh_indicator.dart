// BullRefreshIndicator — custom pull-to-refresh painted as 5 vertical
// "candles" growing bottom-up. Pure Flutter — no external dependencies.
//
// The spec called for the `custom_refresh_indicator` package; since this
// project must stay dep-free, this widget reimplements the same surface
// area against the built-in `RefreshIndicator` machinery. It works by:
//
//   • Wrapping the scrollable in a `RefreshIndicator` whose visual indicator
//     is hidden (`color: Colors.transparent`, `displacement: 0`).
//   • Listening to `OverscrollNotification` + `ScrollUpdateNotification`
//     to drive a local 0..1 drag-value `AnimationController`-style state.
//   • Painting our own 5-candle indicator in a `Positioned` `SizedBox` at
//     the top of the `Stack`.
//
// Lifecycle states (idle → dragging → armed → loading → complete → idle)
// drive haptics:
//   • Light impact when crossing the armed threshold.
//   • Medium impact on entry to loading.
//   • No haptic on complete — the visual closes the loop.
//
// Accessibility: when `MediaQuery.disableAnimations` is true, the loading
// loop falls back to a static held-state painter (no ticker pulse).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

enum _IndicatorPhase { idle, dragging, armed, loading, complete }

class BullRefreshIndicator extends StatefulWidget {
  /// Async callback invoked when the user releases past the armed threshold.
  /// Resolve when the underlying refresh is done. Throw to surface an error.
  final Future<void> Function() onRefresh;

  /// The scrollable child — typically a `ListView`.
  final Widget child;

  const BullRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<BullRefreshIndicator> createState() => _BullRefreshIndicatorState();
}

class _BullRefreshIndicatorState extends State<BullRefreshIndicator>
    with TickerProviderStateMixin {
  static const double _armedDistance = 64;
  static const double _maxDistance = 96;
  static const double _indicatorHeight = 64;

  double _drag = 0;
  _IndicatorPhase _phase = _IndicatorPhase.idle;
  bool _firedLight = false;
  bool _firedMedium = false;
  String _statusLabel = '';
  bool _errorOnComplete = false;

  late final AnimationController _loopCtrl;
  late final AnimationController _exitCtrl;
  Timer? _completeTimer;

  @override
  void initState() {
    super.initState();
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _loopCtrl.dispose();
    _exitCtrl.dispose();
    _completeTimer?.cancel();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (_phase == _IndicatorPhase.loading || _phase == _IndicatorPhase.complete) {
      return false;
    }
    if (n is OverscrollNotification) {
      // Only react to top overscroll (drag down from top).
      if (n.metrics.pixels <= 0 && n.overscroll < 0) {
        final next = (_drag - n.overscroll).clamp(0.0, _maxDistance);
        _updateDrag(next);
      }
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.pixels < 0) {
        // Some platforms emit negative pixel values during pull.
        final next = (-n.metrics.pixels).clamp(0.0, _maxDistance);
        _updateDrag(next);
      } else if (_drag > 0) {
        // Scrolled back up — release the drag visual.
        _updateDrag(0);
      }
    } else if (n is ScrollEndNotification) {
      if (_phase == _IndicatorPhase.armed) {
        _triggerRefresh();
      } else if (_phase == _IndicatorPhase.dragging) {
        _updateDrag(0);
      }
    }
    return false;
  }

  void _updateDrag(double v) {
    setState(() {
      _drag = v;
      if (v <= 0.001) {
        if (_phase != _IndicatorPhase.loading &&
            _phase != _IndicatorPhase.complete) {
          _phase = _IndicatorPhase.idle;
          _firedLight = false;
          _firedMedium = false;
        }
      } else if (v >= _armedDistance) {
        if (_phase != _IndicatorPhase.armed) {
          _phase = _IndicatorPhase.armed;
          if (!_firedLight) {
            _firedLight = true;
            HapticFeedback.lightImpact();
          }
        }
      } else {
        _phase = _IndicatorPhase.dragging;
      }
    });
  }

  Future<void> _triggerRefresh() async {
    setState(() {
      _phase = _IndicatorPhase.loading;
      _drag = _armedDistance;
      _statusLabel = 'Updating…';
    });
    if (!_firedMedium) {
      _firedMedium = true;
      HapticFeedback.mediumImpact();
    }
    try {
      await widget.onRefresh();
      _errorOnComplete = false;
    } catch (_) {
      _errorOnComplete = true;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    setState(() {
      _phase = _IndicatorPhase.complete;
      _statusLabel = _errorOnComplete
          ? "Couldn't update · try again"
          : 'Updated $hh:$mm:$ss';
    });
    final holdMs = _errorOnComplete ? 2000 : 300;
    _completeTimer = Timer(Duration(milliseconds: holdMs), () async {
      if (!mounted) return;
      await _exitCtrl.forward(from: 0);
      if (!mounted) return;
      _exitCtrl.value = 0;
      setState(() {
        _phase = _IndicatorPhase.idle;
        _drag = 0;
        _firedLight = false;
        _firedMedium = false;
        _statusLabel = '';
        _errorOnComplete = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Visible height of the indicator (drag during dragging, fixed during
    // loading/complete, fading out during the exit animation).
    double visibleHeight;
    if (_phase == _IndicatorPhase.loading) {
      visibleHeight = _indicatorHeight;
    } else if (_phase == _IndicatorPhase.complete) {
      // Stays open for the readout, then fades up via _exitCtrl.
      visibleHeight = _indicatorHeight;
    } else {
      visibleHeight = _drag.clamp(0.0, _maxDistance);
    }

    // Drag value 0..1 (1 == armed).
    final dragValue = (_drag / _armedDistance).clamp(0.0, 1.5);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Stack(
        children: [
          // Translate the scroll child down by the visible indicator height
          // when actively pulling/refreshing so the indicator slots above it.
          Transform.translate(
            offset: Offset(0, visibleHeight),
            child: widget.child,
          ),
          // Indicator overlay.
          if (visibleHeight > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: Listenable.merge([_loopCtrl, _exitCtrl]),
                builder: (_, __) {
                  final exitT = _exitCtrl.value;
                  return Transform.translate(
                    offset: Offset(0, -exitT * 8),
                    child: Opacity(
                      opacity: 1.0 - exitT,
                      child: SizedBox(
                        height: _indicatorHeight,
                        width: double.infinity,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            CustomPaint(
                              size: const Size(double.infinity, 42),
                              painter: _MarketPulsePainter(
                                phase: _phase,
                                dragValue: dragValue,
                                loop: reduceMotion ? 0.5 : _loopCtrl.value,
                                errored: _errorOnComplete,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_statusLabel.isNotEmpty)
                              Text(
                                _statusLabel,
                                style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _errorOnComplete
                                      ? AppColors.red
                                      : AppColors.text3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  _MarketPulsePainter — premium pull-to-refresh.
//
//  Draws an upward-trending stock chart that progressively reveals
//  itself as the user pulls. Replaces the original 5-candle painter
//  with something far more brand-aligned for a finance app:
//
//    • Smooth cubic sparkline through 9 control points (realistic
//      "rally with a dip" shape — looks like an actual chart).
//    • Soft accent-colored glow under the stroke (blurred 4 dp pass
//      then a sharp 2.2 dp stroke on top).
//    • Gradient fill under the line (accent → transparent), only
//      from the leftmost point to the visible endpoint.
//    • Glowing endpoint dot with a halo that BREATHES during the
//      loading phase (sin-wave loop tied to the global loop ctrl).
//    • An animated ↑ arrow appears above the endpoint when armed.
//    • Error state swaps the line to red + draws an ✗ on the endpoint.
//
//  Phase behavior:
//    • idle / dragging:  revealT = clamp(dragValue, 0, 1)
//    • armed:            revealT = 1, vivid accent
//    • loading:          revealT = 0.4 + 0.6 * loop (chart visibly
//                        re-draws itself in a smooth loop)
//    • complete:         revealT = 1, fades via parent opacity
// ═══════════════════════════════════════════════════════════════
class _MarketPulsePainter extends CustomPainter {
  final _IndicatorPhase phase;
  final double dragValue;
  final double loop;
  final bool errored;

  _MarketPulsePainter({
    required this.phase,
    required this.dragValue,
    required this.loop,
    required this.errored,
  });

  // Normalized control points (x, y in [0..1]; y inverted so 0 = top).
  // Shape: starts low-left, dips once for realism, rallies hard to top-right.
  static const List<Offset> _chart = <Offset>[
    Offset(0.00, 0.82),
    Offset(0.12, 0.68),
    Offset(0.24, 0.74),
    Offset(0.36, 0.55),
    Offset(0.50, 0.62),
    Offset(0.64, 0.42),
    Offset(0.78, 0.28),
    Offset(0.90, 0.16),
    Offset(1.00, 0.06),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Center the chart in a 220-dp wide box (or smaller on narrow phones).
    final chartW = math.min(size.width - 24, 220.0);
    if (chartW < 80) return;
    final chartH = size.height - 12; // 6 dp top + 6 dp bottom breathing
    final left = (size.width - chartW) / 2;
    final top = 6.0;
    final rect = Rect.fromLTWH(left, top, chartW, chartH);

    // Compute how much of the chart to reveal in this frame.
    final double revealT;
    switch (phase) {
      case _IndicatorPhase.idle:
      case _IndicatorPhase.dragging:
        revealT = dragValue.clamp(0.0, 1.0);
        break;
      case _IndicatorPhase.armed:
        revealT = 1.0;
        break;
      case _IndicatorPhase.loading:
        // Reveal eases in a smooth wave — chart appears to re-draw itself.
        revealT = 0.45 + 0.55 * loop;
        break;
      case _IndicatorPhase.complete:
        revealT = 1.0;
        break;
    }
    if (revealT < 0.02) return;

    // Build the visible point list. Anything past revealT gets clipped
    // to the interpolated point on the last segment.
    final pts = <Offset>[];
    for (var i = 0; i < _chart.length; i++) {
      final p = _chart[i];
      if (p.dx <= revealT) {
        pts.add(Offset(
          rect.left + p.dx * rect.width,
          rect.top  + p.dy * rect.height,
        ));
      } else {
        // Interpolate the endpoint on the segment that crosses revealT.
        if (i == 0) break;
        final prev = _chart[i - 1];
        final segT = (revealT - prev.dx) / (p.dx - prev.dx);
        final iy   = prev.dy + (p.dy - prev.dy) * segT;
        pts.add(Offset(
          rect.left + revealT * rect.width,
          rect.top  + iy      * rect.height,
        ));
        break;
      }
    }
    if (pts.length < 2) return;

    // Build a cubic-smoothed path through pts — gives the sparkline an
    // organic, "drawn-by-hand" curvature instead of jagged polylines.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cp1 = Offset((p0.dx + p1.dx) / 2, p0.dy);
      final cp2 = Offset((p0.dx + p1.dx) / 2, p1.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

    // Brand color selection. Accent on success, red on error. Armed +
    // loading get the fully saturated accent; pre-arm uses 70% opacity
    // so the chart "lights up" at the threshold.
    final lineColor = errored
        ? AppColors.red
        : (phase == _IndicatorPhase.armed || phase == _IndicatorPhase.loading
            ? AppColors.accent
            : AppColors.accent.withOpacity(0.70));

    // ── Gradient fill below the line ──
    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, rect.bottom)
      ..lineTo(pts.first.dx, rect.bottom)
      ..close();
    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          lineColor.withOpacity(0.34),
          lineColor.withOpacity(0.00),
        ],
      ).createShader(rect));

    // ── Soft glow under the stroke (blurred 4 dp) ──
    canvas.drawPath(path, Paint()
      ..color = lineColor.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // ── Sharp stroke on top ──
    canvas.drawPath(path, Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // ── Endpoint: halo + dot + inner-ring + (optional) arrow/X ──
    final endX = pts.last.dx;
    final endY = pts.last.dy;

    double dotR = 3.5;
    double haloR = 6.0;
    double haloAlpha = 0.35;
    if (phase == _IndicatorPhase.armed) {
      dotR = 4.5;
      haloR = 9.0;
      haloAlpha = 0.50;
    } else if (phase == _IndicatorPhase.loading) {
      // sin-wave breathing pulse
      final b = (1 + math.sin(loop * 2 * math.pi)) / 2; // 0..1
      dotR = 4.0 + b * 1.6;
      haloR = 8.0 + b * 6.0;
      haloAlpha = 0.28 + b * 0.32;
    }
    canvas.drawCircle(Offset(endX, endY), haloR,
        Paint()..color = lineColor.withOpacity(haloAlpha));
    canvas.drawCircle(Offset(endX, endY), dotR,
        Paint()..color = lineColor);
    canvas.drawCircle(Offset(endX, endY), dotR,
        Paint()
          ..color = Colors.white.withOpacity(0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // ── Armed: ↑ arrow above the endpoint ──
    if (phase == _IndicatorPhase.armed && !errored) {
      final ax = endX;
      final ay = endY - 10;
      final arrow = Path()
        ..moveTo(ax, ay - 6)
        ..lineTo(ax - 4, ay - 1)
        ..moveTo(ax, ay - 6)
        ..lineTo(ax + 4, ay - 1)
        ..moveTo(ax, ay - 6)
        ..lineTo(ax, ay + 2);
      canvas.drawPath(arrow, Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
    }

    // ── Errored complete: ✗ over the endpoint ──
    if (errored && phase == _IndicatorPhase.complete) {
      final x = Path()
        ..moveTo(endX - 4, endY - 4)
        ..lineTo(endX + 4, endY + 4)
        ..moveTo(endX + 4, endY - 4)
        ..lineTo(endX - 4, endY + 4);
      canvas.drawPath(x, Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _MarketPulsePainter old) =>
      old.phase != phase ||
      old.dragValue != dragValue ||
      old.loop != loop ||
      old.errored != errored;
}
