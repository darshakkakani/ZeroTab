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
                              painter: _BullPainter(
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

// ─────────────────────────────────────────────────────────────
//  _BullPainter — 5 candles + wicks, growth driven by dragValue,
//  pulse driven by loopCtrl when in loading state.
// ─────────────────────────────────────────────────────────────
class _BullPainter extends CustomPainter {
  final _IndicatorPhase phase;
  final double dragValue;
  final double loop;
  final bool errored;

  _BullPainter({
    required this.phase,
    required this.dragValue,
    required this.loop,
    required this.errored,
  });

  static const _bodyWidth = 6.0;
  static const _gap = 4.0;
  static const _maxHeights = <double>[18, 14, 26, 20, 32];
  static const _baseHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final totalWidth = 5 * _bodyWidth + 4 * _gap;
    final startX = (size.width - totalWidth) / 2;
    final baseline = size.height - 6; // 6 dp from bottom (within painter area)

    for (var i = 0; i < 5; i++) {
      final colour = i.isEven
          ? (errored ? AppColors.red : AppColors.green)
          : (errored ? AppColors.red : AppColors.red);
      // Heights per spec:
      //   dragging: 4 + max[i] * clamp((v - 0.15*i) * 5, 0, 1)
      double growT;
      if (phase == _IndicatorPhase.dragging ||
          phase == _IndicatorPhase.idle) {
        growT = ((dragValue - 0.15 * i) * 5).clamp(0.0, 1.0);
      } else if (phase == _IndicatorPhase.armed) {
        growT = 1.0;
      } else if (phase == _IndicatorPhase.loading) {
        // Rightmost candle pulses, others hold.
        if (i == 4) {
          // Pulse between 24..32 of the 32-max scale → 0.75..1.0.
          final pulse = 0.75 + 0.25 * loop;
          growT = pulse;
        } else {
          growT = 1.0;
        }
      } else {
        growT = 1.0;
      }

      final h = _baseHeight + _maxHeights[i] * growT;
      final x = startX + i * (_bodyWidth + _gap);
      final top = baseline - h;
      final brightOpacity = phase == _IndicatorPhase.armed ? 1.0 : 0.92;

      final paint = Paint()..color = colour.withOpacity(brightOpacity);
      // Body.
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, _bodyWidth, h),
        const Radius.circular(1),
      );
      canvas.drawRRect(body, paint);
      // Wick — 1 dp wide centred above + below.
      final wickPaint = Paint()
        ..color = colour.withOpacity(brightOpacity * 0.6)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      final cx = x + _bodyWidth / 2;
      canvas.drawLine(Offset(cx, top - 3), Offset(cx, top), wickPaint);
      canvas.drawLine(
          Offset(cx, baseline), Offset(cx, baseline + 3), wickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BullPainter old) =>
      old.phase != phase ||
      old.dragValue != dragValue ||
      old.loop != loop ||
      old.errored != errored;
}
