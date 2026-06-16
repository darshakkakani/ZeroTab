// Chart + holding-detail data service. All sources are free and unauthed:
//
//   • Stocks / ETFs / Commodities → Yahoo Finance v8 chart endpoint.
//     Returns OHLCV time series PLUS a rich `meta` block with 52w
//     range, day range, volume, exchange, company name — used to fill
//     the Overview tab without a second API call.
//   • Mutual funds → api.mfapi.in (daily NAVs).
//
// CORS:
//   When running as Flutter Web (`kIsWeb`), browser security blocks
//   direct cross-origin XHR to query1.finance.yahoo.com and
//   api.mfapi.in. We route through the user's own Supabase Edge
//   Function `/market-data`, which fetches the upstream URL server-
//   side and re-emits the payload with permissive CORS headers. The
//   Edge Function is deployed with --no-verify-jwt so no auth header
//   is required. On mobile (non-web) dio bypasses CORS, so we call
//   the upstream URL directly and skip the proxy entirely.

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';

enum HoldingKind { stock, mf, etf, commodity }

class Candle {
  final int    timeSec;
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

class QuoteMeta {
  final String? longName, exchange, instrumentType, currency, symbol;
  final double? regularMarketPrice;
  final double? previousClose;
  final double? dayHigh, dayLow;
  final double? fiftyTwoWeekHigh, fiftyTwoWeekLow;
  final double? volume;
  const QuoteMeta({
    this.longName, this.exchange, this.instrumentType, this.currency, this.symbol,
    this.regularMarketPrice, this.previousClose,
    this.dayHigh, this.dayLow,
    this.fiftyTwoWeekHigh, this.fiftyTwoWeekLow,
    this.volume,
  });

