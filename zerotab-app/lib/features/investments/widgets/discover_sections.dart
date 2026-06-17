// Discover sections widget — Discover tab body inside the Invest screen.
//
// V2 redesign (premium): the inline search field, the inline search-result
// list, the `_MarketCard` private widget and the `_Section` inline header
// have all been retired. Search now lives in a full-screen modal pushed
// from the top app-bar's search icon (see `full_screen_search.dart`), and
// each rail uses the polished `AnimatedStatCard` (with mini-sparkline) +
// `RailSectionHeader` (with tinted icon badge, count chip, "See all" link).
//
// Structure:
//   1. `MarketPulseStrip` — hero (NSE/BSE status bar + 4 index tiles).
//   2. Asset-class filter chip row (unchanged).
//   3. Theme rails — Indices, Trending IN, US, EU, ETFs, Crypto, Gold, FX.
//
// The whole list is wrapped in `BullRefreshIndicator` for pull-to-refresh
// (5-candle painter, haptics on armed + loading entry). Refresh bumps a
// `_generation` int; cards re-mount via `Key('${ticker}-$_generation')`
// which fires a fresh `fetchSparkline` for each visible tile.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/holding_chart_screen.dart';
import '../services/chart_data_service.dart' show HoldingKind;
import '../../../shared/models/models.dart';
import 'animated_stat_card.dart';
import 'bull_refresh_indicator.dart';
import 'market_pulse_strip.dart';
import 'rail_section_header.dart';

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
  const DiscoverSections({super.key});

  @override
  ConsumerState<DiscoverSections> createState() => _DiscoverSectionsState();
}

class _DiscoverSectionsState extends ConsumerState<DiscoverSections>
    with AutomaticKeepAliveClientMixin {
  _AssetClass _filter = _AssetClass.all;
  // Generation counter — bumped on every pull-to-refresh. Cards key off this
  // so they re-mount and re-fetch when the user pulls.
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    // Bump generation → forces every visible card to re-mount and re-fetch.
    setState(() => _generation += 1);
    // Keep the bull-candle loop visible at least one cycle, even when every
    // tile is served from the in-memory cache and would return instantly.
    await Future<void>.delayed(const Duration(milliseconds: 800));
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
    return BullRefreshIndicator(
      onRefresh: _refresh,
      child: _browseSections(),
    );
  }

  // ─── Browse mode ────────────────────────────────────────────
  Widget _browseSections() => ListView(
    padding: const EdgeInsets.only(top: 4, bottom: 100),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      // Hero pulse strip — scrolls away with the rest of the content.
      MarketPulseStrip(generation: _generation),
      // Asset-class filter chip row
      _filterChipRow(),
      if (_showRail(_AssetClass.all))
        _Rail(title: 'Market Indices', icon: Icons.show_chart_rounded,
          tintFg: AppColors.accent, tiles: _indices, onTap: _openTileFor,
          generation: _generation),
      if (_showRail(_AssetClass.stocksIn))
        _Rail(title: 'Trending in India', icon: Icons.local_fire_department_rounded,
          tintFg: AppColors.red, flagEmoji: '🇮🇳',
          tiles: _trendingIn, onTap: _openTileFor, generation: _generation),
      if (_showRail(_AssetClass.stocksUs))
        _Rail(title: 'Top US Stocks', icon: Icons.public_rounded,
          tintFg: AppColors.accent, flagEmoji: '🇺🇸',
          tiles: _usStocks, onTap: _openTileFor, generation: _generation),
      if (_filter == _AssetClass.all)
        _Rail(title: 'European Stocks', icon: Icons.public_rounded,
          tintFg: AppColors.accent, flagEmoji: '🇪🇺',
          tiles: _euStocks, onTap: _openTileFor, generation: _generation),
      if (_showRail(_AssetClass.etf))
        _Rail(title: 'Global ETFs', icon: Icons.donut_large_rounded,
          tintFg: AppColors.text2, tintBg: AppColors.bg3,
          tiles: _globalEtfs, onTap: _openTileFor, generation: _generation),
      if (_showRail(_AssetClass.crypto))
        _Rail(title: 'Cryptocurrencies', icon: Icons.currency_bitcoin_rounded,
          tintFg: AppColors.gold,
          tiles: _crypto, onTap: _openTileFor, generation: _generation),
      if (_showRail(_AssetClass.gold))
        _Rail(title: 'Gold & Precious Metals', icon: Icons.diamond_rounded,
          tintFg: AppColors.gold,
          tiles: _goldRail, onTap: _openTileFor, generation: _generation),
      if (_filter == _AssetClass.all)
        _Rail(title: 'Currencies vs INR', icon: Icons.swap_horiz_rounded,
          tintFg: AppColors.text2, tintBg: AppColors.bg3,
          tiles: _currencies, onTap: _openTileFor, generation: _generation),
      // MF & Bonds rails currently have no curated tiles — show a tasteful
      // empty card when the user filters down to them.
      if (_filter == _AssetClass.mf)
        const _EmptyRailNote(label: 'Mutual Fund discovery rails coming soon'),
      if (_filter == _AssetClass.bonds)
        const _EmptyRailNote(label: 'Bond discovery rails coming soon'),
      const SizedBox(height: 24),
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
//  Rail — RailSectionHeader + horizontal carousel of AnimatedStatCards
// ─────────────────────────────────────────────────────────────
class _Rail extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tintFg;
  final Color? tintBg;
  final String? flagEmoji;
  final List<_MarketTile> tiles;
  final ValueChanged<_MarketTile> onTap;
  final int generation;

  const _Rail({
    required this.title,
    required this.icon,
    required this.tintFg,
    required this.tiles,
    required this.onTap,
    required this.generation,
    this.tintBg,
    this.flagEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailSectionHeader(
          title: title,
          icon: icon,
          tintFg: tintFg,
          tintBg: tintBg,
          count: tiles.length,
          flagEmoji: flagEmoji,
          onSeeAll: null, // See-all is intentionally a v2+ stub for now.
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final t = tiles[i];
              return AnimatedStatCard(
                key: ValueKey('${t.ticker}-$generation'),
                ticker: t.ticker,
                name: t.name,
                exchange: t.exchange,
                kind: t.kind,
                mountIndex: i,
                onTap: () => onTap(t),
              );
            },
          ),
        ),
      ],
    );
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
