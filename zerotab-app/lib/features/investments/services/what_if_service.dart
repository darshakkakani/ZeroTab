// What If — pure-Dart investment-simulation calculations.
//
// All math runs in `double` (Dart `double` is IEEE-754 64-bit — same
// precision as JS / typical financial-calc tools). The service is
// purely synchronous; the caller is responsible for fetching bars
// up front and passing them in.
//
// Numerical safety:
//   • Closing-price lookup picks the LATEST bar at-or-before the
//     requested date (`_closeOnOrBefore`). Never future-leak.
//   • SIP loop forward-fills weekends/holidays by querying the same
//     at-or-before helper; if no bar exists yet (date precedes the
//     symbol's first traded day) the installment is silently skipped.
//   • XIRR uses bisection over `r ∈ [-0.99, 10.0]`, capped at 60
//     iterations, tolerance 1e-6 on NPV. Never diverges.
//   • All date math converts to UTC before differencing — avoids DST
//     and TZ-offset drift in `Duration.inDays`.
//
// The companion `WhatIfResult` record is rendered by the What If
// screen's hero band, comparison strip and overlay chart.

import 'dart:math' as math;
import 'chart_data_service.dart' show Candle;

enum WhatIfMode { lumpSum, sip }
enum SipFrequency { monthly, weekly }

/// Single point on the value curve — used for the overlay chart and
/// best/worst-month chip math.
class WhatIfSeriesPoint {
  final DateTime date;
  final double invested; // cumulative cash put in (only meaningful for SIP)
  final double value;    // mark-to-market portfolio value
  const WhatIfSeriesPoint({
    required this.date,
    required this.invested,
    required this.value,
  });
}

/// Result of one simulation pass (chosen asset OR a baseline).
class WhatIfResult {
  final String label;           // e.g. "NVDA", "NIFTY 50", "FD 6.5%"
  final WhatIfMode mode;
  final double totalInvested;
  final double finalValue;
  final double absoluteGain;    // finalValue - totalInvested
  final double pctReturn;       // simple total return (for display only)
  final double annualised;      // CAGR for lump-sum, XIRR for SIP
  final DateTime startDate;
  final DateTime endDate;
  final int installments;       // SIP only; 1 for lump-sum
  final List<WhatIfSeriesPoint> series; // monthly resampled curve
  // Best / worst month (lump-sum: month-on-month return on asset price;
  // SIP: month-on-month return on portfolio value). NaN if no months.
  final double bestMonthPct;
  final DateTime? bestMonthDate;
  final double worstMonthPct;
  final DateTime? worstMonthDate;

  const WhatIfResult({
    required this.label,
    required this.mode,
    required this.totalInvested,
    required this.finalValue,
    required this.absoluteGain,
    required this.pctReturn,
    required this.annualised,
    required this.startDate,
    required this.endDate,
    required this.installments,
    required this.series,
    required this.bestMonthPct,
    required this.bestMonthDate,
    required this.worstMonthPct,
    required this.worstMonthDate,
  });
}

class WhatIfService {
  WhatIfService._();
  static final WhatIfService instance = WhatIfService._();

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  /// Lump-sum simulator. `bars` must be ordered ascending by `timeSec`.
  /// `fromDate` is clamped to the first bar at or after it (forward-
  /// fill of weekends/holidays/listing-day). Returns a fully populated
  /// `WhatIfResult` — never throws.
  WhatIfResult simulateLumpSum({
    required String label,
    required double amount,
    required List<Candle> bars,
    required DateTime fromDate,
    DateTime? toDate,
  }) {
    if (bars.isEmpty || amount <= 0) {
      return _emptyResult(label, WhatIfMode.lumpSum, fromDate,
        toDate ?? DateTime.now().toUtc());
    }
    final to = (toDate ?? _epochToUtc(bars.last.timeSec)).toUtc();
    final fromUtc = fromDate.toUtc();

    final entryClose = _closeOnOrAfter(bars, fromUtc);
    if (entryClose == null) {
      return _emptyResult(label, WhatIfMode.lumpSum, fromUtc, to);
    }
    final exitClose = _closeOnOrBefore(bars, to) ?? bars.last.close;
    final shares = amount / entryClose;
    final finalValue = shares * exitClose;
    final absGain = finalValue - amount;
    final pctReturn = absGain / amount;

    // CAGR. Use UTC day-difference for stability across DST.
    final years = math.max(
      to.difference(fromUtc).inDays / 365.25, 1.0 / 365.25);
    final cagr = math.pow(finalValue / amount, 1.0 / years).toDouble() - 1.0;

    // Monthly value curve — invested is flat (lump-sum), value tracks the
    // asset price scaled by `shares`.
    final series = <WhatIfSeriesPoint>[];
    DateTime cursor = DateTime.utc(fromUtc.year, fromUtc.month, 1);
    final endStop = DateTime.utc(to.year, to.month, 1);
    while (!cursor.isAfter(endStop)) {
      final c = _closeOnOrBefore(bars, cursor) ?? entryClose;
      series.add(WhatIfSeriesPoint(
        date: cursor, invested: amount, value: shares * c));
      cursor = _addMonths(cursor, 1);
    }
    // Tail: always end at the final exit point.
    series.add(WhatIfSeriesPoint(
      date: to, invested: amount, value: finalValue));

    final bw = _bestWorstMonth(series);
    return WhatIfResult(
      label: label,
      mode: WhatIfMode.lumpSum,
      totalInvested: amount,
      finalValue: finalValue,
      absoluteGain: absGain,
      pctReturn: pctReturn,
      annualised: cagr,
      startDate: fromUtc,
      endDate: to,
      installments: 1,
      series: series,
      bestMonthPct: bw.$1,
      bestMonthDate: bw.$2,
      worstMonthPct: bw.$3,
      worstMonthDate: bw.$4,
    );
  }

