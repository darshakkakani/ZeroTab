// ignore_for_file: use_build_context_synchronously
//
// Holding Chart Screen — Dhan-style detail page for a single holding.
//
// Pure-Dart rendering — no WebView. Works identically on Flutter Web
// (github.io) and on mobile (Android / iOS), because everything is
// drawn by Flutter's own canvas:
//   • Area / Line views use fl_chart's LineChart (gradient fills,
//     dashed crosshair, built-in touch gestures, tooltip).
//   • Candle view is a custom CustomPainter widget that shares the
//     same y-scale + crosshair behaviour, so it visually matches
//     Dhan's candlestick view.
//
// Data sources (free, no auth):
//   • Stocks/ETFs/Commodities → Yahoo Finance v8 chart (OHLCV plus a
//     rich meta block — 52-week range, day range, volume, exchange,
//     long name). On Flutter Web, calls transparently route through
//     corsproxy.io (see chart_data_service.dart).
//   • Mutual funds → api.mfapi.in (daily NAV history).
//
// Layout (top → bottom):
//   • App-bar: name, symbol, exchange, "Delayed 15 min" / "NAV (EOD)" pill
//   • Hero price block (tabular figure + TF change %)
//   • Tool strip: Area / Candle / Line chips + MA20 / MA50 / EMA9 / Vol toggles
//   • Chart canvas (~36 % of screen)
//   • Timeframe row: 1D / 5D / 1M / 3M / 6M / 1Y / 5Y / All
//   • TabBar: Overview · Performance · Similar

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/providers.dart';
import '../services/chart_data_service.dart';
import '../services/indicators.dart';

export '../services/chart_data_service.dart' show HoldingKind;

class HoldingChartScreen extends ConsumerStatefulWidget {
  final MFHoldingModel holding;
  final HoldingKind kind;

  // Override symbol/exchange for sector-peer drill-down (no Supabase
  // holding row exists for a peer).
  final String? overrideSymbol;
  final String? overrideExchange;
  final String? overrideName;

  const HoldingChartScreen({
    super.key,
    required this.holding,
    required this.kind,
    this.overrideSymbol,
    this.overrideExchange,
    this.overrideName,
  });

  @override
  ConsumerState<HoldingChartScreen> createState() => _HoldingChartScreenState();
}

enum _ChartKind { area, candle, line }

class _CrossInfo {
  final int    time;
  final double  close;
  final double? open, high, low, volume;
  const _CrossInfo({
    required this.time, required this.close,
    this.open, this.high, this.low, this.volume,
  });
}

