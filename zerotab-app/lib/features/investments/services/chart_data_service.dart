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
import 'dart:math' as math;
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

/// Normalised prefetch unit produced by `ChartDataService.prefetchHoldings`.
/// `symbol` is the original user-supplied id (used as mfapi.in scheme code
/// for MFs); `ticker` is the resolved Yahoo ticker (empty for MFs).
class _PrefetchJob {
  final HoldingKind kind;
  final String symbol;
  final String ticker;
  final ChartTimeframe tf;
  const _PrefetchJob({
    required this.kind,
    required this.symbol,
    required this.ticker,
    required this.tf,
  });
}

class ChartDataService {
  // ── Singleton instance ─────────────────────────────────────────
  //
  // The service is treated as a process-wide singleton so the in-memory
  // result cache (`_resultCache`) survives screen-pop. Without this, the
  // holding-chart screen would lose every prefetched timeframe the moment
  // the user navigates back to the holdings list — defeating the whole
  // point of the background prefetch we kick off after initial render.
  //
  // Using a default factory constructor (rather than `ChartDataService.shared`)
  // means existing call sites that do `ChartDataService()` automatically
  // pick up the shared instance — zero churn at the call site.
  //
  // The optional `dio` parameter is still honoured for tests; passing a
  // custom Dio bypasses the cached instance and produces a fresh one.
  static ChartDataService? _instance;

  factory ChartDataService([Dio? dio]) {
    if (dio != null) return ChartDataService._internal(dio);
    return _instance ??= ChartDataService._internal(null);
  }

  ChartDataService._internal(Dio? dio)
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

  final Dio _dio;

  // Shared, process-lifetime cache keyed by (ticker-or-scheme, tf-label).
  // Lives on the singleton so navigation back-out preserves prefetched
  // bars. Holds successful fetches only — failed fetches are not cached.
  final Map<String, ChartFetchResult> _resultCache = {};

  String _resultKey(String idOrTicker, ChartTimeframe tf) =>
      '$idOrTicker::${tf.label}';

  /// Read-only view of the shared cache, exposed for screens that want
  /// to do their own cache-hit checks (e.g. instant timeframe swaps).
  Map<String, ChartFetchResult> get resultCache => _resultCache;

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

  // ── Symbol → Yahoo-ticker resolution ───────────────────────────
  //
  // `classifyAndResolve` is the single source of truth for turning a
  // (symbol, market) pair into a Yahoo Finance v8 ticker string. It
  // covers every market we currently care about; new markets are a
  // one-line addition to `_marketSuffix`.
  //
  // The `market` argument is interpreted loosely — it can be a literal
  // exchange code (`NSE`, `BSE`, `HKEX`), a country/region tag (`HK`,
  // `JP`, `UK`, `DE`, `CN`, `US`, `IN`), or even Yahoo's own suffix
  // (`.HK`, `.T`). All variants converge to the same suffix.
  //
  // Crypto is a special case: `kind == commodity` with a `-` in the
  // symbol (e.g. `BTC-USD`) is treated as a crypto pair and passed
  // through; otherwise commodities go through the commodity map.

