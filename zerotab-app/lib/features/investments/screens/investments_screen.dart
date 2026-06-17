import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/widgets/zt_card.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../services/chart_data_service.dart';
import '../widgets/discover_sections.dart';
import '../widgets/full_screen_search.dart';
import 'holding_chart_screen.dart';

// ── Enums ──────────────────────────────────────────────────
enum _SortMode { value, gainPct, lossPct, name }
enum _AssetTab { all, stocks, mf, etf, commodity }
enum _HoldingType { stock, mf, etf, commodity }

// ── Type colours ───────────────────────────────────────────
extension _HoldingTypeX on _HoldingType {
  Color get accent {
    switch (this) {
      case _HoldingType.stock:     return AppColors.accent;
      case _HoldingType.mf:        return AppColors.teal;
      case _HoldingType.etf:       return AppColors.dataETF;
      case _HoldingType.commodity: return AppColors.gold;
    }
  }
  String get badge {
    switch (this) {
      case _HoldingType.stock:     return 'S';
      case _HoldingType.mf:        return 'MF';
      case _HoldingType.etf:       return 'ET';
      case _HoldingType.commodity: return 'CM';
    }
  }
  String get ltpLabel {
    return this == _HoldingType.mf ? 'NAV' : 'LTP';
  }
}

// ── Main screen ────────────────────────────────────────────
class InvestmentsScreen extends ConsumerStatefulWidget {
  const InvestmentsScreen({super.key});
  @override
  ConsumerState<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends ConsumerState<InvestmentsScreen>
    with TickerProviderStateMixin {
  // Outer tab controller — Portfolio · Discover · IPO (top-level IA).
  late TabController _topCtrl;
  // Inner tab controller — All · Stocks · MF · ETF · Commodity
  // (asset-class strip nested inside the Portfolio tab body).
  late TabController _tabCtrl;
  _SortMode _sort = _SortMode.value;
  OverlayEntry? _toastOverlay;

  // (Discover search is now a full-screen modal pushed from the header
  // icon — no embedded FocusNode is needed at the screen level any more.)

  // Prefetch is fire-and-forget — kick it off once per screen mount so
  // we don't hammer the network on every rebuild when other providers
  // settle. Lives at the State level (not in the Riverpod cache) so
  // unmount/remount of the screen gets a fresh prefetch pass if the
  // user comes back later with stale data.
  bool _prefetchKicked = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _topCtrl = TabController(length: 3, initialIndex: 0, vsync: this);
    _topCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _topCtrl.dispose();
    _tabCtrl.dispose();
    _toastOverlay?.remove();
    super.dispose();
  }

  _AssetTab get _currentTab => _AssetTab.values[_tabCtrl.index];

