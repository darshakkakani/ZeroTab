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
                              size: const Size(double.infinity, 48),
                              painter: _ZeroTabChargePainter(
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
//  _ZeroTabChargePainter — the brand pull-to-refresh emblem.
//
//  A coin/ring with a gold upward arrow inside, drawn as a single
//  custom painter so the animation states feel coherent across
//  pull → armed → loading → complete.
//
//  Layers (back to front):
//   1. Soft accent halo (blurred behind the coin, opacity scales
//      with pull progress)
//   2. Inner bg2 wash filling the coin's interior so the arrow has
//      a clean platter to sit on
//   3. Outer ring stroke with a SWEEP-gradient (accent → gold →
//      accent2 → accent) — the ring spins during loading, locking
//      to 0 in armed/complete
//   4. Gold upward arrow centered inside (linear-gradient gold tip
//      to amber base) with a 0.7-dp white highlight stroke
//   5. Loading: six orbital particles at radius (ring+8) drifting
//      counter to the ring's rotation, each on its own sin-wave
//      opacity cycle — gives a "compounding returns" feel
//   6. Armed: a second concentric ring 4 dp outside the coin
//      flashes briefly in gold
//   7. Errored complete: a red ✗ overlays the arrow
//
//  Phase scaling:
//   • idle:                 not drawn
//   • dragging(t):          scale 0→1 by t, tilt 0→30°
//   • armed:                scale 1.05, rotation 0
//   • loading:              scale 1.00 ± 0.05*sin, rotation = loop·2π
//   • complete:             scale 1.0, rotation 0
// ═══════════════════════════════════════════════════════════════
class _ZeroTabChargePainter extends CustomPainter {
  final _IndicatorPhase phase;
  final double dragValue;
  final double loop;
  final bool errored;

  _ZeroTabChargePainter({
    required this.phase,
    required this.dragValue,
    required this.loop,
    required this.errored,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Per-phase pull / rotation / pulse.
    final double pullT;
    final double rotation;
    final double pulse;
    switch (phase) {
      case _IndicatorPhase.idle:
        return;
      case _IndicatorPhase.dragging:
        pullT    = dragValue.clamp(0.0, 1.0);
        rotation = pullT * math.pi / 6;        // gentle tilt while pulling
        pulse    = 1.0;
        break;
      case _IndicatorPhase.armed:
        pullT    = 1.0;
        rotation = 0;
        pulse    = 1.05;
        break;
      case _IndicatorPhase.loading:
        pullT    = 1.0;
        rotation = loop * 2 * math.pi;
        pulse    = 1.0 + 0.05 * math.sin(loop * 2 * math.pi);
        break;
      case _IndicatorPhase.complete:
        pullT    = 1.0;
        rotation = 0;
        pulse    = 1.0;
        break;
    }
    if (pullT < 0.03) return;

    const baseR  = 17.0;
    final radius = baseR * pullT * pulse;
    final accent  = errored ? AppColors.red  : AppColors.accent;
    final accent2 = errored ? AppColors.red  : AppColors.accent2;
    final gold    = AppColors.gold;

    // 1. Soft halo
    canvas.drawCircle(
      Offset(cx, cy),
      radius + 14,
      Paint()
        ..color = accent.withOpacity(0.20 * pullT)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    // 2. Inner fill (lets the arrow sit on a clean platter)
    canvas.drawCircle(
      Offset(cx, cy),
      radius - 2,
      Paint()..color = AppColors.bg2.withOpacity(0.88),
    );

    // 3. Outer ring with sweep-gradient (rotates during loading)
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    final ringRect = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: errored
              ? [AppColors.red, AppColors.red.withOpacity(0.5), AppColors.red]
              : [accent, gold, accent2, accent],
          stops: const [0.0, 0.35, 0.70, 1.0],
        ).createShader(ringRect)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap   = StrokeCap.round,
    );
    canvas.restore();

    // 4. Gold upward arrow ↑ centered in the coin
    final arrowSize = radius * 0.50;
    final arrowPath = Path()
      ..moveTo(cx,                       cy - arrowSize)
      ..lineTo(cx + arrowSize * 0.55,    cy - arrowSize * 0.15)
      ..lineTo(cx + arrowSize * 0.25,    cy - arrowSize * 0.15)
      ..lineTo(cx + arrowSize * 0.25,    cy + arrowSize * 0.55)
      ..lineTo(cx - arrowSize * 0.25,    cy + arrowSize * 0.55)
      ..lineTo(cx - arrowSize * 0.25,    cy - arrowSize * 0.15)
      ..lineTo(cx - arrowSize * 0.55,    cy - arrowSize * 0.15)
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Color(0xFFFFD56E), Color(0xFFE8A422)],
        ).createShader(Rect.fromCenter(
          center: Offset(cx, cy),
          width:  arrowSize * 1.2,
          height: arrowSize * 1.6,
        )),
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color       = Colors.white.withOpacity(0.35)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    // 5. Loading: six orbital particles at radius+8
    if (phase == _IndicatorPhase.loading) {
      const numParticles = 6;
      final orbitR = radius + 8;
      for (var i = 0; i < numParticles; i++) {
        final pOff   = i * (2 * math.pi / numParticles);
        final angle  = -rotation + pOff;
        final r      = orbitR + 2 * math.sin(loop * 4 * math.pi + i * 0.7);
        final px     = cx + math.cos(angle) * r;
        final py     = cy + math.sin(angle) * r;
        final alpha  = 0.5 + 0.5 *
            math.sin(loop * 2 * math.pi + i * 0.4).abs();
        canvas.drawCircle(
          Offset(px, py),
          1.5,
          Paint()..color = accent.withOpacity(alpha * 0.9),
        );
      }
    }

    // 6. Armed: gold flash ring 4 dp outside the coin
    if (phase == _IndicatorPhase.armed && !errored) {
      canvas.drawCircle(
        Offset(cx, cy),
        radius + 4,
        Paint()
          ..color       = gold.withOpacity(0.40)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 7. Errored complete: red ✗ over the arrow
    if (errored && phase == _IndicatorPhase.complete) {
      final xSize = radius * 0.42;
      final xPaint = Paint()
        ..color       = AppColors.red
        ..strokeWidth = 2.0
        ..strokeCap   = StrokeCap.round;
      canvas.drawLine(
        Offset(cx - xSize, cy - xSize),
        Offset(cx + xSize, cy + xSize),
        xPaint,
      );
      canvas.drawLine(
        Offset(cx + xSize, cy - xSize),
        Offset(cx - xSize, cy + xSize),
        xPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ZeroTabChargePainter old) =>
      old.phase     != phase     ||
      old.dragValue != dragValue ||
      old.loop      != loop      ||
      old.errored   != errored;
}
