// ignore_for_file: use_build_context_synchronously
//
// Holding Chart Screen — TradingView/Dhan-style price chart for a single
// holding (stock, ETF, MF, commodity). Uses free public APIs:
//   • Stocks/ETFs: Yahoo Finance v8 chart endpoint (SYMBOL.NS for NSE,
//     SYMBOL.BO for BSE). Returns OHLCV time series.
//   • Mutual funds: api.mfapi.in/mf/<scheme_code> — daily NAV history.
//
// Chart renders via fl_chart's LineChart with a gradient area fill and a
// long-press crosshair (same UX pattern Dhan and Groww use as their default
// view). Timeframe buttons (1D / 1W / 1M / 3M / 1Y / MAX) re-fetch as
// needed; results are cached in-memory for the screen lifetime.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';

enum HoldingKind { stock, mf, etf, commodity }

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

class _Range {
  final String label;
  final String yfRange;       // Yahoo: 1d/5d/1mo/3mo/1y/max
  final String yfInterval;    // Yahoo: 1m / 5m / 1d / 1wk
  final int    mfDays;        // mfapi.in cutoff (days back)
  const _Range(this.label, this.yfRange, this.yfInterval, this.mfDays);
}

const _ranges = <_Range>[
  _Range('1D',  '1d',  '5m',  1),
  _Range('1W',  '5d',  '15m', 7),
  _Range('1M',  '1mo', '1d',  30),
  _Range('3M',  '3mo', '1d',  90),
  _Range('1Y',  '1y',  '1d',  365),
  _Range('MAX', 'max', '1wk', 100000),
];

class _Point {
  final DateTime t;
  final double   close;
  const _Point(this.t, this.close);
}

