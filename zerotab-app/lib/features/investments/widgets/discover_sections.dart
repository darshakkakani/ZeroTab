// Discover sections widget — Discover tab body inside the Invest screen.
//
// This widget powers the **Discover** tab of the new outer 3-tab Invest IA
// (Portfolio · Discover · IPO). It provides:
//
//   1. A sticky search field (Yahoo /v1/finance/search via chartDataService)
//   2. Asset-class filter chips (Stocks IN · Stocks US · MF · ETF · Crypto ·
//      Gold · Bonds) — visible when search is empty, controls which rails
//      render below.
//   3. Theme rails — horizontal carousels of curated symbols (Indices,
//      US stocks, EU stocks, Japan, HK/China, Global ETFs, Crypto, Forex).
//      Each card auto-loads its LTP + day-% via chartDataService.fetchQuote.
//
// All taps drill into the existing `HoldingChartScreen` via its
// override-symbol constructor — zero new data layer, zero schema, zero
// auth surface. Routes through the same Edge Function CORS proxy as the
// rest of the app.
//
// Lives in its own file so the Discover tab body is testable in isolation
// and so `investments_screen.dart` stays focused on portfolio logic.
// `GlobalMarketsScreen` (the standalone Discover screen) is untouched —
// this widget is a peer implementation tuned for the embedded tab.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/providers.dart';
import '../services/chart_data_service.dart';
import '../screens/holding_chart_screen.dart';

// ── Curated symbol matrix ─────────────────────────────────────
class _MarketTile {
  final String ticker;     // Yahoo Finance ticker
  final String name;       // Card label
  final String exchange;   // Exchange code → flag + routing
  final HoldingKind kind;  // stock | etf | commodity
  const _MarketTile(this.ticker, this.name, this.exchange, this.kind);
}

// Asset-class filter for the chip row.
enum _AssetClass { all, stocksIn, stocksUs, mf, etf, crypto, gold, bonds }

extension _AssetClassX on _AssetClass {
  String get label {
    switch (this) {
      case _AssetClass.all:      return 'All';
      case _AssetClass.stocksIn: return 'Stocks IN';
      case _AssetClass.stocksUs: return 'Stocks US';
      case _AssetClass.mf:       return 'MF';
      case _AssetClass.etf:      return 'ETF';
      case _AssetClass.crypto:   return 'Crypto';
      case _AssetClass.gold:     return 'Gold';
      case _AssetClass.bonds:    return 'Bonds';
    }
  }
}

const List<_MarketTile> _indices = [
  _MarketTile('^NSEI',   'Nifty 50',          'NSI', HoldingKind.commodity),
  _MarketTile('^BSESN',  'Sensex',            'BSE', HoldingKind.commodity),
  _MarketTile('^GSPC',   'S&P 500',           'NMS', HoldingKind.commodity),
  _MarketTile('^IXIC',   'NASDAQ',            'NMS', HoldingKind.commodity),
  _MarketTile('^DJI',    'Dow Jones',         'NYQ', HoldingKind.commodity),
  _MarketTile('^FTSE',   'FTSE 100',          'LSE', HoldingKind.commodity),
  _MarketTile('^N225',   'Nikkei 225',        'TYO', HoldingKind.commodity),
  _MarketTile('^HSI',    'Hang Seng',         'HKG', HoldingKind.commodity),
];

const List<_MarketTile> _trendingIn = [
  _MarketTile('RELIANCE.NS', 'Reliance',      'NSI', HoldingKind.stock),
  _MarketTile('TCS.NS',      'TCS',           'NSI', HoldingKind.stock),
  _MarketTile('HDFCBANK.NS', 'HDFC Bank',     'NSI', HoldingKind.stock),
  _MarketTile('INFY.NS',     'Infosys',       'NSI', HoldingKind.stock),
  _MarketTile('ICICIBANK.NS','ICICI Bank',    'NSI', HoldingKind.stock),
  _MarketTile('SBIN.NS',     'SBI',           'NSI', HoldingKind.stock),
  _MarketTile('BHARTIARTL.NS','Bharti Airtel','NSI', HoldingKind.stock),
  _MarketTile('LT.NS',       'L&T',           'NSI', HoldingKind.stock),
];