  /// Static suffix table — keys may be exchange codes, country codes,
  /// or pre-qualified Yahoo suffixes. Values are the exact suffix Yahoo
  /// expects (including the leading dot).
  static const Map<String, String> _marketSuffix = {
    // ── United States (bare symbol, no suffix) ──────────────────────────
    'US': '', 'USA': '',
    'NASDAQ': '', 'NMS': '', 'NCM': '', 'NGM': '',          // NASDAQ tiers
    'NYSE': '', 'NYQ': '', 'ASE': '',                       // NYSE / NYSE American
    'NYSEARCA': '', 'PCX': '', 'ARCA': '',                  // NYSE Arca
    'AMEX': '', 'BATS': '', 'CBOE': '', 'IEX': '',
    'OTC': '', 'PNK': '', 'OBB': '', 'OEM': '',             // OTC / Pink Sheets

    // ── Crypto & FX (Yahoo expects symbol as-is: BTC-USD, USDINR=X) ────
    'CCC': '', 'CRYPTO': '',
    'CCY': '', 'FX': '', 'CUR': '',

    // ── India ──────────────────────────────────────────────────────────
    'NSE': '.NS', 'NSI': '.NS', 'IN': '.NS', 'INDIA': '.NS',
    'BSE': '.BO', 'BO': '.BO', 'BOM': '.BO',

    // ── United Kingdom / Ireland ───────────────────────────────────────
    'LSE': '.L', 'LON': '.L', 'L': '.L', 'UK': '.L', 'GB': '.L',
    'IOB': '.IL',                                           // London Int'l Order Book
    'ISE': '.IR',                                           // Irish Stock Exchange

    // ── Continental Europe ─────────────────────────────────────────────
    'GER': '.DE', 'XET': '.DE', 'XETRA': '.DE', 'FRA': '.F', 'FWB': '.F',
    'BER': '.BE', 'STU': '.SG', 'HAM': '.HM', 'HAN': '.HA', 'MUN': '.MU', 'DUS': '.DU',
    'AMS': '.AS',                                           // Euronext Amsterdam
    'PAR': '.PA', 'EPA': '.PA',                             // Euronext Paris
    'BRU': '.BR',                                           // Euronext Brussels
    'LIS': '.LS',                                           // Euronext Lisbon
    'EBS': '.SW', 'SWX': '.SW', 'VTX': '.VX',               // SIX Swiss
    'MIL': '.MI', 'BIT': '.MI',                             // Borsa Italiana
    'MCE': '.MC', 'BME': '.MC',                             // Bolsa de Madrid
    'ATH': '.AT',                                           // Athens
    'WAR': '.WA',                                           // Warsaw
    'BUD': '.BD',                                           // Budapest
    'PRA': '.PR',                                           // Prague
    'IST': '.IS',                                           // Istanbul
    'STO': '.ST',                                           // Stockholm
    'CPH': '.CO',                                           // Copenhagen
    'HEL': '.HE',                                           // Helsinki
    'OSL': '.OL',                                           // Oslo
    'ICE': '.IC',                                           // Iceland
    'MOEX': '.ME', 'MCX': '.ME',                            // Moscow

    // ── Asia-Pacific ───────────────────────────────────────────────────
    'TYO': '.T', 'TSE': '.T', 'JPX': '.T', 'JP': '.T', 'T': '.T',
    'HKG': '.HK', 'HKEX': '.HK', 'HK': '.HK',
    'SHA': '.SS', 'SHH': '.SS', 'SSE': '.SS', 'SS': '.SS', 'CN': '.SS',
    'SHE': '.SZ', 'SHZ': '.SZ', 'SZSE': '.SZ', 'SZ': '.SZ',
    'TAI': '.TW', 'TWO': '.TWO', 'TPE': '.TW',              // Taiwan
    'KSC': '.KS', 'KOSPI': '.KS',                           // Korea KOSPI
    'KOE': '.KQ', 'KOSDAQ': '.KQ',                          // Korea KOSDAQ
    'ASX': '.AX', 'AU': '.AX',                              // Australia
    'NZ': '.NZ', 'NZE': '.NZ',                              // New Zealand
    'SES': '.SI', 'SGX': '.SI', 'SG': '.SI',                // Singapore
    'KLS': '.KL', 'MYX': '.KL',                             // Malaysia
    'JKT': '.JK', 'IDX': '.JK',                             // Indonesia
    'SET': '.BK', 'BKK': '.BK',                             // Thailand
    'PSE': '.PS',                                           // Philippines
    'HOSE': '.VN', 'HNX': '.HN',                            // Vietnam

    // ── Americas ───────────────────────────────────────────────────────
    'TOR': '.TO', 'TSX': '.TO',                             // Toronto
    'TSXV': '.V', 'CVE': '.V',                              // TSX Venture
    'CNQ': '.CN', 'CSE': '.CN',                             // Canadian Securities
    'NEO': '.NE',                                           // NEO Exchange
    'SAO': '.SA', 'BVMF': '.SA', 'BVSP': '.SA',             // Brazil B3
    'MEX': '.MX', 'BMV': '.MX',                             // Mexico
    'BCBA': '.BA',                                          // Buenos Aires
    'SGO': '.SN',                                           // Santiago

    // ── Africa & Middle East ───────────────────────────────────────────
    'JNB': '.JO', 'JSE': '.JO',                             // Johannesburg
    'CAI': '.CA',                                           // Cairo
    'TLV': '.TA',                                           // Tel Aviv
    'SAU': '.SR',                                           // Saudi (Tadawul)
    'DFM': '.AE', 'ADX': '.AE',                             // UAE
    'QSE': '.QA',                                           // Qatar
  };

