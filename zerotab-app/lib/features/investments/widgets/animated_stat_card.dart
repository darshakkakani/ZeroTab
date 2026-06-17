// AnimatedStatCard — premium Discover card with embedded mini-sparkline.
//
// Replaces the older `_MarketCard` private widget that used to live inside
// `discover_sections.dart`. Two visual variants are supported via the
// `compact` constructor flag:
//
//   • Default (rail) — 168 × 112, full anatomy (ticker, name, sparkline, LTP).
//   • Compact (pulse strip) — 144 × 88, no name row.
//
// Data loading
// ------------
// Each card fetches its own intraday series via
// `ChartDataService.fetchSparkline(ticker)` (a thin convenience over
// `fetchYahoo` keyed to `ChartTimeframes.intraday1d`). The result's `meta`
// block provides the live LTP + previous-close + currency for the LTP row
// and day-% pill, while its `bars.close` list paints the sparkline. There
// are no new caches or network paths — `fetchSparkline` reuses the same
// per-(ticker, timeframe) cache as every other chart fetch in the app.
//
// Animations are deliberately lightweight (no Lottie, no extra deps):
//   • Press scale via `AnimatedScale`.
//   • Sparkline draw-in via `AnimationController` + `PathMetric.extractPath`.
//   • LTP tick flash via `AnimationController` triggered in `didUpdateWidget`.
//   • Skeleton shimmer via a single `AnimationController`-driven gradient.
//
// "Reduce Motion" support: when `MediaQuery.disableAnimations` is true, all
// transitions snap to their final state — no count-ups, no flashes, no
// draw-ins. Critical for accessibility and battery-saver modes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/services/providers.dart';
import '../services/chart_data_service.dart';

// ─────────────────────────────────────────────────────────────
//  Public widget
// ─────────────────────────────────────────────────────────────
class AnimatedStatCard extends ConsumerStatefulWidget {
  /// Yahoo ticker — same string fed to `fetchYahoo`/`fetchSparkline`.
  final String ticker;

  /// Display label (company / instrument name). Hidden in compact variant.
  final String name;

  /// Yahoo exchange code — drives flag glyph + currency inference.
  final String exchange;

  /// Used when forwarding into `HoldingChartScreen` after tap.
  final HoldingKind kind;

  /// Compact (pulse-strip) variant: smaller footprint, no name row.
  final bool compact;

  /// Tap handler — caller decides whether to push the chart screen.
  final VoidCallback onTap;

  /// Stagger index for mount fade. Capped internally at 6.
  final int mountIndex;

  /// Optional explicit card width. When null, falls back to the variant
  /// default (168 for the rail variant, 144 for compact pulse-strip).
  /// Set by the rail's LayoutBuilder so cards expose exactly 2.4 cards
  /// of peek per viewport.
  final double? width;

  /// When false, the card skips the intraday-bar fetch and renders LTP +
  /// day-% only. Used by low-density rails (Indices, ETFs, FX) where the
  /// spark would read as a flat smudge.
  final bool showSparkline;

  /// When true, the card swaps its solid surface for a subtle indigo
  /// gradient. Used by the spotlight "AI & Tech Leaders" rail to signal
  /// the editorial slot without being a "crypto rainbow".
  final bool accentGradient;

  const AnimatedStatCard({
    super.key,
    required this.ticker,
    required this.name,
    required this.exchange,
    required this.kind,
    required this.onTap,
    this.compact = false,
    this.mountIndex = 0,
    this.width,
    this.showSparkline = true,
    this.accentGradient = false,
  });

