// Chart data service — fetches OHLCV history from free sources.
//
//   • Stocks / ETFs / Commodities → Yahoo Finance v8 chart endpoint.
//     Returns full OHLCV; Yahoo's intraday data on Indian listings is
//     ~15-min delayed (SEBI rule for unlicensed consumers).
//
//   • Mutual funds → api.mfapi.in. NAVs are daily only.
//
// Both APIs are free and require no auth.

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

enum HoldingKind { stock, mf, etf, commodity }

class Candle {
  final int    timeSec;   // unix seconds (UTC)
  final double open, high, low, close;
  final double volume;
  const Candle({
    required this.timeSec,
    required this.open, required this.high,
    required this.low,  required this.close,
    required this.volume,
  });

  Map<String, dynamic> toCandleJson() => {
        'time': timeSec,
        'open': open, 'high': high, 'low': low, 'close': close,
      };
  Map<String, dynamic> toVolumeJson(bool up) => {
        'time':  timeSec,
        'value': volume,
        'color': up ? 'rgba(30,191,122,0.55)' : 'rgba(224,74,63,0.55)',
      };
}

/// Time-frame catalog. Each TF maps to a (yahoo range, yahoo interval) pair
/// for stocks/ETFs/commodities, and to a number-of-days cutoff for MF NAVs.
class ChartTimeframe {
  final String label;
  final String yfRange;
  final String yfInterval;
  final int    mfDays;          // 0 ⇒ MF not supported on this TF
  final bool   intraday;        // implies we need second-precision time
  const ChartTimeframe(this.label, this.yfRange, this.yfInterval,
      this.mfDays, this.intraday);
}

class ChartTimeframes {
  // Stocks / ETFs / Commodities timeframes — Yahoo permits these
  // (range, interval) combos on Indian listings:
  //   1m bars         range ≤ 7d
  //   5m / 15m / 30m  range ≤ 60d
  //   60m             range ≤ 730d
  //   1d / 1wk / 1mo  range up to max
  //
  // MF NAVs are daily-only, so 1m/5m/15m/1H slots collapse to a day-or-more
  // cutoff equivalent (we just hide them for MF in the UI).
  static const intraday1d = ChartTimeframe('1D',  '1d',  '1m',  1,       true);
  static const intraday5d = ChartTimeframe('5D',  '5d',  '5m',  7,       true);
  static const day1m      = ChartTimeframe('1M',  '1mo', '15m', 30,      true);
  static const day3m      = ChartTimeframe('3M',  '3mo', '60m', 90,      true);
  static const day6m      = ChartTimeframe('6M',  '6mo', '1d',  180,     false);
  static const year1      = ChartTimeframe('1Y',  '1y',  '1d',  365,     false);
  static const year5      = ChartTimeframe('5Y',  '5y',  '1wk', 1825,    false);
  static const all        = ChartTimeframe('All', 'max', '1mo', 100000,  false);

  // Order shown to users — stocks support every entry, MF skips intraday TFs.
  static const allForStock = [
    intraday1d, intraday5d, day1m, day3m, day6m, year1, year5, all,
  ];
  static const allForMF = [
    day1m, day3m, day6m, year1, year5, all,
  ];
}

class ChartDataException implements Exception {
  final String message;
  ChartDataException(this.message);
  @override
  String toString() => message;
}

