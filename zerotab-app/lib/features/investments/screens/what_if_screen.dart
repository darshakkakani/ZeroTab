// What If — investment-simulation screen.
//
// Inputs (top → bottom):
//   1. Asset chip (read-only — symbol + name)
//   2. Mode toggle: Lump-sum / SIP
//   3. Amount field (currency-aware: ₹ for NSE/IN, $ for US/Crypto)
//   4. Start date picker (calendar)
//   5. Compare-against checkboxes
//   → Compute button
//
// Outputs (top → bottom):
//   • Hero band — big tabular-money line, +/-Δ pill, annualised metric
//   • Comparison strip — small cards for each baseline checked
//   • Overlay chart — `fl_chart` LineChart with up to 4 curves +
//     dashed cumulative-invested step line for SIP
//   • Story sentence card
//
// All math runs in `WhatIfService` (pure Dart). This screen only
// stitches the fetch + state + render — no business logic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/services/providers.dart';
import '../services/chart_data_service.dart'
    show Candle, ChartDataService, HoldingKind;
import '../services/what_if_service.dart';

class WhatIfScreen extends ConsumerStatefulWidget {
  final String  initialSymbol;
  final String  initialName;
  final String  initialExchange;
  final HoldingKind initialKind;
  // Pre-fill defaults (used when entering from the Discover card or the
  // chart-screen tab). All optional — sensible defaults applied when null.
  final WhatIfMode? initialMode;
  final double?    initialAmount;
  final DateTime?  initialFromDate;

  const WhatIfScreen({
    super.key,
    required this.initialSymbol,
    required this.initialName,
    required this.initialExchange,
    this.initialKind = HoldingKind.stock,
    this.initialMode,
    this.initialAmount,
    this.initialFromDate,
  });