  void _showToast(String msg, {bool success = true}) {
    _toastOverlay?.remove();
    final dotColor = success ? AppColors.teal : AppColors.red;
    _toastOverlay = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 14,
        left: 0, right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1730),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: const Color(0xFF2A2545)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.32),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 9),
                Text(msg, style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w500, color: AppColors.text)),
              ]),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_toastOverlay!);
    Future.delayed(const Duration(seconds: 2), () {
      _toastOverlay?.remove();
      _toastOverlay = null;
    });
  }

  Future<void> _refresh() async {
    try {
      switch (_currentTab) {
        case _AssetTab.all:
          await Future.wait([
            api.post(ApiConstants.stockRefresh, data: {}),
            api.post(ApiConstants.mfRefreshNav, data: {}),
            api.post(ApiConstants.etfRefresh, data: {}),
            api.post(ApiConstants.commodityRefresh, data: {}),
          ]);
          ref.invalidate(stockHoldingsProvider);
          ref.invalidate(mfHoldingsProvider);
          ref.invalidate(etfHoldingsProvider);
          ref.invalidate(commodityHoldingsProvider);
        case _AssetTab.stocks:
          await api.post(ApiConstants.stockRefresh, data: {});
          ref.invalidate(stockHoldingsProvider);
        case _AssetTab.mf:
          await api.post(ApiConstants.mfRefreshNav, data: {});
          ref.invalidate(mfHoldingsProvider);
        case _AssetTab.etf:
          await api.post(ApiConstants.etfRefresh, data: {});
          ref.invalidate(etfHoldingsProvider);
        case _AssetTab.commodity:
          await api.post(ApiConstants.commodityRefresh, data: {});
          ref.invalidate(commodityHoldingsProvider);
      }
      if (mounted) _showToast('Prices updated ✓');
    } catch (_) {
      if (mounted) _showToast('Refresh failed', success: false);
    }
  }

  void _showAdd() {
    if (_currentTab == _AssetTab.all) {
      _showTypeChooser();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        switch (_currentTab) {
          case _AssetTab.stocks:   return _AddStockSheet(onAdded: () => ref.invalidate(stockHoldingsProvider));
          case _AssetTab.mf:       return _AddMFSheet(onAdded: () => ref.invalidate(mfHoldingsProvider));
          case _AssetTab.etf:      return _AddETFSheet(onAdded: () => ref.invalidate(etfHoldingsProvider));
          case _AssetTab.commodity:return _AddCommoditySheet(onAdded: () => ref.invalidate(commodityHoldingsProvider));
          case _AssetTab.all:      return const SizedBox.shrink();
        }
      },
    );
  }

  void _showTypeChooser() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddTypeChooserSheet(
        onChoose: (type) {
          Navigator.pop(ctx);
          Future.microtask(() => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) {
              switch (type) {
                case _HoldingType.stock:     return _AddStockSheet(onAdded: () => ref.invalidate(stockHoldingsProvider));
                case _HoldingType.mf:        return _AddMFSheet(onAdded: () => ref.invalidate(mfHoldingsProvider));
                case _HoldingType.etf:       return _AddETFSheet(onAdded: () => ref.invalidate(etfHoldingsProvider));
                case _HoldingType.commodity: return _AddCommoditySheet(onAdded: () => ref.invalidate(commodityHoldingsProvider));
              }
            },
          ));
        },
      ),
    );
  }

  Future<void> _deleteHolding(MFHoldingModel h, _HoldingType type) async {
    try {
      switch (type) {
        case _HoldingType.stock:
          await api.delete('${ApiConstants.stockHoldings}/${h.id}');
          ref.invalidate(stockHoldingsProvider);
        case _HoldingType.mf:
          await api.delete('${ApiConstants.mfHoldings}/${h.id}');
          ref.invalidate(mfHoldingsProvider);
        case _HoldingType.etf:
          await api.delete('${ApiConstants.etfHoldings}/${h.id}');
          ref.invalidate(etfHoldingsProvider);
        case _HoldingType.commodity:
          await api.delete('${ApiConstants.commodityHoldings}/${h.id}');
          ref.invalidate(commodityHoldingsProvider);
      }
      if (mounted) _showToast('Position removed');
    } catch (_) {
      if (mounted) _showToast('Delete failed', success: false);
    }
  }

  // ── Prefetch chart data so HoldingChartScreen opens instantly ──
  //
  // Goals (in order):
  //   1) Never block list rendering — runs after the first frame paints.
  //   2) Best-effort, silent on failure — the chart screen will fall back
  //      to a normal cold fetch if anything throws here.
  //   3) Bounded cost — at most 2 concurrent fetches; MF prefetches are
  //      capped to the top 5 holdings by current value because mfapi.in
  //      ships ~500 KB of full history per scheme. Stocks/ETF/commodity
  //      pull the 1D timeframe (small response).
  //
  // Cache target: the Riverpod `chartCacheProvider` — same map that
  // HoldingChartScreen reads via its `_cache` getter, keyed by
  // '<symbolOrCode>-<exchange>-<tfLabel>' (matches its private
  // _cacheKey getter so prefetch entries are picked up automatically).
  Future<void> _prefetchCharts({
    required List<MFHoldingModel> stocks,
    required List<MFHoldingModel> mf,
    required List<MFHoldingModel> etfs,
    required List<MFHoldingModel> commodities,
  }) async {
    // Tiny breather so the first frame finishes painting before we
    // dispatch any network work. Matches the 400ms used inside
    // HoldingChartScreen for the same reason.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final svc   = ref.read(chartDataServiceProvider);
    final cache = ref.read(chartCacheProvider);

    // Build the job list. Each job is a (key, fetcher) pair: we skip
    // jobs whose cache slot is already populated (e.g. user already
    // visited the chart and bounced back).
    final jobs = <({String key, Future<ChartFetchResult> Function() fetch})>[];

    // Stocks / ETFs / Commodities → 1D Yahoo bars. Symbols come from
    // the same getters HoldingChartScreen uses (`stockSymbol`,
    // `etfSymbol`, `commoditySymbol`) so the cache keys collide
    // exactly with what the chart screen later asks for.
    void addYahoo(MFHoldingModel h, HoldingKind kind, String symbol) {
      if (symbol.isEmpty) return;
      const tf = ChartTimeframes.intraday1d;
      final key = '$symbol-${h.stockExchange}-${tf.label}';
      if (cache.containsKey(key)) return;
      jobs.add((
        key: key,
        fetch: () async {
          final ticker = svc.yahooTicker(
            kind: kind, symbol: symbol, exchange: h.stockExchange);
          return svc.fetchYahoo(ticker: ticker, tf: tf);
        },
      ));
    }
    for (final h in stocks)      addYahoo(h, HoldingKind.stock,     h.stockSymbol);
    for (final h in etfs)        addYahoo(h, HoldingKind.etf,       h.etfSymbol);
    for (final h in commodities) addYahoo(h, HoldingKind.commodity, h.commoditySymbol);

    // MF cap — only the top 5 by current value get prefetched. mfapi.in
    // returns the full NAV history per scheme (~500 KB each), so an
    // uncapped fan-out on a 30-fund portfolio would burn ~15 MB of
    // bandwidth on screens the user may never visit.
    final mfSorted = List<MFHoldingModel>.from(mf)
      ..sort((a, b) => (b.currentValue ?? 0).compareTo(a.currentValue ?? 0));
    final mfTop = mfSorted.take(5);
    for (final h in mfTop) {
      final code = h.schemeCode;
      if (code == null || code.isEmpty) continue;
      const tf = ChartTimeframes.day1m;
      final key = '$code-${h.stockExchange}-${tf.label}';
      if (cache.containsKey(key)) continue;
      jobs.add((
        key: key,
        fetch: () => svc.fetchMF(schemeCode: code, tf: tf),
      ));
    }

    // Throttled execution: 2 jobs at a time. Future.wait on each slice
    // means each batch waits for both to settle before the next slice
    // dispatches — keeps proxy load predictable and matches the same
    // pattern HoldingChartScreen uses for its own timeframe prefetch.
    for (int i = 0; i < jobs.length; i += 2) {
      if (!mounted) return;
      final batch = jobs.sublist(i, math.min(i + 2, jobs.length));
      await Future.wait(batch.map((job) async {
        try {
          cache[job.key] = await job.fetch();
        } catch (_) {
          // Silent: HoldingChartScreen will retry on demand.
        }
      }));
    }
  }

  // ── Sorting ──────────────────────────────────────────────
  List<MFHoldingModel> _sorted(List<MFHoldingModel> items) {
    final copy = List<MFHoldingModel>.from(items);
    switch (_sort) {
      case _SortMode.value:   copy.sort((a,b) => (b.currentValue??0).compareTo(a.currentValue??0));
      case _SortMode.gainPct: copy.sort((a,b) => b.gainLossPct.compareTo(a.gainLossPct));
      case _SortMode.lossPct: copy.sort((a,b) => a.gainLossPct.compareTo(b.gainLossPct));
      case _SortMode.name:    copy.sort((a,b) => (a.schemeName??'').compareTo(b.schemeName??''));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(stockHoldingsProvider);
    final mfAsync     = ref.watch(mfHoldingsProvider);
    final etfsAsync   = ref.watch(etfHoldingsProvider);
    final commAsync   = ref.watch(commodityHoldingsProvider);

    // Show loading if any primary provider is still fetching
    if (stocksAsync.isLoading || mfAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 1.5)),
      );
    }

    final stocks      = stocksAsync.value ?? [];
    final mf          = (mfAsync.value ?? []).where((h) => h.isMF).toList();
    final etfs        = etfsAsync.value ?? [];
    final commodities = commAsync.value ?? [];

    // ── Prefetch holding charts (once, after first frame) ────────
    // All four AsyncValues are resolved (not loading) by the time we
    // reach this point — the loading guard above returns early
    // otherwise. addPostFrameCallback keeps the network work out of
    // the build phase, and _prefetchKicked guarantees one-shot per
    // mount even though the build runs every time tabs/sort changes.
    if (!_prefetchKicked &&
        !stocksAsync.isLoading && !mfAsync.isLoading &&
        !etfsAsync.isLoading   && !commAsync.isLoading) {
      _prefetchKicked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Fire-and-forget — never awaited from build.
        _prefetchCharts(
          stocks: stocks, mf: mf, etfs: etfs, commodities: commodities,
        );
      });
    }

    final allItems    = [...stocks, ...mf, ...etfs, ...commodities];
    final totalValue    = allItems.fold(0.0, (s,h) => s + (h.currentValue ?? 0));
    final totalInvested = allItems.fold(0.0, (s,h) => s + (h.investedAmount ?? 0));
    final totalGain     = totalValue - totalInvested;
    final totalGainPct  = totalInvested > 0 ? (totalGain / totalInvested) * 100 : 0.0;
    final stocksValue   = stocks.fold(0.0, (s,h) => s + (h.currentValue ?? 0));
    final mfValue       = mf.fold(0.0, (s,h) => s + (h.currentValue ?? 0));
    final etfValue      = etfs.fold(0.0, (s,h) => s + (h.currentValue ?? 0));
    final commValue     = commodities.fold(0.0, (s,h) => s + (h.currentValue ?? 0));

    // FAB is only meaningful on the Portfolio tab — Discover & IPO have
    // no "add" affordance, so we hide it there to prevent collision
    // with the search field and to keep the IPO surface clean.
    final showFab = _topCtrl.index == 1;

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: _UniformFAB(onTap: _showAdd),
            )
          : null,
      body: SafeArea(
        child: Column(children: [
          // ── Top app-bar: "Investments" + per-tab context icon ──
          _buildTopAppBar(),
          // ── Outer TabBar: Portfolio · Discover · IPO ──
          _buildTopTabBar(),
          // ── Outer TabBarView ──
          Expanded(
            child: TabBarView(
              controller: _topCtrl,
              // The Portfolio body owns horizontal swipes via its
              // nested asset-class TabBarView, so we disable swipe on
              // the outer view to avoid gesture conflicts.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _DiscoverTabContent(),
                _buildPortfolioTab(
                  stocks: stocks, mf: mf, etfs: etfs, commodities: commodities,
                  allItems: allItems,
                  totalValue: totalValue, totalInvested: totalInvested,
                  totalGain: totalGain, totalGainPct: totalGainPct,
                  stocksValue: stocksValue, mfValue: mfValue,
                  etfValue: etfValue, commValue: commValue,
                ),
                const _IpoTabContent(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Search modal route — full-screen, transparent barrier, fade + slight
  //  upward slide. Exit faster than enter to keep dismiss snappy.
  // ─────────────────────────────────────────────────────────────
  Route<void> _buildSearchRoute() => PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => const FullScreenSearchSheet(),
        transitionsBuilder: (_, anim, __, child) {
          final fade = CurvedAnimation(
              parent: anim, curve: Curves.easeOutCubic);
          final slide = Tween<Offset>(
                  begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      );

  // ─────────────────────────────────────────────────────────────
  //  Top app-bar — "Investments" title + per-tab trailing icon.
  //  Trailing icon switches on the active outer tab:
  //    Portfolio → refresh (existing handler)
  //    Discover  → search (focuses the Discover sticky search field)
  //    IPO       → no icon
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopAppBar() {
    Widget? trailing;
    switch (_topCtrl.index) {
      case 0:
        // Discover — search
        trailing = _HeaderBtn(
          icon: Icons.search_rounded,
          onTap: () => Navigator.of(context).push(_buildSearchRoute()),
        );
      case 1:
        // Portfolio — refresh prices
        trailing = _HeaderBtn(icon: Icons.refresh_rounded, onTap: _refresh);
      case 2:
      default:
        // IPO — no trailing icon
        trailing = null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        const Expanded(
          child: Text('Investments', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 22, fontWeight: FontWeight.w700,
            letterSpacing: -0.7, color: AppColors.text)),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Outer TabBar — Portfolio · Discover · IPO. Sticky directly
  //  below the app-bar, equal-width tabs, underline indicator.
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopTabBar() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1))),
      child: TabBar(
        controller: _topCtrl,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.text,
        unselectedLabelColor: AppColors.text2,
        labelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 13.5, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 13.5, fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Discover'),
          Tab(text: 'Portfolio'),
          Tab(text: 'IPO'),
        ],
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────
  //  Portfolio tab body — _GrandHero, asset-class nested TabBar,
  //  sort chips, and holdings TabBarView. Unchanged from the
  //  pre-refactor layout except the embedded _USStubCard is gone
  //  (Discover is now a peer tab).
  // ─────────────────────────────────────────────────────────────
  Widget _buildPortfolioTab({
    required List<MFHoldingModel> stocks,
    required List<MFHoldingModel> mf,
    required List<MFHoldingModel> etfs,
    required List<MFHoldingModel> commodities,
    required List<MFHoldingModel> allItems,
    required double totalValue,
    required double totalInvested,
    required double totalGain,
    required double totalGainPct,
    required double stocksValue,
    required double mfValue,
    required double etfValue,
    required double commValue,
  }) {
    return Column(children: [
      const SizedBox(height: 12),

      // ── Grand Portfolio Hero ─────────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _GrandHero(
          totalValue: totalValue,
          totalInvested: totalInvested,
          totalGain: totalGain,
          totalGainPct: totalGainPct,
          positions: allItems.length,
          stocksValue: stocksValue,
          mfValue: mfValue,
          etfValue: etfValue,
          commValue: commValue,
        ),
      ),
      const SizedBox(height: 14),

      // ── Asset-class nested TabBar (underline style) ──────
      Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border, width: 1))),
        child: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          indicatorColor: AppColors.accent,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.text,
          unselectedLabelColor: AppColors.text3,
          labelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w400),
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'All  (${allItems.length})'),
            Tab(text: 'Stocks  (${stocks.length})'),
            Tab(text: 'MF  (${mf.length})'),
            Tab(text: 'ETF  (${etfs.length})'),
            Tab(text: 'Commodity  (${commodities.length})'),
          ],
        ),
      ),

      // ── Sort chips (hidden on All overview tab) ──────────
      if (_currentTab != _AssetTab.all) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _SortChip('Value',  _SortMode.value,   _sort, (m) => setState(() => _sort = m)),
              _SortChip('Gain %', _SortMode.gainPct, _sort, (m) => setState(() => _sort = m)),
              _SortChip('Loss %', _SortMode.lossPct, _sort, (m) => setState(() => _sort = m)),
              _SortChip('Name',   _SortMode.name,    _sort, (m) => setState(() => _sort = m)),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ] else
        const SizedBox(height: 8),

      // ── Tab views ────────────────────────────────────────
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── All tab (AngelOne-style section overview) ──
            _AllTabContent(
              stocks:      stocks,
              mfHoldings:  mf,
              etfs:        etfs,
              commodities: commodities,
              onAdd:       _showAdd,
              onSwitchTab: (i) => _tabCtrl.animateTo(i),
              onRefresh: () async {
                ref.invalidate(stockHoldingsProvider);
                ref.invalidate(mfHoldingsProvider);
                ref.invalidate(etfHoldingsProvider);
                ref.invalidate(commodityHoldingsProvider);
              },
            ),
            // ── Stocks tab ──
            //
            // The legacy _USStubCard ("Explore Global Markets") that used
            // to live here has been removed — the Discover top-level tab
            // is its peer replacement, one tap away on the outer TabBar.
            _TypeTabContent(
              holdings: _sorted(stocks),
              type: _HoldingType.stock,
              emptyIcon: Icons.show_chart_rounded,
              emptyTitle: 'No stock positions',
              emptySubtitle: 'Track your NSE/BSE equity holdings',
              onAdd: _showAdd,
              onDelete: _deleteHolding,
              onRefresh: () async => ref.invalidate(stockHoldingsProvider),
            ),
            // ── MF tab ──
            _TypeTabContent(
              holdings: _sorted(mf),
              type: _HoldingType.mf,
              emptyIcon: Icons.pie_chart_outline_rounded,
              emptyTitle: 'No mutual fund holdings',
              emptySubtitle: 'Add MF holdings manually or via CAS upload',
              onAdd: _showAdd,
              onDelete: _deleteHolding,
              onRefresh: () async => ref.invalidate(mfHoldingsProvider),
            ),
            // ── ETF tab ──
            _TypeTabContent(
              holdings: _sorted(etfs),
              type: _HoldingType.etf,
              emptyIcon: Icons.analytics_outlined,
              emptyTitle: 'No ETF positions',
              emptySubtitle: 'Track NIFTYBEES, GOLDBEES and other NSE ETFs',
              onAdd: _showAdd,
              onDelete: _deleteHolding,
              onRefresh: () async => ref.invalidate(etfHoldingsProvider),
            ),
            // ── Commodity tab ──
            _TypeTabContent(
              holdings: _sorted(commodities),
              type: _HoldingType.commodity,
              emptyIcon: Icons.diamond_outlined,
              emptyTitle: 'No commodity positions',
              emptySubtitle: 'Track Gold, Silver, Crude Oil and other MCX commodities',
              onAdd: _showAdd,
              onDelete: _deleteHolding,
              onRefresh: () async => ref.invalidate(commodityHoldingsProvider),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  Discover tab content — wraps the reusable DiscoverSections
//  widget. Kept as a tiny ConsumerStatefulWidget with
//  AutomaticKeepAliveClientMixin so the search field state and
//  loaded carousel quotes survive swipes between top tabs.
// ─────────────────────────────────────────────────────────────
class _DiscoverTabContent extends StatefulWidget {
  const _DiscoverTabContent();

  @override
  State<_DiscoverTabContent> createState() => _DiscoverTabContentState();
}

class _DiscoverTabContentState extends State<_DiscoverTabContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const DiscoverSections();
  }
}

