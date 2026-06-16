// ignore_for_file: use_build_context_synchronously
//
// Holding Chart Screen — TradingView-grade price chart for a single holding
// (stock / ETF / MF / commodity). The chart itself is the open-source
// TradingView Lightweight Charts library (Apache 2.0) loaded inside a
// WebView; ZeroTab feeds it OHLCV bars + indicator overlays computed in
// pure Dart.
//
// Data sources (free, no auth):
//   • Stocks / ETFs / Commodities → Yahoo Finance v8 chart (~15-min delayed
//     on Indian listings per SEBI rules).
//   • Mutual funds → api.mfapi.in (daily NAVs).
//
// User-visible features:
//   • Timeframes: 1D / 5D / 1M / 3M / 6M / 1Y / 5Y / All  (intraday TFs
//     hidden for MFs since NAVs are daily-only).
//   • Chart type: Area · Candlestick · Line.
//   • Indicators: MA20 · MA50 · EMA9  (toggle chips).
//   • Volume sub-panel for stocks / ETFs.
//   • Crosshair tooltip with OHLC + volume that follows cursor; price &
//     time axis labels rendered natively by the chart engine.
//   • Pinch-zoom, two-finger time scroll, fit-to-content.

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

// Re-export HoldingKind so callers (investments_screen.dart) keep their
// existing `import 'holding_chart_screen.dart'` path working.
export '../services/chart_data_service.dart' show HoldingKind;

class HoldingChartScreen extends StatefulWidget {
  final MFHoldingModel holding;
  final HoldingKind kind;
  const HoldingChartScreen({
    super.key,
    required this.holding,
    required this.kind,
  });

  @override
  State<HoldingChartScreen> createState() => _HoldingChartScreenState();
}

enum _ChartKind { area, candle, line }

class _CrossInfo {
  final int      time;
  final double?  open, high, low, volume;
  final double   close;
  const _CrossInfo({
    required this.time, required this.close,
    this.open, this.high, this.low, this.volume,
  });
}

class _HoldingChartScreenState extends State<HoldingChartScreen> {
  final ChartDataService _svc = ChartDataService();
  late WebViewController _wv;
  bool _wvReady = false;
  bool _loading = true;
  String? _error;

  late List<ChartTimeframe> _tfs;
  int _tfIdx = 2;
  _ChartKind _kind = _ChartKind.area;

  // Indicator toggles
  bool _ma20 = false;
  bool _ma50 = false;
  bool _ema9 = false;

  bool _showVolume = true;

  List<Candle> _bars = const [];
  _CrossInfo? _cross;

  @override
  void initState() {
    super.initState();
    _tfs = widget.kind == HoldingKind.mf
        ? ChartTimeframes.allForMF
        : ChartTimeframes.allForStock;
    // Default landing TF — "1M" for stocks (matches Dhan default),
    // first item for MFs.
    if (widget.kind != HoldingKind.mf) {
      _tfIdx = _tfs.indexOf(ChartTimeframes.day1m).clamp(0, _tfs.length - 1);
    } else {
      _tfIdx = 0;
    }
    _showVolume = widget.kind != HoldingKind.mf;
    _initWebView();
  }

