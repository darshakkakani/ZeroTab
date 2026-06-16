// ignore_for_file: use_build_context_synchronously
//
// Holding Chart Screen — Dhan-style detail page for a single holding.
// Layout (top → bottom):
//   • Compact app-bar with name, symbol, exchange, "Delayed 15 min" pill
//   • Hero price block (large tabular figure + TF change %)
//   • Chart-type + indicator chips (Area / Candle / Line · MA20 · MA50 · EMA9 · Volume)
//   • Chart surface (≈38% of screen) — TradingView Lightweight Charts
//     loaded via WebView; on web the HTML still runs but data fetches
//     transparently route through corsproxy.io so the chart actually
//     renders.
//   • Timeframe selector (1D · 5D · 1M · 3M · 6M · 1Y · 5Y · All)
//   • Tab bar — Overview · Performance · Similar
//   • Tab content (scrollable, Dhan-style):
//       Overview   → company name, exchange, instrument, today's range,
//                    52-week range, volume, holding summary card
//       Performance→ 1D/1W/1M/3M/6M/1Y absolute & % returns derived from
//                    the chart history; visual bar plot
//       Similar    → sector peers (hard-coded sector→ticker map) tappable
//                    to navigate into the chart for that peer

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
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

  late WebViewController _wv;
  bool _wvReady = false;
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

  // Cache fetches per (tf, kind, ticker) so timeframe re-taps are instant.
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
    _initWebView();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Resolved symbol/exchange/name — uses overrides when this screen
  //  is opened as a peer drill-down.
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
  //  WebView setup
  // ─────────────────────────────────────────────────────────────
  void _initWebView() {
    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0820))
      ..addJavaScriptChannel('FlutterChart', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (mounted) setState(() => _error = 'Chart engine: ${e.description}');
        },
      ))
      ..loadFlutterAsset('assets/charts/tradingview_chart.html');
  }

  void _onJsMessage(JavaScriptMessage m) {
    try {
      final msg = jsonDecode(m.message) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'ready':
          _wvReady = true;
          _fetchAndRender();
          break;
        case 'cross':
          setState(() => _cross = _CrossInfo(
                time:  (msg['t'] as num).toInt(),
                close: (msg['c'] as num).toDouble(),
                open:  (msg['o'] as num?)?.toDouble(),
                high:  (msg['h'] as num?)?.toDouble(),
                low:   (msg['l'] as num?)?.toDouble(),
                volume:(msg['v'] as num?)?.toDouble(),
              ));
          break;
        case 'cross_clear':
          if (_cross != null) setState(() => _cross = null);
          break;
        case 'js_error':
          debugPrint('[chart js] ${msg['msg']}');
          break;
      }
    } catch (e) {
      debugPrint('chart channel parse: $e');
    }
  }

  Future<void> _post(Map<String, dynamic> payload) async {
    if (!_wvReady) return;
    final js = jsonEncode(payload);
    await _wv.runJavaScript('window.__chartHandle && window.__chartHandle($js);');
  }

  // ─────────────────────────────────────────────────────────────
  //  Data fetch + render
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
        res = await _svc.fetchMF(
          schemeCode: _symbolOrCode, tf: tf);
        _cache[key] = res;
      } else {
        final ticker = _svc.yahooTicker(
          kind: widget.kind, symbol: _symbolOrCode, exchange: _exchange);
        res = await _svc.fetchYahoo(ticker: ticker, tf: tf);
        _cache[key] = res;
      }
      _bars = res.bars;
      _meta = res.meta;

      await _pushToChart();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = _friendly(e.toString());
      });
    }
  }

  Future<void> _pushToChart() async {
    final candleJson = _bars.map((b) => b.toCandleJson()).toList();
    final volumeJson = _showVolume && widget.kind != HoldingKind.mf
        ? List<Map<String, dynamic>>.generate(_bars.length, (i) {
            final up = i == 0
                ? _bars[i].close >= _bars[i].open
                : _bars[i].close >= _bars[i - 1].close;
            return _bars[i].toVolumeJson(up);
          })
        : null;
    await _post({'type': 'volume', 'enabled': volumeJson != null});
    await _post({
      'type': 'data',
      'bars': candleJson,
      if (volumeJson != null) 'volume': volumeJson,
    });
    await _post({
      'type': 'kind',
      'kind': _kind == _ChartKind.candle
          ? 'candle' : _kind == _ChartKind.line ? 'line' : 'area',
    });
    await _post({'type': 'clear_overlays'});
    if (_ma20) {
      await _post({
        'type': 'overlay', 'name': 'ma20', 'color': '#E8A422', 'width': 1.4,
        'data': Indicators.sma(_bars, 20).map((p) => p.toJson()).toList(),
      });
    }
    if (_ma50) {
      await _post({
        'type': 'overlay', 'name': 'ma50', 'color': '#00C4A8', 'width': 1.4,
        'data': Indicators.sma(_bars, 50).map((p) => p.toJson()).toList(),
      });
    }
    if (_ema9) {
      await _post({
        'type': 'overlay', 'name': 'ema9', 'color': '#7B5FFF', 'width': 1.4,
        'data': Indicators.ema(_bars, 9).map((p) => p.toJson()).toList(),
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
    if (e.contains('CORS') || e.contains('XMLHttpRequest')) {
      return 'Network blocked by browser. Try again in a moment.';
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
    // Chart takes ~36% of total height (premium-feeling on phones,
    // doesn't dominate on tablets).
    final chartH  = (screenH * 0.36).clamp(220.0, 360.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        _topBar(),
        _heroPrice(ltp: ltp, tfAbs: tfAbs, tfPct: tfPct, up: up, col: col),
        _toolStrip(),
        SizedBox(
          height: chartH,
          child: Stack(children: [
            WebViewWidget(controller: _wv),
            if (_loading) Container(
              color: AppColors.bg.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 1.6)),
            ),
            if (_error != null) Container(
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
            ),
          ]),
        ),
        _timeframeBar(),
        // ── Tabs ──
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
        _indChip('MA 20', _ma20, AppColors.gold, () {
          setState(() => _ma20 = !_ma20); _pushToChart();
        }),
        _indChip('MA 50', _ma50, AppColors.teal, () {
          setState(() => _ma50 = !_ma50); _pushToChart();
        }),
        _indChip('EMA 9', _ema9, AppColors.accent, () {
          setState(() => _ema9 = !_ema9); _pushToChart();
        }),
        if (widget.kind != HoldingKind.mf)
          _indChip('Vol', _showVolume, AppColors.accent2, () {
            setState(() => _showVolume = !_showVolume); _pushToChart();
          }),
      ]),
    ),
  );

  Widget _kindChip(_ChartKind k, String label, IconData icon) {
    final active = k == _kind;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: () async {
          if (k == _kind) return;
          setState(() => _kind = k);
          await _post({
            'type': 'kind',
            'kind': k == _ChartKind.candle
                ? 'candle' : k == _ChartKind.line ? 'line' : 'area',
          });
        },
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
    // Compute returns at canonical look-backs from the LATEST chart we
    // happen to have. We need long-horizon data to fill 1Y/5Y, so we
    // pull the "All" cache if not already loaded.
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
    // Need a long series — use ALL timeframe (cache if not loaded).
    final allTf = widget.kind == HoldingKind.mf
        ? ChartTimeframes.all : ChartTimeframes.all;
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

  // ─── Holding summary card ───────────────────────────────────
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

// ─── Internal value-types ─────────────────────────────────────
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

// 52-week range visual
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

// Sector-peer row — fetches a 1D quick quote async to show LTP + day %.
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
      // 1d/1m gives current price + previousClose in meta — that's all
      // we need for the row's LTP + day %.
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