class _HoldingChartScreenState extends State<HoldingChartScreen> {
  final Dio _http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      // Yahoo refuses empty UAs; a real-looking one keeps it stable.
      'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json,text/plain,*/*',
    },
  ));

  int _rangeIdx = 2; // default to 1M (matches Dhan default)
  final Map<int, List<_Point>> _cache = {};   // rangeIdx → series
  final Map<int, String>       _errors = {};
  bool _loading = false;

  _Point? _crosshair;

  @override
  void initState() {
    super.initState();
    _fetch(_rangeIdx);
  }

  String get _symbolOrCode {
    switch (widget.kind) {
      case HoldingKind.stock:     return widget.holding.stockSymbol;
      case HoldingKind.etf:       return widget.holding.etfSymbol;
      case HoldingKind.commodity: return widget.holding.commoditySymbol;
      case HoldingKind.mf:        return widget.holding.schemeCode ?? '';
    }
  }

  String _yfTicker() {
    final s = _symbolOrCode.toUpperCase();
    if (s.contains('.')) return s; // already qualified
    if (widget.kind == HoldingKind.commodity) {
      // Map common MCX symbols to Yahoo's futures (best-effort).
      const map = {
        'GOLD': 'GC=F', 'GOLDPETAL': 'GC=F',
        'SILVER': 'SI=F', 'CRUDEOIL': 'CL=F',
        'NATURALGAS': 'NG=F', 'COPPER': 'HG=F',
      };
      return map[s] ?? s;
    }
    // Default Indian listing: NSE (.NS). Exchange field may override.
    final exch = (widget.holding.stockExchange).toUpperCase();
    if (exch == 'BSE') return '$s.BO';
    return '$s.NS';
  }

  Future<void> _fetch(int rangeIdx) async {
    if (_cache.containsKey(rangeIdx)) {
      setState(() { _rangeIdx = rangeIdx; _crosshair = null; });
      return;
    }
    setState(() {
      _rangeIdx = rangeIdx;
      _loading = true;
      _errors.remove(rangeIdx);
      _crosshair = null;
    });
    try {
      final pts = widget.kind == HoldingKind.mf
          ? await _fetchMF(_ranges[rangeIdx])
          : await _fetchYahoo(_ranges[rangeIdx]);
      _cache[rangeIdx] = pts;
    } catch (e) {
      _errors[rangeIdx] = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_Point>> _fetchYahoo(_Range r) async {
    final t = _yfTicker();
    if (t.isEmpty) throw 'no symbol';
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/$t'
        '?range=${r.yfRange}&interval=${r.yfInterval}';
    final resp = await _http.get<dynamic>(url);
    final data = resp.data is String
        ? jsonDecode(resp.data as String)
        : resp.data;
    final result = (data['chart']?['result'] as List?)?.first;
    if (result == null) throw 'no data';
    final ts     = (result['timestamp'] as List?) ?? const [];
    final closes = (((result['indicators']?['quote'] as List?)?.first
        as Map<String, dynamic>?)?['close'] as List?) ?? const [];
    final out = <_Point>[];
    for (int i = 0; i < ts.length && i < closes.length; i++) {
      final c = closes[i];
      if (c == null) continue;
      out.add(_Point(
        DateTime.fromMillisecondsSinceEpoch((ts[i] as int) * 1000),
        (c as num).toDouble(),
      ));
    }
    if (out.isEmpty) throw 'empty series';
    return out;
  }

  Future<List<_Point>> _fetchMF(_Range r) async {
    final code = _symbolOrCode;
    if (code.isEmpty) throw 'no scheme code';
    final resp = await _http.get<dynamic>('https://api.mfapi.in/mf/$code');
    final data = resp.data is String
        ? jsonDecode(resp.data as String)
        : resp.data;
    final list = (data['data'] as List?) ?? const [];
    final cutoff = DateTime.now().subtract(Duration(days: r.mfDays));
    final fmt = DateFormat('dd-MM-yyyy');
    final out = <_Point>[];
    for (final row in list) {
      final m = row as Map<String, dynamic>;
      final d = m['date'] as String?;
      final n = m['nav']  as String?;
      if (d == null || n == null) continue;
      final dt = fmt.parse(d);
      if (dt.isBefore(cutoff)) continue;
      final nav = double.tryParse(n);
      if (nav == null) continue;
      out.add(_Point(dt, nav));
    }
    if (out.isEmpty) throw 'no NAV history';
    // mfapi.in returns newest-first; chart needs ascending.
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  // ─── UI ─────────────────────────────────────────────────────────

  String get _title {
    final s = widget.holding.schemeName;
    if (s != null && s.isNotEmpty) return s;
    return _symbolOrCode;
  }

  Color get _accent {
    switch (widget.kind) {
      case HoldingKind.stock:     return AppColors.accent;
      case HoldingKind.mf:        return AppColors.teal;
      case HoldingKind.etf:       return AppColors.dataETF;
      case HoldingKind.commodity: return AppColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = _cache[_rangeIdx];
    final err = _errors[_rangeIdx];

    final last  = pts != null && pts.isNotEmpty ? pts.last.close : null;
    final first = pts != null && pts.isNotEmpty ? pts.first.close : null;
    final pctChange = (first != null && first != 0 && last != null)
        ? ((last - first) / first) * 100
        : null;
    final priceChange = (first != null && last != null) ? last - first : null;
    final up = (pctChange ?? 0) >= 0;
    final changeColor = up ? AppColors.green : AppColors.red;

    final ltp  = _crosshair?.close ?? last ?? widget.holding.stockCurrentPrice;
    final ltpT = _crosshair?.t;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // ─ Top bar ─
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 4),
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
                    fontFamily: 'DMSans', fontSize: 15,
                    fontWeight: FontWeight.w700, color: AppColors.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_symbolOrCode + (widget.kind == HoldingKind.stock
                      ? '  ·  ${widget.holding.stockExchange}' : ''),
                    style: const TextStyle(fontFamily: 'DMMono',
                      fontSize: 10.5, color: AppColors.text3),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              )),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.text2, size: 19),
                onPressed: _loading ? null : () {
                  _cache.remove(_rangeIdx);
                  _fetch(_rangeIdx);
                },
              ),
            ]),
          ),

          // ─ Price + change ─
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${ltp.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'DMMono', fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1, height: 1.0,
                      color: AppColors.text,
                      fontFeatures: [
                        FontFeature.tabularFigures(),
                        FontFeature.liningFigures(),
                      ]),
                  ),
                  const SizedBox(height: 6),
                  if (pctChange != null)
                    Row(children: [
                      Icon(up ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                        color: changeColor, size: 13),
                      const SizedBox(width: 2),
                      Text(
                        '${priceChange! >= 0 ? "+" : ""}${priceChange.toStringAsFixed(2)}  '
                        '(${pctChange >= 0 ? "+" : ""}${pctChange.toStringAsFixed(2)}%)',
                        style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
                          fontWeight: FontWeight.w600, color: changeColor)),
                      const SizedBox(width: 6),
                      Text(_ranges[_rangeIdx].label,
                        style: const TextStyle(fontFamily: 'DMSans',
                          fontSize: 10.5, color: AppColors.text3)),
                    ]),
                ],
              )),
              if (ltpT != null)
                Text(DateFormat('d MMM, HH:mm').format(ltpT),
                  style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 10.5, color: AppColors.text3)),
            ]),
          ),

          // ─ Chart area ─
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 14, 6),
            child: _buildChart(pts, err),
          )),

          // ─ Timeframe selector ─
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(children: [
              for (int i = 0; i < _ranges.length; i++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _RangeButton(
                    label: _ranges[i].label,
                    active: i == _rangeIdx,
                    accent: _accent,
                    onTap: () => _fetch(i),
                  ),
                )),
            ]),
          ),

          // ─ Holding summary ─
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: _HoldingSummary(holding: widget.holding, kind: widget.kind),
          ),
        ]),
      ),
    );
  }

  Widget _buildChart(List<_Point>? pts, String? err) {
    if (_loading && pts == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent, strokeWidth: 1.5));
    }
    if (err != null && pts == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.signal_cellular_nodata_rounded,
              color: AppColors.text3, size: 28),
          const SizedBox(height: 10),
          const Text('Chart data unavailable',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
              fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(_friendlyErr(err),
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
              color: AppColors.text3), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _fetch(_rangeIdx),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.border)),
            child: const Text('Retry')),
        ]),
      );
    }
    if (pts == null || pts.length < 2) {
      return const Center(child: Text('Not enough data points',
        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
          color: AppColors.text3)));
    }

    final spots = <FlSpot>[
      for (int i = 0; i < pts.length; i++)
        FlSpot(i.toDouble(), pts[i].close),
    ];
    double minY = spots.first.y, maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final pad = (maxY - minY) * 0.08;
    if (pad == 0) { minY -= 1; maxY += 1; } else { minY -= pad; maxY += pad; }

    final up = pts.last.close >= pts.first.close;
    final lineColor = up ? AppColors.green : AppColors.red;

    return LineChart(
      LineChartData(
        minY: minY, maxY: maxY,
        minX: 0, maxX: (pts.length - 1).toDouble(),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: lineColor,
            barWidth: 1.8,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  lineColor.withOpacity(0.28),
                  lineColor.withOpacity(0.00),
                ],
              ),
            ),
          ),
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
              final i = it.x.toInt().clamp(0, pts.length - 1);
              final p = pts[i];
              return LineTooltipItem(
                '₹${p.close.toStringAsFixed(2)}\n${DateFormat('d MMM yyyy').format(p.t)}',
                const TextStyle(
                  fontFamily: 'DMMono', fontSize: 11,
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
                  color: lineColor,
                  strokeWidth: 2, strokeColor: AppColors.bg)),
            )).toList(),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions ||
                response == null || response.lineBarSpots == null ||
                response.lineBarSpots!.isEmpty) {
              if (_crosshair != null) {
                setState(() => _crosshair = null);
              }
              return;
            }
            final i = response.lineBarSpots!.first.x.toInt()
                .clamp(0, pts.length - 1);
            setState(() => _crosshair = pts[i]);
          },
        ),
      ),
      duration: const Duration(milliseconds: 250),
    );
  }

  String _friendlyErr(String e) {
    if (e.contains('SocketException') || e.contains('connection')) {
      return 'No internet connection';
    }
    if (e.contains('404') || e.contains('no data') || e.contains('empty')) {
      return 'No history found for this symbol';
    }
    if (e.contains('Timeout') || e.contains('timeout')) {
      return 'Network is slow — try again';
    }
    return 'Try again in a moment';
  }
}