class _HoldingChartScreenState extends ConsumerState<HoldingChartScreen>
    with SingleTickerProviderStateMixin {
  // Riverpod-shared singletons. Reading via `ref.read` (not `watch`) so
  // we don't rebuild on every cache mutation; this screen is the only
  // writer once mounted, and InvestmentsScreen primed the entries before
  // this screen was even pushed.
  ChartDataService get _svc => ref.read(chartDataServiceProvider);
  Map<String, ChartFetchResult> get _cache => ref.read(chartCacheProvider);

  bool _loading = true;
  String? _error;

  late TabController _tabs;
  late List<ChartTimeframe> _tfs;
  int _tfIdx = 2;
  _ChartKind _kind = _ChartKind.area;

  bool _ma20 = false;
  bool _ma50 = false;
  bool _ema9 = false;
  bool _showVolume = true;

  List<Candle> _bars = const [];
  QuoteMeta?   _meta;
  _CrossInfo?  _cross;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tfs  = widget.kind == HoldingKind.mf
        ? ChartTimeframes.allForMF
        : ChartTimeframes.allForStock;
    if (widget.kind != HoldingKind.mf) {
      _tfIdx = _tfs.indexOf(ChartTimeframes.day1m).clamp(0, _tfs.length - 1);
    } else {
      _tfIdx = 0;
    }
    _showVolume = widget.kind != HoldingKind.mf;
    _fetchAndRender().then((_) => _prefetchOtherTimeframes());
  }

  // ── Background pre-fetch of OTHER timeframes ──────────────────
  //
  // After the initial render completes we silently fetch the rest of
  // the timeframe matrix and stash each result in _cache. Result: when
  // the user actually taps another timeframe button, the new bars are
  // already in memory and switch is instant — no spinner, no blink.
  //
  // We fetch 2 at a time (so the CORS proxy isn't hammered with 8
  // parallel requests) and prioritize the most-used windows first
  // (research across Groww/Dhan/Kite shows >70% of users only ever
  // look at 1D, 1M, 1Y, ALL — those go first).
  Future<void> _prefetchOtherTimeframes() async {
    // Tiny breather so the visible chart finishes its initial paint
    // before we kick off background work — keeps the first frame smooth.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final priority = <ChartTimeframe>[
      if (widget.kind != HoldingKind.mf) ChartTimeframes.intraday1d,
      ChartTimeframes.day1m,
      ChartTimeframes.year1,
      ChartTimeframes.all,
      if (widget.kind != HoldingKind.mf) ChartTimeframes.intraday5d,
      ChartTimeframes.day3m,
      ChartTimeframes.day6m,
      ChartTimeframes.year5,
    ];
    final pending = priority.where((tf) {
      if (widget.kind == HoldingKind.mf && tf.intraday) return false;
      final key = '$_symbolOrCode-$_exchange-${tf.label}';
      return !_cache.containsKey(key);
    }).toList();

    for (int i = 0; i < pending.length; i += 2) {
      if (!mounted) return;
      final batch = pending.sublist(i, math.min(i + 2, pending.length));
      await Future.wait(batch.map((tf) => _silentFetch(tf)));
    }
  }

  Future<void> _silentFetch(ChartTimeframe tf) async {
    final key = '$_symbolOrCode-$_exchange-${tf.label}';
    if (_cache.containsKey(key)) return;
    try {
      final ChartFetchResult res;
      if (widget.kind == HoldingKind.mf) {
        res = await _svc.fetchMF(schemeCode: _symbolOrCode, tf: tf);
      } else {
        final ticker = _svc.yahooTicker(
          kind: widget.kind, symbol: _symbolOrCode, exchange: _exchange);
        res = await _svc.fetchYahoo(ticker: ticker, tf: tf);
      }
      _cache[key] = res;
    } catch (_) {
      // Best-effort — silent. User can still tap the TF; we'll show
      // a real error then if the fetch fails for real.
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Resolved symbol/exchange/name — uses overrides for peer drill-down
  // ─────────────────────────────────────────────────────────────
  String get _symbolOrCode {
    if (widget.overrideSymbol != null) return widget.overrideSymbol!;
    switch (widget.kind) {
      case HoldingKind.stock:     return widget.holding.stockSymbol;
      case HoldingKind.etf:       return widget.holding.etfSymbol;
      case HoldingKind.commodity: return widget.holding.commoditySymbol;
      case HoldingKind.mf:        return widget.holding.schemeCode ?? '';
    }
  }

  String get _exchange =>
      widget.overrideExchange ?? widget.holding.stockExchange;

  String get _title {
    if (widget.overrideName != null) return widget.overrideName!;
    final s = widget.holding.schemeName;
    if (s != null && s.isNotEmpty) return s;
    return _meta?.longName ?? _symbolOrCode;
  }

  bool get _isPeer => widget.overrideSymbol != null;

  // ─────────────────────────────────────────────────────────────
  //  Data fetch
  // ─────────────────────────────────────────────────────────────
  String get _cacheKey {
    final tf = _tfs[_tfIdx];
    return '$_symbolOrCode-$_exchange-${tf.label}';
  }

  Future<void> _fetchAndRender() async {
    final tf  = _tfs[_tfIdx];
    final key = _cacheKey;

    // ── Instant path: cache hit ─────────────────────────────────
    // Don't set _loading=true here — that would trigger a rebuild
    // with the spinner branch before the data swap, producing the
    // "blink" the user reported. Just swap bars in one setState so
    // the AnimatedSwitcher (in _buildChart) does a smooth fade.
    final cached = _cache[key];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _bars = cached.bars;
        _meta = cached.meta;
        _loading = false;
        _error = null;
        _cross = null;
      });
      return;
    }

    // ── Cold path: keep showing the OLD bars while we fetch new
    // ones, so the chart never goes blank. The AnimatedSwitcher
    // sees no key change yet (data is unchanged), no flicker.
    setState(() { _loading = true; _error = null; _cross = null; });

    try {
      final ChartFetchResult res;
      if (widget.kind == HoldingKind.mf) {
        res = await _svc.fetchMF(schemeCode: _symbolOrCode, tf: tf);
      } else {
        final ticker = _svc.yahooTicker(
          kind: widget.kind, symbol: _symbolOrCode, exchange: _exchange);
        res = await _svc.fetchYahoo(ticker: ticker, tf: tf);
      }
      _cache[key] = res;
      // Stale check: user may have tapped ANOTHER timeframe while we
      // were fetching; only render if we're still the active TF.
      if (!mounted || _cacheKey != key) return;
      setState(() {
        _bars = res.bars;
        _meta = res.meta;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = _friendly(e.toString());
      });
    }
  }

  String _friendly(String e) {
    if (e.contains('SocketException') || e.contains('connection')) {
      return 'No internet connection';
    }
    if (e.contains('Timeout')) return 'Network is slow — please retry';
    if (e.contains('404') || e.contains('No data') || e.contains('No bars')) {
      return 'No price history available for this symbol';
    }
    if (e.contains('No NAV') || e.contains('NAV history')) {
      return 'No NAV history found for this scheme';
    }
    return 'Unable to load chart data';
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ltp = _cross?.close
        ?? _meta?.regularMarketPrice
        ?? (_bars.isNotEmpty ? _bars.last.close : widget.holding.stockCurrentPrice);
    final firstClose = _bars.isNotEmpty ? _bars.first.close : null;
    final lastClose  = _bars.isNotEmpty ? _bars.last.close  : null;
    final tfPct = (firstClose != null && lastClose != null && firstClose != 0)
        ? ((lastClose - firstClose) / firstClose) * 100 : null;
    final tfAbs = (firstClose != null && lastClose != null)
        ? lastClose - firstClose : null;
    final up = (tfPct ?? 0) >= 0;
    final col = up ? AppColors.green : AppColors.red;

    final screenH = MediaQuery.of(context).size.height;
    final chartH  = (screenH * 0.32).clamp(200.0, 340.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        _topBar(),
        _heroPrice(ltp: ltp, tfAbs: tfAbs, tfPct: tfPct, up: up, col: col),
        _toolStrip(),
        SizedBox(height: chartH, child: _buildChart()),
        _timeframeBar(),
        Container(
          decoration: const BoxDecoration(border: Border(
            bottom: BorderSide(color: AppColors.border, width: 1))),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            indicatorColor: AppColors.accent,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.text3,
            labelStyle: const TextStyle(fontFamily: 'DMSans',
              fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontFamily: 'DMSans',
              fontSize: 12, fontWeight: FontWeight.w500),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Performance'),
              Tab(text: 'Similar'),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _overviewTab(),
          _performanceTab(),
          _similarTab(),
        ])),
      ])),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Chart canvas (pure Flutter — works on every platform)
  // ─────────────────────────────────────────────────────────────
  Widget _buildChart() {
    if (_error != null) {
      return Container(
        color: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.signal_cellular_nodata_rounded,
              color: AppColors.text3, size: 26),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
                color: AppColors.text2)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () { _cache.remove(_cacheKey); _fetchAndRender(); },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.border)),
            child: const Text('Retry'),
          ),
        ]),
      );
    }
    if (_loading && _bars.isEmpty) {
      return const Center(child: SizedBox(width: 22, height: 22,
        child: CircularProgressIndicator(
          color: AppColors.accent, strokeWidth: 1.6)));
    }
    if (_bars.length < 2) {
      return const Center(child: Text('Not enough data points',
        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
            color: AppColors.text3)));
    }
    // The key encodes everything that should trigger a *visual* swap.
    // AnimatedSwitcher uses it to cross-fade between configs — that
    // eliminates the "blink" the user reported when changing TFs.
    final swapKey = ValueKey<String>(
      'chart-${_tfs[_tfIdx].label}-$_kind-$_ma20-$_ma50-$_ema9-$_showVolume-'
      '${_bars.isNotEmpty ? _bars.first.timeSec : 0}-${_bars.length}');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Stack(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim, child: child),
          child: KeyedSubtree(
            key: swapKey,
            child: _kind == _ChartKind.candle
                ? _CandleChartView(
                    bars: _bars,
                    ma20: _ma20 ? Indicators.sma(_bars, 20) : const [],
                    ma50: _ma50 ? Indicators.sma(_bars, 50) : const [],
                    ema9: _ema9 ? Indicators.ema(_bars,  9) : const [],
                    showVolume: _showVolume,
                    onCross: (c) => setState(() => _cross = c),
                  )
                : _AreaLineChartView(
                    bars: _bars,
                    filled: _kind == _ChartKind.area,
                    ma20: _ma20 ? Indicators.sma(_bars, 20) : const [],
                    ma50: _ma50 ? Indicators.sma(_bars, 50) : const [],
                    ema9: _ema9 ? Indicators.ema(_bars,  9) : const [],
                    showVolume: _showVolume,
                    onCross: (c) => setState(() => _cross = c),
                  ),
          ),
        ),
        // Subtle top-right spinner during cold fetch — visible only
        // when we're truly loading AND already have a stale chart on
        // screen (so the spinner doesn't double up with the cold-
        // start CircularProgressIndicator branch above).
        if (_loading && _bars.isNotEmpty) Positioned(
          top: 6, right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.bg2.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 9, height: 9,
                child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 1.2)),
              SizedBox(width: 5),
              Text('Updating',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                  color: AppColors.text2, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────
  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_rounded,
            color: AppColors.text, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title, style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 14.5,
            fontWeight: FontWeight.w700, color: AppColors.text),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Row(children: [
            Text(_symbolOrCode, style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 10.5, color: AppColors.text3)),
            if (widget.kind == HoldingKind.stock) ...[
              const Text('  ·  ', style: TextStyle(
                fontFamily: 'DMSans', color: AppColors.text3, fontSize: 10.5)),
              Text(_meta?.exchange ?? _exchange, style: const TextStyle(
                fontFamily: 'DMSans', fontSize: 10.5,
                fontWeight: FontWeight.w600, color: AppColors.text3)),
            ],
          ]),
        ],
      )),
    ]),
  );

  Widget _heroPrice({
    required double ltp, required double? tfAbs, required double? tfPct,
    required bool up, required Color col,
  }) {
    final tfLabel = _tfs[_tfIdx].label;
    final crossDate = _cross != null
        ? DateTime.fromMillisecondsSinceEpoch(_cross!.time * 1000, isUtc: false)
        : null;

    // Day-change (intraday) priority for the hero chip. Falls back to
    // selected-timeframe change when intraday meta is unavailable.
    final cp  = _meta?.previousClose;
    final dayAbs = (cp != null && cp != 0) ? ltp - cp : null;
    final dayPct = (cp != null && cp != 0) ? ((ltp - cp) / cp) * 100 : null;
    final showDay = dayAbs != null && dayPct != null;
    final chipUp = showDay ? dayAbs >= 0 : up;
    final chipCol = chipUp ? AppColors.green : AppColors.red;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Big price + inline currency ──
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('₹', style: TextStyle(
                  fontFamily: 'DMMono', fontSize: 18,
                  fontWeight: FontWeight.w500, color: AppColors.text2,
                  height: 1.0)),
              ),
              const SizedBox(width: 2),
              Text(ltp.toStringAsFixed(2), style: const TextStyle(
                fontFamily: 'DMMono', fontSize: 32, height: 1.0,
                fontWeight: FontWeight.w700, letterSpacing: -1.4,
                color: AppColors.text,
                fontFeatures: [
                  FontFeature.tabularFigures(),
                  FontFeature.liningFigures(),
                ])),
            ]),
            const SizedBox(height: 8),
            // ── Day-change pill + TF-change muted ──
            Row(children: [
              if (showDay) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipCol.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: chipCol.withValues(alpha: 0.30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(chipUp ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                    color: chipCol, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    '${dayAbs >= 0 ? "+" : ""}${dayAbs.toStringAsFixed(2)} '
                    '(${dayPct >= 0 ? "+" : ""}${dayPct.toStringAsFixed(2)}%)',
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 11.5,
                      fontWeight: FontWeight.w700, color: chipCol)),
                ]),
              ),
              if (showDay) const SizedBox(width: 8),
              if (showDay) const Text('Today',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                    color: AppColors.text3, fontWeight: FontWeight.w500)),
              if (tfPct != null && tfAbs != null) ...[
                if (showDay) const SizedBox(width: 10),
                if (showDay) Container(
                  width: 1, height: 11, color: AppColors.border2),
                if (showDay) const SizedBox(width: 10),
                Icon(up ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                  color: col, size: 12),
                const SizedBox(width: 2),
                Text(
                  '${tfPct >= 0 ? "+" : ""}${tfPct.toStringAsFixed(2)}%',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 11.5,
                    fontWeight: FontWeight.w600, color: col)),
                const SizedBox(width: 4),
                Text(tfLabel, style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 10.5, color: AppColors.text3,
                    fontWeight: FontWeight.w500)),
              ],
            ]),
          ],
        )),
        if (crossDate != null) Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.border)),
          child: Text(
            DateFormat('d MMM, HH:mm').format(crossDate),
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 10,
                color: AppColors.text2)),
        ),
      ]),
    );
  }

  Widget _toolStrip() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: SizedBox(height: 28,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _kindChip(_ChartKind.area,   'Area',   Icons.show_chart_rounded),
        _kindChip(_ChartKind.candle, 'Candle', Icons.candlestick_chart_rounded),
        _kindChip(_ChartKind.line,   'Line',   Icons.timeline_rounded),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: AppColors.border2,
            margin: const EdgeInsets.symmetric(vertical: 6)),
        const SizedBox(width: 8),
        _indChip('MA 20', _ma20, AppColors.gold, () =>
            setState(() => _ma20 = !_ma20)),
        _indChip('MA 50', _ma50, AppColors.teal, () =>
            setState(() => _ma50 = !_ma50)),
        _indChip('EMA 9', _ema9, AppColors.accent, () =>
            setState(() => _ema9 = !_ema9)),
        if (widget.kind != HoldingKind.mf)
          _indChip('Vol', _showVolume, AppColors.accent2, () =>
              setState(() => _showVolume = !_showVolume)),
      ]),
    ),
  );

  Widget _kindChip(_ChartKind k, String label, IconData icon) {
    final active = k == _kind;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: () { if (k != _kind) setState(() => _kind = k); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withValues(alpha: 0.18) : AppColors.bg2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.accent.withValues(alpha: 0.55) : AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: active ? AppColors.accent : AppColors.text3),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontFamily: 'DMSans',
              fontSize: 11, fontWeight: FontWeight.w600,
              color: active ? AppColors.accent : AppColors.text2)),
          ]),
        ),
      ),
    );
  }

  Widget _indChip(String label, bool active, Color accent, VoidCallback onTap) =>
    Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.18) : AppColors.bg2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.55) : AppColors.border)),
          child: Text(label, style: TextStyle(fontFamily: 'DMSans',
            fontSize: 11, fontWeight: FontWeight.w600,
            color: active ? accent : AppColors.text2)),
        ),
      ),
    );

  Widget _timeframeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    child: Row(children: [
      for (int i = 0; i < _tfs.length; i++)
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: GestureDetector(
            onTap: _loading ? null : () {
              if (i == _tfIdx) return;
              setState(() => _tfIdx = i);
              _fetchAndRender();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 28,
              decoration: BoxDecoration(
                color: i == _tfIdx
                    ? AppColors.accent.withValues(alpha: 0.20)
                    : AppColors.bg2,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: i == _tfIdx
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : AppColors.border),
              ),
              alignment: Alignment.center,
              child: Text(_tfs[i].label, style: TextStyle(
                fontFamily: 'DMSans', fontSize: 11,
                fontWeight: FontWeight.w700,
                color: i == _tfIdx ? AppColors.accent : AppColors.text2,
              )),
            ),
          ),
        )),
    ]),
  );

  // ─── Overview tab — broker-grade grouped sections ───────────
  //
  // Each section is its own visually-distinct card with a small
  // leading icon, a tight header line, and a 2-column stat grid.
  // The pattern is borrowed from Dhan/Groww/Zerodha mobile and
  // tightened: heavier section dividers, brand-tinted icons,
  // tabular figures everywhere, soft inner shadows on cards.
  Widget _overviewTab() {
    final m  = _meta;
    final h  = widget.holding;
    final cp = m?.previousClose;
    final lp = m?.regularMarketPrice ?? (_bars.isNotEmpty ? _bars.last.close : null);
    final dayChange    = (cp != null && lp != null) ? lp - cp : null;
    final dayChangePct = (cp != null && lp != null && cp != 0)
        ? ((lp - cp) / cp) * 100 : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Your holding (hidden when drilling into a peer) ──
        if (!_isPeer) ...[
          _summaryCard(),
          const SizedBox(height: 14),
        ],

        // ── Today's activity ──
        _SectionCard(
          icon: Icons.today_rounded,
          iconColor: AppColors.accent,
          title: "Today's activity",
          subtitle: _meta?.exchange != null ? '${_meta!.exchange} live' : null,
          loading: _loading && _bars.isEmpty,
          child: _statGrid([
            if (dayChange != null)
              _Stat("Day's change",
                '${dayChange >= 0 ? "+" : ""}₹${dayChange.toStringAsFixed(2)}',
                sub: dayChangePct != null
                    ? '${dayChangePct >= 0 ? "+" : ""}${dayChangePct.toStringAsFixed(2)}%'
                    : null,
                color: dayChange >= 0 ? AppColors.green : AppColors.red),
            if (m?.dayLow != null && m?.dayHigh != null)
              _Stat("Day's range",
                '₹${m!.dayLow!.toStringAsFixed(2)} – ₹${m.dayHigh!.toStringAsFixed(2)}'),
            if (m?.volume != null && m!.volume! > 0)
              _Stat('Volume', _fmtVol(m.volume!)),
            if (m?.previousClose != null)
              _Stat('Prev. close', '₹${m!.previousClose!.toStringAsFixed(2)}'),
          ]),
        ),
        const SizedBox(height: 12),

        // ── 52-week range ──
        if (m?.fiftyTwoWeekHigh != null && m?.fiftyTwoWeekLow != null) ...[
          _SectionCard(
            icon: Icons.timeline_rounded,
            iconColor: AppColors.gold,
            title: '52-week range',
            subtitle: 'Where price sits in the year',
            loading: false,
            child: _RangeBar(
              low: m!.fiftyTwoWeekLow!,
              high: m.fiftyTwoWeekHigh!,
              current: m.regularMarketPrice
                  ?? (_bars.isNotEmpty ? _bars.last.close : m.fiftyTwoWeekLow!),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Key info / Instrument ──
        _SectionCard(
          icon: Icons.account_balance_rounded,
          iconColor: AppColors.teal,
          title: widget.kind == HoldingKind.mf ? 'About fund' : 'About company',
          subtitle: null,
          loading: _loading && _bars.isEmpty,
          child: _statGrid([
            if (m?.longName != null) _Stat('Name', m!.longName!),
            if (m?.instrumentType != null)
              _Stat('Type', _humanInstrument(m!.instrumentType!)),
            if (m?.exchange != null) _Stat('Exchange', m!.exchange!),
            if (m?.currency != null) _Stat('Currency', m!.currency!),
            if (widget.kind == HoldingKind.mf && h.amcName != null)
              _Stat('AMC', h.amcName!),
          ]),
        ),
      ]),
    );
  }

  String _humanInstrument(String t) {
    switch (t.toUpperCase()) {
      case 'EQUITY':     return 'Equity';
      case 'ETF':        return 'Exchange-traded fund';
      case 'MUTUALFUND': return 'Mutual fund';
      case 'FUTURE':     return 'Futures';
      case 'CRYPTO':     return 'Cryptocurrency';
      case 'INDEX':      return 'Index';
      default:           return t;
    }
  }

  Widget _sectionTitle(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Text(s.toUpperCase(), style: const TextStyle(
      fontFamily: 'DMSans', fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 0.5,
      color: AppColors.text3)),
  );

  Widget _statGrid(List<_Stat?> raw) {
    final stats = raw.whereType<_Stat>().toList();
    if (stats.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisExtent: 60,
        crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: stats.length,
      itemBuilder: (_, i) {
        final s = stats[i];
        // Flat tile — inside _SectionCard so we drop the outer border;
        // a subtle bg3 panel keeps each stat visually grouped without
        // adding noise. Label is uppercase tracking, value is mono.
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: AppColors.bg3.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(s.label.toUpperCase(), style: const TextStyle(
              fontFamily: 'DMSans', fontSize: 9,
              fontWeight: FontWeight.w600, letterSpacing: 0.4,
              color: AppColors.text3)),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Expanded(child: Text(s.value, style: TextStyle(
                fontFamily: 'DMMono', fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: s.color ?? AppColors.text,
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                  FontFeature.liningFigures(),
                ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (s.sub != null) const SizedBox(width: 5),
              if (s.sub != null) Text(s.sub!, style: TextStyle(
                fontFamily: 'DMMono', fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: s.color ?? AppColors.text2,
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                  FontFeature.liningFigures(),
                ])),
            ]),
          ]),
        );
      },
    );
  }

  // ─── Performance tab ────────────────────────────────────────
  Widget _performanceTab() {
    return FutureBuilder<List<_PerfRow>>(
      future: _computePerformance(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 1.5));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(40),
            child: Text('Not enough history to compute returns',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                  color: AppColors.text3))));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final r = rows[i];
            final up = r.pct >= 0;
            final col = up ? AppColors.green : AppColors.red;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
              child: Row(children: [
                SizedBox(width: 44, child: Text(r.label,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
                    fontWeight: FontWeight.w700, color: AppColors.text))),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(height: 6, color: AppColors.bg3),
                    LayoutBuilder(builder: (_, c) {
                      final w = (r.pctAbs.clamp(0, 50) / 50) * c.maxWidth;
                      return Container(width: w, height: 6, color: col);
                    }),
                  ]),
                )),
                const SizedBox(width: 12),
                Text('${up ? "+" : ""}${r.pct.toStringAsFixed(2)}%',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 12.5,
                    fontWeight: FontWeight.w700, color: col)),
              ]),
            );
          },
        );
      },
    );
  }

  Future<List<_PerfRow>> _computePerformance() async {
    const allTf = ChartTimeframes.all;
    final key = '$_symbolOrCode-$_exchange-${allTf.label}';
    ChartFetchResult? res = _cache[key];
    try {
      if (res == null) {
        if (widget.kind == HoldingKind.mf) {
          res = await _svc.fetchMF(schemeCode: _symbolOrCode, tf: allTf);
        } else {
          final ticker = _svc.yahooTicker(
            kind: widget.kind, symbol: _symbolOrCode, exchange: _exchange);
          res = await _svc.fetchYahoo(ticker: ticker, tf: allTf);
        }
        _cache[key] = res;
      }
    } catch (_) {
      return const [];
    }

    final bars = res.bars;
    if (bars.length < 2) return const [];
    final now = bars.last;
    const periods = [
      ('1D',     1),
      ('1W',     7),
      ('1M',    30),
      ('3M',    90),
      ('6M',   180),
      ('1Y',   365),
      ('3Y',  1095),
      ('5Y',  1825),
      ('MAX',  -1),
    ];
    final rows = <_PerfRow>[];
    for (final p in periods) {
      Candle? past;
      if (p.$2 < 0) {
        past = bars.first;
      } else {
        final cutoff = now.timeSec - p.$2 * 86400;
        for (int i = bars.length - 1; i >= 0; i--) {
          if (bars[i].timeSec <= cutoff) { past = bars[i]; break; }
        }
      }
      if (past == null || past.close == 0) continue;
      final pct = ((now.close - past.close) / past.close) * 100;
      rows.add(_PerfRow(label: p.$1, pct: pct, pctAbs: pct.abs()));
    }
    return rows;
  }

  // ─── Similar tab ────────────────────────────────────────────
  Widget _similarTab() {
    if (widget.kind == HoldingKind.mf) {
      return const Center(child: Padding(padding: EdgeInsets.all(40),
        child: Text('Peer comparison coming soon for mutual funds',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
              color: AppColors.text3))));
    }
    final peers = peersOf(_symbolOrCode, limit: 5);
    if (peers.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(40),
        child: Text('No sector peers mapped for this symbol yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
              color: AppColors.text3))));
    }
    final sector = sectorOf(_symbolOrCode);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      children: [
        if (sector != null) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('${peers.length} peers in $sector sector',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                color: AppColors.text3)),
        ),
        for (int i = 0; i < peers.length; i++) _PeerRow(
          symbol: peers[i],
          exchange: _exchange,
          svc: _svc,
          index: i,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HoldingChartScreen(
              holding: widget.holding,
              kind: HoldingKind.stock,
              overrideSymbol: peers[i],
              overrideExchange: _exchange,
              overrideName: peers[i],
            ),
          )),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final h    = widget.holding;
    final qty  = widget.kind == HoldingKind.stock ? h.stockQty : (h.units ?? 0);
    final avg  = h.avgNav ?? 0;
    final inv  = h.investedAmount ?? 0;
    final cur  = h.currentValue   ?? 0;
    final gain = h.gainLoss;
    final gPct = h.gainLossPct;
    final up   = gain >= 0;
    final col  = up ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('YOUR HOLDING', style: TextStyle(fontFamily: 'DMSans',
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5,
          color: AppColors.text3)),
        const SizedBox(height: 10),
        Row(children: [
          _kv('Qty', qty == qty.roundToDouble()
              ? qty.toStringAsFixed(0) : qty.toStringAsFixed(3)),
          _kv('Avg', '₹${avg.toStringAsFixed(2)}'),
          _kv('Invested', formatInr(inv, compact: true)),
        ]),
        const SizedBox(height: 10),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current value', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
              const SizedBox(height: 2),
              Text(formatInr(cur, compact: false),
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 16,
                  fontWeight: FontWeight.w700, color: AppColors.text,
                  fontFeatures: [
                    FontFeature.tabularFigures(),
                    FontFeature.liningFigures(),
                  ])),
            ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('P&L', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
            const SizedBox(height: 2),
            Text(
              '${up ? "+" : "-"}${formatInr(gain.abs(), compact: false)}',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 15,
                  fontWeight: FontWeight.w700, color: col,
                  fontFeatures: const [
                    FontFeature.tabularFigures(),
                    FontFeature.liningFigures(),
                  ])),
            Text('${up ? "+" : ""}${gPct.toStringAsFixed(2)}%',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5,
                  fontWeight: FontWeight.w600, color: col)),
          ]),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: const TextStyle(fontFamily: 'DMSans',
          fontSize: 10, color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(v, style: const TextStyle(fontFamily: 'DMMono', fontSize: 12,
          fontWeight: FontWeight.w600, color: AppColors.text)),
    ]),
  );

  String _fmtVol(double v) {
    if (v >= 1e7) return '${(v / 1e7).toStringAsFixed(2)} Cr';
    if (v >= 1e5) return '${(v / 1e5).toStringAsFixed(2)} L';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)} K';
    return v.toStringAsFixed(0);
  }
}