// ─────────────────────────────────────────────────────────────
//  IPO tab content — placeholder for now. Reuses the in-package
//  IpoPlaceholder widget plus four disabled segmented chips
//  (Mainboard · SME · Buyback · GMP). No FAB, no search icon.
// ─────────────────────────────────────────────────────────────
class _IpoTabContent extends StatelessWidget {
  const _IpoTabContent();

  static const _segments = ['Mainboard', 'SME', 'Buyback', 'GMP'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
      children: [
        // ── Hero strip ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('IPOs', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6, color: AppColors.text)),
              const SizedBox(height: 4),
              const Text(
                'Mainboard, SME, Buyback & GMP — coming soon',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12.5,
                  color: AppColors.text3, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ── Segmented chips (visual only, no taps wired) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: List.generate(_segments.length, (i) {
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == _segments.length - 1 ? 0 : 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text(_segments[i], style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text3)),
              ),
            );
          })),
        ),
        // ── Placeholder card ──────────────────────────────
        const IpoPlaceholder(),
      ],
    );
  }
}

// ── Uniform FAB — shared across Spend / Invest / Debt ─────────
class _UniformFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _UniformFAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF0ECFF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B5FFF).withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.add_rounded,
          color: Color(0xFF2A1A6E),
          size: 24,
        ),
      ),
    );
  }
}

