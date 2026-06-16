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
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';
import '../services/chart_data_service.dart';
import '../services/indicators.dart';

export '../services/chart_data_service.dart' show HoldingKind;

class HoldingChartScreen extends StatefulWidget {
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
  State<HoldingChartScreen> createState() => _HoldingChartScreenState();
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

class _HoldingChartScreenState extends State<HoldingChartScreen>
    with SingleTickerProviderStateMixin {
  final ChartDataService _svc = ChartDataService();

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

  // Cache: per (symbol, exchange, tf) so re-tapping timeframes is instant.
  final Map<String, ChartFetchResult> _cache = {};

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
    _fetchAndRender();
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
    setState(() { _loading = true; _error = null; _cross = null; });

    try {
      ChartFetchResult res;
      if (_cache[key] != null) {
        res = _cache[key]!;
      } else if (widget.kind == HoldingKind.mf) {
        res = await _svc.fetchMF(schemeCode: _symbolOrCode, tf: tf);
        _cache[key] = res;
      } else {
        final ticker = _svc.yahooTicker(
          kind: widget.kind, symbol: _symbolOrCode, exchange: _exchange);
        res = await _svc.fetchYahoo(ticker: ticker, tf: tf);
        _cache[key] = res;
      }
      if (!mounted) return;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
            const Text('  ·  ', style: TextStyle(
              fontFamily: 'DMSans', color: AppColors.text3, fontSize: 10.5)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.25))),
              child: Text(
                widget.kind == HoldingKind.mf ? 'NAV (EOD)' : 'Delayed 15 min',
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 8.5,
                    fontWeight: FontWeight.w700, color: AppColors.gold,
                    letterSpacing: 0.3)),
            ),
          ]),
        ],
      )),
      IconButton(
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh_rounded,
            color: AppColors.text2, size: 19),
        onPressed: _loading ? null : () {
          _cache.remove(_cacheKey);
          _fetchAndRender();
        },
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('₹${ltp.toStringAsFixed(2)}', style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 30, height: 1.0,
              fontWeight: FontWeight.w700, letterSpacing: -1.1,
              color: AppColors.text,
              fontFeatures: [
                FontFeature.tabularFigures(),
                FontFeature.liningFigures(),
              ])),
            const SizedBox(height: 5),
            if (tfPct != null && tfAbs != null) Row(children: [
              Icon(up ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
                color: col, size: 13),
              const SizedBox(width: 2),
              Text(
                '${tfAbs >= 0 ? "+" : ""}${tfAbs.toStringAsFixed(2)}  '
                '(${tfPct >= 0 ? "+" : ""}${tfPct.toStringAsFixed(2)}%)',
                style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
                  fontWeight: FontWeight.w600, color: col)),
              const SizedBox(width: 6),
              Text(tfLabel, style: const TextStyle(fontFamily: 'DMSans',
                  fontSize: 10.5, color: AppColors.text3)),
            ]),
          ],
        )),
        if (crossDate != null) Text(
          DateFormat('d MMM, HH:mm').format(crossDate),
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 10.5,
              color: AppColors.text3)),
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

  // ─── Overview tab ───────────────────────────────────────────
  Widget _overviewTab() {
    final m  = _meta;
    final h  = widget.holding;
    final cp = m?.previousClose;
    final lp = m?.regularMarketPrice ?? (_bars.isNotEmpty ? _bars.last.close : null);
    final dayChange    = (cp != null && lp != null) ? lp - cp : null;
    final dayChangePct = (cp != null && lp != null && cp != 0)
        ? ((lp - cp) / cp) * 100 : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_isPeer) ...[
          _summaryCard(),
          const SizedBox(height: 12),
        ],
        _sectionTitle('Today'),
        _statGrid([
          if (dayChange != null)
            _Stat('Day change',
              '${dayChange >= 0 ? "+" : ""}₹${dayChange.toStringAsFixed(2)}',
              sub: dayChangePct != null
                  ? '${dayChangePct >= 0 ? "+" : ""}${dayChangePct.toStringAsFixed(2)}%'
                  : null,
              color: dayChange >= 0 ? AppColors.green : AppColors.red),
          if (m?.dayLow != null && m?.dayHigh != null)
            _Stat('Range',
              '₹${m!.dayLow!.toStringAsFixed(2)} – ₹${m.dayHigh!.toStringAsFixed(2)}'),
          if (m?.volume != null)
            _Stat('Volume', _fmtVol(m!.volume!)),
          if (m?.previousClose != null)
            _Stat('Prev close', '₹${m!.previousClose!.toStringAsFixed(2)}'),
        ]),
        const SizedBox(height: 16),
        if (m?.fiftyTwoWeekHigh != null && m?.fiftyTwoWeekLow != null) ...[
          _sectionTitle('52-week range'),
          _RangeBar(
            low: m!.fiftyTwoWeekLow!,
            high: m.fiftyTwoWeekHigh!,
            current: m.regularMarketPrice
                ?? (_bars.isNotEmpty ? _bars.last.close : m.fiftyTwoWeekLow!),
          ),
          const SizedBox(height: 16),
        ],
        _sectionTitle('Instrument'),
        _statGrid([
          if (m?.longName != null) _Stat('Name', m!.longName!),
          if (m?.instrumentType != null) _Stat('Type', m!.instrumentType!),
          if (m?.exchange != null) _Stat('Exchange', m!.exchange!),
          if (m?.currency != null) _Stat('Currency', m!.currency!),
          if (widget.kind == HoldingKind.mf && h.amcName != null)
            _Stat('AMC', h.amcName!),
        ]),
      ]),
    );
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
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(s.label, style: const TextStyle(fontFamily: 'DMSans',
                fontSize: 10, color: AppColors.text3)),
            Row(children: [
              Expanded(child: Text(s.value, style: TextStyle(
                fontFamily: 'DMMono', fontSize: 13, fontWeight: FontWeight.w700,
                color: s.color ?? AppColors.text), maxLines: 1,
                overflow: TextOverflow.ellipsis)),
              if (s.sub != null) const SizedBox(width: 6),
              if (s.sub != null) Text(s.sub!, style: TextStyle(
                fontFamily: 'DMMono', fontSize: 10.5, fontWeight: FontWeight.w600,
                color: s.color ?? AppColors.text2)),
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
    final peers = peersOf(_symbolOrCode);
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
        for (final p in peers) _PeerRow(
          symbol: p,
          exchange: _exchange,
          svc: _svc,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HoldingChartScreen(
              holding: widget.holding,
              kind: HoldingKind.stock,
              overrideSymbol: p,
              overrideExchange: _exchange,
              overrideName: p,
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

// ─── 52-week range visual ────────────────────────────────────
class _RangeBar extends StatelessWidget {
  final double low, high, current;
  const _RangeBar({required this.low, required this.high, required this.current});
  @override
  Widget build(BuildContext context) {
    final span = (high - low).clamp(0.0001, double.infinity);
    final pos  = ((current - low) / span).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Area / Line chart view (fl_chart)
// ═══════════════════════════════════════════════════════════════
class _AreaLineChartView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final closes = bars.map((b) => b.close).toList(growable: false);
    double minY = closes.first, maxY = closes.first;
    for (final v in closes) {
      if (v < minY) minY = v;
      if (v > maxY) maxY = v;
    }
    for (final i in [...ma20, ...ma50, ...ema9]) {
      if (i.value < minY) minY = i.value;
      if (i.value > maxY) maxY = i.value;
    }
    final pad = (maxY - minY) * 0.08;
    if (pad == 0) { minY -= 1; maxY += 1; } else { minY -= pad; maxY += pad; }

    final up = bars.last.close >= bars.first.close;
    final lineColor = up ? AppColors.green : AppColors.red;

    final mainSpots = <FlSpot>[
      for (int i = 0; i < bars.length; i++)
        FlSpot(i.toDouble(), bars[i].close),
    ];

    LineChartBarData lineSeries(List<IndicatorPoint> pts, Color c) {
      final spots = <FlSpot>[];
      // Map indicator times → bar indices using a hash to find x.
      final timeToIdx = <int, int>{
        for (int i = 0; i < bars.length; i++) bars[i].timeSec: i,
      };
      for (final p in pts) {
        final i = timeToIdx[p.time];
        if (i != null) spots.add(FlSpot(i.toDouble(), p.value));
      }
      return LineChartBarData(
        spots: spots,
        isCurved: false,
        color: c,
        barWidth: 1.3,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
      );
    }

    return LineChart(
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
            showTitles: true, reservedSize: 48,
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('₹${v.toStringAsFixed(0)}',
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                  color: AppColors.text3)),
            ),
          )),
          leftTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 22,
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
            isCurved: false,
            color: lineColor,
            barWidth: 1.8,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: filled
              ? BarAreaData(show: true, gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withOpacity(0.28),
                    lineColor.withOpacity(0.00),
                  ]))
              : BarAreaData(show: false),
          ),
          if (ma20.isNotEmpty) lineSeries(ma20, AppColors.gold),
          if (ma50.isNotEmpty) lineSeries(ma50, AppColors.teal),
          if (ema9.isNotEmpty) lineSeries(ema9, AppColors.accent),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.bg2,
            tooltipBorder: const BorderSide(color: AppColors.border),
            tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            getTooltipItems: (items) => items.map((it) {
              if (it.barIndex != 0) return null; // only show tooltip for main
              final i = it.x.toInt().clamp(0, bars.length - 1);
              final b = bars[i];
              return LineTooltipItem(
                '₹${b.close.toStringAsFixed(2)}\n${DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(b.timeSec * 1000, isUtc: false))}',
                const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                  fontWeight: FontWeight.w600, color: AppColors.text),
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (_, indicators) => indicators.map((_) =>
            TouchedSpotIndicatorData(
              FlLine(color: lineColor.withOpacity(0.5), strokeWidth: 1,
                  dashArray: [4, 4]),
              FlDotData(show: true, getDotPainter: (s, _, __, ___) =>
                FlDotCirclePainter(radius: 3.5,
                  color: lineColor, strokeWidth: 2, strokeColor: AppColors.bg)),
            )).toList(),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions ||
                response == null || response.lineBarSpots == null ||
                response.lineBarSpots!.isEmpty) {
              onCross(null);
              return;
            }
            final i = response.lineBarSpots!.first.x.toInt()
                .clamp(0, bars.length - 1);
            final b = bars[i];
            onCross(_CrossInfo(
              time: b.timeSec, close: b.close,
              open: b.open, high: b.high, low: b.low, volume: b.volume,
            ));
          },
        ),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}

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
  const _PeerRow({
    required this.symbol, required this.exchange,
    required this.svc, required this.onTap,
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
    _load();
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