// ─── value types ─────────────────────────────────────────────
class _Stat {
  final String label, value;
  final String? sub;
  final Color? color;
  const _Stat(this.label, this.value, {this.sub, this.color});
}

class _PerfRow {
  final String label;
  final double pct, pctAbs;
  const _PerfRow({required this.label, required this.pct, required this.pctAbs});
}

// ─── Section card — broker-style grouped section ─────────────
//
// Combines a small leading icon, title, optional subtitle and the
// section body inside one bordered card. Modeled after the
// "section cards" in Dhan and Robinhood (large brokers' detail
// pages all share this exact pattern — small icon left, title,
// optional caption, divider, content).
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String?  subtitle;
  final bool     loading;
  final Widget   child;
  const _SectionCard({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.loading, required this.child,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(7)),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                fontFamily: 'DMSans', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.text)),
              if (subtitle != null) Text(subtitle!,
                style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 10.5, color: AppColors.text3)),
            ])),
          if (loading) const SizedBox(width: 12, height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.4, color: AppColors.text3)),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

// ─── 52-week range visual ────────────────────────────────────
class _RangeBar extends StatelessWidget {
  final double low, high, current;
  const _RangeBar({required this.low, required this.high, required this.current});
  @override
  Widget build(BuildContext context) {
    final span = (high - low).clamp(0.0001, double.infinity);
    final pos  = ((current - low) / span).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Low ₹${low.toStringAsFixed(2)}',
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                color: AppColors.text3)),
          Text('High ₹${high.toStringAsFixed(2)}',
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                color: AppColors.text3)),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (_, c) {
          final dotX = pos * c.maxWidth;
          return SizedBox(
            height: 18,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 0, right: 0, top: 7,
                child: Container(height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      AppColors.red, AppColors.gold, AppColors.green,
                    ]),
                    borderRadius: BorderRadius.circular(2)))),
              Positioned(left: dotX - 6, top: 0,
                child: Container(width: 12, height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.text,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4),
                        blurRadius: 4, offset: const Offset(0, 1))]))),
            ]),
          );
        }),
        const SizedBox(height: 6),
        Text('Current ₹${current.toStringAsFixed(2)}',
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 11.5,
              fontWeight: FontWeight.w700, color: AppColors.text)),
      ]);
  }
}