  factory QuoteMeta.fromYahoo(Map<String, dynamic> m) => QuoteMeta(
        longName:           m['longName'] as String?,
        exchange:           m['fullExchangeName'] as String? ??
                            m['exchangeName'] as String?,
        instrumentType:     m['instrumentType'] as String?,
        currency:           m['currency'] as String?,
        symbol:             m['symbol'] as String?,
        regularMarketPrice: (m['regularMarketPrice'] as num?)?.toDouble(),
        previousClose:      (m['chartPreviousClose'] as num?)?.toDouble() ??
                            (m['previousClose'] as num?)?.toDouble(),
        dayHigh:            (m['regularMarketDayHigh'] as num?)?.toDouble(),
        dayLow:             (m['regularMarketDayLow']  as num?)?.toDouble(),
        fiftyTwoWeekHigh:   (m['fiftyTwoWeekHigh'] as num?)?.toDouble(),
        fiftyTwoWeekLow:    (m['fiftyTwoWeekLow']  as num?)?.toDouble(),
        volume:             (m['regularMarketVolume'] as num?)?.toDouble(),
      );
}

class ChartFetchResult {
  final List<Candle> bars;
  final QuoteMeta?   meta;
  const ChartFetchResult({required this.bars, this.meta});
}

class ChartTimeframe {
  final String label;
  final String yfRange;
  final String yfInterval;
  final int    mfDays;
  final bool   intraday;
  const ChartTimeframe(this.label, this.yfRange, this.yfInterval,
      this.mfDays, this.intraday);
}

class ChartTimeframes {
  static const intraday1d = ChartTimeframe('1D',  '1d',  '1m',  1,       true);
  static const intraday5d = ChartTimeframe('5D',  '5d',  '5m',  7,       true);
  static const day1m      = ChartTimeframe('1M',  '1mo', '15m', 30,      true);
  static const day3m      = ChartTimeframe('3M',  '3mo', '60m', 90,      true);
  static const day6m      = ChartTimeframe('6M',  '6mo', '1d',  180,     false);
  static const year1      = ChartTimeframe('1Y',  '1y',  '1d',  365,     false);
  static const year5      = ChartTimeframe('5Y',  '5y',  '1wk', 1825,    false);
  static const all        = ChartTimeframe('All', 'max', '1mo', 100000,  false);

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
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 18),
            headers: const {
              'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
              'Accept': 'application/json,text/plain,*/*',
            },
          ));

  // ── CORS handling — two-tier fallback ──────────────────────────
  //
  // Mobile (non-web): dio bypasses CORS entirely; we call the upstream
  //                   directly with no proxy. This branch is the ground
  //                   truth path and never breaks.
  //
  // Web (kIsWeb):
  //   Tier 1 — User's own Supabase Edge Function `/market-data`. This is
  //            the right long-term proxy: stable, cache-controlled,
  //            free up to 500K invocations/month. But it only works if
  //            the function is actually deployed on the user's project.
  //   Tier 2 — r.jina.ai public reader. Free, CORS-friendly, no auth.
  //            Used as automatic fallback whenever Tier 1 returns
  //            404 (function not deployed yet), 5xx (function broken)
  //            or throws (network blip).
  //
  // Once a tier works in a session we stick to it via _stickyTier so
  // subsequent fetches don't waste a round-trip checking the dead one.
  String _wrapEdgeFn(String url) {
    final base = ApiConstants.supabaseUrl;
    if (base.isEmpty) return '';
    return '$base/functions/v1/market-data?url=${Uri.encodeComponent(url)}';
  }

  String _wrapJina(String url) => 'https://r.jina.ai/$url';

  int _stickyTier = 0; // 0 = Edge Function, 1 = Jina, set by first success

  Future<Response<dynamic>> _fetch(String url) async {
    if (!kIsWeb) return _dio.get<dynamic>(url);

    // Build candidate proxies in priority order, skipping Edge Function
    // when there's no SUPABASE_URL configured.
    final candidates = <String>[];
    final edgeFn = _wrapEdgeFn(url);
    if (edgeFn.isNotEmpty) candidates.add(edgeFn);
    candidates.add(_wrapJina(url));

    // Reorder so the sticky tier is tried first.
    if (_stickyTier == 1 && candidates.length > 1) {
      final j = candidates.removeLast();
      candidates.insert(0, j);
    }

    Object? lastErr;
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        final resp = await _dio.get<dynamic>(candidate,
            options: Options(
              // r.jina.ai sometimes returns text/plain instead of
              // application/json — accept anything and parse later.
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s >= 200 && s < 300,
            ));
        // Success: lock in this tier for the session.
        _stickyTier = candidate.contains('r.jina.ai') ? 1 : 0;
        return resp;
      } catch (e) {
        lastErr = e;
        // Continue to next candidate.
      }
    }
    throw ChartDataException('All chart-data proxies failed: $lastErr');
  }

  String yahooTicker({
    required HoldingKind kind,
    required String symbol,
    String exchange = 'NSE',
  }) {
    final s = symbol.toUpperCase().trim();
    if (s.isEmpty) return '';
    if (s.contains('.')) return s;
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

  Future<ChartFetchResult> fetchYahoo({
    required String ticker,
    required ChartTimeframe tf,
  }) async {
    if (ticker.isEmpty) throw ChartDataException('No symbol');
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/$ticker'
        '?range=${tf.yfRange}&interval=${tf.yfInterval}'
        '&includePrePost=false&events=history';
    final resp = await _fetch(url);
    final body = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
    final err  = body['chart']?['error'];
    if (err != null) throw ChartDataException(err['description'] ?? 'Yahoo error');
    final result = (body['chart']?['result'] as List?)?.first;
    if (result == null) throw ChartDataException('No data');

    final ts = (result['timestamp'] as List?) ?? const [];
    final quote = ((result['indicators']?['quote'] as List?)?.first ?? {})
        as Map<String, dynamic>;
    final opens   = (quote['open']   as List?) ?? const [];
    final highs   = (quote['high']   as List?) ?? const [];
    final lows    = (quote['low']    as List?) ?? const [];
    final closes  = (quote['close']  as List?) ?? const [];
    final volumes = (quote['volume'] as List?) ?? const [];

    final bars = <Candle>[];
    for (int i = 0; i < ts.length; i++) {
      final t = ts[i] as int;
      final c = closes.length > i ? closes[i] : null;
      if (c == null) continue;
      final o = (opens.length  > i && opens[i]  != null) ? opens[i]  as num : c;
      final h = (highs.length  > i && highs[i]  != null) ? highs[i]  as num : c;
      final l = (lows.length   > i && lows[i]   != null) ? lows[i]   as num : c;
      final v = (volumes.length > i && volumes[i] != null) ? volumes[i] as num : 0;
      bars.add(Candle(
        timeSec: t,
        open: o.toDouble(), high: h.toDouble(),
        low:  l.toDouble(), close: (c as num).toDouble(),
        volume: v.toDouble(),
      ));
    }
    if (bars.isEmpty) throw ChartDataException('No bars in range');

    final metaJson = result['meta'] as Map<String, dynamic>?;
    final meta = metaJson != null ? QuoteMeta.fromYahoo(metaJson) : null;
    return ChartFetchResult(bars: bars, meta: meta);
  }

  Future<ChartFetchResult> fetchMF({
    required String schemeCode,
    required ChartTimeframe tf,
  }) async {
    if (schemeCode.isEmpty) throw ChartDataException('No scheme code');
    final url  = 'https://api.mfapi.in/mf/$schemeCode';
    final resp = await _fetch(url);
    final body = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
    final list = (body['data'] as List?) ?? const [];
    if (list.isEmpty) throw ChartDataException('No NAV history');

    final cutoff = DateTime.now().subtract(Duration(days: tf.mfDays));
    final fmt    = DateFormat('dd-MM-yyyy');
    final bars   = <Candle>[];
    for (final row in list) {
      final m = row as Map<String, dynamic>;
      final d = m['date'] as String?;
      final n = m['nav']  as String?;
      if (d == null || n == null) continue;
      final dt  = fmt.parse(d);
      if (tf.mfDays > 0 && dt.isBefore(cutoff)) continue;
      final nav = double.tryParse(n);
      if (nav == null) continue;
      bars.add(Candle(
        timeSec: dt.toUtc().millisecondsSinceEpoch ~/ 1000,
        open: nav, high: nav, low: nav, close: nav, volume: 0,
      ));
    }
    if (bars.length < 2) throw ChartDataException('Not enough NAV history');
    bars.sort((a, b) => a.timeSec.compareTo(b.timeSec));

    final fundMeta = body['meta'] as Map<String, dynamic>?;
    final meta = QuoteMeta(
      longName: fundMeta?['scheme_name'] as String?,
      currency: 'INR',
      instrumentType: 'MUTUALFUND',
      regularMarketPrice: bars.last.close,
      previousClose:      bars.length > 1 ? bars[bars.length - 2].close : null,
      fiftyTwoWeekHigh:   _max(bars.where((b) =>
          b.timeSec * 1000 > DateTime.now().subtract(const Duration(days: 365))
              .millisecondsSinceEpoch)),
      fiftyTwoWeekLow:    _min(bars.where((b) =>
          b.timeSec * 1000 > DateTime.now().subtract(const Duration(days: 365))
              .millisecondsSinceEpoch)),
    );
    return ChartFetchResult(bars: bars, meta: meta);
  }

  double? _max(Iterable<Candle> bars) {
    double? m;
    for (final b in bars) { if (m == null || b.close > m) m = b.close; }
    return m;
  }
  double? _min(Iterable<Candle> bars) {
    double? m;
    for (final b in bars) { if (m == null || b.close < m) m = b.close; }
    return m;
  }
}