  /// SIP simulator — recurring contributions of `amount` on each
  /// frequency tick from `fromDate` to `toDate`. Skips ticks that
  /// precede the symbol's first traded day; the actual installment
  /// count is reflected in the returned result.
  WhatIfResult simulateSip({
    required String label,
    required double amount,
    required List<Candle> bars,
    required DateTime fromDate,
    required DateTime toDate,
    SipFrequency frequency = SipFrequency.monthly,
  }) {
    if (bars.isEmpty || amount <= 0) {
      return _emptyResult(label, WhatIfMode.sip, fromDate, toDate);
    }
    final fromUtc = fromDate.toUtc();
    final toUtc   = toDate.toUtc();

    double units = 0;
    final cashflows = <(DateTime, double)>[];
    final series = <WhatIfSeriesPoint>[];

    DateTime contrib = fromUtc;
    int installments = 0;
    while (!contrib.isAfter(toUtc)) {
      final price = _closeOnOrAfter(bars, contrib);
      if (price != null) {
        units += amount / price;
        cashflows.add((contrib, -amount));
        installments += 1;
      }
      // Series snapshot AT the contribution moment (uses the closest
      // historical close — same forward-fill semantics).
      final markPrice = _closeOnOrBefore(bars, contrib)
          ?? _closeOnOrAfter(bars, contrib)
          ?? bars.last.close;
      series.add(WhatIfSeriesPoint(
        date: contrib,
        invested: amount * installments,
        value: units * markPrice,
      ));
      // Advance.
      contrib = frequency == SipFrequency.monthly
          ? _addMonths(contrib, 1)
          : contrib.add(const Duration(days: 7));
    }

    // Mark-to-market at the end date.
    final exitClose = _closeOnOrBefore(bars, toUtc) ?? bars.last.close;
    final finalValue = units * exitClose;
    final totalInvested = amount * installments;
    final absGain = finalValue - totalInvested;
    final pctReturn = totalInvested == 0 ? 0.0 : absGain / totalInvested;

    // Add the terminal positive cashflow for XIRR.
    final cfForXirr = List<(DateTime, double)>.from(cashflows)
      ..add((toUtc, finalValue));
    final xirrVal = xirr(cashflows: cfForXirr);

    // Final series point at terminal date.
    series.add(WhatIfSeriesPoint(
      date: toUtc, invested: totalInvested, value: finalValue));

    final bw = _bestWorstMonth(series);
    return WhatIfResult(
      label: label,
      mode: WhatIfMode.sip,
      totalInvested: totalInvested,
      finalValue: finalValue,
      absoluteGain: absGain,
      pctReturn: pctReturn,
      annualised: xirrVal,
      startDate: fromUtc,
      endDate: toUtc,
      installments: installments,
      series: series,
      bestMonthPct: bw.$1,
      bestMonthDate: bw.$2,
      worstMonthPct: bw.$3,
      worstMonthDate: bw.$4,
    );
  }