// ═══════════════════════════════════════════════════════════════
//  Area / Line chart view — broker-grade UX
//
//  • fl_chart renders the main line + area + grid + axis labels.
//  • Native fl_chart touch is DISABLED. We layer a CustomPainter on
//    top that draws a real broker-style crosshair: dashed vertical +
//    horizontal lines tracking the cursor, with pill labels showing
//    the exact price on the right axis and the exact date on the
//    bottom axis (matches Dhan / Kite / Groww UX).
//  • Crosshair responds to BOTH mouse hover (web) and touch drag
//    (mobile) — the previous build only fired on tap because fl_chart
//    doesn't expose pure hover events.
//  • A pulse dot at the latest data point shows the current price
//    visually — same "live tick" affordance Dhan uses.
// ═══════════════════════════════════════════════════════════════
class _AreaLineChartView extends StatefulWidget {
  final List<Candle> bars;
  final bool filled;
  final List<IndicatorPoint> ma20, ma50, ema9;
  final bool showVolume;
  final ValueChanged<_CrossInfo?> onCross;
  const _AreaLineChartView({
    required this.bars, required this.filled,
    required this.ma20, required this.ma50, required this.ema9,
    required this.showVolume, required this.onCross,
  });
  @override
  State<_AreaLineChartView> createState() => _AreaLineChartViewState();
}