class ChartDataService {
  final Dio _dio;
  ChartDataService([Dio? dio])
      : _dio = dio ?? Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: const {
              'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
              'Accept': 'application/json,text/plain,*/*',
            },
          ));

  // Symbol resolution — turns ZeroTab's holding identifiers into a Yahoo
  // ticker. NSE-listed stocks/ETFs → "<symbol>.NS"; BSE → "<symbol>.BO";
  // MCX commodities → Yahoo's continuous-futures symbols (best-effort map).
  String yahooTicker({
    required HoldingKind kind,
    required String symbol,
    String exchange = 'NSE',
  }) {
    final s = symbol.toUpperCase().trim();
    if (s.isEmpty) return '';
    if (s.contains('.')) return s; // already qualified
    if (kind == HoldingKind.commodity) {
      const map = {
        'GOLD': 'GC=F', 'GOLDPETAL': 'GC=F', 'GOLDM': 'GC=F',
        'SILVER': 'SI=F', 'SILVERM': 'SI=F',
        'CRUDEOIL': 'CL=F', 'NATURALGAS': 'NG=F',
        'COPPER': 'HG=F', 'ZINC': 'ZN=F', 'ALUMINIUM': 'ALI=F',
      };
      return map[s] ?? s;
    }
    return exchange.toUpperCase() == 'BSE' ? '$s.BO' : '$s.NS';
  }

  // ── Yahoo Finance ───────────────────────────────────────────────
  Future<List<Candle>> fetchYahoo({
    required String ticker,
    required ChartTimeframe tf,
  }) async {
    if (ticker.isEmpty) throw ChartDataException('No symbol');
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/$ticker'
        '?range=${tf.yfRange}&interval=${tf.yfInterval}'
        '&includePrePost=false&events=history';
    final resp = await _dio.get<dynamic>(url);
    final body = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
    final err  = body['chart']?['error'];
    if (err != null) throw ChartDataException(err['description'] ?? 'Yahoo error');
    final result = (body['chart']?['result'] as List?)?.first;
    if (result == null) throw ChartDataException('No data');

    final timestamps = (result['timestamp'] as List?) ?? const [];
    final quote = ((result['indicators']?['quote'] as List?)?.first ?? {})
        as Map<String, dynamic>;
    final opens   = (quote['open']   as List?) ?? const [];
    final highs   = (quote['high']   as List?) ?? const [];
    final lows    = (quote['low']    as List?) ?? const [];
    final closes  = (quote['close']  as List?) ?? const [];
    final volumes = (quote['volume'] as List?) ?? const [];

    final out = <Candle>[];
    for (int i = 0; i < timestamps.length; i++) {
      final t = timestamps[i] as int;
      final c = closes.length > i ? closes[i] : null;
      if (c == null) continue; // Yahoo emits null bars for holidays / gaps
      final o = (opens.length  > i && opens[i]  != null) ? opens[i]  as num : c;
      final h = (highs.length  > i && highs[i]  != null) ? highs[i]  as num : c;
      final l = (lows.length   > i && lows[i]   != null) ? lows[i]   as num : c;
      final v = (volumes.length > i && volumes[i] != null) ? volumes[i] as num : 0;
      out.add(Candle(
        timeSec: t,
        open: o.toDouble(), high: h.toDouble(),
        low:  l.toDouble(), close: (c as num).toDouble(),
        volume: v.toDouble(),
      ));
    }
    if (out.isEmpty) throw ChartDataException('No bars in range');
    return out;
  }

  // ── mfapi.in (Indian mutual fund NAV history) ──────────────────
  Future<List<Candle>> fetchMF({
    required String schemeCode,
    required ChartTimeframe tf,
  }) async {
    if (schemeCode.isEmpty) throw ChartDataException('No scheme code');
    final resp = await _dio.get<dynamic>('https://api.mfapi.in/mf/$schemeCode');
    final body = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
    final list = (body['data'] as List?) ?? const [];
    if (list.isEmpty) throw ChartDataException('No NAV history');

    final cutoff = DateTime.now().subtract(Duration(days: tf.mfDays));
    final fmt    = DateFormat('dd-MM-yyyy');
    final out    = <Candle>[];
    for (final row in list) {
      final m = row as Map<String, dynamic>;
      final d = m['date'] as String?;
      final n = m['nav']  as String?;
      if (d == null || n == null) continue;
      final dt  = fmt.parse(d);
      if (tf.mfDays > 0 && dt.isBefore(cutoff)) continue;
      final nav = double.tryParse(n);
      if (nav == null) continue;
      // NAV history has no OHLC — synthesize a daily candle where O=H=L=C=NAV.
      out.add(Candle(
        timeSec: dt.toUtc().millisecondsSinceEpoch ~/ 1000,
        open: nav, high: nav, low: nav, close: nav, volume: 0,
      ));
    }
    if (out.length < 2) throw ChartDataException('Not enough NAV history');
    out.sort((a, b) => a.timeSec.compareTo(b.timeSec));
    return out;
  }
}