  @override
  ConsumerState<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends ConsumerState<WhatIfScreen> {
  ChartDataService get _svc => ref.read(chartDataServiceProvider);
  WhatIfService get _calc => WhatIfService.instance;

  late WhatIfMode _mode;
  late TextEditingController _amountCtrl;
  late DateTime _fromDate;
  late DateTime _toDate;

  // Baselines
  bool _cmpNifty = false;
  bool _cmpSp500 = false;
  bool _cmpGold  = false;
  bool _cmpFd    = false;

  bool _busy = false;
  String? _error;

  WhatIfResult? _primary;
  List<WhatIfResult> _baselines = const [];

  bool get _isCrypto =>
      widget.initialKind == HoldingKind.commodity &&
      widget.initialSymbol.toUpperCase().contains('-USD');

  bool get _isUs {
    final ex = widget.initialExchange.toUpperCase();
    return const {'NMS','NYQ','NCM','NGM','ASE','PCX','NASDAQ','NYSE','NYSEARCA','BATS','IEX'}
        .contains(ex);
  }

  bool get _isInr => !(_isUs || _isCrypto);

  String get _currencySymbol => _isInr ? '₹' : '\$';
  String get _currencyCode   => _isInr ? 'INR' : 'USD';

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? WhatIfMode.sip;
    // Default amount: ₹10,000 for INR symbols, $100 for USD-denominated.
    final defaultAmt = widget.initialAmount ?? (_isInr ? 10000.0 : 100.0);
    _amountCtrl = TextEditingController(text: defaultAmt.toStringAsFixed(0));
    final now = DateTime.now().toUtc();
    _fromDate = widget.initialFromDate ??
        DateTime.utc(now.year - 5, now.month, now.day);
    _toDate = now;
    // Defaults for compare-against per §2.2.
    if (_isCrypto) {
      _cmpNifty = true;       // crypto: NIFTY only, FD hidden.
    } else if (_isUs) {
      _cmpSp500 = true;
      _cmpFd = true;
    } else {
      _cmpNifty = true;
      _cmpFd = true;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Compute
  // ─────────────────────────────────────────────────────────────
  Future<void> _compute() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount greater than 0.');
      return;
    }
    if (!_fromDate.isBefore(_toDate)) {
      setState(() => _error = 'End date must be after start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final yahooTicker = _svc.yahooTicker(
        kind: widget.initialKind,
        symbol: widget.initialSymbol,
        exchange: widget.initialExchange,
      );
      final bars = await _svc.fetchHistoricalSeries(
        ticker: yahooTicker,
        from: _fromDate,
        to: _toDate,
      );
      if (bars.length < 2) {
        setState(() {
          _busy = false;
          _error = 'Not enough price history for this symbol in the chosen range.';
        });
        return;
      }
      final primary = _run(
        label: widget.initialSymbol,
        amount: amount,
        bars: bars,
      );

      // Baselines — each best-effort. Network failures skip silently.
      final out = <WhatIfResult>[];
      if (_cmpNifty) {
        final r = await _runIndexBaseline('NIFTY 50', '^NSEI', amount);
        if (r != null) out.add(r);
      }
      if (_cmpSp500) {
        final r = await _runIndexBaseline('S&P 500', '^GSPC', amount);
        if (r != null) out.add(r);
      }
      if (_cmpGold) {
        final r = await _runIndexBaseline('Gold', 'GC=F', amount);
        if (r != null) out.add(r);
      }
      if (_cmpFd && !_isCrypto) {
        out.add(_calc.compareBaseline(
          label: 'FD 6.5%',
          mode: _mode,
          amount: amount,
          annualRate: 0.065,
          fromDate: _fromDate,
          toDate: _toDate,
        ));
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _primary = primary;
        _baselines = out;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not load price history. Try a different date range.';
      });
    }
  }

  WhatIfResult _run({
    required String label,
    required double amount,
    required List<Candle> bars,
  }) {
    return _mode == WhatIfMode.lumpSum
        ? _calc.simulateLumpSum(
            label: label,
            amount: amount,
            bars: bars,
            fromDate: _fromDate,
            toDate: _toDate,
          )
        : _calc.simulateSip(
            label: label,
            amount: amount,
            bars: bars,
            fromDate: _fromDate,
            toDate: _toDate,
          );
  }

  Future<WhatIfResult?> _runIndexBaseline(
      String label, String ticker, double amount) async {
    try {
      final bars = await _svc.fetchHistoricalSeries(
        ticker: ticker, from: _fromDate, to: _toDate);
      if (bars.length < 2) return null;
      return _run(label: label, amount: amount, bars: bars);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('What If',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 16,
            fontWeight: FontWeight.w700, color: AppColors.text)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (!_isInr) _fxNotice(),
            _inputsCard(),
            const SizedBox(height: 14),
            _computeButton(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _errorLine(_error!),
            ],
            if (_primary != null) ...[
              const SizedBox(height: 18),
              _heroBand(_primary!),
              const SizedBox(height: 12),
              if (_baselines.isNotEmpty) _comparisonStrip(_primary!, _baselines),
              const SizedBox(height: 14),
              _overlayChart(_primary!, _baselines),
              const SizedBox(height: 14),
              _storyCard(_primary!, _baselines),
              const SizedBox(height: 10),
              _bestWorstChips(_primary!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fxNotice() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border)),
      child: const Row(children: [
        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.text3),
        SizedBox(width: 8),
        Expanded(child: Text(
          'Showing in USD. Currency conversion is coming soon.',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
            color: AppColors.text2))),
      ]),
    ),
  );

  // ── Inputs card ─────────────────────────────────────────────
  Widget _inputsCard() => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Asset'),
      _assetChip(),
      const SizedBox(height: 14),
      _label('Mode'),
      _modeSegment(),
      const SizedBox(height: 14),
      _label('Amount'),
      _amountField(),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [_label('Start date'), _dateBtn(_fromDate, isStart: true)])),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [_label('End date'), _dateBtn(_toDate, isStart: false)])),
      ]),
      const SizedBox(height: 14),
      _label('Compare against'),
      _baselineChecks(),
    ]),
  );

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(s.toUpperCase(),
      style: const TextStyle(fontFamily: 'DMSans', fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 0.5,
        color: AppColors.text3)),
  );

  Widget _assetChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.bg3,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border)),
    child: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: const Icon(Icons.show_chart_rounded,
          color: AppColors.accent, size: 15)),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.initialSymbol, style: const TextStyle(
          fontFamily: 'DMMono', fontSize: 13,
          fontWeight: FontWeight.w700, color: AppColors.text)),
        Text(widget.initialName, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 11,
          color: AppColors.text3), maxLines: 1,
          overflow: TextOverflow.ellipsis),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg4,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.border2)),
        child: Text(_currencyCode, style: const TextStyle(
          fontFamily: 'DMMono', fontSize: 9.5,
          fontWeight: FontWeight.w700, color: AppColors.text2,
          letterSpacing: 0.3)),
      ),
    ]),
  );

  Widget _modeSegment() => Row(children: [
    Expanded(child: _segBtn('Lump-sum', _mode == WhatIfMode.lumpSum,
      () => setState(() => _mode = WhatIfMode.lumpSum))),
    const SizedBox(width: 8),
    Expanded(child: _segBtn('SIP', _mode == WhatIfMode.sip,
      () => setState(() => _mode = WhatIfMode.sip))),
  ]);

  Widget _segBtn(String label, bool active, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.bg3,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: active
              ? AppColors.accent.withValues(alpha: 0.55)
              : AppColors.border)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontFamily: 'DMSans', fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? AppColors.accent2 : AppColors.text2)),
      ),
    );

  Widget _amountField() => TextField(
    controller: _amountCtrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    ],
    style: const TextStyle(fontFamily: 'DMMono', fontSize: 16,
      fontWeight: FontWeight.w700, color: AppColors.text),
    decoration: InputDecoration(
      prefixText: '$_currencySymbol ',
      prefixStyle: const TextStyle(fontFamily: 'DMMono', fontSize: 16,
        fontWeight: FontWeight.w700, color: AppColors.text2),
      hintText: '0',
      filled: true,
      fillColor: AppColors.bg3,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    ),
  );

  Widget _dateBtn(DateTime d, {required bool isStart}) => GestureDetector(
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: d,
        firstDate: DateTime(1990, 1, 1),
        lastDate: now,
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.bg2,
              onSurface: AppColors.text)),
          child: child!),
      );
      if (picked != null) {
        setState(() {
          if (isStart) {
            _fromDate = picked.toUtc();
          } else {
            _toDate = picked.toUtc();
          }
        });
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Icon(Icons.calendar_today_rounded,
          size: 13, color: AppColors.text3),
        const SizedBox(width: 8),
        Text(DateFormat('d MMM yyyy').format(d.toLocal()),
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 12.5,
            fontWeight: FontWeight.w600, color: AppColors.text)),
      ]),
    ),
  );

  Widget _baselineChecks() {
    final entries = <(String, bool, ValueChanged<bool>)>[
      if (!_isCrypto || !_isUs) ('NIFTY 50', _cmpNifty, (v) => setState(() => _cmpNifty = v)),
      if (_isUs || _isCrypto)   ('S&P 500',  _cmpSp500, (v) => setState(() => _cmpSp500 = v)),
      ('Gold', _cmpGold, (v) => setState(() => _cmpGold = v)),
      if (!_isCrypto) ('Bank FD 6.5%', _cmpFd, (v) => setState(() => _cmpFd = v)),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (label, active, onChanged) in entries)
        GestureDetector(
          onTap: () => onChanged(!active),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.bg3,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: active
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : AppColors.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: active ? AppColors.accent : AppColors.text3),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontFamily: 'DMSans', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.accent2 : AppColors.text2)),
            ]),
          ),
        ),
    ]);
  }

  Widget _computeButton() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    final enabled = amount > 0 && _fromDate.isBefore(_toDate) && !_busy;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? _compute : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.bg3,
          disabledForegroundColor: AppColors.text3,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        child: _busy
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 1.6))
            : const Text('Compute',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                  fontWeight: FontWeight.w700, letterSpacing: -0.2)),
      ),
    );
  }

  Widget _errorLine(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.red.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.red.withValues(alpha: 0.35))),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.red),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(
        fontFamily: 'DMSans', fontSize: 12, color: AppColors.red))),
    ]),
  );

  // ── Hero band ───────────────────────────────────────────────
  Widget _heroBand(WhatIfResult r) {
    final up = r.absoluteGain >= 0;
    final col = up ? AppColors.green : AppColors.red;
    final dur = _humanDuration(r.startDate, r.endDate);
    final annLabel = r.mode == WhatIfMode.lumpSum ? 'CAGR' : 'XIRR';
    final annPct = r.annualised.isNaN
        ? '—' : '${(r.annualised * 100).toStringAsFixed(1)}%';
    final sub = r.mode == WhatIfMode.lumpSum
        ? '$annLabel $annPct over $dur'
        : '$annLabel $annPct over ${r.installments} SIPs';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1F1845), Color(0xFF120E2A)]),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.30))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You would have', style: TextStyle(
          fontFamily: 'DMSans', fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2.withValues(alpha: 0.7))),
        const SizedBox(height: 6),
        _CountUp(
          value: r.finalValue,
          currencySymbol: _currencySymbol,
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 30,
            fontWeight: FontWeight.w700, letterSpacing: -1.2,
            color: AppColors.text, height: 1.0,
            fontFeatures: [
              FontFeature.tabularFigures(),
              FontFeature.liningFigures(),
            ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: col.withValues(alpha: 0.40))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(up ? Icons.trending_up_rounded
                : Icons.trending_down_rounded, size: 12, color: col),
            const SizedBox(width: 5),
            Text('${up ? "+" : "-"}$_currencySymbol'
              '${r.absoluteGain.abs().toStringAsFixed(0)}'
              ' (${up ? "+" : ""}${(r.pctReturn * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11.5,
                fontWeight: FontWeight.w700, color: col)),
          ]),
        ),
        const SizedBox(height: 6),
        Text(sub, style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: AppColors.text2.withValues(alpha: 0.8))),
      ]),
    );
  }

  // ── Comparison strip ───────────────────────────────────────
  Widget _comparisonStrip(WhatIfResult primary, List<WhatIfResult> baselines) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: baselines.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == 0) return _compareCard(primary, primary, accent: true);
          return _compareCard(baselines[i - 1], primary);
        },
      ),
    );
  }

  Widget _compareCard(WhatIfResult r, WhatIfResult primary,
      {bool accent = false}) {
    final delta = r.finalValue - primary.finalValue;
    final up = delta >= 0;
    final col = up ? AppColors.green : AppColors.red;
    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent
            ? AppColors.accent.withValues(alpha: 0.55)
            : AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.label, style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent ? AppColors.accent2 : AppColors.text2),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text('$_currencySymbol${r.finalValue.toStringAsFixed(0)}',
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 15,
            fontWeight: FontWeight.w700, color: AppColors.text,
            fontFeatures: [
              FontFeature.tabularFigures(),
              FontFeature.liningFigures(),
            ])),
        const SizedBox(height: 4),
        if (!accent) Text(
          '${up ? "+" : "-"}$_currencySymbol${delta.abs().toStringAsFixed(0)}',
          style: TextStyle(fontFamily: 'DMMono', fontSize: 11,
            fontWeight: FontWeight.w700, color: col))
        else const Text('Your pick',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
            color: AppColors.text3)),
      ]),
    );
  }

  // ── Overlay chart ─────────────────────────────────────────
  Widget _overlayChart(WhatIfResult primary, List<WhatIfResult> baselines) {
    final allSeries = [primary, ...baselines];
    if (allSeries.every((s) => s.series.length < 2)) {
      return const SizedBox.shrink();
    }

    // X-domain: union of all series start/end (epoch days from primary.start).
    final originSec = primary.startDate.toUtc().millisecondsSinceEpoch ~/ 1000;
    double toX(DateTime d) {
      final sec = d.toUtc().millisecondsSinceEpoch ~/ 1000;
      return (sec - originSec) / 86400.0;
    }

    double minY = double.infinity, maxY = -double.infinity;
    for (final s in allSeries) {
      for (final p in s.series) {
        if (p.value < minY) minY = p.value;
        if (p.value > maxY) maxY = p.value;
      }
    }
    if (primary.mode == WhatIfMode.sip) {
      for (final p in primary.series) {
        if (p.invested < minY) minY = p.invested;
        if (p.invested > maxY) maxY = p.invested;
      }
    }
    if (!minY.isFinite || !maxY.isFinite || maxY == minY) {
      return const SizedBox.shrink();
    }
    final pad = (maxY - minY) * 0.06;
    minY -= pad;
    maxY += pad;

    final colors = <Color>[
      AppColors.accent, AppColors.gold, AppColors.teal, AppColors.dataETF];

    LineChartBarData curve(WhatIfResult s, Color c, {bool primaryCurve = false}) {
      return LineChartBarData(
        isCurved: true, curveSmoothness: 0.18,
        color: c,
        barWidth: primaryCurve ? 2.5 : 1.5,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        spots: [
          for (final p in s.series) FlSpot(toX(p.date), p.value),
        ],
      );
    }

    final invested = LineChartBarData(
      isCurved: false,
      color: AppColors.text3,
      barWidth: 1.0,
      dashArray: const [4, 4],
      dotData: const FlDotData(show: false),
      spots: [
        for (final p in primary.series) FlSpot(toX(p.date), p.invested),
      ],
    );

    final bars = <LineChartBarData>[
      curve(primary, colors[0], primaryCurve: true),
      for (int i = 0; i < baselines.length; i++)
        curve(baselines[i], colors[(i + 1) % colors.length]),
      if (primary.mode == WhatIfMode.sip) invested,
    ];

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border)),
      child: LineChart(
        LineChartData(
          minY: minY, maxY: maxY,
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4.0,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 44,
              getTitlesWidget: (v, _) => Text(_short(v),
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                  color: AppColors.text3)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 22,
              interval: ((toX(primary.endDate) - 0).abs() / 4.0)
                  .clamp(1.0, double.infinity),
              getTitlesWidget: (v, _) {
                final sec = originSec + (v * 86400.0).round();
                final d = DateTime.fromMillisecondsSinceEpoch(
                  sec * 1000, isUtc: true);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('MMM yy').format(d),
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                      color: AppColors.text3)));
              }),
            ),
          ),
          lineBarsData: bars,
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.bg4,
              getTooltipItems: (spots) {
                return spots.map((sp) {
                  final col = sp.bar.color ?? AppColors.text;
                  return LineTooltipItem(
                    '$_currencySymbol${sp.y.toStringAsFixed(0)}',
                    TextStyle(fontFamily: 'DMMono', fontSize: 11,
                      fontWeight: FontWeight.w700, color: col),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Story sentence ─────────────────────────────────────────
  Widget _storyCard(WhatIfResult primary, List<WhatIfResult> baselines) {
    final story = _composeStory(primary, baselines);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bg3.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7)),
          alignment: Alignment.center,
          child: const Icon(Icons.auto_awesome_rounded,
            color: AppColors.teal, size: 15)),
        const SizedBox(width: 10),
        Expanded(child: Text(story, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 13, height: 1.55,
          color: AppColors.text))),
      ]),
    );
  }

  String _composeStory(WhatIfResult r, List<WhatIfResult> baselines) {
    final startStr = DateFormat('MMM yyyy').format(r.startDate.toLocal());
    final amt = '$_currencySymbol${(r.totalInvested / r.installments).toStringAsFixed(0)}';
    final value = '$_currencySymbol${r.finalValue.toStringAsFixed(0)}';
    final cmp = baselines.isEmpty ? null : baselines.first;
    final cmpFrag = cmp == null
        ? ''
        : (r.finalValue >= cmp.finalValue
            ? ' — ${(r.finalValue / cmp.finalValue).toStringAsFixed(1)}× '
              'better than the same plan in ${cmp.label}.'
            : ' — that\'s ${(cmp.finalValue / r.finalValue).toStringAsFixed(1)}× '
              'less than ${cmp.label} over the same period.');
    if (r.mode == WhatIfMode.lumpSum) {
      return 'If you invested $amt in ${r.label} in $startStr, today '
          'you would have $value$cmpFrag';
    }
    return 'If you invested $amt in ${r.label} every month from $startStr, '
        'today you would have $value$cmpFrag';
  }

  // ── Best / worst month chips ───────────────────────────────
  Widget _bestWorstChips(WhatIfResult r) {
    if (r.bestMonthDate == null && r.worstMonthDate == null) {
      return const SizedBox.shrink();
    }
    return Row(children: [
      if (r.bestMonthDate != null) Expanded(child: _monthChip(
        'Best month',
        DateFormat('MMM yyyy').format(r.bestMonthDate!.toLocal()),
        r.bestMonthPct, AppColors.green)),
      if (r.bestMonthDate != null && r.worstMonthDate != null)
        const SizedBox(width: 8),
      if (r.worstMonthDate != null) Expanded(child: _monthChip(
        'Worst month',
        DateFormat('MMM yyyy').format(r.worstMonthDate!.toLocal()),
        r.worstMonthPct, AppColors.red)),
    ]);
  }

  Widget _monthChip(String title, String dateStr, double pct, Color col) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 9.5,
          fontWeight: FontWeight.w700, letterSpacing: 0.5,
          color: AppColors.text3)),
        const SizedBox(height: 4),
        Text('$dateStr  ${pct >= 0 ? "+" : ""}'
          '${(pct * 100).toStringAsFixed(1)}%',
          style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
            fontWeight: FontWeight.w700, color: col)),
      ]),
    );

  // ── helpers ───────────────────────────────────────────────
  String _short(double v) {
    if (v.abs() >= 1e7) return '${(v / 1e7).toStringAsFixed(1)}Cr';
    if (v.abs() >= 1e5) return '${(v / 1e5).toStringAsFixed(1)}L';
    if (v.abs() >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _humanDuration(DateTime a, DateTime b) {
    final days = b.toUtc().difference(a.toUtc()).inDays.abs();
    final years = days ~/ 365;
    final months = (days % 365) ~/ 30;
    if (years == 0) return '$months mo';
    if (months == 0) return '${years}y';
    return '${years}y ${months}mo';
  }
}

// ─────────────────────────────────────────────────────────────
//  Tween count-up — animates a number 0 → target on landing.
// ─────────────────────────────────────────────────────────────
class _CountUp extends StatelessWidget {
  final double value;
  final String currencySymbol;
  final TextStyle style;
  const _CountUp({
    required this.value,
    required this.currencySymbol,
    required this.style,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => Text(
      '$currencySymbol${v.toStringAsFixed(0)}',
      style: style,
    ),
  );
}