class _AreaLineChartViewState extends State<_AreaLineChartView> {
  // Chart-plot insets (must match the fl_chart titles' reservedSize so
  // the overlay crosshair lines up to the pixel with fl_chart's axes).
  static const double _topInset    = 6;
  static const double _bottomInset = 22;
  static const double _rightInset  = 36;
  static const double _leftInset   = 0;

  Offset? _cursor;

  void _setCursor(Offset? p, Rect plotRect, List<Candle> bars) {
    setState(() => _cursor = p);
    if (p == null || !plotRect.contains(p) || bars.isEmpty) {
      widget.onCross(null);
      return;
    }
    final t = (p.dx - plotRect.left) / plotRect.width;
    final i = (t * (bars.length - 1)).round().clamp(0, bars.length - 1);
    final b = bars[i];
    widget.onCross(_CrossInfo(
      time: b.timeSec, close: b.close,
      open: b.open, high: b.high, low: b.low, volume: b.volume,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    final closes = bars.map((b) => b.close).toList(growable: false);
    double minY = closes.first, maxY = closes.first;
    for (final v in closes) {
      if (v < minY) minY = v;
      if (v > maxY) maxY = v;
    }
    for (final i in [...widget.ma20, ...widget.ma50, ...widget.ema9]) {
      if (i.value < minY) minY = i.value;
      if (i.value > maxY) maxY = i.value;
    }
    // 5% padding above + below the actual data. Clamp minY at zero —
    // a price chart should never show negative axis labels (the old
    // build was showing "-₹12" for fast-growing stocks like CUPID).
    final pad = (maxY - minY) * 0.05;
    if (pad == 0) {
      minY = math.max(0, minY - 1);
      maxY += 1;
    } else {
      minY = math.max(0, minY - pad);
      maxY += pad;
    }

    final up        = bars.last.close >= bars.first.close;
    final lineColor = up ? AppColors.green : AppColors.red;

    final mainSpots = <FlSpot>[
      for (int i = 0; i < bars.length; i++)
        FlSpot(i.toDouble(), bars[i].close),
    ];

    LineChartBarData lineSeries(List<IndicatorPoint> pts, Color c) {
      final spots = <FlSpot>[];
      final timeToIdx = <int, int>{
        for (int i = 0; i < bars.length; i++) bars[i].timeSec: i,
      };
      for (final p in pts) {
        final i = timeToIdx[p.time];
        if (i != null) spots.add(FlSpot(i.toDouble(), p.value));
      }
      return LineChartBarData(
        spots: spots,
        isCurved: false, color: c, barWidth: 1.3,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
      );
    }

    return LayoutBuilder(builder: (ctx, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final plotRect = Rect.fromLTRB(
        _leftInset, _topInset,
        size.width - _rightInset, size.height - _bottomInset,
      );

      // Pulse dot position — at the latest data point.
      final lastIdx = bars.length - 1;
      final lastX = plotRect.left + (lastIdx / (bars.length - 1)) * plotRect.width;
      final lastY = plotRect.top + (1 - (bars.last.close - minY) / (maxY - minY)) * plotRect.height;

      final chart = LineChart(
        LineChartData(
          minY: minY, maxY: maxY,
          minX: 0, maxX: (bars.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ((maxY - minY) / 4).clamp(0.0001, double.infinity),
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0x14FFFFFF), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: _rightInset,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('₹${v.toStringAsFixed(0)}',
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 9,
                    color: AppColors.text3)),
              ),
            )),
            leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: _bottomInset,
              interval: (bars.length / 4).clamp(1, double.infinity),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                final t = DateTime.fromMillisecondsSinceEpoch(
                    bars[i].timeSec * 1000, isUtc: false);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(DateFormat('d MMM').format(t),
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
                        color: AppColors.text3)),
                );
              },
            )),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: mainSpots,
              isCurved: false, color: lineColor, barWidth: 1.9,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: widget.filled
                ? BarAreaData(show: true, gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [
                      lineColor.withOpacity(0.32),
                      lineColor.withOpacity(0.00),
                    ]))
                : BarAreaData(show: false),
            ),
            if (widget.ma20.isNotEmpty) lineSeries(widget.ma20, AppColors.gold),
            if (widget.ma50.isNotEmpty) lineSeries(widget.ma50, AppColors.teal),
            if (widget.ema9.isNotEmpty) lineSeries(widget.ema9, AppColors.accent),
          ],
          // Disable fl_chart's native touch — we draw our own crosshair
          // on top so it works on mouse hover (web) AND touch drag.
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: const Duration(milliseconds: 220),
      );

      return MouseRegion(
        onHover: (e) => _setCursor(e.localPosition, plotRect, bars),
        onExit:  (_) => _setCursor(null, plotRect, bars),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:   (d) => _setCursor(d.localPosition, plotRect, bars),
          onPanStart:  (d) => _setCursor(d.localPosition, plotRect, bars),
          onPanUpdate: (d) => _setCursor(d.localPosition, plotRect, bars),
          onPanEnd:    (_) => _setCursor(null, plotRect, bars),
          onPanCancel: ()  => _setCursor(null, plotRect, bars),
          child: Stack(children: [
            chart,
            // Pulse dot at latest price (no-op when cursor active so
            // it doesn't compete visually with the crosshair).
            if (_cursor == null && lastX.isFinite && lastY.isFinite)
              Positioned(
                left: lastX - 6, top: lastY - 6,
                child: _PulseDot(color: lineColor),
              ),
            if (_cursor != null) IgnorePointer(
              child: CustomPaint(
                size: size,
                painter: _CrosshairPainter(
                  cursor: _cursor!,
                  plotRect: plotRect,
                  bars: bars,
                  minY: minY, maxY: maxY,
                  accent: lineColor,
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

// Live "tick" indicator — soft pulsing halo at the latest data point.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return SizedBox(
          width: 12, height: 12,
          child: Stack(alignment: Alignment.center, children: [
            // Outward expanding halo
            Container(
              width:  12 * (0.4 + t * 0.6),
              height: 12 * (0.4 + t * 0.6),
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: widget.color.withOpacity(0.40 * (1 - t))),
            ),
            // Solid dot
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [BoxShadow(color: widget.color.withOpacity(0.6),
                    blurRadius: 4)]),
            ),
          ]),
        );
      },
    );
  }
}