// ── Header button ──────────────────────────────────────────
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _HeaderBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: filled ? AppColors.accent : AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: filled ? null : Border.all(color: AppColors.border2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: filled ? 18 : 16,
        color: filled ? Colors.white : AppColors.text2),
    ),
  );
}

// ── Grand Portfolio Hero ───────────────────────────────────
class _GrandHero extends StatelessWidget {
  final double totalValue, totalInvested, totalGain, totalGainPct;
  final int positions;
  final double stocksValue, mfValue, etfValue, commValue;

  const _GrandHero({
    required this.totalValue,
    required this.totalInvested,
    required this.totalGain,
    required this.totalGainPct,
    required this.positions,
    required this.stocksValue,
    required this.mfValue,
    required this.etfValue,
    required this.commValue,
  });

  @override
  Widget build(BuildContext context) {
    final pos = totalGain >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0E0A1E), Color(0xFF080611)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.accent.withOpacity(0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top row: label + positions badge ──
        Row(children: [
          const Text('PORTFOLIO VALUE', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w500,
            letterSpacing: 0.8, color: AppColors.text3)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.accent.withOpacity(0.25)),
            ),
            child: Text('$positions positions', style: const TextStyle(
              fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w500,
              color: AppColors.accent2)),
          ),
        ]),
        const SizedBox(height: 6),

        // ── Big value + gain ──
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            totalValue > 0 ? formatInr(totalValue) : '—',
            style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 26, fontWeight: FontWeight.w700,
              letterSpacing: -1.0, color: AppColors.text),
          ),
          const Spacer(),
          if (totalValue > 0)
            _GainChip(pct: totalGainPct, gain: totalGain, large: true),
        ]),
        const SizedBox(height: 12),

        // ── 3-col stat strip ──
        if (totalValue > 0) ...[
          IntrinsicHeight(
            child: Row(children: [
              _HeroStat(
                label: 'INVESTED',
                value: formatInr(totalInvested, compact: true),
                color: AppColors.text2,
              ),
              _VertDivider(),
              _HeroStat(
                label: 'TOTAL GAIN',
                value: '${pos ? '+' : '-'}${formatInr(totalGain.abs(), compact: true)}',
                color: pos ? AppColors.green : AppColors.red,
              ),
              _VertDivider(),
              _HeroStat(
                label: 'RETURN',
                value: '${pos ? '+' : ''}${totalGainPct.toStringAsFixed(1)}%',
                color: pos ? AppColors.green : AppColors.red,
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Allocation bar ──
          _AllocationBar(
            stocksValue: stocksValue,
            mfValue: mfValue,
            etfValue: etfValue,
            commValue: commValue,
            totalValue: totalValue,
          ),
        ],

        if (totalValue == 0) ...[
          const SizedBox(height: 4),
          const Text('Add your first investment to see your portfolio overview',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3, height: 1.5)),
        ],
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _HeroStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
        fontWeight: FontWeight.w500, letterSpacing: 0.5, color: AppColors.text3)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
        fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    color: AppColors.border,
  );
}

// ── Allocation bar ─────────────────────────────────────────
class _AllocationBar extends StatelessWidget {
  final double stocksValue, mfValue, etfValue, commValue, totalValue;
  const _AllocationBar({
    required this.stocksValue, required this.mfValue,
    required this.etfValue, required this.commValue, required this.totalValue,
  });

  int _flex(double v) => totalValue > 0 ? ((v / totalValue) * 1000).round().clamp(0, 1000) : 0;

  @override
  Widget build(BuildContext context) {
    final sf = _flex(stocksValue);
    final mf = _flex(mfValue);
    final ef = _flex(etfValue);
    final cf = _flex(commValue);
    final hasAny = sf + mf + ef + cf > 0;
    if (!hasAny) return const SizedBox.shrink();

    return Column(children: [
      // Bar
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: Row(children: [
            if (sf > 0) Flexible(flex: sf, child: Container(color: AppColors.accent)),
            if (mf > 0) Flexible(flex: mf, child: Container(color: AppColors.teal)),
            if (ef > 0) Flexible(flex: ef, child: Container(color: AppColors.dataETF)),
            if (cf > 0) Flexible(flex: cf, child: Container(color: AppColors.gold)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      // Legend
      Row(children: [
        if (stocksValue > 0) _AllocDot('Stocks', AppColors.accent, stocksValue / totalValue),
        if (mfValue > 0) _AllocDot('MF', AppColors.teal, mfValue / totalValue),
        if (etfValue > 0) _AllocDot('ETF', AppColors.dataETF, etfValue / totalValue),
        if (commValue > 0) _AllocDot('Commod', AppColors.gold, commValue / totalValue),
      ]),
    ]);
  }
}

class _AllocDot extends StatelessWidget {
  final String label;
  final Color color;
  final double fraction;
  const _AllocDot(this.label, this.color, this.fraction);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ${(fraction * 100).toStringAsFixed(0)}%',
        style: const TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
    ]),
  );
}

// ── Gain chip ──────────────────────────────────────────────
class _GainChip extends StatelessWidget {
  final double pct, gain;
  final bool large;
  const _GainChip({required this.pct, required this.gain, this.large = false});

  @override
  Widget build(BuildContext context) {
    final pos = gain >= 0;
    final color = pos ? AppColors.green : AppColors.red;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 9 : 7, vertical: large ? 4 : 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pos ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: large ? 11 : 9, color: color),
        const SizedBox(width: 2),
        Text('${pct.abs().toStringAsFixed(1)}%', style: TextStyle(
          fontFamily: 'DMMono', fontSize: large ? 12 : 10,
          fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ── All tab — AngelOne-style asset class section overview ──
class _AllTabContent extends StatelessWidget {
  final List<MFHoldingModel> stocks;
  final List<MFHoldingModel> mfHoldings;
  final List<MFHoldingModel> etfs;
  final List<MFHoldingModel> commodities;
  final VoidCallback onAdd;
  final ValueChanged<int> onSwitchTab;   // tab index: 1=stocks,2=mf,3=etf,4=commodity
  final Future<void> Function() onRefresh;

  const _AllTabContent({
    required this.stocks,
    required this.mfHoldings,
    required this.etfs,
    required this.commodities,
    required this.onAdd,
    required this.onSwitchTab,
    required this.onRefresh,
  });

  bool get _hasAny =>
      stocks.isNotEmpty || mfHoldings.isNotEmpty ||
      etfs.isNotEmpty   || commodities.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.bg3,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: !_hasAny
                  ? _EmptyState(
                      icon:     Icons.account_balance_wallet_outlined,
                      title:    'No investments yet',
                      subtitle: 'Add stocks, mutual funds, ETFs or commodities',
                      onAdd:    onAdd,
                      color:    AppColors.accent,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Overview label ───────────────────────────
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'ASSET CLASSES',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: AppColors.text3,
                            ),
                          ),
                        ),

                        // ── Section cards ────────────────────────────
                        if (stocks.isNotEmpty)
                          _SectionCard(
                            title:    'EQUITY STOCKS',
                            icon:     Icons.show_chart_rounded,
                            color:    AppColors.accent,
                            holdings: stocks,
                            tabIndex: 1,
                            onTap:    () => onSwitchTab(1),
                          ),
                        if (mfHoldings.isNotEmpty) ...[
                          if (stocks.isNotEmpty) const SizedBox(height: 10),
                          _SectionCard(
                            title:    'MUTUAL FUNDS',
                            icon:     Icons.pie_chart_outline_rounded,
                            color:    AppColors.teal,
                            holdings: mfHoldings,
                            tabIndex: 2,
                            onTap:    () => onSwitchTab(2),
                          ),
                        ],
                        if (etfs.isNotEmpty) ...[
                          if (stocks.isNotEmpty || mfHoldings.isNotEmpty)
                            const SizedBox(height: 10),
                          _SectionCard(
                            title:    'ETF',
                            icon:     Icons.analytics_outlined,
                            color:    AppColors.dataETF,
                            holdings: etfs,
                            tabIndex: 3,
                            onTap:    () => onSwitchTab(3),
                          ),
                        ],
                        if (commodities.isNotEmpty) ...[
                          if (stocks.isNotEmpty || mfHoldings.isNotEmpty ||
                              etfs.isNotEmpty)
                            const SizedBox(height: 10),
                          _SectionCard(
                            title:    'COMMODITY',
                            icon:     Icons.diamond_outlined,
                            color:    AppColors.gold,
                            holdings: commodities,
                            tabIndex: 4,
                            onTap:    () => onSwitchTab(4),
                          ),
                        ],

                        // Note: the legacy "Explore Global Markets" stub
                        // card that used to render here has been deleted
                        // — Discover is now a top-level tab on the outer
                        // TabBar (Portfolio · Discover · IPO).
                      ],
                    ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

// ── Portfolio allocation bar chart ─────────────────────────

class _PortfolioBarChart extends StatelessWidget {
  final List<MFHoldingModel> stocks, mfHoldings, etfs, commodities;
  const _PortfolioBarChart({
    required this.stocks,
    required this.mfHoldings,
    required this.etfs,
    required this.commodities,
  });