// ─────────────────────────────────────────────────────────────────
//  Sector / peer mapping — used by the "Similar" tab. Hand-curated
//  for top NSE stocks. When the user's holding matches a sector, we
//  show the other tickers from the same sector minus the holding
//  itself. Hard-coded is fine for v1; cheaper than a third-party
//  API call and avoids another CORS surface.
// ─────────────────────────────────────────────────────────────────
const Map<String, List<String>> kSectorPeers = {
  'IT': [
    'TCS', 'INFY', 'HCLTECH', 'WIPRO', 'TECHM', 'LTIM', 'PERSISTENT',
    'COFORGE', 'MPHASIS', 'OFSS',
  ],
  'BANK': [
    'HDFCBANK', 'ICICIBANK', 'SBIN', 'KOTAKBANK', 'AXISBANK',
    'INDUSINDBK', 'BANDHANBNK', 'IDFCFIRSTB', 'FEDERALBNK', 'BANKBARODA',
  ],
  'OIL': [
    'RELIANCE', 'ONGC', 'IOC', 'BPCL', 'HPCL', 'GAIL', 'PETRONET',
  ],
  'AUTO': [
    'MARUTI', 'TATAMOTORS', 'M&M', 'BAJAJ-AUTO', 'HEROMOTOCO', 'EICHERMOT',
    'TVSMOTOR', 'ASHOKLEY',
  ],
  'PHARMA': [
    'SUNPHARMA', 'CIPLA', 'DRREDDY', 'DIVISLAB', 'LUPIN', 'BIOCON',
    'TORNTPHARM', 'AUROPHARMA', 'GLENMARK', 'ZYDUSLIFE',
  ],
  'FMCG': [
    'HINDUNILVR', 'ITC', 'NESTLEIND', 'BRITANNIA', 'DABUR', 'GODREJCP',
    'MARICO', 'COLPAL', 'TATACONSUM',
  ],
  'METAL': [
    'TATASTEEL', 'JSWSTEEL', 'HINDALCO', 'VEDL', 'COALINDIA', 'JINDALSTEL',
    'SAIL', 'NMDC', 'NATIONALUM',
  ],
  'FINANCE': [
    'BAJFINANCE', 'BAJAJFINSV', 'HDFCAMC', 'CHOLAFIN', 'MUTHOOTFIN',
    'M&MFIN', 'SBILIFE', 'HDFCLIFE', 'ICICIPRULI', 'ICICIGI',
  ],
  'POWER': [
    'NTPC', 'POWERGRID', 'TATAPOWER', 'ADANIPOWER', 'JSW-ENERGY',
    'TORNTPOWER', 'CESC',
  ],
  'TELECOM': [
    'BHARTIARTL', 'IDEA', 'TATACOMM', 'INDUS-TOWERS',
  ],
  'CEMENT': [
    'ULTRACEMCO', 'SHREECEM', 'AMBUJACEM', 'ACC', 'DALBHARAT', 'JKCEMENT',
  ],
  'INFRA': [
    'LT', 'ADANIPORTS', 'ADANIENT', 'GMRINFRA', 'IRB',
  ],
};

/// Reverse lookup: ticker → sector key. O(N) over kSectorPeers but
/// the map is tiny; called once per "Similar" tab open.
String? sectorOf(String ticker) {
  final t = ticker.toUpperCase().split('.').first;
  for (final entry in kSectorPeers.entries) {
    if (entry.value.contains(t)) return entry.key;
  }
  return null;
}

List<String> peersOf(String ticker, {int limit = 6}) {
  final s = sectorOf(ticker);
  if (s == null) return const [];
  final t = ticker.toUpperCase().split('.').first;
  return kSectorPeers[s]!
      .where((p) => p != t)
      .take(limit)
      .toList(growable: false);
}