// Broker-grade crosshair overlay. Renders:
//   1. Dashed vertical line at cursor.x (clamped to plot)
//   2. Dashed horizontal line at cursor.y (clamped to plot)
//   3. Accent-colored price pill flush against the right axis
//   4. Accent-colored date pill on the bottom axis
//   5. Highlight halo at the data point (vertical-line × line intersection)
class _CrosshairPainter extends CustomPainter {
  final Offset cursor;
  final Rect plotRect;
  final List<Candle> bars;
  final double minY, maxY;
  final Color accent;
  _CrosshairPainter({
    required this.cursor, required this.plotRect, required this.bars,
    required this.minY, required this.maxY, required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!plotRect.contains(cursor)) return;
    final t = (cursor.dx - plotRect.left) / plotRect.width;
    final i = (t * (bars.length - 1)).round().clamp(0, bars.length - 1);
    final b = bars[i];

    // Snap vertical line to the actual data bar (not the raw cursor)
    // so the crosshair aligns with the bar under the cursor.
    final x = plotRect.left + (i / (bars.length - 1)) * plotRect.width;
    final y = plotRect.top  + (1 - (b.close - minY) / (maxY - minY)) * plotRect.height;

    final pCross = Paint()
      ..color = AppColors.accent.withOpacity(0.70)
      ..strokeWidth = 1;
    _dashedV(canvas, x, plotRect.top,  plotRect.bottom, pCross);
    _dashedH(canvas, y, plotRect.left, plotRect.right,  pCross);

    // Highlight halo at the data point
    canvas.drawCircle(Offset(x, y), 8,
      Paint()..color = accent.withOpacity(0.18));
    canvas.drawCircle(Offset(x, y), 4,
      Paint()..color = accent);
    canvas.drawCircle(Offset(x, y), 4,
      Paint()..color = AppColors.bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);

    // Price pill — right axis, vertically aligned to y
    _drawPill(canvas,
      text: '₹${b.close.toStringAsFixed(2)}',
      anchor: Offset(plotRect.right + 2, y),
      align: _PillAlign.right,
      bg: AppColors.accent,
      fg: Colors.white,
      fontFamily: 'DMMono',
    );

    // Date pill — bottom axis, horizontally aligned to x
    final dt = DateTime.fromMillisecondsSinceEpoch(b.timeSec * 1000, isUtc: false);
    final fmt = bars.length > 200
        ? DateFormat('d MMM yy')
        : DateFormat('d MMM');
    _drawPill(canvas,
      text: fmt.format(dt),
      anchor: Offset(x, plotRect.bottom + 2),
      align: _PillAlign.bottom,
      bg: AppColors.accent,
      fg: Colors.white,
      fontFamily: 'DMSans',
    );
  }