const List<_MarketTile> _usStocks = [
  _MarketTile('AAPL',  'Apple',         'NMS', HoldingKind.stock),
  _MarketTile('MSFT',  'Microsoft',     'NMS', HoldingKind.stock),
  _MarketTile('GOOGL', 'Alphabet',      'NMS', HoldingKind.stock),
  _MarketTile('AMZN',  'Amazon',        'NMS', HoldingKind.stock),
  _MarketTile('NVDA',  'NVIDIA',        'NMS', HoldingKind.stock),
  _MarketTile('META',  'Meta Platforms','NMS', HoldingKind.stock),
  _MarketTile('TSLA',  'Tesla',         'NMS', HoldingKind.stock),
  _MarketTile('NFLX',  'Netflix',       'NMS', HoldingKind.stock),
];

const List<_MarketTile> _euStocks = [
  _MarketTile('ASML.AS', 'ASML Holding', 'AMS', HoldingKind.stock),
  _MarketTile('SAP.DE',  'SAP',          'GER', HoldingKind.stock),
  _MarketTile('NESN.SW', 'Nestlé',       'EBS', HoldingKind.stock),
  _MarketTile('MC.PA',   'LVMH',         'PAR', HoldingKind.stock),
  _MarketTile('SHEL.L',  'Shell',        'LSE', HoldingKind.stock),
  _MarketTile('AZN.L',   'AstraZeneca',  'LSE', HoldingKind.stock),
  _MarketTile('SIE.DE',  'Siemens',      'GER', HoldingKind.stock),
];

const List<_MarketTile> _crypto = [
  _MarketTile('BTC-USD',  'Bitcoin',     'CCC', HoldingKind.commodity),
  _MarketTile('ETH-USD',  'Ethereum',    'CCC', HoldingKind.commodity),
  _MarketTile('SOL-USD',  'Solana',      'CCC', HoldingKind.commodity),
  _MarketTile('BNB-USD',  'BNB',         'CCC', HoldingKind.commodity),
  _MarketTile('XRP-USD',  'XRP',         'CCC', HoldingKind.commodity),
  _MarketTile('ADA-USD',  'Cardano',     'CCC', HoldingKind.commodity),
  _MarketTile('DOGE-USD', 'Dogecoin',    'CCC', HoldingKind.commodity),
];