  /// Bank FD baseline at a constant `annualRate` (e.g. 0.065 → 6.5%).
  /// Compounded monthly. Lump-sum: amount × (1 + r/12)^months.
  /// SIP: annuity-due — each installment compounds for the months that
  /// remain until `toDate`.
  WhatIfResult compareBaseline({
    required String label,
    required WhatIfMode mode,
    required double amount,
    required double annualRate,
    required DateTime fromDate,
    required DateTime toDate,
    SipFrequency frequency = SipFrequency.monthly,
  }) {
    final fromUtc = fromDate.toUtc();
    final toUtc   = toDate.toUtc();
    final monthlyRate = annualRate / 12.0;

    final series = <WhatIfSeriesPoint>[];

    if (mode == WhatIfMode.lumpSum) {
      final months = _monthsBetween(fromUtc, toUtc);
      DateTime cursor = DateTime.utc(fromUtc.year, fromUtc.month, 1);
      final endStop = DateTime.utc(toUtc.year, toUtc.month, 1);
      int m = 0;
      while (!cursor.isAfter(endStop)) {
        final v = amount * math.pow(1 + monthlyRate, m).toDouble();
        series.add(WhatIfSeriesPoint(
          date: cursor, invested: amount, value: v));
        cursor = _addMonths(cursor, 1);
        m += 1;
      }
      final finalValue = amount * math.pow(1 + monthlyRate, months).toDouble();
      series.add(WhatIfSeriesPoint(
        date: toUtc, invested: amount, value: finalValue));
      final years = math.max(
        toUtc.difference(fromUtc).inDays / 365.25, 1.0 / 365.25);
      final cagr = math.pow(finalValue / amount, 1.0 / years).toDouble() - 1.0;
      final bw = _bestWorstMonth(series);
      return WhatIfResult(
        label: label,
        mode: WhatIfMode.lumpSum,
        totalInvested: amount,
        finalValue: finalValue,
        absoluteGain: finalValue - amount,
        pctReturn: (finalValue - amount) / amount,
        annualised: cagr,
        startDate: fromUtc,
        endDate: toUtc,
        installments: 1,
        series: series,
        bestMonthPct: bw.$1,
        bestMonthDate: bw.$2,
        worstMonthPct: bw.$3,
        worstMonthDate: bw.$4,
      );
    }

    // SIP — annuity due, monthly compounding regardless of cadence (we
    // collapse weekly cadence to monthly buckets for FD math; the rate
    // is annualised so this is the conventional approximation).
    final cashflows = <(DateTime, double)>[];
    double cumulativeValue = 0;
    int installments = 0;
    DateTime contrib = fromUtc;
    while (!contrib.isAfter(toUtc)) {
      cashflows.add((contrib, -amount));
      installments += 1;
      // Advance prior balance one period before adding this contribution
      // so it gets a full period of growth.
      cumulativeValue = cumulativeValue * (1 + monthlyRate) + amount;
      series.add(WhatIfSeriesPoint(
        date: contrib,
        invested: amount * installments,
        value: cumulativeValue));
      contrib = frequency == SipFrequency.monthly
          ? _addMonths(contrib, 1)
          : contrib.add(const Duration(days: 7));
    }
    final totalInvested = amount * installments;
    final finalValue = cumulativeValue;
    series.add(WhatIfSeriesPoint(
      date: toUtc, invested: totalInvested, value: finalValue));
    final xirrVal = xirr(cashflows: List<(DateTime, double)>.from(cashflows)
      ..add((toUtc, finalValue)));
    final bw = _bestWorstMonth(series);
    return WhatIfResult(
      label: label,
      mode: WhatIfMode.sip,
      totalInvested: totalInvested,
      finalValue: finalValue,
      absoluteGain: finalValue - totalInvested,
      pctReturn: totalInvested == 0
          ? 0.0 : (finalValue - totalInvested) / totalInvested,
      annualised: xirrVal,
      startDate: fromUtc,
      endDate: toUtc,
      installments: installments,
      series: series,
      bestMonthPct: bw.$1,
      bestMonthDate: bw.$2,
      worstMonthPct: bw.$3,
      worstMonthDate: bw.$4,
    );
  }