  void _dashedV(Canvas c, double x, double y1, double y2, Paint p) {
    const dash = 4.0, gap = 4.0;
    double y = y1;
    while (y < y2) {
      final end = math.min(y + dash, y2);
      c.drawLine(Offset(x, y), Offset(x, end), p);
      y += dash + gap;
    }
  }
  void _dashedH(Canvas c, double y, double x1, double x2, Paint p) {
    const dash = 4.0, gap = 4.0;
    double x = x1;
    while (x < x2) {
      final end = math.min(x + dash, x2);
      c.drawLine(Offset(x, y), Offset(end, y), p);
      x += dash + gap;
    }
  }
  void _drawPill(Canvas c, {
    required String text,
    required Offset anchor,
    required _PillAlign align,
    required Color bg, required Color fg, required String fontFamily,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        fontFamily: fontFamily, fontSize: 10, fontWeight: FontWeight.w700,
        color: fg)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    const padX = 5.0, padY = 2.5;
    final w = tp.width + padX * 2;
    final h = tp.height + padY * 2;
    Rect r;
    switch (align) {
      case _PillAlign.right:
        r = Rect.fromLTWH(anchor.dx, anchor.dy - h / 2, w, h);
        break;
      case _PillAlign.bottom:
        r = Rect.fromLTWH(anchor.dx - w / 2, anchor.dy, w, h);
        break;
    }
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
        Paint()..color = bg);
    tp.paint(c, Offset(r.left + padX, r.top + padY));
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) =>
    old.cursor != cursor || old.bars != bars ||
    old.minY != minY || old.maxY != maxY;
}

enum _PillAlign { right, bottom }

// ═══════════════════════════════════════════════════════════════
//  Candlestick chart view (CustomPainter)
//  Renders candles + optional MA/EMA overlays + optional volume,
//  with a manual touch-driven crosshair that mirrors fl_chart's UX.
// ═══════════════════════════════════════════════════════════════
class _CandleChartView extends StatefulWidget {
  final List<Candle> bars;
  final List<IndicatorPoint> ma20, ma50, ema9;
  final bool showVolume;
  final ValueChanged<_CrossInfo?> onCross;
  const _CandleChartView({
    required this.bars,
    required this.ma20, required this.ma50, required this.ema9,
    required this.showVolume, required this.onCross,
  });

  @override
  State<_CandleChartView> createState() => _CandleChartViewState();
}

class _CandleChartViewState extends State<_CandleChartView> {
  Offset? _touch;