  @override
  Widget build(BuildContext context) {
    final stocksVal = stocks.fold(0.0, (s, h) => s + (h.currentValue ?? 0));
    final mfVal     = mfHoldings.fold(0.0, (s, h) => s + (h.currentValue ?? 0));
    final etfVal    = etfs.fold(0.0, (s, h) => s + (h.currentValue ?? 0));
    final commVal   = commodities.fold(0.0, (s, h) => s + (h.currentValue ?? 0));
    final total     = stocksVal + mfVal + etfVal + commVal;
    if (total == 0) return const SizedBox.shrink();

    const stocks_c = AppColors.accent;
    const mf_c     = AppColors.teal;
    const etf_c    = AppColors.dataETF;
    const comm_c   = AppColors.gold;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PORTFOLIO ALLOCATION',
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 10,
              fontWeight: FontWeight.w600, letterSpacing: 0.6,
              color: AppColors.text3),
          ),
          const SizedBox(height: 10),

          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                if (stocksVal > 0) Expanded(
                  flex: (stocksVal / total * 1000).round(),
                  child: Container(color: stocks_c)),
                if (mfVal > 0) Expanded(
                  flex: (mfVal / total * 1000).round(),
                  child: Container(color: mf_c)),
                if (etfVal > 0) Expanded(
                  flex: (etfVal / total * 1000).round(),
                  child: Container(color: etf_c)),
                if (commVal > 0) Expanded(
                  flex: (commVal / total * 1000).round(),
                  child: Container(color: comm_c)),
              ]),
            ),
          ),
          const SizedBox(height: 10),

          // Legend
          Wrap(spacing: 14, runSpacing: 6, children: [
            if (stocksVal > 0) _BarLegend('Stocks', (stocksVal / total * 100), stocks_c),
            if (mfVal     > 0) _BarLegend('MF',     (mfVal     / total * 100), mf_c),
            if (etfVal    > 0) _BarLegend('ETF',    (etfVal    / total * 100), etf_c),
            if (commVal   > 0) _BarLegend('Commod', (commVal   / total * 100), comm_c),
          ]),
        ],
      ),
    );
  }
}

class _BarLegend extends StatelessWidget {
  final String label;
  final double pct;
  final Color  color;
  const _BarLegend(this.label, this.pct, this.color);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text('$label  ${pct.toStringAsFixed(0)}%',
      style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.text2)),
  ]);
}

// ── Week's AI Insight — Coming Soon card ───────────────────

class _AiInsightComingSoon extends StatelessWidget {
  const _AiInsightComingSoon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1520), Color(0xFF0A0F1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.teal.withOpacity(0.18)),
      ),
      child: Row(children: [
        // Icon
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.teal.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.teal.withOpacity(0.2)),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.psychology_outlined, color: AppColors.teal, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text(
                  "Week's AI Insight",
                  style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w600, color: AppColors.text),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                  ),
                  child: const Text('Coming Soon', style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.teal)),
                ),
              ]),
              const SizedBox(height: 3),
              const Text(
                'Personalized portfolio analysis & rebalancing suggestions from your AI CFO.',
                style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 11,
                  color: AppColors.text3, height: 1.4),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Asset class section card (AngelOne compact style) ──────
class _SectionCard extends StatelessWidget {
  final String    title;
  final IconData  icon;
  final Color     color;
  final List<MFHoldingModel> holdings;
  final int       tabIndex;
  final VoidCallback onTap;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.holdings,
    required this.tabIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double totalInvested = 0, totalCurrent = 0;
    for (final h in holdings) {
      totalInvested += h.investedAmount ?? 0;
      totalCurrent  += h.currentValue   ?? 0;
    }
    final gainLoss = totalCurrent - totalInvested;
    final gainPct  = totalInvested > 0
        ? gainLoss / totalInvested * 100 : 0.0;
    final isGain   = gainLoss >= 0;
    final gainColor = isGain ? AppColors.green : AppColors.red;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.bg3,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(children: [
          // ── Icon ────────────────────────────────────────
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),

          // ── Title + count ────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: color,
                    )),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('${holdings.length}',
                      style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 9,
                        fontWeight: FontWeight.w600, color: color)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  formatInr(totalCurrent, compact: true),
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  'Inv. ${formatInr(totalInvested, compact: true)}',
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),

          // ── Gain chip + arrow ────────────────────────────
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: gainColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isGain ? '+' : ''}${gainPct.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gainColor,
                    ),
                  ),
                  Text(
                    '${isGain ? '+' : ''}${formatInr(gainLoss.abs(), compact: true)}',
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 9,
                      color: gainColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 11, color: AppColors.text3),
          ]),
        ]),
      ),
    );
  }
}

// ── Type-specific tab content ──────────────────────────────
class _TypeTabContent extends StatelessWidget {
  final List<MFHoldingModel> holdings;
  final _HoldingType type;
  final IconData emptyIcon;
  final String emptyTitle, emptySubtitle;
  final VoidCallback onAdd;
  final Future<void> Function(MFHoldingModel, _HoldingType) onDelete;
  final Future<void> Function() onRefresh;
  final Widget? extraSection;