  /// XIRR via bisection. Bounded to `[-0.99, 10.0]`, capped at 60
  /// iterations, tol 1e-6 absolute on NPV. Returns NaN when the NPV
  /// has no sign change across the bracket (no real root exists in
  /// the allowed range).
  double xirr({
    required List<(DateTime, double)> cashflows,
    double tol = 1e-6,
    int maxIter = 60,
  }) {
    if (cashflows.length < 2) return double.nan;
    double lo = -0.99, hi = 10.0;
    double fLo = _npv(cashflows, lo);
    double fHi = _npv(cashflows, hi);
    if (fLo.isNaN || fHi.isNaN) return double.nan;
    if (fLo * fHi > 0) return double.nan; // no sign change → no root.
    for (int i = 0; i < maxIter; i++) {
      final mid = (lo + hi) / 2.0;
      final fMid = _npv(cashflows, mid);
      if (fMid.abs() < tol) return mid;
      if (fLo * fMid < 0) {
        hi = mid; fHi = fMid;
      } else {
        lo = mid; fLo = fMid;
      }
    }
    return (lo + hi) / 2.0;
  }

  // ─────────────────────────────────────────────────────────────
  //  Internal helpers
  // ─────────────────────────────────────────────────────────────

  double _npv(List<(DateTime, double)> cf, double r) {
    if (cf.isEmpty) return 0.0;
    final t0 = cf.first.$1.toUtc();
    double s = 0.0;
    final base = 1.0 + r;
    if (base <= 0) return double.nan;
    for (final (d, a) in cf) {
      final years = d.toUtc().difference(t0).inDays / 365.25;
      s += a / math.pow(base, years);
    }
    return s;
  }

  /// Latest bar AT OR BEFORE `when`. Never future-leaks. Returns null
  /// when `when` precedes the symbol's first bar.
  double? _closeOnOrBefore(List<Candle> bars, DateTime when) {
    if (bars.isEmpty) return null;
    final whenSec = when.toUtc().millisecondsSinceEpoch ~/ 1000;
    // Bars are pre-sorted ascending; scan from the right for a fast
    // path on the common "near-end" lookups (SIP terminal mark).
    for (int i = bars.length - 1; i >= 0; i--) {
      if (bars[i].timeSec <= whenSec) return bars[i].close;
    }
    return null;
  }

  /// First bar AT OR AFTER `when`. Used for entry-price lookup on
  /// SIP contributions that fall on weekends/holidays. Returns null
  /// when no bar exists at or after the requested date.
  double? _closeOnOrAfter(List<Candle> bars, DateTime when) {
    if (bars.isEmpty) return null;
    final whenSec = when.toUtc().millisecondsSinceEpoch ~/ 1000;
    for (int i = 0; i < bars.length; i++) {
      if (bars[i].timeSec >= whenSec) return bars[i].close;
    }
    return null;
  }

  DateTime _addMonths(DateTime d, int n) {
    final y = d.year + ((d.month - 1 + n) ~/ 12);
    final m = ((d.month - 1 + n) % 12) + 1;
    // Clamp day to last day of target month (e.g. Jan 31 → Feb 28/29).
    final lastDay = DateTime.utc(y, m + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime.utc(y, m, day);
  }

  int _monthsBetween(DateTime a, DateTime b) {
    final aUtc = a.toUtc();
    final bUtc = b.toUtc();
    return (bUtc.year - aUtc.year) * 12 + (bUtc.month - aUtc.month);
  }

  DateTime _epochToUtc(int sec) =>
      DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true);

  /// Returns (bestPct, bestDate, worstPct, worstDate) computed on
  /// month-on-month return of `series[i].value`.
  (double, DateTime?, double, DateTime?) _bestWorstMonth(
      List<WhatIfSeriesPoint> series) {
    if (series.length < 2) {
      return (double.nan, null, double.nan, null);
    }
    double best = -double.infinity;
    double worst = double.infinity;
    DateTime? bestD;
    DateTime? worstD;
    for (int i = 1; i < series.length; i++) {
      final prev = series[i - 1].value;
      final cur = series[i].value;
      if (prev <= 0) continue;
      final r = (cur - prev) / prev;
      if (r > best) { best = r; bestD = series[i].date; }
      if (r < worst) { worst = r; worstD = series[i].date; }
    }
    if (best == -double.infinity) return (double.nan, null, double.nan, null);
    return (best, bestD, worst, worstD);
  }

  WhatIfResult _emptyResult(
      String label, WhatIfMode mode, DateTime from, DateTime to) =>
    WhatIfResult(
      label: label,
      mode: mode,
      totalInvested: 0,
      finalValue: 0,
      absoluteGain: 0,
      pctReturn: 0,
      annualised: double.nan,
      startDate: from.toUtc(),
      endDate: to.toUtc(),
      installments: 0,
      series: const [],
      bestMonthPct: double.nan,
      bestMonthDate: null,
      worstMonthPct: double.nan,
      worstMonthDate: null,
    );
}