  void _setTouch(Offset? p, Size size) {
    setState(() => _touch = p);
    if (p == null) {
      widget.onCross(null);
      return;
    }
    // axes inset must match the painter; keep them in lockstep.
    const right = 50.0, bottom = 22.0, left = 0.0, top = 6.0;
    final plotW = size.width - left - right;
    if (plotW <= 0) return;
    final n = widget.bars.length;
    final i = ((p.dx - left) / plotW * n).floor().clamp(0, n - 1);
    final b = widget.bars[i];
    widget.onCross(_CrossInfo(
      time: b.timeSec, close: b.close,
      open: b.open, high: b.high, low: b.low, volume: b.volume,
    ));
    // Ensure paint axes still match.
    // ignore: unused_local_variable
    final _ = top + bottom;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:   (d) => _setTouch(d.localPosition, size),
        onPanStart:  (d) => _setTouch(d.localPosition, size),
        onPanUpdate: (d) => _setTouch(d.localPosition, size),
        onPanCancel: () => _setTouch(null, size),
        onTapCancel: () => _setTouch(null, size),
        child: CustomPaint(
          size: size,
          painter: _CandlePainter(
            bars: widget.bars,
            ma20: widget.ma20,
            ma50: widget.ma50,
            ema9: widget.ema9,
            showVolume: widget.showVolume,
            touch: _touch,
          ),
        ),
      );
    });
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> bars;
  final List<IndicatorPoint> ma20, ma50, ema9;
  final bool showVolume;
  final Offset? touch;

  _CandlePainter({
    required this.bars,
    required this.ma20, required this.ma50, required this.ema9,
    required this.showVolume, required this.touch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const right  = 50.0;
    const bottom = 22.0;
    const top    = 6.0;
    const left   = 0.0;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    if (plotW <= 0 || plotH <= 0) return;

    // ── Y scale across both candles and indicator values
    double minY = bars.first.low, maxY = bars.first.high;
    for (final b in bars) {
      if (b.low  < minY) minY = b.low;
      if (b.high > maxY) maxY = b.high;
    }
    for (final p in [...ma20, ...ma50, ...ema9]) {
      if (p.value < minY) minY = p.value;
      if (p.value > maxY) maxY = p.value;
    }
    final yPad = (maxY - minY) * 0.06;
    if (yPad == 0) { minY -= 1; maxY += 1; } else { minY -= yPad; maxY += yPad; }
    final yRange = (maxY - minY).clamp(0.0001, double.infinity);

    double xOf(int i) => left + (i + 0.5) * (plotW / bars.length);
    double yOf(double v) => top + (1 - (v - minY) / yRange) * plotH;

    // Volume area = bottom 20% of plot. We carve it out by scaling
    // candles into the upper 80 % when volumes are shown.
    final candleTop   = top;
    final candleBot   = showVolume ? top + plotH * 0.80 : top + plotH;
    final volumeTop   = candleBot;
    final volumeBot   = top + plotH;
    final candleH     = candleBot - candleTop;
    double yCOf(double v) =>
        candleTop + (1 - (v - minY) / yRange) * candleH;

    // ── Grid + Y-axis labels (4 horizontal lines)
    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(
      fontFamily: 'DMMono', fontSize: 9.5, color: AppColors.text3);
    for (int i = 0; i <= 4; i++) {
      final y = candleTop + (candleH * i / 4);
      canvas.drawLine(
        Offset(left, y), Offset(left + plotW, y), gridPaint);
      final price = maxY - (maxY - minY) * (i / 4);
      _drawText(canvas,
          '₹${price.toStringAsFixed(0)}',
          Offset(left + plotW + 6, y - 5), labelStyle);
    }

    // ── X-axis labels (4 evenly spaced)
    for (int i = 0; i < 4; i++) {
      final idx = ((bars.length - 1) * i / 3).round();
      final t = DateTime.fromMillisecondsSinceEpoch(
          bars[idx].timeSec * 1000, isUtc: false);
      _drawText(canvas, DateFormat('d MMM').format(t),
          Offset(xOf(idx) - 14, top + plotH + 4),
          const TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: AppColors.text3));
    }

    // ── Volume bars
    if (showVolume) {
      double maxVol = 1;
      for (final b in bars) { if (b.volume > maxVol) maxVol = b.volume; }
      final volH = volumeBot - volumeTop;
      for (int i = 0; i < bars.length; i++) {
        final b = bars[i];
        if (b.volume <= 0) continue;
        final up = i == 0
            ? b.close >= b.open
            : b.close >= bars[i - 1].close;
        final color = (up ? AppColors.green : AppColors.red).withOpacity(0.4);
        final bw = (plotW / bars.length) * 0.7;
        final x  = xOf(i);
        final h  = (b.volume / maxVol) * volH;
        canvas.drawRect(
          Rect.fromLTRB(x - bw/2, volumeBot - h, x + bw/2, volumeBot),
          Paint()..color = color);
      }
    }

    // ── Candles
    final candleW = (plotW / bars.length) * 0.7;
    final wickW   = math.max(1.0, candleW * 0.10);
    for (int i = 0; i < bars.length; i++) {
      final b = bars[i];
      final up = b.close >= b.open;
      final color = up ? AppColors.green : AppColors.red;
      final x  = xOf(i);
      // Wick
      canvas.drawLine(
        Offset(x, yCOf(b.high)),
        Offset(x, yCOf(b.low)),
        Paint()..color = color..strokeWidth = wickW);
      // Body
      final yo = yCOf(b.open), yc = yCOf(b.close);
      final bodyTop    = math.min(yo, yc);
      final bodyBottom = math.max(yo, yc);
      final bodyH = math.max(1.0, bodyBottom - bodyTop);
      canvas.drawRect(
        Rect.fromLTWH(x - candleW/2, bodyTop, candleW, bodyH),
        Paint()..color = color);
    }

    // ── Indicator overlays
    void drawSeries(List<IndicatorPoint> pts, Color color) {
      if (pts.isEmpty) return;
      final timeToIdx = <int, int>{
        for (int i = 0; i < bars.length; i++) bars[i].timeSec: i,
      };
      final path = Path();
      bool started = false;
      for (final p in pts) {
        final i = timeToIdx[p.time];
        if (i == null) continue;
        final dx = xOf(i);
        final dy = yCOf(p.value);
        if (!started) { path.moveTo(dx, dy); started = true; }
        else            path.lineTo(dx, dy);
      }
      canvas.drawPath(path, Paint()
        ..color = color..style = PaintingStyle.stroke..strokeWidth = 1.3);
    }
    drawSeries(ma20, AppColors.gold);
    drawSeries(ma50, AppColors.teal);
    drawSeries(ema9, AppColors.accent);

    // ── Crosshair (dashed lines + price + time labels)
    if (touch != null) {
      final t = touch!;
      if (t.dx >= left && t.dx <= left + plotW &&
          t.dy >= top  && t.dy <= top + plotH) {
        final n = bars.length;
        final i = ((t.dx - left) / plotW * n).floor().clamp(0, n - 1);
        final x = xOf(i);
        final crossPaint = Paint()
          ..color = AppColors.accent.withOpacity(0.6)
          ..strokeWidth = 1;
        _dashedLine(canvas, Offset(x, top), Offset(x, top + plotH), crossPaint);
        _dashedLine(canvas, Offset(left, t.dy),
            Offset(left + plotW, t.dy), crossPaint);

        // Price label on right axis
        final price = maxY - ((t.dy - top) / plotH) * yRange;
        final priceTxt = '₹${price.toStringAsFixed(2)}';
        final tp = TextPainter(
          text: TextSpan(text: priceTxt, style: const TextStyle(
            fontFamily: 'DMMono', fontSize: 10, color: Colors.white,
            fontWeight: FontWeight.w700)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        final boxR = Rect.fromLTWH(
            left + plotW + 2, t.dy - 8, tp.width + 8, 16);
        canvas.drawRRect(RRect.fromRectAndRadius(boxR, const Radius.circular(3)),
            Paint()..color = AppColors.accent);
        tp.paint(canvas, Offset(boxR.left + 4, boxR.top + 1));

        // Time label on x-axis
        final tt = DateTime.fromMillisecondsSinceEpoch(
            bars[i].timeSec * 1000, isUtc: false);
        final tStr = DateFormat('d MMM').format(tt);
        final tp2 = TextPainter(
          text: TextSpan(text: tStr, style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 9.5, color: Colors.white,
            fontWeight: FontWeight.w700)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        final boxT = Rect.fromLTWH(
            x - tp2.width/2 - 4, top + plotH + 2, tp2.width + 8, 14);
        canvas.drawRRect(RRect.fromRectAndRadius(boxT, const Radius.circular(3)),
            Paint()..color = AppColors.accent);
        tp2.paint(canvas, Offset(boxT.left + 4, boxT.top + 0.5));
      }
    }
  }

  void _drawText(Canvas canvas, String s, Offset at, TextStyle st) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    final dist = (b - a).distance;
    final dir  = (b - a) / dist;
    double walked = 0;
    while (walked < dist) {
      final start = a + dir * walked;
      final end   = a + dir * math.min(walked + dash, dist);
      canvas.drawLine(start, end, paint);
      walked += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
    old.bars  != bars || old.ma20 != ma20 || old.ma50 != ma50 ||
    old.ema9  != ema9 || old.showVolume != showVolume || old.touch != touch;
}

// ═══════════════════════════════════════════════════════════════
//  Sector-peer row
// ═══════════════════════════════════════════════════════════════
class _PeerRow extends StatefulWidget {
  final String symbol, exchange;
  final ChartDataService svc;
  final VoidCallback onTap;
  final int index;
  const _PeerRow({
    required this.symbol, required this.exchange,
    required this.svc, required this.onTap, required this.index,
  });
  @override
  State<_PeerRow> createState() => _PeerRowState();
}

class _PeerRowState extends State<_PeerRow> {
  double? _price;
  double? _changePct;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Stagger peer fetches so we don't hammer the CORS proxy with 6+
    // parallel requests (some proxies rate-limit hard and start
    // returning 403). 250 ms × row-index keeps the proxy happy and
    // reads as a graceful cascade in the UI.
    _scheduleLoad();
  }

  Future<void> _scheduleLoad() async {
    final delay = Duration(milliseconds: 250 * widget.index);
    await Future.delayed(delay);
    if (mounted) _load();
  }

  Future<void> _load() async {
    try {
      final ticker = widget.svc.yahooTicker(
        kind: HoldingKind.stock,
        symbol: widget.symbol,
        exchange: widget.exchange,
      );
      final res = await widget.svc.fetchYahoo(
        ticker: ticker, tf: ChartTimeframes.intraday1d);
      final m = res.meta;
      if (!mounted) return;
      setState(() {
        _price = m?.regularMarketPrice ?? res.bars.last.close;
        if (m?.previousClose != null && m!.previousClose! != 0) {
          _changePct = ((_price! - m.previousClose!) / m.previousClose!) * 100;
        }
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = (_changePct ?? 0) >= 0;
    final col = up ? AppColors.green : AppColors.red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(
                widget.symbol.length >= 2
                    ? widget.symbol.substring(0, 2) : widget.symbol,
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                  fontWeight: FontWeight.w700, color: AppColors.accent)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.symbol, style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppColors.text)),
                Text(widget.exchange, style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
              ])),
            if (!_loaded)
              const SizedBox(width: 14, height: 14, child:
                CircularProgressIndicator(strokeWidth: 1.2, color: AppColors.accent))
            else if (_price != null) Column(
              crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${_price!.toStringAsFixed(2)}', style: const TextStyle(
                  fontFamily: 'DMMono', fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.text)),
                if (_changePct != null) Text(
                  '${up ? "+" : ""}${_changePct!.toStringAsFixed(2)}%',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 10.5,
                      fontWeight: FontWeight.w600, color: col)),
              ])
            else const Icon(Icons.chevron_right_rounded,
                color: AppColors.text3, size: 18),
          ]),
        ),
      ),
    );
  }
}