const List<_MarketTile> _currencies = [
  _MarketTile('USDINR=X', 'USD / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('EURINR=X', 'EUR / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('GBPINR=X', 'GBP / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('JPYINR=X', 'JPY / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('AEDINR=X', 'AED / INR', 'CCY', HoldingKind.commodity),
];

const List<_MarketTile> _globalEtfs = [
  _MarketTile('SPY',  'SPDR S&P 500',          'PCX', HoldingKind.etf),
  _MarketTile('QQQ',  'Invesco QQQ',           'NMS', HoldingKind.etf),
  _MarketTile('VOO',  'Vanguard S&P 500',      'PCX', HoldingKind.etf),
  _MarketTile('VTI',  'Vanguard Total Market', 'PCX', HoldingKind.etf),
  _MarketTile('GLD',  'SPDR Gold Shares',      'PCX', HoldingKind.etf),
  _MarketTile('EEM',  'iShares MSCI EM',       'PCX', HoldingKind.etf),
];

const List<_MarketTile> _goldRail = [
  _MarketTile('GC=F',     'Gold Futures',  'CCC', HoldingKind.commodity),
  _MarketTile('SI=F',     'Silver Futures','CCC', HoldingKind.commodity),
  _MarketTile('GLD',      'SPDR Gold ETF', 'PCX', HoldingKind.etf),
  _MarketTile('GOLDBEES.NS','GoldBees',    'NSI', HoldingKind.etf),
];

// ─────────────────────────────────────────────────────────────
//  Public widget — embedded Discover body
// ─────────────────────────────────────────────────────────────
class DiscoverSections extends ConsumerStatefulWidget {
  /// Optional FocusNode — when supplied, the parent (Invest screen's
  /// app-bar search icon) can call `.requestFocus()` to jump the user
  /// straight into typing.
  final FocusNode? searchFocusNode;
  const DiscoverSections({super.key, this.searchFocusNode});

  @override
  ConsumerState<DiscoverSections> createState() => _DiscoverSectionsState();
}

class _DiscoverSectionsState extends ConsumerState<DiscoverSections>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _ctrl = TextEditingController();
  late final FocusNode _focus;
  bool _ownsFocus = false;

  Timer? _debounce;
  String _query = '';
  List<SearchResult> _results = const [];
  bool _searching = false;
  _AssetClass _filter = _AssetClass.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.searchFocusNode != null) {
      _focus = widget.searchFocusNode!;
    } else {
      _focus = FocusNode();
      _ownsFocus = true;
    }
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.removeListener(_onFocusChange);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(v);
    });
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

  void _openTile({
    required String ticker,
    required String exchange,
    required String name,
    required HoldingKind kind,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HoldingChartScreen(
        holding: _stubHolding(),
        kind: kind,
        overrideSymbol:   ticker,
        overrideExchange: exchange,
        overrideName:     name,
      ),
    ));
  }

  MFHoldingModel _stubHolding() => MFHoldingModel(
    id: 'discover', userId: '',
    investedAmount: 0, currentValue: 0,
  );

  void _openTileFor(_MarketTile t) => _openTile(
    ticker: t.ticker, exchange: t.exchange, name: t.name, kind: t.kind);

  // ── Filter logic ────────────────────────────────────────────
  //
  // The asset-class chip row controls which rails render. `all` shows
  // every rail. The other filters hide all but the rail(s) that match.
  bool _showRail(_AssetClass kind) {
    if (_filter == _AssetClass.all) return true;
    return _filter == kind;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showSearchResults = _query.isNotEmpty;
    return Column(children: [
      _searchField(),
      Expanded(child: showSearchResults
          ? _searchResultsList()
          : _browseSections()),
    ]);
  }

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focus.hasFocus
              ? AppColors.accent.withValues(alpha: 0.55)
              : AppColors.border)),
      child: Row(children: [
        const Icon(Icons.search_rounded, color: AppColors.text3, size: 18),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 13.5,
              color: AppColors.text),
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: 'Search Apple, Tencent, BTC, NIFTY, EUR/INR…',
            hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 12.5,
                color: AppColors.text3),
          ),
        )),
        if (_ctrl.text.isNotEmpty)
          GestureDetector(
            onTap: () { _ctrl.clear(); _onChanged(''); },
            child: const Icon(Icons.close_rounded,
                color: AppColors.text3, size: 16),
          ),
      ]),
    ),
  );

  // ─── Search results ─────────────────────────────────────────
  Widget _searchResultsList() {
    if (_searching) {
      return const Center(child: SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(
          color: AppColors.accent, strokeWidth: 1.6)));
    }
    if (_results.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded,
              color: AppColors.text3, size: 28),
          const SizedBox(height: 10),
          Text('No matches for "$_query"',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 12.5,
                color: AppColors.text2)),
          const SizedBox(height: 6),
          const Text('Try a company name or ticker (e.g. AAPL, RELIANCE, BTC)',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                color: AppColors.text3)),
        ]),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _SearchRow(
        result: _results[i],
        onTap: () => _openTile(
          ticker:   _results[i].symbol,
          exchange: _results[i].exchange,
          name:     _results[i].longName ?? _results[i].shortName,
          kind:     _results[i].inferredKind,
        ),
      ),
    );
  }

  // ─── Browse mode ────────────────────────────────────────────
  Widget _browseSections() => ListView(
    padding: const EdgeInsets.only(top: 0, bottom: 100),
    children: [
      // Asset-class filter chip row
      _filterChipRow(),
      if (_showRail(_AssetClass.all))
        _Section(title: 'Market Indices',  icon: Icons.show_chart_rounded,
          color: AppColors.accent,  tiles: _indices,    onTap: _openTileFor),
      if (_showRail(_AssetClass.stocksIn))
        _Section(title: 'Trending in India', icon: Icons.flag_rounded,
          color: AppColors.accent,  tiles: _trendingIn, onTap: _openTileFor,
          flagEmoji: '🇮🇳'),
      if (_showRail(_AssetClass.stocksUs))
        _Section(title: 'Top US Stocks',     icon: Icons.flag_rounded,
          color: AppColors.accent2, tiles: _usStocks,   onTap: _openTileFor,
          flagEmoji: '🇺🇸'),
      if (_filter == _AssetClass.all)
        _Section(title: 'European Stocks',   icon: Icons.flag_rounded,
          color: AppColors.teal,    tiles: _euStocks,   onTap: _openTileFor,
          flagEmoji: '🇪🇺'),
      if (_showRail(_AssetClass.etf))
        _Section(title: 'Global ETFs',       icon: Icons.donut_large_rounded,
          color: AppColors.dataETF, tiles: _globalEtfs, onTap: _openTileFor),
      if (_showRail(_AssetClass.crypto))
        _Section(title: 'Cryptocurrencies', icon: Icons.currency_bitcoin_rounded,
          color: AppColors.gold,    tiles: _crypto,     onTap: _openTileFor),
      if (_showRail(_AssetClass.gold))
        _Section(title: 'Gold & Precious Metals', icon: Icons.diamond_outlined,
          color: AppColors.gold,    tiles: _goldRail,   onTap: _openTileFor),
      if (_filter == _AssetClass.all)
        _Section(title: 'Currencies vs INR', icon: Icons.currency_exchange_rounded,
          color: AppColors.teal,    tiles: _currencies, onTap: _openTileFor),
      // MF & Bonds rails currently have no curated tiles — show a tasteful
      // empty card when the user filters down to them so we don't pretend
      // to have data we don't.
      if (_filter == _AssetClass.mf)
        const _EmptyRailNote(label: 'Mutual Fund discovery rails coming soon'),
      if (_filter == _AssetClass.bonds)
        const _EmptyRailNote(label: 'Bond discovery rails coming soon'),
      const SizedBox(height: 16),
    ],
  );

  Widget _filterChipRow() => Padding(
    padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
    child: SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _AssetClass.values.map((c) {
          final active = _filter == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.bg2,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: active
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border),
                ),
                child: Text(c.label, style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.accent2 : AppColors.text2)),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  Section — labelled horizontal carousel of _MarketCard widgets