  /// Commodity-symbol → Yahoo futures-ticker translations. NSE/MCX names
  /// on the left, CME/COMEX `=F` tickers on the right.
  static const Map<String, String> _commodityMap = {
    'GOLD': 'GC=F', 'GOLDPETAL': 'GC=F', 'GOLDM': 'GC=F',
    'SILVER': 'SI=F', 'SILVERM': 'SI=F',
    'CRUDEOIL': 'CL=F', 'NATURALGAS': 'NG=F',
    'COPPER': 'HG=F', 'ZINC': 'ZN=F', 'ALUMINIUM': 'ALI=F',
  };

  /// Classify (symbol, market) and return the Yahoo ticker.
  ///
  /// Rules, in order:
  ///   1. Empty input → empty string.
  ///   2. Symbol already has a `.` (e.g. `AAPL.MX`) → trust it, return as-is.
  ///   3. Index symbol (`^GSPC`) → return as-is; HTTP layer URL-encodes `^`.
  ///   4. Crypto pair (contains `-`, e.g. `BTC-USD`, `ETH-INR`) → return as-is.
  ///   5. `kind == commodity` → look up in `_commodityMap`; passthrough on miss.
  ///   6. `kind == mf` → return symbol unchanged (mfapi.in doesn't use tickers).
  ///   7. Stocks / ETFs → consult `_marketSuffix`:
  ///        - exact match (case-insensitive) wins
  ///        - empty suffix means US bare-symbol (`AAPL`)
  ///        - no match falls back to legacy NSE/BSE logic for safety
  String classifyAndResolve({
    required HoldingKind kind,
    required String symbol,
    String market = 'NSE',
  }) {
    final s = symbol.toUpperCase().trim();
    if (s.isEmpty) return '';

    // Pre-qualified — caller already added a suffix.
    if (s.contains('.')) return s;

    // Index — preserve the `^`, leave URL-encoding (%5E) to the HTTP layer.
    if (s.startsWith('^')) return s;

    // Crypto pair (BTC-USD, ETH-INR, etc.). Yahoo's exact format.
    if (s.contains('-')) return s;

    // Commodity futures.
    if (kind == HoldingKind.commodity) {
      return _commodityMap[s] ?? s;
    }

    // Mutual funds don't have tickers; mfapi.in keys by scheme code.
    if (kind == HoldingKind.mf) return s;

    // Stocks / ETFs — look up the suffix table.
    final m = market.toUpperCase().trim();
    if (_marketSuffix.containsKey(m)) {
      final suffix = _marketSuffix[m]!;
      return suffix.isEmpty ? s : '$s$suffix';
    }
    // Unknown exchange → bare symbol. India tiles all carry NSI/NSE/BSE so
    // they hit the map; falling back to bare avoids appending .NS to US/EU/
    // crypto symbols that don't have an explicit market hint.
    return s;
  }

  /// Legacy entry point — kept for backwards compatibility. Routes
  /// through `classifyAndResolve` so the suffix logic lives in one place.
  String yahooTicker({
    required HoldingKind kind,
    required String symbol,
    String exchange = 'NSE',
  }) =>
      classifyAndResolve(kind: kind, symbol: symbol, market: exchange);

  Future<ChartFetchResult> fetchYahoo({
    required String ticker,
    required ChartTimeframe tf,
  }) async {
    if (ticker.isEmpty) throw ChartDataException('No symbol');

    // Shared-cache hit → return immediately. Prefetch + on-tap fetch
    // both populate this map so navigation back-out preserves results.
    final cacheKey = _resultKey(ticker, tf);
    final hit = _resultCache[cacheKey];
    if (hit != null) return hit;

    // URL-encode the ticker (covers `^` in index symbols → `%5E`).
    final encTicker = Uri.encodeComponent(ticker);
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/$encTicker'
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
    final out = ChartFetchResult(bars: bars, meta: meta);
    _resultCache[cacheKey] = out;
    return out;
  }