  void _initWebView() {
    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0820))
      ..addJavaScriptChannel('FlutterChart', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (mounted) setState(() => _error = 'Chart engine failed: ${e.description}');
        },
      ))
      ..loadFlutterAsset('assets/charts/tradingview_chart.html');
  }

  // ─────────────────────────────────────────────────────────────
  //  JS bridge — Flutter → JS uses runJavaScript, JS → Flutter uses
  //  the FlutterChart channel (set up above). Messages on either
  //  side are JSON strings.
  // ─────────────────────────────────────────────────────────────
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
        case 'data_loaded':
          // no-op, useful for debugging
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
  //  Data load + push into JS
  // ─────────────────────────────────────────────────────────────
  Future<void> _fetchAndRender() async {
    final tf = _tfs[_tfIdx];
    setState(() { _loading = true; _error = null; _cross = null; });
    try {
      List<Candle> bars;
      if (widget.kind == HoldingKind.mf) {
        bars = await _svc.fetchMF(
          schemeCode: widget.holding.schemeCode ?? '', tf: tf);
      } else {
        final ticker = _svc.yahooTicker(
          kind: widget.kind,
          symbol: _symbolOrCode,
          exchange: widget.kind == HoldingKind.stock
              ? widget.holding.stockExchange : 'NSE',
        );
        bars = await _svc.fetchYahoo(ticker: ticker, tf: tf);
      }
      _bars = bars;

      // Bars
      final candleJson = bars.map((b) => b.toCandleJson()).toList();
      final volumeJson = _showVolume && widget.kind != HoldingKind.mf
          ? List<Map<String, dynamic>>.generate(bars.length, (i) {
              final up = i == 0
                  ? bars[i].close >= bars[i].open
                  : bars[i].close >= bars[i - 1].close;
              return bars[i].toVolumeJson(up);
            })
          : null;
      await _post({
        'type': 'volume',
        'enabled': volumeJson != null,
      });
      await _post({
        'type': 'data',
        'bars': candleJson,
        if (volumeJson != null) 'volume': volumeJson,
      });

      // Chart kind
      await _post({
        'type': 'kind',
        'kind': _kind == _ChartKind.candle
            ? 'candle' : _kind == _ChartKind.line ? 'line' : 'area',
      });

      // Re-apply indicator overlays
      await _post({'type': 'clear_overlays'});
      if (_ma20) {
        await _post({
          'type': 'overlay', 'name': 'ma20', 'color': '#E8A422', 'width': 1.4,
          'data': Indicators.sma(bars, 20).map((p) => p.toJson()).toList(),
        });
      }
      if (_ma50) {
        await _post({
          'type': 'overlay', 'name': 'ma50', 'color': '#00C4A8', 'width': 1.4,
          'data': Indicators.sma(bars, 50).map((p) => p.toJson()).toList(),
        });
      }
      if (_ema9) {
        await _post({
          'type': 'overlay', 'name': 'ema9', 'color': '#7B5FFF', 'width': 1.4,
          'data': Indicators.ema(bars, 9).map((p) => p.toJson()).toList(),
        });
      }

      if (mounted) setState(() => _loading = false);
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

  String get _symbolOrCode {
    switch (widget.kind) {
      case HoldingKind.stock:     return widget.holding.stockSymbol;
      case HoldingKind.etf:       return widget.holding.etfSymbol;
      case HoldingKind.commodity: return widget.holding.commoditySymbol;
      case HoldingKind.mf:        return widget.holding.schemeCode ?? '';
    }
  }

  String get _title {
    final s = widget.holding.schemeName;
    if (s != null && s.isNotEmpty) return s;
    return _symbolOrCode;
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ltp        = _cross?.close
        ?? (_bars.isNotEmpty ? _bars.last.close : widget.holding.stockCurrentPrice);
    final firstClose = _bars.isNotEmpty ? _bars.first.close : null;
    final lastClose  = _bars.isNotEmpty ? _bars.last.close  : null;
    final tfChange   = (firstClose != null && lastClose != null && firstClose != 0)
        ? ((lastClose - firstClose) / firstClose) * 100 : null;
    final tfDelta    = (firstClose != null && lastClose != null)
        ? lastClose - firstClose : null;
    final up         = (tfChange ?? 0) >= 0;
    final changeColor = up ? AppColors.green : AppColors.red;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        _topBar(),
        _priceBlock(ltp: ltp, tfChange: tfChange, tfDelta: tfDelta, up: up,
            changeColor: changeColor),
        _toolStrip(),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Stack(children: [
            // Translucent loading veil over the WebView, so the chart
            // surface stays mounted during re-fetches (no flicker).
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
                    color: AppColors.text3, size: 28),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 12.5,
                      color: AppColors.text2)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _fetchAndRender,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.border)),
                  child: const Text('Retry'),
                ),
              ]),
            ),
          ]),
        )),
        _timeframeBar(),
        _summaryCard(),
      ])),
    );
  }

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
              Text(widget.holding.stockExchange, style: const TextStyle(
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
        onPressed: _loading ? null : _fetchAndRender,
      ),
    ]),
  );

  Widget _priceBlock({
    required double  ltp,
    required double? tfChange,
    required double? tfDelta,
    required bool    up,
    required Color   changeColor,
  }) {
    final tfLabel = _tfs[_tfIdx].label;
    final crossDate = _cross != null
        ? DateTime.fromMillisecondsSinceEpoch(_cross!.time * 1000, isUtc: false)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('₹${ltp.toStringAsFixed(2)}', style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 32, height: 1.0,
              fontWeight: FontWeight.w700, letterSpacing: -1.2,
              color: AppColors.text,
              fontFeatures: [
                FontFeature.tabularFigures(),
                FontFeature.liningFigures(),
              ])),
            const SizedBox(height: 6),
            if (tfChange != null && tfDelta != null) Row(children: [
              Icon(up ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
                color: changeColor, size: 13),
              const SizedBox(width: 2),
              Text(
                '${tfDelta >= 0 ? "+" : ""}${tfDelta.toStringAsFixed(2)}  '
                '(${tfChange >= 0 ? "+" : ""}${tfChange.toStringAsFixed(2)}%)',
                style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
                  fontWeight: FontWeight.w600, color: changeColor)),
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

  // ── Chart type + indicators row ─────────────────────────────────
  Widget _toolStrip() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: SizedBox(height: 30,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        _kindChip(_ChartKind.area,   'Area',   Icons.show_chart_rounded),
        _kindChip(_ChartKind.candle, 'Candle', Icons.candlestick_chart_rounded),
        _kindChip(_ChartKind.line,   'Line',   Icons.timeline_rounded),
        const SizedBox(width: 10),
        Container(width: 1, height: 18, color: AppColors.border2,
            margin: const EdgeInsets.symmetric(vertical: 6)),
        const SizedBox(width: 10),
        _indChip('MA 20', _ma20, AppColors.gold, () {
          setState(() => _ma20 = !_ma20); _fetchAndRender();
        }),
        _indChip('MA 50', _ma50, AppColors.teal, () {
          setState(() => _ma50 = !_ma50); _fetchAndRender();
        }),
        _indChip('EMA 9', _ema9, AppColors.accent, () {
          setState(() => _ema9 = !_ema9); _fetchAndRender();
        }),
        if (widget.kind != HoldingKind.mf)
          _indChip('Volume', _showVolume, AppColors.accent2, () {
            setState(() => _showVolume = !_showVolume); _fetchAndRender();
          }),
      ]),
    ),
  );

  Widget _kindChip(_ChartKind k, String label, IconData icon) {
    final active = k == _kind;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
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
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withValues(alpha: 0.18) : AppColors.bg2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.accent.withValues(alpha: 0.55) : AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13,
              color: active ? AppColors.accent : AppColors.text3),
            const SizedBox(width: 5),
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
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  // ── Timeframe selector ──────────────────────────────────────────
  Widget _timeframeBar() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
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
              height: 30,
              decoration: BoxDecoration(
                color: i == _tfIdx
                    ? AppColors.accent.withValues(alpha: 0.20)
                    : AppColors.bg2,
                borderRadius: BorderRadius.circular(8),
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

  // ── Holding summary ─────────────────────────────────────────────
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ),
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
}