class _RangeButton extends StatelessWidget {
  final String label;
  final bool   active;
  final Color  accent;
  final VoidCallback onTap;
  const _RangeButton({
    required this.label, required this.active,
    required this.accent, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 30,
      decoration: BoxDecoration(
        color: active ? accent.withOpacity(0.18) : AppColors.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? accent.withOpacity(0.55) : AppColors.border),
      ),
      alignment: Alignment.center,
      child: Text(label, style: TextStyle(
        fontFamily: 'DMSans', fontSize: 11,
        fontWeight: FontWeight.w700,
        color: active ? accent : AppColors.text2)),
    ),
  );
}

class _HoldingSummary extends StatelessWidget {
  final MFHoldingModel holding;
  final HoldingKind kind;
  const _HoldingSummary({required this.holding, required this.kind});

  @override
  Widget build(BuildContext context) {
    final qty   = kind == HoldingKind.stock
        ? holding.stockQty : (holding.units ?? 0);
    final avg   = holding.avgNav ?? 0;
    final inv   = holding.investedAmount ?? 0;
    final cur   = holding.currentValue   ?? 0;
    final gain  = holding.gainLoss;
    final gPct  = holding.gainLossPct;
    final up    = gain >= 0;
    final color = up ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(14),
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
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current value', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 10.5,
                color: AppColors.text3)),
              const SizedBox(height: 3),
              Text(formatInr(cur, compact: false),
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 17,
                  fontWeight: FontWeight.w700, color: AppColors.text,
                  fontFeatures: [
                    FontFeature.tabularFigures(),
                    FontFeature.liningFigures(),
                  ])),
            ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('P&L', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 10.5,
              color: AppColors.text3)),
            const SizedBox(height: 3),
            Text(
              '${up ? "+" : "-"}${formatInr(gain.abs(), compact: false)}',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 16,
                fontWeight: FontWeight.w700, color: color,
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                  FontFeature.liningFigures(),
                ])),
            Text('${up ? "+" : ""}${gPct.toStringAsFixed(2)}%',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
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
}