  const _TypeTabContent({
    required this.holdings,
    required this.type,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onAdd,
    required this.onDelete,
    required this.onRefresh,
    this.extraSection,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: type.accent,
      backgroundColor: AppColors.bg3,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: holdings.isEmpty
                ? _EmptyState(
                    icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle,
                    onAdd: onAdd, color: type.accent,
                  )
                : Container(
                    decoration: AppDecorations.card(radius: AppRadius.xl),
                    child: Column(children: List.generate(holdings.length, (i) {
                      final h = holdings[i];
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        _DismissibleRow(
                          holding: h,
                          type: type,
                          showTypeBadge: false,
                          onDelete: onDelete,
                        ),
                        if (i < holdings.length - 1)
                          const Divider(color: AppColors.border, height: 1, indent: 66),
                      ]);
                    })),
                  ),
            ),
          ),
          if (extraSection != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(child: extraSection!),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

// ── Dismissible row wrapper ────────────────────────────────
class _DismissibleRow extends StatelessWidget {
  final MFHoldingModel holding;
  final _HoldingType type;
  final bool showTypeBadge;
  final Future<void> Function(MFHoldingModel, _HoldingType) onDelete;

  const _DismissibleRow({
    required this.holding,
    required this.type,
    required this.showTypeBadge,
    required this.onDelete,
  });

  String get _key => '${type.name}-${holding.id}';

  @override
  Widget build(BuildContext context) => Dismissible(
    key: Key(_key),
    direction: DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 20),
        const SizedBox(height: 2),
        Text('Remove', style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
          fontWeight: FontWeight.w500, color: AppColors.red)),
      ]),
    ),
    confirmDismiss: (_) async {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl),
            side: const BorderSide(color: AppColors.border2)),
          title: const Text('Remove position?', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          content: const Text('This will remove the holding from your portfolio.',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: AppColors.text2)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
          ],
        ),
      ) ?? false;
    },
    onDismissed: (_) => onDelete(holding, type),
    child: Builder(builder: (ctx) => InkWell(
      onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => HoldingChartScreen(
          holding: holding,
          kind: switch (type) {
            _HoldingType.stock     => HoldingKind.stock,
            _HoldingType.mf        => HoldingKind.mf,
            _HoldingType.etf       => HoldingKind.etf,
            _HoldingType.commodity => HoldingKind.commodity,
          },
        ),
      )),
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: _DhanRow(holding: holding, type: type, showTypeBadge: showTypeBadge),
    )),
  );
}

// ── Dhan-style 3-row holding row ──────────────────────────
class _DhanRow extends StatelessWidget {
  final MFHoldingModel holding;
  final _HoldingType type;
  final bool showTypeBadge;
  const _DhanRow({required this.holding, required this.type, required this.showTypeBadge});

  String get _name {
    if (holding.schemeName != null && holding.schemeName!.isNotEmpty) return holding.schemeName!;
    if (type == _HoldingType.stock) return holding.stockSymbol;
    if (type == _HoldingType.etf)   return holding.etfSymbol;
    if (type == _HoldingType.commodity) return holding.commoditySymbol;
    return 'Unknown';
  }

  String get _avatarText {
    switch (type) {
      case _HoldingType.stock:
        return holding.stockSymbol.length >= 2 ? holding.stockSymbol.substring(0, 2) : holding.stockSymbol;
      case _HoldingType.mf:
        return (holding.schemeName ?? 'MF').substring(0, 2).toUpperCase();
      case _HoldingType.etf:
        return holding.etfSymbol.length >= 3 ? holding.etfSymbol.substring(0, 3) : holding.etfSymbol;
      case _HoldingType.commodity:
        return _commodityEmoji;
    }
  }

  String get _commodityEmoji {
    const map = {
      'GOLD': '🥇', 'GOLDPETAL': '🥇', 'SILVER': '🥈',
      'CRUDEOIL': '🛢️', 'NATURALGAS': '⛽', 'COPPER': '🔶', 'ALUMINIUM': '⬜',
    };
    return map[holding.commoditySymbol.toUpperCase()] ?? '💎';
  }

  String get _subtitle {
    switch (type) {
      case _HoldingType.stock:
        final qty = holding.stockQty;
        final avg = holding.avgNav ?? 0;
        return '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} shares  ·  avg ${formatInr(avg, compact: true)}  ·  ${holding.stockExchange}';
      case _HoldingType.mf:
        final units = holding.units ?? 0;
        final avg = holding.avgNav ?? 0;
        return '${units.toStringAsFixed(3)} units  ·  avg NAV ${formatInr(avg, compact: true)}';
      case _HoldingType.etf:
        final units = holding.units ?? 0;
        final avg = holding.avgNav ?? 0;
        return '${units.toStringAsFixed(0)} units  ·  avg ${formatInr(avg, compact: true)}  ·  NSE';
      case _HoldingType.commodity:
        final units = holding.units ?? 0;
        final avg = holding.avgNav ?? 0;
        return '${units.toStringAsFixed(0)} units  ·  avg ${formatInr(avg, compact: true)}  ·  MCX';
    }
  }

  double get _qty {
    switch (type) {
      case _HoldingType.stock:     return holding.stockQty;
      case _HoldingType.mf:        return holding.units ?? 0;
      case _HoldingType.etf:       return holding.units ?? 0;
      case _HoldingType.commodity: return holding.units ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final curVal  = holding.currentValue ?? 0;
    final invAmt  = holding.investedAmount ?? 0;
    final gain    = holding.gainLoss;
    final gainPct = holding.gainLossPct;
    final qty     = _qty;
    final ltp     = qty > 0 ? curVal / qty : 0.0;
    final isEmoji = type == _HoldingType.commodity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Avatar ──
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: type.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            alignment: Alignment.center,
            child: isEmoji
              ? Text(_avatarText, style: const TextStyle(fontSize: 20))
              : Text(_avatarText, style: TextStyle(
                  fontFamily: 'DMMono', fontSize: 11, fontWeight: FontWeight.w700,
                  color: type.accent)),
          ),
          // Type badge (only in All tab)
          if (showTypeBadge)
            Positioned(
              right: -4, top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: type.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(type.badge, style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 7, fontWeight: FontWeight.w700,
                  color: Colors.white, height: 1.2)),
              ),
            ),
        ]),
        const SizedBox(width: 12),

        // ── Left column ──
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Row 1: Name
          Text(_name, style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600,
            color: AppColors.text, height: 1.2),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          // Row 2: qty · avg · exchange
          Text(_subtitle, style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3, height: 1.3)),
          const SizedBox(height: 3),
          // Row 3: LTP
          Text('${type.ltpLabel}  ${formatInr(ltp, compact: true)}',
            style: TextStyle(fontFamily: 'DMMono', fontSize: 11,
              color: type.accent.withOpacity(0.85))),
        ])),
        const SizedBox(width: 10),

        // ── Right column ──
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // Gain% chip
          _GainChip(pct: gainPct, gain: gain),
          const SizedBox(height: 5),
          // Invested amount (muted)
          Text('Inv ${formatInr(invAmt, compact: true)}',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
          const SizedBox(height: 3),
          // Current value (prominent)
          Text(formatInr(curVal, compact: true), style: const TextStyle(
            fontFamily: 'DMMono', fontSize: 13, fontWeight: FontWeight.w600,
            color: AppColors.text)),
        ]),
      ]),
    );
  }
}

// ── Sort chip ──────────────────────────────────────────────
class _SortChip extends StatelessWidget {
  final String label;
  final _SortMode mode, current;
  final ValueChanged<_SortMode> onTap;
  const _SortChip(this.label, this.mode, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final active = mode == current;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.15) : AppColors.bg3,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: active ? AppColors.accent.withOpacity(0.45) : AppColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w500,
          color: active ? AppColors.accent2 : AppColors.text3)),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onAdd;
  final Color color;
  const _EmptyState({required this.icon, required this.title, required this.subtitle,
    required this.onAdd, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: AppDecorations.card(radius: AppRadius.xl),
    child: Column(children: [
      Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color.withOpacity(0.8), size: 26),
      ),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontFamily: 'DMSans', fontSize: 15,
        fontWeight: FontWeight.w600, color: AppColors.text)),
      const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(
        fontFamily: 'DMSans', fontSize: 12, color: AppColors.text2, height: 1.5)),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: onAdd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 15, color: color),
            const SizedBox(width: 6),
            Text('Add position', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    ]),
  );
}

// Note: the legacy _USStubCard ("Explore Global Markets" CTA) and
// _USStubSheet ("US Stocks — Coming Soon" bottom sheet) widgets that
// used to live here have been deleted as part of the new outer-tab IA
// (Portfolio · Discover · IPO). The dedicated Discover top-level tab
// is now the canonical entry point for global markets discovery — see
// `lib/features/investments/widgets/discover_sections.dart`.