  Future<ChartFetchResult> fetchMF({
    required String schemeCode,
    required ChartTimeframe tf,
  }) async {
    if (schemeCode.isEmpty) throw ChartDataException('No scheme code');

    // Shared-cache hit. mfapi.in returns ~500KB of full history per
    // scheme, so caching is doubly important for MF symbols.
    final cacheKey = _resultKey(schemeCode, tf);
    final hit = _resultCache[cacheKey];
    if (hit != null) return hit;

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
    final out = ChartFetchResult(bars: bars, meta: meta);
    _resultCache[cacheKey] = out;
    return out;
  }

  // ── Bulk prefetch ──────────────────────────────────────────────
  //
  // Warm the cache for a list of holdings in the background so that
  // tapping any holding row renders its chart instantly. The expected
  // call site is the Investments screen, post-frame, ~600ms after the
  // holdings list lands (see `InvestmentsScreen._prefetchCharts`).
  //
  // Each item is a map with:
  //   • `symbol`    (String, required) — stock ticker or MF scheme code
  //   • `exchange`  (String, optional) — market code; defaults to `NSE`
  //   • `kind`      (String, required) — one of `stock`, `mf`, `etf`,
  //                                       `commodity` (case-insensitive)
  //   • `tf`        (ChartTimeframe, optional) — defaults to `day1m` for
  //                  stocks/etfs/commodities, `day3m` for MFs
  //
  // Idempotent — items whose `(ticker, tf)` is already in the cache are
  // skipped. Failures are swallowed silently; a real fetch later will
  // surface the error to the user normally.
  //
  // Concurrency is capped at 2 parallel jobs (mfapi.in returns ~500KB
  // per scheme and we don't want to hammer either upstream).
  Future<void> prefetchHoldings(
    List<Map<String, dynamic>> items, {
    int concurrency = 2,
  }) async {
    if (items.isEmpty) return;

    // 1. Normalise & dedupe items into concrete fetch jobs.
    final jobs = <_PrefetchJob>[];
    final seen = <String>{};
    for (final raw in items) {
      final symbol = (raw['symbol'] as String?)?.trim() ?? '';
      if (symbol.isEmpty) continue;

      final kindStr = (raw['kind'] as String?)?.toLowerCase().trim() ?? 'stock';
      final kind = _parseKind(kindStr);
      final exchange = (raw['exchange'] as String?)?.trim();
      final providedTf = raw['tf'];
      final tf = providedTf is ChartTimeframe
          ? providedTf
          : (kind == HoldingKind.mf
              ? ChartTimeframes.day3m
              : ChartTimeframes.day1m);

      // Resolve to the same cache key the fetch methods use.
      final String cacheId;
      if (kind == HoldingKind.mf) {
        cacheId = symbol.toUpperCase();
      } else {
        cacheId = classifyAndResolve(
          kind: kind,
          symbol: symbol,
          market: exchange ?? 'NSE',
        );
        if (cacheId.isEmpty) continue;
      }
      final key = _resultKey(cacheId, tf);
      if (_resultCache.containsKey(key)) continue; // idempotent skip
      if (!seen.add(key)) continue;                 // dedupe within batch

      jobs.add(_PrefetchJob(
        kind: kind, symbol: symbol, ticker: cacheId, tf: tf,
      ));
    }
    if (jobs.isEmpty) return;

    // 2. Run in fixed-size batches; Future.wait per batch caps fan-out.
    final width = concurrency < 1 ? 1 : concurrency;
    for (int i = 0; i < jobs.length; i += width) {
      final slice = jobs.sublist(i, math.min(i + width, jobs.length));
      await Future.wait(slice.map(_runPrefetchJob));
    }
  }

  Future<void> _runPrefetchJob(_PrefetchJob job) async {
    try {
      if (job.kind == HoldingKind.mf) {
        await fetchMF(schemeCode: job.symbol, tf: job.tf);
      } else {
        await fetchYahoo(ticker: job.ticker, tf: job.tf);
      }
    } catch (_) {
      // Best-effort — swallow. A real fetch later will surface the
      // error through the normal UI path if it still fails.
    }
  }