// ─────────────────────────────────────────────────────────────
class _Section extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_MarketTile> tiles;
  final ValueChanged<_MarketTile> onTap;
  final String? flagEmoji;
  const _Section({
    required this.title, required this.icon, required this.color,
    required this.tiles, required this.onTap, this.flagEmoji,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Row(children: [
          if (flagEmoji != null)
            Padding(padding: const EdgeInsets.only(right: 8),
              child: Text(flagEmoji!, style: const TextStyle(fontSize: 16)))
          else
            Padding(padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.center,
                child: Icon(icon, size: 13, color: color))),
          Text(title, style: const TextStyle(fontFamily: 'DMSans',
              fontSize: 13.5, fontWeight: FontWeight.w700,
              color: AppColors.text)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border)),
            child: Text('${tiles.length}',
              style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                  color: AppColors.text3)),
          ),
        ]),
      ),
      SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: tiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _MarketCard(
            tile: tiles[i],
            onTap: () => onTap(tiles[i]),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  Card with auto-loaded LTP + day %
// ─────────────────────────────────────────────────────────────
class _MarketCard extends ConsumerStatefulWidget {
  final _MarketTile tile;
  final VoidCallback onTap;
  const _MarketCard({required this.tile, required this.onTap});
  @override
  ConsumerState<_MarketCard> createState() => _MarketCardState();
}

class _MarketCardState extends ConsumerState<_MarketCard> {
  QuoteMeta? _meta;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = ref.read(chartDataServiceProvider);
    final m = await svc.fetchQuote(widget.tile.ticker);
    if (!mounted) return;
    setState(() {
      _meta = m;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t   = widget.tile;
    final m   = _meta;
    final ltp = m?.regularMarketPrice;
    final pc  = m?.previousClose;
    final pct = (ltp != null && pc != null && pc != 0)
        ? ((ltp - pc) / pc) * 100 : null;
    final up = (pct ?? 0) >= 0;
    final col = up ? AppColors.green : AppColors.red;
    final currency = m?.currency ?? _inferCurrency(t.exchange);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Expanded(child: Text(
                _displayTicker(t.ticker),
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 11.5,
                  fontWeight: FontWeight.w700, color: AppColors.text),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(_flagFor(t.exchange), style: const TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(t.name, style: const TextStyle(
              fontFamily: 'DMSans', fontSize: 11, color: AppColors.text2,
              height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            if (!_loaded) const _ShimmerBar()
            else if (ltp != null) Row(children: [
              Expanded(child: Text(
                '${_currencySign(currency)}${_fmtNum(ltp)}',
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 12,
                  fontWeight: FontWeight.w700, color: AppColors.text,
                  fontFeatures: [
                    FontFeature.tabularFigures(),
                    FontFeature.liningFigures(),
                  ]),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (pct != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3)),
                child: Text(
                  '${up ? "+" : ""}${pct.toStringAsFixed(2)}%',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                    fontWeight: FontWeight.w700, color: col)),
              ),
            ])
            else const Text('—',
              style: TextStyle(fontFamily: 'DMMono', fontSize: 11,
                  color: AppColors.text3)),
          ],
        ),
      ),
    );
  }

  String _displayTicker(String t) {
    if (t.endsWith('=X')) return t.substring(0, t.length - 2);
    return t;
  }

  String _currencySign(String currency) {
    switch (currency.toUpperCase()) {
      case 'INR': return '₹';
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'JPY': return '¥';
      case 'HKD': return 'HK\$';
      case 'CNY': case 'RMB': return '¥';
      default:    return '';
    }
  }

  String _fmtNum(double v) {
    if (v.abs() >= 100000) return v.toStringAsFixed(0);
    if (v.abs() >= 100)    return v.toStringAsFixed(1);
    if (v.abs() >= 1)      return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  String _flagFor(String code) {
    switch (code) {
      case 'NSI': case 'BSE': return '🇮🇳';
      case 'NMS': case 'NYQ': case 'NCM': case 'PCX': return '🇺🇸';
      case 'LSE': return '🇬🇧';
      case 'GER': case 'XETRA': case 'FRA': return '🇩🇪';
      case 'PAR': return '🇫🇷';
      case 'AMS': return '🇳🇱';
      case 'EBS': case 'SWX': return '🇨🇭';
      case 'TYO': return '🇯🇵';
      case 'HKG': return '🇭🇰';
      case 'SHH': case 'SHZ': return '🇨🇳';
      case 'CCC': return '🪙';
      case 'CCY': return '💱';
      default:    return '🌐';
    }
  }

  String _inferCurrency(String exch) {
    switch (exch) {
      case 'NSI': case 'BSE': return 'INR';
      case 'NMS': case 'NYQ': case 'PCX': return 'USD';
      case 'LSE': return 'GBP';
      case 'GER': case 'FRA': case 'AMS': case 'PAR': return 'EUR';
      case 'EBS': return 'CHF';
      case 'TYO': return 'JPY';
      case 'HKG': return 'HKD';
      case 'SHH': case 'SHZ': return 'CNY';
      case 'CCY': return 'INR';
      case 'CCC': return 'USD';
      default:    return '';
    }
  }
}

class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar();
  @override
  Widget build(BuildContext context) => Container(
    height: 12, width: 70,
    decoration: BoxDecoration(
      color: AppColors.bg3,
      borderRadius: BorderRadius.circular(3)),
  );
}