// ── Add type chooser sheet ────────────────────────────────
class _AddTypeChooserSheet extends StatelessWidget {
  final void Function(_HoldingType) onChoose;
  const _AddTypeChooserSheet({required this.onChoose});

  static const _types = [
    (_HoldingType.stock,     '📈', 'Stocks',     'NSE / BSE equities'),
    (_HoldingType.mf,        '🧩', 'Mutual Fund','SIP / lumpsum holdings'),
    (_HoldingType.etf,       '⚡', 'ETF',        'NIFTYBEES, GOLDBEES & more'),
    (_HoldingType.commodity, '🏅', 'Commodity',  'Gold, Silver, Crude Oil'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      border: Border.all(color: AppColors.border2),
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 36, height: 4,
        decoration: BoxDecoration(color: AppColors.border2,
          borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Align(alignment: Alignment.centerLeft,
        child: Text('Add position', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
          fontWeight: FontWeight.w700, color: AppColors.text))),
      const SizedBox(height: 14),
      ..._types.map((t) => GestureDetector(
        onTap: () => onChoose(t.$1),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bg3,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Text(t.$2, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$3, style: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
                fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(t.$4, style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                color: AppColors.text3)),
            ]),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: AppColors.text3, size: 18),
          ]),
        ),
      )),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
// Add sheets (unchanged)
// ═══════════════════════════════════════════════════════════

Widget _sheetContainer({required BuildContext context, required Widget child}) {
  final bottom = MediaQuery.of(context).viewInsets.bottom;
  return Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      border: Border.all(color: AppColors.border2),
    ),
    padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
    child: SingleChildScrollView(child: child),
  );
}

Widget _sheetHandle() => Center(child: Container(
  width: 36, height: 4,
  decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2))));

Widget _sheetLabel(String t) => Text(t, style: const TextStyle(
  fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3));

Widget _sheetField(TextEditingController c, String label, String hint,
    {bool number = false, bool allCaps = false}) =>
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sheetLabel(label),
    const SizedBox(height: 5),
    Container(
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: c,
        textCapitalization: allCaps ? TextCapitalization.characters : TextCapitalization.none,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: TextStyle(fontFamily: allCaps ? 'DMMono' : 'DMSans', fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ),
  ]);

// ── Add Stock Sheet ───────────────────────────────────────

class _AddStockSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddStockSheet({required this.onAdded});
  @override State<_AddStockSheet> createState() => _AddStockSheetState();
}
class _AddStockSheetState extends State<_AddStockSheet> {
  final _symbolCtrl = TextEditingController();
  final _nameCtrl   = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _avgCtrl    = TextEditingController();
  String _exchange  = 'NSE';
  bool _loading = false;
  double? _livePrice;
  bool _fetchingPrice = false;

  @override
  void dispose() {
    _symbolCtrl.dispose(); _nameCtrl.dispose();
    _qtyCtrl.dispose(); _avgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPrice() async {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    setState(() => _fetchingPrice = true);
    try {
      final res = await api.get('${ApiConstants.stockQuote}?symbol=$sym&exchange=$_exchange');
      final price = (res.data['price'] as num?)?.toDouble();
      if (price != null && mounted) setState(() => _livePrice = price);
    } catch (_) {}
    if (mounted) setState(() => _fetchingPrice = false);
  }

  Future<void> _submit() async {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final avg = double.tryParse(_avgCtrl.text) ?? 0;
    if (sym.isEmpty || qty <= 0 || avg <= 0) return;
    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.stockHoldings, data: {
        'symbol': sym, 'company_name': _nameCtrl.text.trim().isEmpty ? sym : _nameCtrl.text.trim(),
        'exchange': _exchange, 'qty': qty, 'avg_price': avg,
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => _sheetContainer(context: context, child: Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sheetHandle(), const SizedBox(height: 16),
      const Text('Add Stock Position', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
        fontWeight: FontWeight.w700, color: AppColors.text)),
      const SizedBox(height: 20),
      Row(children: [
        _sheetLabel('Exchange'),
        const SizedBox(width: 12),
        ...['NSE','BSE'].map((e) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _exchange = e),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _exchange == e ? AppColors.accent.withOpacity(0.18) : AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: _exchange == e ? AppColors.accent.withOpacity(0.5) : AppColors.border),
              ),
              child: Text(e, style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                fontWeight: FontWeight.w600, color: _exchange == e ? AppColors.accent2 : AppColors.text2)),
            ),
          ),
        )),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _sheetField(_symbolCtrl, 'Symbol *', 'e.g. RELIANCE', allCaps: true)),
        const SizedBox(width: 10),
        Padding(padding: const EdgeInsets.only(top: 22), child: ElevatedButton(
          onPressed: _fetchingPrice ? null : _fetchPrice,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.bg3, foregroundColor: AppColors.accent2,
            minimumSize: const Size(80, 44), elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.border))),
          child: _fetchingPrice
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent2))
            : const Text('Get Price', style: TextStyle(fontFamily: 'DMSans', fontSize: 12)),
        )),
      ]),
      if (_livePrice != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 13, color: AppColors.teal),
            const SizedBox(width: 6),
            Text('Live: ${formatInr(_livePrice!)}', style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 12, color: AppColors.teal)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      _sheetField(_nameCtrl, 'Company Name', 'e.g. Reliance Industries (optional)'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _sheetField(_qtyCtrl, 'Quantity *', '0', number: true)),
        const SizedBox(width: 12),
        Expanded(child: _sheetField(_avgCtrl, 'Avg Buy Price (₹) *', '0.00', number: true)),
      ]),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        child: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Add Position', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
      )),
    ],
  ));
}

// ── Add MF Sheet ──────────────────────────────────────────

class _AddMFSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddMFSheet({required this.onAdded});
  @override State<_AddMFSheet> createState() => _AddMFSheetState();
}
class _AddMFSheetState extends State<_AddMFSheet> {
  final _schemeCtrl = TextEditingController();
  final _amcCtrl    = TextEditingController();
  final _unitsCtrl  = TextEditingController();
  final _avgCtrl    = TextEditingController();
  final _curCtrl    = TextEditingController();
  bool _loading = false;

  @override void dispose() {
    _schemeCtrl.dispose(); _amcCtrl.dispose();
    _unitsCtrl.dispose(); _avgCtrl.dispose(); _curCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name  = _schemeCtrl.text.trim();
    final units = double.tryParse(_unitsCtrl.text) ?? 0;
    final avg   = double.tryParse(_avgCtrl.text) ?? 0;
    final cur   = double.tryParse(_curCtrl.text.isEmpty ? _avgCtrl.text : _curCtrl.text) ?? avg;
    if (name.isEmpty || units <= 0 || avg <= 0) return;
    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.mfHoldings, data: {
        'scheme_name': name, 'amc_name': _amcCtrl.text.trim().isEmpty ? 'Unknown AMC' : _amcCtrl.text.trim(),
        'units': units, 'avg_nav': avg, 'current_nav': cur,
        'invested_amount': units * avg, 'current_value': units * cur,
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => _sheetContainer(context: context, child: Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sheetHandle(), const SizedBox(height: 16),
      const Text('Add Mutual Fund', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
        fontWeight: FontWeight.w700, color: AppColors.text)),
      const SizedBox(height: 20),
      _sheetField(_schemeCtrl, 'Scheme Name *', 'e.g. Parag Parikh Flexi Cap Fund'),
      const SizedBox(height: 12),
      _sheetField(_amcCtrl, 'AMC Name', 'e.g. PPFAS Mutual Fund'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _sheetField(_unitsCtrl, 'Units *', '0.000', number: true)),
        const SizedBox(width: 12),
        Expanded(child: _sheetField(_avgCtrl, 'Avg NAV (₹) *', '0.00', number: true)),
      ]),
      const SizedBox(height: 12),
      _sheetField(_curCtrl, 'Current NAV (₹)', 'Leave blank to use avg NAV', number: true),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        child: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Add Fund', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
      )),
    ],
  ));
}