  HoldingKind _parseKind(String s) {
    switch (s) {
      case 'mf': case 'mutualfund': case 'mutual_fund':
        return HoldingKind.mf;
      case 'etf':
        return HoldingKind.etf;
      case 'commodity': case 'commodities':
        return HoldingKind.commodity;
      case 'stock': case 'equity': default:
        return HoldingKind.stock;
    }
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

  // ══════════════════════════════════════════════════════════════
  //  GLOBAL DISCOVERY — symbol search + lightweight quote fetch
  //  Powers the GlobalMarketsScreen (Discover tab).
  // ══════════════════════════════════════════════════════════════

  // 60-second TTL cache for quote lookups (per-card LTP fetches on
  // the discover screen). Yahoo's /v8/chart returns the meta block we
  // need on any timeframe — we use the cheapest (1d/15m).
  final Map<String, _CachedQuote> _quoteCache = {};

  /// Universal symbol search via Yahoo's `/v1/finance/search` endpoint.
  /// Returns SearchResult objects covering every quote type Yahoo
  /// recognises: EQUITY, ETF, INDEX, CRYPTOCURRENCY, CURRENCY,
  /// MUTUALFUND, FUTURE. Routes through the same Edge Function proxy
  /// as everything else.
  Future<List<SearchResult>> searchSymbols(String query,
      {int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final encQ = Uri.encodeQueryComponent(q);
    final url = 'https://query2.finance.yahoo.com/v1/finance/search'
        '?q=$encQ&quotesCount=$limit&newsCount=0';
    try {
      final resp = await _fetch(url);
      final body = resp.data is String
          ? jsonDecode(resp.data as String) : resp.data;
      final quotes = (body['quotes'] as List?) ?? const [];
      final out = <SearchResult>[];
      for (final raw in quotes) {
        final m = raw as Map<String, dynamic>;
        final sym = m['symbol'] as String?;
        if (sym == null || sym.isEmpty) continue;
        out.add(SearchResult(
          symbol:    sym,
          shortName: (m['shortname'] as String?) ?? sym,
          longName:  (m['longname']  as String?),
          exchange:  (m['exchange']  as String?) ?? '',
          exchDisp:  (m['exchDisp']  as String?),
          quoteType: (m['quoteType'] as String?) ?? 'EQUITY',
          sector:    m['sector']   as String?,
          industry:  m['industry'] as String?,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Convenience sugar over `fetchYahoo` used by Discover's mini-sparkline
  /// cards. Intentionally identical in behaviour to:
  ///     fetchYahoo(ticker: ticker, tf: ChartTimeframes.intraday1d)
  /// — no new caching, no new network path. The named method exists purely
  /// so the call site reads as "give me an intraday spark for this ticker"
  /// instead of "give me a 1d/1m bar series".
  Future<ChartFetchResult> fetchSparkline(String ticker) =>
      fetchYahoo(ticker: ticker, tf: ChartTimeframes.intraday1d);

  /// Quote-only path used by cards that don't render a sparkline. Returns
  /// a `ChartFetchResult` with empty bars and just the meta block (price +
  /// previous-close + currency). Cheaper than `fetchSparkline` because we
  /// request the coarsest interval Yahoo offers and discard the bars.
  Future<ChartFetchResult> fetchQuoteOnly(String ticker) async {
    final res = await fetchYahoo(ticker: ticker, tf: ChartTimeframes.intraday1d);
    // Drop the bars — caller only needs `meta`.
    return ChartFetchResult(bars: const [], meta: res.meta);
  }

  /// Lightweight quote — just the meta block (price + day change +
  /// 52-week range), no candles. 60-s in-memory cache because Discover
  /// cards refresh together and we want to avoid hammering Yahoo for
  /// the same ticker if the user scrolls back and forth.
  Future<QuoteMeta?> fetchQuote(String yahooTicker) async {
    final t = yahooTicker.trim();
    if (t.isEmpty) return null;

    final hit = _quoteCache[t];
    final now = DateTime.now();
    if (hit != null && now.difference(hit.fetchedAt).inSeconds < 60) {
      return hit.meta;
    }

    final encTicker = Uri.encodeComponent(t);
    final url = 'https://query1.finance.yahoo.com/v8/finance/chart/$encTicker'
        '?range=1d&interval=15m';
    try {
      final resp = await _fetch(url);
      final body = resp.data is String
          ? jsonDecode(resp.data as String) : resp.data;
      final result = (body['chart']?['result'] as List?)?.first;
      if (result == null) return null;
      final metaJson = result['meta'] as Map<String, dynamic>?;
      if (metaJson == null) return null;
      final meta = QuoteMeta.fromYahoo(metaJson);
      _quoteCache[t] = _CachedQuote(meta: meta, fetchedAt: now);
      return meta;
    } catch (_) {
      return null;
    }
  }
}

class _CachedQuote {
  final QuoteMeta meta;
  final DateTime fetchedAt;
  const _CachedQuote({required this.meta, required this.fetchedAt});
}

/// One hit from Yahoo Finance's universal symbol search.
class SearchResult {
  final String symbol;        // Yahoo ticker, ready for fetchYahoo
  final String shortName;     // Brief display name
  final String? longName;     // Full company / instrument name
  final String exchange;      // Raw exchange code (NMS, NSI, HKG, ...)
  final String? exchDisp;     // Human-readable exchange ("NASDAQ", "BSE")
  final String quoteType;     // EQUITY | ETF | INDEX | CRYPTOCURRENCY |
                              // CURRENCY | MUTUALFUND | FUTURE
  final String? sector;
  final String? industry;

  const SearchResult({
    required this.symbol,
    required this.shortName,
    this.longName,
    required this.exchange,
    this.exchDisp,
    required this.quoteType,
    this.sector,
    this.industry,
  });

  /// Maps an exchange code to a country/asset flag — used by the
  /// Discover screen's per-card badge. Falls back to a quote-type emoji
  /// when the exchange isn't recognised (e.g. CCC for crypto).
  String get flag {
    switch (exchange.toUpperCase()) {
      case 'NSI': case 'BSE': case 'BOM': return '🇮🇳';
      case 'NMS': case 'NYQ': case 'NCM':
      case 'ASE': case 'NGM': case 'PCX': case 'PNK': return '🇺🇸';
      case 'HKG': return '🇭🇰';
      case 'TYO': case 'JPX': return '🇯🇵';
      case 'LSE': case 'IOB': return '🇬🇧';
      case 'GER': case 'FRA': case 'STU': case 'XETRA': case 'BER':
        return '🇩🇪';
      case 'PAR': return '🇫🇷';
      case 'AMS': return '🇳🇱';
      case 'MIL': return '🇮🇹';
      case 'MCE': return '🇪🇸';
      case 'EBS': case 'SWX': return '🇨🇭';
      case 'CPH': return '🇩🇰';
      case 'STO': return '🇸🇪';
      case 'SHH': case 'SHZ': return '🇨🇳';
      case 'TWO': case 'TAI': return '🇹🇼';
      case 'KSC': case 'KOE': return '🇰🇷';
      case 'ASX': return '🇦🇺';
      case 'TOR': case 'TSX': return '🇨🇦';
      case 'SAO': return '🇧🇷';
      case 'MEX': return '🇲🇽';
      case 'JNB': return '🇿🇦';
      case 'SES': return '🇸🇬';
      case 'KLS': return '🇲🇾';
      case 'CCC': return '🪙'; // Crypto
      case 'CCY': return '💱'; // Currency
      default:
        switch (quoteType.toUpperCase()) {
          case 'CRYPTOCURRENCY': return '🪙';
          case 'CURRENCY':       return '💱';
          case 'INDEX':          return '📊';
          case 'ETF':            return '📦';
          case 'FUTURE':         return '🛢️';
          case 'MUTUALFUND':     return '🏦';
          default:               return '🌐';
        }
    }
  }

  /// Map exchange to a HoldingKind for routing into HoldingChartScreen.
  /// Yahoo's quoteType is the most reliable signal.
  HoldingKind get inferredKind {
    switch (quoteType.toUpperCase()) {
      case 'MUTUALFUND':     return HoldingKind.mf;
      case 'ETF':            return HoldingKind.etf;
      case 'CRYPTOCURRENCY':
      case 'CURRENCY':
      case 'INDEX':
      case 'FUTURE':         return HoldingKind.commodity;
      default:               return HoldingKind.stock;
    }
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