// ─── Search result row ───────────────────────────────────────
class _SearchRow extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  const _SearchRow({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chipColor = _typeColor(result.quoteType);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.center,
            child: Text(result.flag, style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(result.symbol,
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 12.5,
                    fontWeight: FontWeight.w700, color: AppColors.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(_typeLabel(result.quoteType),
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 8.5,
                      fontWeight: FontWeight.w700, color: chipColor,
                      letterSpacing: 0.3)),
                ),
              ]),
              const SizedBox(height: 1),
              Text(result.longName ?? result.shortName,
                style: const TextStyle(fontFamily: 'DMSans',
                  fontSize: 11.5, color: AppColors.text2),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              if (result.exchDisp != null && result.exchDisp!.isNotEmpty)
                Text(result.exchDisp!,
                  style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 10, color: AppColors.text3)),
            ],
          )),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.text3, size: 18),
        ]),
      ),
    );
  }

  Color _typeColor(String t) {
    switch (t.toUpperCase()) {
      case 'EQUITY':         return AppColors.accent;
      case 'ETF':            return AppColors.dataETF;
      case 'INDEX':          return AppColors.gold;
      case 'CRYPTOCURRENCY': return AppColors.accent2;
      case 'CURRENCY':       return AppColors.teal;
      case 'MUTUALFUND':     return AppColors.teal;
      case 'FUTURE':         return AppColors.coral;
      default:               return AppColors.text2;
    }
  }
  String _typeLabel(String t) {
    switch (t.toUpperCase()) {
      case 'EQUITY':         return 'STOCK';
      case 'ETF':            return 'ETF';
      case 'INDEX':          return 'INDEX';
      case 'CRYPTOCURRENCY': return 'CRYPTO';
      case 'CURRENCY':       return 'FOREX';
      case 'MUTUALFUND':     return 'FUND';
      case 'FUTURE':         return 'FUTURE';
      default:               return t.toUpperCase();
    }
  }
}

// ─── Empty rail note ─────────────────────────────────────────
class _EmptyRailNote extends StatelessWidget {
  final String label;
  const _EmptyRailNote({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
      child: Row(children: [
        const Icon(Icons.hourglass_empty_rounded,
            color: AppColors.text3, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 12,
          color: AppColors.text2))),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  IPO placeholder — embedded inside the IPO tab body
// ─────────────────────────────────────────────────────────────
class IpoPlaceholder extends StatelessWidget {
  const IpoPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1F1845), Color(0xFF120E2A)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.30))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.rocket_launch_rounded,
                color: AppColors.gold, size: 17)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('IPO Watch', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 1),
              const Text('Mainboard · SME · Buyback · GMP',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                  color: AppColors.text3)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.30))),
            child: const Text('Coming soon', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 9,
              fontWeight: FontWeight.w700, color: AppColors.gold,
              letterSpacing: 0.3)),
          ),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Live IPO calendar with Grey Market Premium (GMP) tracking '
          'needs a SEBI-compliant data partnership — no clean free '
          'API exists in 2026 for Indian IPO + SME + GMP data. '
          "We'll light this up when the partnership lands.",
          style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
              color: AppColors.text2, height: 1.5)),
      ]),
    ),
  );
}
