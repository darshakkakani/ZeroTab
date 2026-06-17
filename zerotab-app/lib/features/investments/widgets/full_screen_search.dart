// FullScreenSearchSheet — Discover's search entry point.
//
// Pushed via a custom `PageRouteBuilder` from the Discover header search
// icon (see `investments_screen.dart`). Full-screen, edge-to-edge, with:
//
//   • Top bar: 40 dp close button + auto-focused search field + clear button
//   • Body states managed by `_query` / `_results` / `_searching`:
//       A) Empty query → "Recent" placeholder + "Trending" tiles
//       B) Searching → centred adaptive spinner
//       C) Results → `ListView.separated` of `_SearchRow`
//       D) No matches → empty-state copy
//   • 250 ms debounce on `ChartDataService.searchSymbols`
//   • Rotating placeholder hint via a 3-second Timer.periodic
//   • Tap on a result: pop the sheet THEN push HoldingChartScreen — the
//     order matters, otherwise both animations run simultaneously.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/providers.dart';
import '../screens/holding_chart_screen.dart';
import '../services/chart_data_service.dart';

class FullScreenSearchSheet extends ConsumerStatefulWidget {
  const FullScreenSearchSheet({super.key});

  @override
  ConsumerState<FullScreenSearchSheet> createState() =>
      _FullScreenSearchSheetState();
}

class _FullScreenSearchSheetState
    extends ConsumerState<FullScreenSearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  Timer? _hintRotator;
  int _hintIndex = 0;
  String _query = '';
  List<SearchResult> _results = const [];
  bool _searching = false;

  static const _hints = <String>[
    'Search RELIANCE, TCS, Nifty IT…',
    'Try AAPL, NVDA, S&P 500…',
    'Search BTC, ETH, GLD…',
  ];

  // Hand-picked trending tiles surfaced when the query is empty.
  static const _trending = <_TrendingItem>[
    _TrendingItem('RELIANCE.NS', 'Reliance Industries', 'NSE'),
    _TrendingItem('TCS.NS', 'Tata Consultancy Services', 'NSE'),
    _TrendingItem('INFY.NS', 'Infosys', 'NSE'),
    _TrendingItem('HDFCBANK.NS', 'HDFC Bank', 'NSE'),
    _TrendingItem('AAPL', 'Apple Inc.', 'NASDAQ'),
    _TrendingItem('BTC-USD', 'Bitcoin USD', 'CRYPTO'),
  ];

  @override
  void initState() {
    super.initState();
    _hintRotator = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_query.isNotEmpty) return;
      setState(() => _hintIndex = (_hintIndex + 1) % _hints.length);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hintRotator?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(v));
    setState(() {});
  }

  Future<void> _runSearch(String v) async {
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _searching = true;
    });
    final svc = ref.read(chartDataServiceProvider);
    final results = await svc.searchSymbols(q, limit: 10);
    if (!mounted || _query != q) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _openResult({
    required String ticker,
    required String exchange,
    required String name,
    required HoldingKind kind,
  }) {
    // Pop sheet first, then push chart — keeps animations from overlapping.
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HoldingChartScreen(
        holding: MFHoldingModel(
            id: 'discover', userId: '', investedAmount: 0, currentValue: 0),
        kind: kind,
        overrideSymbol: ticker,
        overrideExchange: exchange,
        overrideName: name,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sticky close button (always visible top-left).
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 24, color: AppColors.text),
              padding: EdgeInsets.zero,
              splashRadius: 20,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _focus.hasFocus
                        ? AppColors.accent.withValues(alpha: 0.55)
                        : AppColors.border),
              ),
              child: Row(children: [
                const Icon(Icons.search_rounded,
                    size: 20, color: AppColors.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    onChanged: _onChanged,
                    cursorColor: AppColors.accent,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      color: AppColors.text,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: _hints[_hintIndex],
                      hintStyle: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          color: AppColors.text3),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            height: 40,
            child: _ctrl.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.text3),
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_query.isEmpty) return _emptyQueryBody();
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty) return _noMatchBody();
    return _resultsBody();
  }

  Widget _emptyQueryBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
      children: [
        _sectionLabel('Recent'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Center(
            child: Text(
              'Your recent searches will appear here',
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                color: AppColors.text3,
              ),
            ),
          ),
        ),
        _sectionLabel('Trending'),
        for (var i = 0; i < _trending.length; i++) ...[
          _SearchRow(
            symbol: _trending[i].ticker,
            name: _trending[i].name,
            exchangeLabel: _trending[i].exchange,
            onTap: () => _openResult(
              ticker: _trending[i].ticker,
              exchange: _trendingExch(_trending[i]),
              name: _trending[i].name,
              kind: _trendingKind(_trending[i]),
            ),
          ),
          if (i != _trending.length - 1)
            const Divider(
              height: 1,
              thickness: 0.5,
              color: AppColors.border,
              indent: 16,
            ),
        ],
      ],
    );
  }

  String _trendingExch(_TrendingItem t) {
    if (t.ticker.endsWith('.NS')) return 'NSI';
    if (t.ticker.endsWith('-USD')) return 'CCC';
    return 'NMS';
  }

  HoldingKind _trendingKind(_TrendingItem t) {
    if (t.ticker.endsWith('-USD')) return HoldingKind.commodity;
    return HoldingKind.stock;
  }

  Widget _noMatchBody() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.text3, size: 32),
            const SizedBox(height: 12),
            Text(
              'No matches for "$_query"',
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a ticker symbol or company name',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      );

  Widget _resultsBody() => ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
        itemCount: _results.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          thickness: 0.5,
          color: AppColors.border,
          indent: 16,
        ),
        itemBuilder: (_, i) {
          final r = _results[i];
          return _SearchRow(
            symbol: r.symbol,
            name: r.longName ?? r.shortName,
            exchangeLabel: _exchangeLabel(r),
            onTap: () => _openResult(
              ticker: r.symbol,
              exchange: r.exchange,
              name: r.longName ?? r.shortName,
              kind: r.inferredKind,
            ),
          );
        },
      );

  String _exchangeLabel(SearchResult r) {
    final disp = r.exchDisp;
    if (disp != null && disp.isNotEmpty) return disp;
    switch (r.quoteType.toUpperCase()) {
      case 'CRYPTOCURRENCY':
        return 'CRYPTO';
      case 'CURRENCY':
        return 'FOREX';
      case 'ETF':
        return 'ETF';
      case 'INDEX':
        return 'INDEX';
      case 'MUTUALFUND':
        return 'FUND';
    }
    return r.exchange;
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.text3,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _TrendingItem {
  final String ticker;
  final String name;
  final String exchange;
  const _TrendingItem(this.ticker, this.name, this.exchange);
}

// ─────────────────────────────────────────────────────────────
//  _SearchRow — 56 dp tap-target row
// ─────────────────────────────────────────────────────────────
class _SearchRow extends StatelessWidget {
  final String symbol;
  final String name;
  final String exchangeLabel;
  final VoidCallback onTap;

  const _SearchRow({
    required this.symbol,
    required this.name,
    required this.exchangeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstChar = symbol.isEmpty ? '?' : symbol[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                firstChar,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              exchangeLabel.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