// ── Add ETF Sheet ─────────────────────────────────────────

class _AddETFSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddETFSheet({required this.onAdded});
  @override State<_AddETFSheet> createState() => _AddETFSheetState();
}
class _AddETFSheetState extends State<_AddETFSheet> {
  final _symbolCtrl = TextEditingController();
  final _unitsCtrl  = TextEditingController();
  final _avgCtrl    = TextEditingController();
  bool _loading = false;
  double? _livePrice;
  bool _fetchingPrice = false;

  static const _quickSymbols = ['NIFTYBEES','GOLDBEES','BANKBEES','LIQUIDBEES','JUNIORBEES','ITBEES'];

  @override void dispose() {
    _symbolCtrl.dispose(); _unitsCtrl.dispose(); _avgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPrice() async {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    setState(() => _fetchingPrice = true);
    try {
      final res = await api.get('${ApiConstants.stockQuote}?symbol=$sym&exchange=NSE');
      final price = (res.data['price'] as num?)?.toDouble();
      if (price != null && mounted) setState(() => _livePrice = price);
    } catch (_) {}
    if (mounted) setState(() => _fetchingPrice = false);
  }

  Future<void> _submit() async {
    final sym   = _symbolCtrl.text.trim().toUpperCase();
    final units = double.tryParse(_unitsCtrl.text) ?? 0;
    final avg   = double.tryParse(_avgCtrl.text) ?? 0;
    if (sym.isEmpty || units <= 0 || avg <= 0) return;
    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.etfHoldings, data: {
        'symbol': sym, 'units': units, 'avg_price': avg,
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => _sheetContainer(context: context, child: Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sheetHandle(), const SizedBox(height: 16),
      const Text('Add ETF', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
        fontWeight: FontWeight.w700, color: AppColors.text)),
      const SizedBox(height: 16),
      _sheetLabel('Quick Select'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: _quickSymbols.map((s) => GestureDetector(
        onTap: () => setState(() => _symbolCtrl.text = s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _symbolCtrl.text == s ? const Color(0x334F9DF7) : AppColors.bg3,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: _symbolCtrl.text == s ? AppColors.dataETF.withOpacity(0.5) : AppColors.border),
          ),
          child: Text(s, style: TextStyle(fontFamily: 'DMMono', fontSize: 10, fontWeight: FontWeight.w600,
            color: _symbolCtrl.text == s ? AppColors.dataETF : AppColors.text3)),
        ),
      )).toList()),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _sheetField(_symbolCtrl, 'ETF Symbol *', 'e.g. NIFTYBEES', allCaps: true)),
        const SizedBox(width: 10),
        Padding(padding: const EdgeInsets.only(top: 22), child: ElevatedButton(
          onPressed: _fetchingPrice ? null : _fetchPrice,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.bg3,
            foregroundColor: AppColors.dataETF, minimumSize: const Size(80, 44), elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.border))),
          child: _fetchingPrice
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dataETF))
            : const Text('Get NAV', style: TextStyle(fontFamily: 'DMSans', fontSize: 12)),
        )),
      ]),
      if (_livePrice != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0x184F9DF7), borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 13, color: AppColors.dataETF),
            const SizedBox(width: 6),
            Text('Live NAV: ${formatInr(_livePrice!)}', style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 12, color: AppColors.dataETF)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _sheetField(_unitsCtrl, 'Units *', '0', number: true)),
        const SizedBox(width: 12),
        Expanded(child: _sheetField(_avgCtrl, 'Avg Buy Price (₹) *', '0.00', number: true)),
      ]),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.dataETF,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        child: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Add ETF', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
      )),
    ],
  ));
}

// ── Add Commodity Sheet ───────────────────────────────────

class _AddCommoditySheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddCommoditySheet({required this.onAdded});
  @override State<_AddCommoditySheet> createState() => _AddCommoditySheetState();
}
class _AddCommoditySheetState extends State<_AddCommoditySheet> {
  String _selected = 'GOLD';
  final _qtyCtrl   = TextEditingController();
  final _avgCtrl   = TextEditingController();
  bool _loading = false;
  double? _livePrice;
  bool _fetchingPrice = false;

  static const _commodities = [
    _CommodityMeta('GOLD',       '🥇', 'Gold',        'per gram'),
    _CommodityMeta('SILVER',     '🥈', 'Silver',      'per gram'),
    _CommodityMeta('CRUDEOIL',   '🛢️', 'Crude Oil',   'per barrel'),
    _CommodityMeta('NATURALGAS', '⛽', 'Natural Gas', 'per mmbtu'),
    _CommodityMeta('COPPER',     '🔶', 'Copper',      'per kg'),
    _CommodityMeta('ALUMINIUM',  '⬜', 'Aluminium',   'per kg'),
  ];

  @override void dispose() {
    _qtyCtrl.dispose(); _avgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPrice() async {
    setState(() => _fetchingPrice = true);
    try {
      final res = await api.get('${ApiConstants.commodityQuote}?symbol=$_selected');
      final price = (res.data['price_inr'] as num?)?.toDouble();
      if (price != null && mounted) setState(() => _livePrice = price);
    } catch (_) {}
    if (mounted) setState(() => _fetchingPrice = false);
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final avg = double.tryParse(_avgCtrl.text) ?? 0;
    if (qty <= 0 || avg <= 0) return;
    final meta = _commodities.firstWhere((c) => c.symbol == _selected);
    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.commodityHoldings, data: {
        'symbol': _selected, 'display_name': meta.name,
        'qty': qty, 'avg_price': avg,
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => _sheetContainer(context: context, child: Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sheetHandle(), const SizedBox(height: 16),
      const Text('Add Commodity', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
        fontWeight: FontWeight.w700, color: AppColors.text)),
      const SizedBox(height: 16),
      _sheetLabel('Commodity'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: _commodities.map((c) => GestureDetector(
        onTap: () => setState(() { _selected = c.symbol; _livePrice = null; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _selected == c.symbol ? AppColors.gold.withOpacity(0.15) : AppColors.bg3,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: _selected == c.symbol ? AppColors.gold.withOpacity(0.5) : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(c.name, style: TextStyle(fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500,
              color: _selected == c.symbol ? AppColors.gold : AppColors.text2)),
          ]),
        ),
      )).toList()),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text(
          'Unit: ${_commodities.firstWhere((c) => c.symbol == _selected).unit}',
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3))),
        ElevatedButton(
          onPressed: _fetchingPrice ? null : _fetchPrice,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.bg3,
            foregroundColor: AppColors.gold, minimumSize: const Size(100, 36), elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm),
              side: BorderSide(color: AppColors.gold.withOpacity(0.3)))),
          child: _fetchingPrice
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
            : const Text('Get Price', style: TextStyle(fontFamily: 'DMSans', fontSize: 12)),
        ),
      ]),
      if (_livePrice != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 13, color: AppColors.gold),
            const SizedBox(width: 6),
            Text('Live: ${formatInr(_livePrice!)}', style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 12, color: AppColors.gold)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _sheetField(_qtyCtrl, 'Quantity *', '0', number: true)),
        const SizedBox(width: 12),
        Expanded(child: _sheetField(_avgCtrl, 'Avg Buy Price (₹) *', '0.00', number: true)),
      ]),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        child: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Add Commodity', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
      )),
    ],
  ));
}

class _CommodityMeta {
  final String symbol, emoji, name, unit;
  const _CommodityMeta(this.symbol, this.emoji, this.name, this.unit);
}