  @override
  ConsumerState<AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends ConsumerState<AnimatedStatCard>
    with TickerProviderStateMixin {
  QuoteMeta? _meta;
  List<double> _closes = const [];
  bool _loaded = false;
  bool _errored = false;
  double? _lastLtp;

  // Sparkline draw-in (first-load only).
  late final AnimationController _sparkCtrl;
  // LTP tick flash (on refresh price change).
  late final AnimationController _flashCtrl;
  Color _flashColor = AppColors.green;
  // Mount-fade visibility flag — flipped on after stagger delay.
  bool _visible = false;
  // Press scale.
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _sparkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    final delay = Duration(milliseconds: 50 * widget.mountIndex.clamp(0, 6));
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _sparkCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(chartDataServiceProvider);
      // When the parent rail has opted out of sparklines, take the cheaper
      // quote-only path — same Yahoo endpoint but the bars are dropped, so
      // no downsample work and no sparkline draw-in.
      final res = widget.showSparkline
          ? await svc.fetchSparkline(widget.ticker)
          : await svc.fetchQuoteOnly(widget.ticker);
      if (!mounted) return;
      // Filter out null closes (Yahoo can return holes for illiquid bars).
      final allCloses = res.bars
          .map((b) => b.close)
          .where((c) => c.isFinite && c > 0)
          .toList(growable: false);
      // Downsample to keep the sparkline path between 24–48 vertices.
      final List<double> closes;
      if (allCloses.length > 48) {
        final step = (allCloses.length / 36).ceil();
        closes = [for (var i = 0; i < allCloses.length; i += step) allCloses[i]];
      } else {
        closes = allCloses;
      }
      final newLtp = res.meta?.regularMarketPrice;
      final priorLtp = _lastLtp;
      setState(() {
        _meta = res.meta;
        _closes = closes;
        _loaded = true;
        _errored = false;
        _lastLtp = newLtp;
      });
      // First-load draw-in only.
      if (!_sparkCtrl.isCompleted && !_reduceMotion) {
        _sparkCtrl.forward(from: 0);
      } else {
        _sparkCtrl.value = 1;
      }
      // Tick flash on refresh price change.
      if (priorLtp != null && newLtp != null && priorLtp != newLtp) {
        _flashColor =
            newLtp >= priorLtp ? AppColors.green : AppColors.red;
        if (!_reduceMotion) {
          _flashCtrl.forward(from: 0);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _errored = true;
      });
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  // Public hook used by parent rails to trigger refresh after pull-to-refresh.
  // Wired via a GlobalKey-free pattern: the parent re-mounts cards using a
  // generation key (`Key('${ticker}-$gen')`), which fires `initState` again
  // and re-runs `_load()` naturally.

  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? (widget.compact ? 144.0 : 168.0);
    final height = widget.compact ? 88.0 : 112.0;
    final m = _meta;
    final ltp = m?.regularMarketPrice;
    final pc = m?.previousClose;
    final pct = (ltp != null && pc != null && pc != 0)
        ? ((ltp - pc) / pc) * 100
        : null;
    final up = (pct ?? 0) >= 0;
    final tint = up ? AppColors.green : AppColors.red;
    final currency = m?.currency ?? _inferCurrency(widget.exchange);

    Widget content = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: Duration(milliseconds: _pressed ? 100 : 140),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: widget.accentGradient ? null : AppColors.bg2,
            gradient: widget.accentGradient
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1A1530), // deep indigo
                      Color(0xFF12182A), // night blue
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.accentGradient
                  ? AppColors.accent2.withOpacity(0.22)
                  : AppColors.border,
              width: widget.accentGradient ? 1 : 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Semantic-tint overlay (subtle, ≤ 6% opacity).
                if (_loaded && !_errored && pct != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const [0.0, 0.55],
                            colors: [
                              tint.withOpacity(0.06),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Pressed-state tint (subtle).
                if (_pressed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.bg3.withOpacity(0.06),
                      ),
                    ),
                  ),
                // Loaded content vs skeleton.
                if (!_loaded)
                  _CardSkeleton(compact: widget.compact)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: _CardContent(
                      ticker: _displayTicker(widget.ticker),
                      flag: _flagFor(widget.exchange),
                      name: widget.name,
                      compact: widget.compact,
                      cardWidth: width,
                      showSparkline: widget.showSparkline,
                      closes: _closes,
                      sparkCtrl: _sparkCtrl,
                      flashCtrl: _flashCtrl,
                      flashColor: _flashColor,
                      currency: currency,
                      ltp: ltp,
                      pct: pct,
                      up: up,
                      errored: _errored,
                      reduceMotion: _reduceMotion,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Mount-fade stagger.
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Loaded-card content (4-row anatomy)
// ─────────────────────────────────────────────────────────────
class _CardContent extends StatelessWidget {
  final String ticker;
  final String flag;
  final String name;
  final bool compact;
  final double cardWidth;
  final bool showSparkline;
  final List<double> closes;
  final AnimationController sparkCtrl;
  final AnimationController flashCtrl;
  final Color flashColor;
  final String currency;
  final double? ltp;
  final double? pct;
  final bool up;
  final bool errored;
  final bool reduceMotion;

  const _CardContent({
    required this.ticker,
    required this.flag,
    required this.name,
    required this.compact,
    required this.cardWidth,
    required this.showSparkline,
    required this.closes,
    required this.sparkCtrl,
    required this.flashCtrl,
    required this.flashColor,
    required this.currency,
    required this.ltp,
    required this.pct,
    required this.up,
    required this.errored,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final sparkColor =
        (closes.isNotEmpty && closes.last >= closes.first)
            ? AppColors.green
            : AppColors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1 — ticker + flag. The ticker is wrapped in a FittedBox so
        // long symbols (RELIANCE, USDINR=X, BRK-B) scale DOWN to fit
        // instead of being '…'-truncated. Card width is clamped ≥140 dp
        // by the rail layout, so the natural floor is ~9–10 sp.
        SizedBox(
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: SizedBox(
                  // Card inner padding is 12 + 12 = 24, then leave room
                  // for a 6 dp gap + 13 dp flag emoji.
                  width: (cardWidth - 24 - 6 - 13).clamp(40.0, 200.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ticker,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        letterSpacing: 0.2,
                        fontFeatures: [FontFeature.tabularFigures()],
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(flag, style: const TextStyle(fontSize: 13, height: 1.0)),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 2),
          // Row 2 — name (single line).
          SizedBox(
            height: 14,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
                height: 1.0,
              ),
            ),
          ),
        ],
        const Spacer(),
        // Row 3 — sparkline. Gated on `showSparkline`: low-density rails
        // (Indices, ETFs, FX) skip the bar fetch entirely and reserve a
        // tiny rhythm gap instead of rendering the line.
        if (showSparkline)
          SizedBox(
            height: compact ? 24 : 32,
            child: closes.length < 2
                ? _ShimmerSparkline(height: compact ? 24 : 32)
                : AnimatedBuilder(
                    animation: sparkCtrl,
                    builder: (_, __) => CustomPaint(
                      size: Size(double.infinity, compact ? 24 : 32),
                      painter: _SparklinePainter(
                        closes: closes,
                        color: sparkColor,
                        progress: reduceMotion ? 1.0 : sparkCtrl.value,
                      ),
                    ),
                  ),
          )
        else
          const SizedBox(height: 4),
        const SizedBox(height: 4),
        // Row 4 — LTP + day-% pill.
        SizedBox(
          height: 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: errored || ltp == null
                    ? const Text('—',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: AppColors.text3,
                          height: 1.0,
                        ))
                    : _LtpText(
                        ltp: ltp!,
                        currency: currency,
                        flashCtrl: flashCtrl,
                        flashColor: flashColor,
                        reduceMotion: reduceMotion,
                      ),
              ),
              const SizedBox(width: 4),
              if (pct != null)
                _PillTag(pct: pct!, up: up)
              else
                const Text('--%',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: AppColors.text3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LTP text with tick-flash background + cross-fade on refresh
// ─────────────────────────────────────────────────────────────
class _LtpText extends StatelessWidget {
  final double ltp;
  final String currency;
  final AnimationController flashCtrl;
  final Color flashColor;
  final bool reduceMotion;

  const _LtpText({
    required this.ltp,
    required this.currency,
    required this.flashCtrl,
    required this.flashColor,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final sign = _currencySign(currency);
    final ltpString = _fmtNum(ltp);
    final keyed = Text(
      ltpString,
      key: ValueKey(ltpString),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        height: 1.0,
        fontFeatures: [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
        ],
      ),
    );
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (sign.isNotEmpty)
          Text(sign,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
                height: 1.0,
              )),
        Flexible(
          child: reduceMotion
              ? keyed
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: keyed,
                ),
        ),
      ],
    );
    if (reduceMotion) return body;
    return AnimatedBuilder(
      animation: flashCtrl,
      builder: (_, child) {
        // Fade in for first 250 ms (hold ~42%), then fade out.
        final v = flashCtrl.value;
        final alpha = v < 0.42 ? 0.12 : 0.12 * (1.0 - ((v - 0.42) / 0.58));
        final clamped = alpha.clamp(0.0, 0.12);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: flashColor.withOpacity(clamped),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Day-% pill with cross-fade on sign change
// ─────────────────────────────────────────────────────────────
class _PillTag extends StatelessWidget {
  final double pct;
  final bool up;
  const _PillTag({required this.pct, required this.up});

  @override
  Widget build(BuildContext context) {
    final tint = up ? AppColors.green : AppColors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(2)}%',
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tint,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Sparkline CustomPainter — quadratic Bézier smoothing
// ─────────────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.closes,
    required this.color,
    required this.progress,
  });

  final List<double> closes;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2) return;
    final double minV = closes.reduce((a, b) => a < b ? a : b);
    final double maxV = closes.reduce((a, b) => a > b ? a : b);
    final double range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    // 8% top/bottom padding.
    final double pad = size.height * 0.08;
    final double usableH = size.height - 2 * pad;
    final double stepX = size.width / (closes.length - 1);

    Offset point(int i) {
      final norm = (closes[i] - minV) / range; // 0..1
      // Invert Y (higher value → smaller Y).
      final y = pad + (1.0 - norm) * usableH;
      return Offset(i * stepX, y);
    }

    final path = Path();
    path.moveTo(point(0).dx, point(0).dy);
    // Quadratic Bézier between midpoints — soft smoothing without splines.
    for (var i = 1; i < closes.length; i++) {
      final prev = point(i - 1);
      final cur = point(i);
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(point(closes.length - 1).dx, point(closes.length - 1).dy);

    // Draw-in animation via PathMetric.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (progress >= 0.999) {
      canvas.drawPath(path, paint);
      return;
    }
    final metrics = path.computeMetrics().toList();
    final out = Path();
    for (final pm in metrics) {
      out.addPath(pm.extractPath(0, pm.length * progress.clamp(0.0, 1.0)),
          Offset.zero);
    }
    canvas.drawPath(out, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.closes != closes ||
      old.color != color ||
      old.progress != progress;
}

// ─────────────────────────────────────────────────────────────
//  Sine-wave shimmer used while sparkline data is loading.
//  Not a flat bar — keeps the visual altitude of the row.
// ─────────────────────────────────────────────────────────────
class _ShimmerSparkline extends StatefulWidget {
  final double height;
  const _ShimmerSparkline({required this.height});
  @override
  State<_ShimmerSparkline> createState() => _ShimmerSparklineState();
}

class _ShimmerSparklineState extends State<_ShimmerSparkline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
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
        size: Size(double.infinity, widget.height),
        painter: _ShimmerSinePainter(progress: _ctrl.value),
      ),
    );
  }
}

class _ShimmerSinePainter extends CustomPainter {
  final double progress;
  _ShimmerSinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment(-1.0 + 2 * progress, 0),
        end: Alignment(0.0 + 2 * progress, 0),
        colors: [
          AppColors.bg3,
          AppColors.bg4,
          AppColors.bg3,
        ],
      ).createShader(Offset.zero & size);

    final path = Path();
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      // Two-cycle sine for an organic look.
      final phase = (t * 2 * 3.141592 * 2);
      final y = size.height / 2 + (size.height * 0.30) *
          (i.isEven ? 1 : -1) * (0.5 + 0.5 *
              (phase.remainder(6.2831853) / 6.2831853));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerSinePainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────────────────────
//  Per-card skeleton — shimmer gradient sweeping across the
//  4-row geometry. One controller, one shimmer per card so a
//  rail of cards reads as a single sheet of light.
// ─────────────────────────────────────────────────────────────
class _CardSkeleton extends StatefulWidget {
  final bool compact;
  const _CardSkeleton({required this.compact});
  @override
  State<_CardSkeleton> createState() => _CardSkeletonState();
}

class _CardSkeletonState extends State<_CardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
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
      builder: (_, __) {
        final progress = _ctrl.value;
        final gradient = LinearGradient(
          begin: Alignment(-1.0 + 2 * progress, 0),
          end: Alignment(0.0 + 2 * progress, 0),
          colors: const [
            AppColors.bg2,
            AppColors.bg3,
            AppColors.bg2,
          ],
          stops: const [0.0, 0.5, 1.0],
        );
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => gradient.createShader(rect),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _SkeletonBlock(width: 52, height: 13),
                    _SkeletonBlock(width: 13, height: 13),
                  ],
                ),
                if (!widget.compact) ...[
                  const SizedBox(height: 4),
                  const _SkeletonBlock(width: 84, height: 11),
                ],
                const Spacer(),
                // Wavy sparkline placeholder.
                _SkeletonBlock(width: double.infinity, height: widget.compact ? 14 : 18),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    _SkeletonBlock(width: 56, height: 16),
                    _SkeletonBlock(width: 42, height: 14),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  const _SkeletonBlock({required this.width, required this.height});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.bg3,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Helpers — ported unchanged from the old `_MarketCard`
// ─────────────────────────────────────────────────────────────
String _displayTicker(String t) {
  if (t.endsWith('=X')) return t.substring(0, t.length - 2);
  if (t.startsWith('^')) return t.substring(1);
  if (t.endsWith('-USD')) return t.substring(0, t.length - 4);
  return t.split('.').first;
}

String _currencySign(String currency) {
  switch (currency.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'JPY':
      return '¥';
    case 'HKD':
      return 'HK\$';
    case 'CNY':
    case 'RMB':
      return '¥';
    default:
      return '';
  }
}

String _fmtNum(double v) {
  if (v.abs() >= 100000) return v.toStringAsFixed(0);
  if (v.abs() >= 100) return v.toStringAsFixed(1);
  if (v.abs() >= 1) return v.toStringAsFixed(2);
  return v.toStringAsFixed(4);
}

String _flagFor(String code) {
  switch (code) {
    case 'NSI':
    case 'BSE':
      return '🇮🇳';
    case 'NMS':
    case 'NYQ':
    case 'NCM':
    case 'PCX':
      return '🇺🇸';
    case 'LSE':
      return '🇬🇧';
    case 'GER':
    case 'XETRA':
    case 'FRA':
      return '🇩🇪';
    case 'PAR':
      return '🇫🇷';
    case 'AMS':
      return '🇳🇱';
    case 'EBS':
    case 'SWX':
      return '🇨🇭';
    case 'TYO':
      return '🇯🇵';
    case 'HKG':
      return '🇭🇰';
    case 'SHH':
    case 'SHZ':
      return '🇨🇳';
    case 'CCC':
      return '●';
    case 'CCY':
      return '💱';
    default:
      return '🌐';
  }
}

String _inferCurrency(String exch) {
  switch (exch) {
    case 'NSI':
    case 'BSE':
      return 'INR';
    case 'NMS':
    case 'NYQ':
    case 'PCX':
      return 'USD';
    case 'LSE':
      return 'GBP';
    case 'GER':
    case 'FRA':
    case 'AMS':
    case 'PAR':
      return 'EUR';
    case 'EBS':
      return 'CHF';
    case 'TYO':
      return 'JPY';
    case 'HKG':
      return 'HKD';
    case 'SHH':
    case 'SHZ':
      return 'CNY';
    case 'CCY':
      return 'INR';
    case 'CCC':
      return 'USD';
    default:
      return '';
  }
}

