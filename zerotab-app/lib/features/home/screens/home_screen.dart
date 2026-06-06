import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/zt_card.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/providers_refresh.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/models/models.dart';
import '../widgets/sparkline_chart.dart';
import '../widgets/insight_card.dart';
import '../../../shared/widgets/ai_brain_icon.dart';

// ── Orange warning colour (AppColors.amber == AppColors.gold → alias bug) ──
const _kOrange = Color(0xFFFF8C42);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync  = ref.watch(financialSummaryProvider);
    final snapshotAsync = ref.watch(snapshotProvider);
    final insightAsync  = ref.watch(latestInsightProvider);
    final profileAsync  = ref.watch(userProfileProvider);
    final currentUser   = ref.watch(currentUserProvider);

    // ── Fix "Demo User" / null display name ──────────────────────────────
    final rawName   = profileAsync.value?.name?.trim();
    final isDefault = rawName == null ||
        rawName.isEmpty ||
        rawName.toLowerCase() == 'demo user' ||
        rawName.toLowerCase() == 'demo';
    final authEmail  = currentUser?.email ?? '';
    final displayName = isDefault
        ? (authEmail.isNotEmpty ? authEmail.split('@').first : 'Welcome back')
        : rawName;

    // ── Pre-warm ALL tab providers so switching tabs is instant ──────────────
    // ref.read() triggers fetch without creating a subscription.
    // By the time user taps Invest/Debt/Spend tab, data is already cached.
    ref.read(mfHoldingsProvider);
    ref.read(accountsProvider);
    ref.read(cashflowProvider);
    ref.read(insightsFeedProvider);
    ref.read(userProfileProvider);
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    ref.read(txnSummaryProvider(monthKey));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const _HomeShimmer(),
          error:   (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.red))),
          data: (summary) => RefreshIndicator(
            onRefresh: () async => refreshAllFinancialData(ref),
            color:           AppColors.accent,
            backgroundColor: AppColors.bg3,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [

                // ── Header ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _HomeHeader(name: displayName, email: authEmail),
                ),

                // ── Net Worth Hero ──────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _NetWorthCard(
                      summary:  summary,
                      snapshot: snapshotAsync.value,
                    ),
                  ),
                ),

                // ── Financial Breakdown — 4 chips ──────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _FinancialBreakdownRow(summary: summary),
                  ),
                ),

                // ── Monthly Cash Flow  [PRIORITY: daily actionable] ─────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: snapshotAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error:   (_, __) => const SizedBox.shrink(),
                      data: (snap) => snap != null && snap.monthlyIncome > 0
                          ? _MonthlyPlanCard(snapshot: snap)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),

                // ── Credit Cards Section  [compact tiles] ──────────────
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(child: _CreditCardSection()),
                ),

                // ── Quick Stats 2×2 ────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: snapshotAsync.when(
                      loading: () => const ZTShimmerBox(
                          width: double.infinity, height: 160, radius: 16),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (snap) => _QuickStats(snapshot: snap),
                    ),
                  ),
                ),

                // ── Upcoming EMIs ───────────────────────────────────────
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(child: _UpcomingEmiStrip()),
                ),

                // ── Demo banner (no data) ───────────────────────────────
                if (summary != null &&
                    summary.netWorth == 0 &&
                    summary.bankBalance == 0 &&
                    summary.mfValue == 0)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                    sliver: SliverToBoxAdapter(child: _DemoBanner()),
                  ),

                // ── AI Insight ──────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: insightAsync.when(
                      loading: () => const ZTShimmerBox(
                          width: double.infinity, height: 130, radius: 20),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (insight) => insight != null
                          ? InsightCard(insight: insight)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),

                // ── Ask AI CFO — quick entry ──────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(child: _AskAiCard()),
                ),

                // ── Cash Flow Shortcut ──────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: GestureDetector(
                      onTap: () => context.push('/cashflow'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: AppDecorations.card(),
                        child: Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: AppDecorations.iconContainer(
                                AppColors.accent, radius: AppRadius.sm),
                            alignment: Alignment.center,
                            child: const _BarChartIcon(),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'View cash flow analysis',
                              style: TextStyle(
                                fontFamily: 'DMSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              size: 13, color: AppColors.text3),
                        ]),
                      ),
                    ),
                  ),
                ),

                // ── Rupee Decision Engine ────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: GestureDetector(
                      onTap: () => context.push('/calculator/rupee-decision'),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0x157B2FFE), Color(0x0D00CFDE)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: const Color(0x287B2FFE)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B2FFE).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            alignment: Alignment.center,
                            child: const Text('₹?',
                              style: TextStyle(fontFamily: 'DMMono',
                                  fontSize: 16, fontWeight: FontWeight.w700,
                                  color: Color(0xFF7B2FFE))),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rupee Decision Engine',
                                  style: TextStyle(fontFamily: 'DMSans',
                                      fontSize: 13, fontWeight: FontWeight.w600,
                                      color: AppColors.text)),
                                SizedBox(height: 2),
                                Text('Prepay loan or invest? Get the exact answer →',
                                  style: TextStyle(fontFamily: 'DMSans',
                                      fontSize: 11, color: Color(0xFF00CFDE))),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              size: 12, color: Color(0xFF7B2FFE)),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Header
// ══════════════════════════════════════════════════════════════════════════════

class _HomeHeader extends StatelessWidget {
  final String name;
  final String email;
  const _HomeHeader({required this.name, required this.email});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _avatarLetter {
    if (name.isNotEmpty) return name[0].toUpperCase();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'U';
  }

  void _showNotificationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(children: [
        // ── Gradient avatar ──────────────────────────────────────
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF9B7FFF), Color(0xFF5A3FCC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            _avatarLetter,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: AppColors.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // ── Notification bell with badge count ──────────────
        _NotificationBell(onTap: () => _showNotificationSheet(context)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Net Worth Hero Card
// ══════════════════════════════════════════════════════════════════════════════

class _NetWorthCard extends StatefulWidget {
  final FinancialSummary? summary;
  final FinancialSnapshotModel? snapshot;
  const _NetWorthCard({required this.summary, required this.snapshot});

  @override
  State<_NetWorthCard> createState() => _NetWorthCardState();
}

class _NetWorthCardState extends State<_NetWorthCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  double _lastNw = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _lastNw = widget.summary?.netWorth ?? 0;
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_NetWorthCard old) {
    super.didUpdateWidget(old);
    final newNw = widget.summary?.netWorth ?? 0;
    if (newNw != _lastNw) {
      _lastNw = newNw;
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s             = widget.summary;
    final snap          = widget.snapshot;
    final nw            = s?.netWorth ?? 0.0;
    final biggestChange = snap?.biggestChange ?? '';
    final isPositive    = !biggestChange.toLowerCase().contains('down');

    // Allocation fractions for mini bar
    final banks  = s?.bankBalance ?? 0;
    final invest = s?.mfValue ?? 0;
    final cards  = s?.creditCardDebt ?? 0;
    final loans  = s?.loanOutstanding ?? 0;
    final total  = banks + invest + cards + loans;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
          colors: [Color(0xFF130F2E), Color(0xFF0F0D21), Color(0xFF0C0A1E)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: const Color(0x2E7B5FFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: label + live dot ─────────────────────────
          Row(children: [
            const Text(
              'TOTAL NET WORTH',
              style: TextStyle(
                fontFamily: 'DMSans', fontSize: 10,
                fontWeight: FontWeight.w600, letterSpacing: 0.12,
                color: AppColors.text3,
              ),
            ),
            const Spacer(),
            const Text('Live',
                style: TextStyle(fontFamily: 'DMMono', fontSize: 10, color: AppColors.teal)),
            const SizedBox(width: 4),
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.teal),
            ),
          ]),
          const SizedBox(height: 8),

          // ── Net worth — single unified text, no glyph collision ──
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              final val = nw * _anim.value;
              final isNeg = val < 0;
              // Use formatInr with sign prefix — ONE widget, ONE font size
              final display = isNeg
                  ? '-${formatInr(val.abs())}'
                  : formatInr(val);
              return Text(
                display,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                  color: isNeg ? AppColors.red : AppColors.text,
                  height: 1.1,
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // ── Change pill ───────────────────────────────────────
          if (biggestChange.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isPositive ? AppColors.greenSoft : AppColors.redSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 11,
                  color: isPositive ? AppColors.green : AppColors.red,
                ),
                const SizedBox(width: 3),
                Text(biggestChange,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isPositive ? AppColors.green : AppColors.red)),
              ]),
            ),

          const SizedBox(height: 16),

          // ── Smart financial summary: 3 key metrics this month ─
          // Replaces vague sparkline — shows actionable data
          if (snap != null)
            _MonthSummaryStrip(snapshot: snap)
          else
            const _MonthSummaryStripEmpty(),

          // ── Asset allocation bar ──────────────────────────────
          if (total > 0) ...[
            const SizedBox(height: 12),
            _MiniAllocationBar(banks: banks, invest: invest, cards: cards, loans: loans),
          ],
        ],
      ),
    );
  }
}

// ── Mini proportional allocation bar ──────────────────────────────────────

class _MiniAllocationBar extends StatelessWidget {
  final double banks, invest, cards, loans;
  const _MiniAllocationBar(
      {required this.banks,
      required this.invest,
      required this.cards,
      required this.loans});

  @override
  Widget build(BuildContext context) {
    final total = banks + invest + cards + loans;
    if (total == 0) return const SizedBox.shrink();
    final bf = banks  / total;
    final inf= invest / total;
    final cf = cards  / total;
    final lf = loans  / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(children: [
            if (bf  > 0) Expanded(flex: (bf  * 1000).round(), child: Container(height: 5, color: AppColors.accent)),
            if (inf > 0) Expanded(flex: (inf * 1000).round(), child: Container(height: 5, color: AppColors.teal)),
            if (cf  > 0) Expanded(flex: (cf  * 1000).round(), child: Container(height: 5, color: AppColors.coral)),
            if (lf  > 0) Expanded(flex: (lf  * 1000).round(), child: Container(height: 5, color: _kOrange)),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _AllocDot(color: AppColors.accent, label: 'Banks',  pct: bf),
          const SizedBox(width: 12),
          _AllocDot(color: AppColors.teal,   label: 'Invest', pct: inf),
          const SizedBox(width: 12),
          _AllocDot(color: AppColors.coral,  label: 'Cards',  pct: cf),
          const SizedBox(width: 12),
          _AllocDot(color: _kOrange,         label: 'Loans',  pct: lf),
        ]),
      ],
    );
  }
}

class _AllocDot extends StatelessWidget {
  final Color  color;
  final String label;
  final double pct;
  const _AllocDot(
      {required this.color, required this.label, required this.pct});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
          width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 4),
      Text(
        '$label ${(pct * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 9, color: AppColors.text3),
      ),
    ],
  );
}

// ── Smart month summary strip ─────────────────────────────────────────────
// Replaces vague sparkline — 3 actionable financial metrics for this month

class _MonthSummaryStrip extends StatelessWidget {
  final FinancialSnapshotModel snapshot;
  const _MonthSummaryStrip({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final income  = snapshot.monthlyIncome;
    final spend   = snapshot.monthlySpend;
    final savings = income > 0 ? ((income - spend) / income * 100).clamp(0.0, 100.0) : 0.0;
    final emi     = snapshot.emiRatio * 100;

    return Row(children: [
      _StatChip(
        label: 'Income',
        value: formatInr(income, compact: true),
        color: const Color(0xFF22C55E),
        icon: Icons.arrow_downward_rounded,
      ),
      const SizedBox(width: 8),
      _StatChip(
        label: 'Spend',
        value: formatInr(spend, compact: true),
        color: const Color(0xFFEF4444),
        icon: Icons.arrow_upward_rounded,
      ),
      const SizedBox(width: 8),
      _StatChip(
        label: 'Saved',
        value: '${savings.toStringAsFixed(0)}%',
        color: const Color(0xFF7B2FFE),
        icon: Icons.savings_outlined,
      ),
    ]);
  }
}

class _MonthSummaryStripEmpty extends StatelessWidget {
  const _MonthSummaryStripEmpty();

  @override
  Widget build(BuildContext context) => Row(children: [
    _StatChip(label: 'Income', value: '—', color: const Color(0xFF22C55E), icon: Icons.arrow_downward_rounded),
    const SizedBox(width: 8),
    _StatChip(label: 'Spend',  value: '—', color: const Color(0xFFEF4444), icon: Icons.arrow_upward_rounded),
    const SizedBox(width: 8),
    _StatChip(label: 'Saved',  value: '—', color: const Color(0xFF7B2FFE), icon: Icons.savings_outlined),
  ]);
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  final IconData icon;
  const _StatChip({required this.label, required this.value,
      required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: color.withValues(alpha: 0.80))),
        ]),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
            fontWeight: FontWeight.w700, color: color)),
      ]),
    ),
  );
}

// ── Notification bell with live badge ────────────────────────────────────────

class _NotificationBell extends ConsumerWidget {
  final VoidCallback onTap;
  const _NotificationBell({required this.onTap});

  int _countAlerts(FinancialSnapshotModel? snap) {
    if (snap == null) return 1; // AI insight always
    int count = 1; // AI insight
    if (snap.emiRatio > 0.35)   count++;
    if (snap.creditUtil > 0.5)  count++;
    if (snap.savingsRate < 0.10) count++;
    return count;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap  = ref.watch(snapshotProvider).value;
    final count = _countAlerts(snap);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.notifications_outlined,
                color: AppColors.text2, size: 18),
          ),
          // Badge — top right corner
          if (count > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                width: 17, height: 17,
                decoration: const BoxDecoration(
                  color: Color(0xFF7B2FFE),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 8.5,
                    fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Notification sheet ────────────────────────────────────────────────────────

class _NotificationSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(snapshotProvider).value;

    final items = <_NotifItem>[
      if (snap != null && snap.emiRatio > 0.35)
        _NotifItem(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFF59E0B),
          title: 'High EMI burden',
          body: 'Your EMIs are ${(snap.emiRatio * 100).toStringAsFixed(0)}% of income — above the safe 35% threshold.',
          time: 'Today',
        ),
      if (snap != null && snap.creditUtil > 0.5)
        _NotifItem(
          icon: Icons.credit_card_off_rounded,
          color: const Color(0xFFEF4444),
          title: 'Credit utilisation high',
          body: 'Using ${(snap.creditUtil * 100).toStringAsFixed(0)}% of your credit limit. Keep it under 30%.',
          time: 'Today',
        ),
      if (snap != null && snap.savingsRate < 0.10)
        _NotifItem(
          icon: Icons.savings_outlined,
          color: const Color(0xFF7B2FFE),
          title: 'Low savings rate',
          body: 'Saving only ${(snap.savingsRate * 100).toStringAsFixed(0)}% of income. Target: 20%+.',
          time: 'Today',
        ),
      _NotifItem(
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF00CFDE),
        title: 'AI insight ready',
        body: 'Your weekly financial analysis is available. Tap to view.',
        time: 'This week',
        onTap: () { Navigator.pop(context); context.go('/chat'); },
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(children: [
              const Text('Notifications',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 16,
                    fontWeight: FontWeight.w700, color: AppColors.text)),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2FFE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${items.length}',
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                        fontWeight: FontWeight.w700, color: Color(0xFF7B2FFE))),
                ),
            ]),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('All clear — no alerts right now.',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                    color: AppColors.text3)),
            )
          else
            ...items.map((item) => _NotifTile(item: item)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NotifItem {
  final IconData icon;
  final Color    color;
  final String   title, body, time;
  final VoidCallback? onTap;
  const _NotifItem({required this.icon, required this.color,
      required this.title, required this.body, required this.time, this.onTap});
}

class _NotifTile extends StatelessWidget {
  final _NotifItem item;
  const _NotifTile({required this.item});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: item.onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(item.icon, color: item.color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(item.title,
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                    fontWeight: FontWeight.w600, color: AppColors.text))),
              Text(item.time, style: const TextStyle(fontFamily: 'DMSans',
                  fontSize: 9.5, color: AppColors.text3)),
            ]),
            const SizedBox(height: 2),
            Text(item.body, style: const TextStyle(fontFamily: 'DMSans',
                fontSize: 11.5, color: AppColors.text2, height: 1.4)),
          ],
        )),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Financial Breakdown — 4 chips (Banks | Cards | Invest | Loans)
// ══════════════════════════════════════════════════════════════════════════════

class _FinancialBreakdownRow extends StatelessWidget {
  final FinancialSummary? summary;
  const _FinancialBreakdownRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <_AccountItem>[
      _AccountItem(
        label:    'Banks',
        value:    formatInr(s?.bankBalance ?? 0, compact: true),
        color:    AppColors.accent,
        icon:     const _BankIcon(),
        negative: false,
      ),
      _AccountItem(
        label:    'Cards',
        value:    formatInr(s?.creditCardDebt ?? 0, compact: true),
        color:    AppColors.coral,
        icon:     const _CardIcon(),
        negative: (s?.creditCardDebt ?? 0) > 0,
      ),
      _AccountItem(
        label:    'Invest',
        value:    formatInr(s?.mfValue ?? 0, compact: true),
        color:    AppColors.teal,
        icon:     const _ChartIcon(),
        negative: false,
      ),
      _AccountItem(
        label:    'Loans',
        value:    formatInr(s?.loanOutstanding ?? 0, compact: true),
        color:    _kOrange,
        icon:     const _HomeIconSvg(),
        negative: (s?.loanOutstanding ?? 0) > 0,
      ),
    ];

    return Row(
      children: List.generate(items.length, (i) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i < items.length - 1 ? 8 : 0),
          child: _AccountChipItem(item: items[i]),
        ),
      )),
    );
  }
}

class _AccountItem {
  final String label, value;
  final Color  color;
  final Widget icon;
  final bool   negative;
  const _AccountItem({
    required this.label, required this.value,
    required this.color, required this.icon, required this.negative,
  });
}

class _AccountChipItem extends StatelessWidget {
  final _AccountItem item;
  const _AccountChipItem({required this.item});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
    decoration: BoxDecoration(
      color: AppColors.bg3,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: [
      Container(
        width: 28, height: 28,
        decoration:
            AppDecorations.iconContainer(item.color, radius: AppRadius.sm),
        alignment: Alignment.center,
        child: SizedBox(width: 14, height: 14, child: item.icon),
      ),
      const SizedBox(height: 5),
      Text(item.label,
          style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(
        item.value,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: item.negative ? AppColors.red : AppColors.text,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Credit Card Section
// ══════════════════════════════════════════════════════════════════════════════

class _CreditCardSection extends ConsumerWidget {
  const _CreditCardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return accountsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (accounts) {
        final cards = accounts
            .where((a) =>
                a.accountType == 'credit_card' ||
                a.sourceType  == 'credit_card')
            .toList();

        double totalOutstanding = 0;
        for (final c in cards) {
          totalOutstanding += (c.currentBalance?.abs() ?? 0);
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card(radius: AppRadius.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section header ───────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.coral.withOpacity(0.12),
                        borderRadius:
                            BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: AppColors.coral,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Credit Cards',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ]),
                  if (cards.isNotEmpty)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text(
                        'Total outstanding',
                        style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 10,
                            color: AppColors.text3),
                      ),
                      Text(
                        formatInr(totalOutstanding, compact: true),
                        style: const TextStyle(
                          fontFamily: 'DMMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.coral,
                        ),
                      ),
                    ]),
                ],
              ),

              // ── Empty state ──────────────────────────────────
              if (cards.isEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bg4,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(children: [
                    const Icon(Icons.add_card_outlined,
                        color: AppColors.coral, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Track bills, due dates & utilization\nby adding your credit cards',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.go('/debt'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.coral.withOpacity(0.15),
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.coral,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ] else ...[
                // ── Horizontal scroll of cards ───────────────
                const SizedBox(height: 12),
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount:      cards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _CreditCardTile(account: cards[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  final AccountModel account;
  const _CreditCardTile({required this.account});

  String _fmtDue(DateTime d) {
    final diff = d.difference(DateTime.now()).inDays;
    if (diff < 0)  return 'Overdue!';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due in $diff days';
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = account.currentBalance?.abs() ?? 0;
    final limit       = account.creditLimit ?? 0;
    final util        = limit > 0 ? (outstanding / limit).clamp(0.0, 1.0) : 0.0;
    final masked      = account.maskedNumber ?? '••••';
    final name        = account.institutionName ??
        account.accountType ?? 'Card';

    final dueDateStr = account.metadata?['due_date'] as String?;
    final dueDate    = dueDateStr != null ? DateTime.tryParse(dueDateStr) : null;

    Color utilColor = AppColors.green;
    if (util > 0.75)      utilColor = AppColors.red;
    else if (util > 0.40) utilColor = _kOrange;

    final isPastDue = dueDate != null && dueDate.isBefore(DateTime.now());

    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPastDue
              ? [const Color(0xFF2A0A0A), const Color(0xFF1C0808)]
              : [const Color(0xFF1E1030), const Color(0xFF160A26)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isPastDue
              ? AppColors.red.withOpacity(0.40)
              : AppColors.coral.withOpacity(0.20),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Row 1: name + masked number ────────────────────
          Row(children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bg4,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '••${masked.length >= 4 ? masked.substring(masked.length - 4) : masked}',
                style: const TextStyle(
                    fontFamily: 'DMMono', fontSize: 9, color: AppColors.text3),
              ),
            ),
          ]),

          const SizedBox(height: 7),

          // ── Row 2: outstanding + limit inline ──────────────
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
            Text(
              formatInr(outstanding, compact: true),
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: utilColor,
                letterSpacing: -0.3,
              ),
            ),
            if (limit > 0) ...[
              const SizedBox(width: 3),
              Text(
                '/ ${formatInr(limit, compact: true)}',
                style: const TextStyle(
                    fontFamily: 'DMMono', fontSize: 9, color: AppColors.text3),
              ),
            ],
          ]),

          const SizedBox(height: 7),

          // ── Utilization bar ─────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value:           util,
              minHeight:       3.5,
              backgroundColor: AppColors.bg4,
              color:           utilColor,
            ),
          ),

          const SizedBox(height: 6),

          // ── Row 3: util % + due date ────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  color: utilColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${(util * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: utilColor),
              ),
            ]),
            if (dueDate != null)
              Text(
                _fmtDue(dueDate),
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 9,
                  color: isPastDue ? AppColors.red : AppColors.text3,
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Investment Portfolio Snapshot
// ══════════════════════════════════════════════════════════════════════════════

class _InvestmentSnapshotCard extends ConsumerWidget {
  const _InvestmentSnapshotCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdingsAsync = ref.watch(mfHoldingsProvider);

    return holdingsAsync.when(
      loading: () =>
          const ZTShimmerBox(width: double.infinity, height: 120, radius: 16),
      error: (_, __) => const SizedBox.shrink(),
      data: (holdings) {
        if (holdings.isEmpty) return const SizedBox.shrink();

        double totalInvested = 0, totalCurrent = 0;
        double stocksVal = 0, mfVal = 0, etfVal = 0, commVal = 0;

        for (final h in holdings) {
          totalInvested += h.investedAmount ?? 0;
          totalCurrent  += h.currentValue   ?? 0;
          if (h.isStock)          stocksVal += h.currentValue ?? 0;
          else if (h.isETF)       etfVal    += h.currentValue ?? 0;
          else if (h.isCommodity) commVal   += h.currentValue ?? 0;
          else                    mfVal     += h.currentValue ?? 0;
        }

        if (totalCurrent == 0) return const SizedBox.shrink();

        final gainLoss    = totalCurrent - totalInvested;
        final gainPct     = totalInvested > 0
            ? gainLoss / totalInvested * 100 : 0.0;
        final isGain      = gainLoss >= 0;

        // Build chip widgets
        final chips = <Widget>[];
        void addChip(String lbl, double v, Color c) {
          if (v <= 0) return;
          if (chips.isNotEmpty) chips.add(const SizedBox(width: 8));
          chips.add(_InvChip(label: lbl, value: v, color: c));
        }
        addChip('Stocks', stocksVal, AppColors.accent);
        addChip('MF',     mfVal,     AppColors.teal);
        addChip('ETF',    etfVal,    const Color(0xFF4A9EFF));
        addChip('Commod', commVal,   const Color(0xFFFFAA00));

        return GestureDetector(
          onTap: () => context.go('/investments'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecorations.card(radius: AppRadius.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: AppColors.teal,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'My Portfolio',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ]),
                    Row(children: const [
                      Text('View all',
                          style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 11,
                              color: AppColors.accent2)),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: AppColors.accent2),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),

                // Value + Gain
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Value',
                          style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 10,
                              color: AppColors.text3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatInr(totalCurrent, compact: true),
                          style: const TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Invested: ${formatInr(totalInvested, compact: true)}',
                          style: const TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 10,
                              color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          isGain ? AppColors.greenSoft : AppColors.redSoft,
                      borderRadius:
                          BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${isGain ? '+' : ''}${gainPct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color:
                                isGain ? AppColors.green : AppColors.red,
                          ),
                        ),
                        Text(
                          '${isGain ? '+' : ''}${formatInr(gainLoss, compact: true)}',
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontSize: 10,
                            color:
                                isGain ? AppColors.green : AppColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),

                // Category chips
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(children: chips),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InvChip extends StatelessWidget {
  final String label;
  final double value;
  final Color  color;
  const _InvChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding:
        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: color)),
      Text(
        formatInr(value, compact: true),
        style: TextStyle(
            fontFamily: 'DMMono',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Monthly Plan Card
// ══════════════════════════════════════════════════════════════════════════════

class _MonthlyPlanCard extends StatelessWidget {
  final FinancialSnapshotModel snapshot;
  const _MonthlyPlanCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final now         = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed  = now.day;
    final monthFrac   = daysPassed / daysInMonth;

    final income    = snapshot.monthlyIncome;
    final spent     = snapshot.monthlySpend;
    final projected = monthFrac > 0 ? spent / monthFrac : spent;
    final onBudget  = projected <= income;
    final pct       = income > 0 ? (spent / income).clamp(0.0, 1.5) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(radius: AppRadius.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text(
            'Monthly Spending Plan',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: onBudget ? AppColors.greenSoft : AppColors.redSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              onBudget ? 'On track' : 'Over pace',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: onBudget ? AppColors.green : AppColors.red,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Spent this month',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: AppColors.text3)),
            const SizedBox(height: 2),
            Text(formatInr(spent, compact: true),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                )),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('of monthly income',
                style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: AppColors.text3)),
            const SizedBox(height: 2),
            Text(formatInr(income, compact: true),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text2,
                )),
          ]),
        ]),
        const SizedBox(height: 10),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           pct.clamp(0.0, 1.0),
              minHeight:       8,
              backgroundColor: AppColors.bg4,
              color: pct > 1.0
                  ? AppColors.red
                  : pct > 0.8
                      ? _kOrange
                      : AppColors.teal,
            ),
          ),
          Positioned(
            left: (monthFrac *
                    (MediaQuery.of(context).size.width - 72))
                .clamp(0, double.infinity),
            top: 0,
            child: Container(
              width: 2, height: 8,
              decoration: BoxDecoration(
                color: AppColors.text3,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            '${(pct * 100).toStringAsFixed(0)}% used · day $daysPassed/$daysInMonth',
            style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 10,
                color: AppColors.text3),
          ),
          Text(
            'Proj: ${formatInr(projected, compact: true)}',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 10,
              color: onBudget ? AppColors.text3 : AppColors.red,
            ),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Upcoming EMI Strip
// ══════════════════════════════════════════════════════════════════════════════

class _UpcomingEmiStrip extends ConsumerWidget {
  const _UpcomingEmiStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    return accountsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (accounts) {
        final loans =
            accounts.where((a) => a.accountType == 'loan').toList();
        if (loans.isEmpty) return const SizedBox.shrink();

        final upcoming = <_EmiItem>[];
        for (final loan in loans) {
          final startStr = loan.loanStartDate;
          if (startStr == null) continue;
          final start = DateTime.tryParse(startStr);
          if (start == null) continue;
          final rate        = loan.interestRate ?? 0;
          final tenor       = loan.tenorMonths  ?? 0;
          final outstanding = loan.currentBalance?.abs() ?? 0;
          if (outstanding <= 0) continue;

          final elapsed   = DateTime.now().difference(start).inDays ~/ 30;
          final remaining = (tenor - elapsed).clamp(0, tenor);
          if (remaining <= 0) continue;
          final emi = _calcEmi(outstanding, rate, remaining);
          if (emi <= 0) continue;

          final now = DateTime.now();
          var dueDate = DateTime(now.year, now.month, start.day);
          if (dueDate.isBefore(now) || dueDate.isAtSameMomentAs(now)) {
            dueDate = DateTime(now.year, now.month + 1, start.day);
          }
          upcoming.add(_EmiItem(
            name:     loan.loanName ?? loan.institutionName ?? 'Loan',
            emi:      emi,
            dueDate:  dueDate,
            daysLeft: dueDate.difference(now).inDays,
          ));
        }

        if (upcoming.isEmpty) return const SizedBox.shrink();
        upcoming.sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final show = upcoming.take(3).toList();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: AppDecorations.card(radius: AppRadius.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: _kOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    size: 12, color: _kOrange,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Upcoming EMIs',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              ...show.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  // Left: circle day indicator
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: item.daysLeft <= 3
                          ? AppColors.red.withOpacity(0.12)
                          : AppColors.bg4,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.daysLeft <= 0
                          ? '!'
                          : '${item.daysLeft}d',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: item.daysLeft <= 3
                            ? AppColors.red
                            : AppColors.text3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                          style: const TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          item.daysLeft == 0
                              ? 'Due today'
                              : item.daysLeft == 1
                                  ? 'Due tomorrow'
                                  : 'Due in ${item.daysLeft} days',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 11,
                            color: item.daysLeft <= 3
                                ? AppColors.red
                                : AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatInr(item.emi, compact: true),
                    style: const TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ]),
              )),
            ],
          ),
        );
      },
    );
  }

  double _calcEmi(double principal, double annualRate, int months) {
    if (months <= 0 || principal <= 0) return 0;
    if (annualRate <= 0) return principal / months;
    final r = annualRate / 12 / 100;
    final n = months.toDouble();
    return principal * r * math.pow(1 + r, n) / (math.pow(1 + r, n) - 1);
  }
}

class _EmiItem {
  final String   name;
  final double   emi;
  final DateTime dueDate;
  final int      daysLeft;
  const _EmiItem(
      {required this.name,
      required this.emi,
      required this.dueDate,
      required this.daysLeft});
}

// ══════════════════════════════════════════════════════════════════════════════
// Demo Banner
// ══════════════════════════════════════════════════════════════════════════════

class _DemoBanner extends ConsumerStatefulWidget {
  const _DemoBanner();

  @override
  ConsumerState<_DemoBanner> createState() => _DemoBannerState();
}

class _DemoBannerState extends ConsumerState<_DemoBanner> {
  bool _loading = false;

  Future<void> _loadDemo() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.demoSeed);
      ref.invalidate(financialSummaryProvider);
      ref.invalidate(snapshotProvider);
      ref.invalidate(latestInsightProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(mfHoldingsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load demo: ${apiErrorMessage(e)}'),
          backgroundColor: AppColors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1040), Color(0xFF110D2B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      border: Border.all(color: const Color(0x2E7B5FFF)),
    ),
    child: Row(children: [
      Container(
        width: 38, height: 38,
        decoration: AppDecorations.iconContainer(
            AppColors.accent, radius: AppRadius.sm),
        alignment: Alignment.center,
        child: const Icon(
            Icons.science_outlined, color: AppColors.accent2, size: 18),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No financial data yet',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              )),
          SizedBox(height: 3),
          Text('Load sample Indian data to explore all features',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                color: AppColors.text2,
                height: 1.4,
              )),
        ]),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: _loadDemo,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color:        AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: _loading
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Load demo',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  )),
        ),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Quick Stats 2×2
// ══════════════════════════════════════════════════════════════════════════════

class _QuickStats extends StatelessWidget {
  final FinancialSnapshotModel? snapshot;
  const _QuickStats({this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s             = snapshot;
    final monthlySpend  = s?.monthlySpend  ?? 0;
    final monthlyIncome = s?.monthlyIncome ?? 0;
    final savingsRate   = s?.savingsRate   ?? 0;
    final emiRatio      = s?.emiRatio      ?? 0;
    final mfXirr        = s?.mfXirr        ?? 0;

    final spendDelta = s?.biggestChange.contains('up') == true
        ? '↑ vs last month'
        : '↓ vs last month';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _StatCard(
          label:    'Monthly spend',
          value:    formatInr(monthlySpend, compact: true),
          sub:      spendDelta,
          subColor: monthlySpend > monthlyIncome * 0.7
              ? AppColors.red : AppColors.text2,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label:    'Savings rate',
          value:    formatPct(savingsRate * 100),
          sub:      '',
          subColor: AppColors.green,
          showBar:  true,
          barColor: savingsRate > 0.2 ? AppColors.green : _kOrange,
          barValue: savingsRate.clamp(0.0, 1.0),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(
          label:    'EMI burden',
          value:    formatPct(emiRatio * 100),
          sub:      '',
          subColor: _kOrange,
          showBar:  true,
          barColor: emiRatio > 0.4 ? AppColors.red : _kOrange,
          barValue: emiRatio.clamp(0.0, 1.0),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label:    'MF XIRR',
          value:    formatPct(mfXirr),
          sub:      mfXirr > 12 ? 'Beating FD ✓' : '',
          subColor: AppColors.green,
        )),
      ]),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final Color  subColor;
  final bool   showBar;
  final Color? barColor;
  final double barValue;

  const _StatCard({
    required this.label, required this.value,
    required this.sub,   required this.subColor,
    this.showBar = false, this.barColor, this.barValue = 0,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: AppDecorations.card(radius: AppRadius.lg),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.text3)),
      const SizedBox(height: 5),
      Text(value,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: AppColors.text,
          )),
      if (showBar) ...[
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value:           barValue,
            minHeight:       3,
            backgroundColor: AppColors.bg4,
            color:           barColor,
          ),
        ),
      ] else if (sub.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(sub,
            style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: subColor)),
      ],
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Loading Shimmer
// ══════════════════════════════════════════════════════════════════════════════

class _HomeShimmer extends StatelessWidget {
  const _HomeShimmer();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.all(20),
    child: Column(children: [
      ZTShimmerBox(width: double.infinity, height: 56,  radius: 12),
      SizedBox(height: 14),
      ZTShimmerBox(width: double.infinity, height: 200, radius: 24),
      SizedBox(height: 12),
      ZTShimmerBox(width: double.infinity, height: 62,  radius: 16),
      SizedBox(height: 14),
      ZTShimmerBox(width: double.infinity, height: 130, radius: 20),
      SizedBox(height: 12),
      ZTShimmerBox(width: double.infinity, height: 120, radius: 16),
      SizedBox(height: 12),
      ZTShimmerBox(width: double.infinity, height: 128, radius: 20),
      SizedBox(height: 16),
      ZTShimmerBox(width: double.infinity, height: 160, radius: 16),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline icon painters
// ══════════════════════════════════════════════════════════════════════════════

class _BarChartIcon extends StatelessWidget {
  const _BarChartIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BarChartPainter(), size: const Size(16, 16));
}

class _BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = AppColors.accent2
      ..strokeWidth = 2
      ..strokeCap  = StrokeCap.round
      ..style      = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width * 0.15, size.height),
        Offset(size.width * 0.15, size.height * 0.6), p);
    canvas.drawLine(Offset(size.width * 0.5, size.height),
        Offset(size.width * 0.5, size.height * 0.3), p);
    canvas.drawLine(Offset(size.width * 0.85, size.height),
        Offset(size.width * 0.85, size.height * 0.05), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _BankIcon extends StatelessWidget {
  const _BankIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BankIconPainter(), size: const Size(14, 14));
}

class _BankIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = AppColors.accent2
      ..strokeWidth = 1.2
      ..strokeCap  = StrokeCap.round
      ..style      = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(0, h * 0.4), Offset(w / 2, 0), p);
    canvas.drawLine(Offset(w / 2, 0), Offset(w, h * 0.4), p);
    canvas.drawLine(Offset(0, h * 0.4), Offset(w, h * 0.4), p);
    canvas.drawLine(Offset(0, h), Offset(w, h), p);
    canvas.drawLine(
        Offset(w * 0.25, h * 0.4), Offset(w * 0.25, h), p);
    canvas.drawLine(
        Offset(w * 0.75, h * 0.4), Offset(w * 0.75, h), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _CardIcon extends StatelessWidget {
  const _CardIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _CardIconPainter(), size: const Size(14, 14));
}

class _CardIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = AppColors.coral
      ..strokeWidth = 1.2
      ..strokeCap  = StrokeCap.round
      ..style      = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, h * 0.15, w, h * 0.7), const Radius.circular(2)),
        p);
    canvas.drawLine(
        Offset(0, h * 0.44), Offset(w, h * 0.44), p..strokeWidth = 1.5);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.1, h * 0.58, w * 0.22, h * 0.2),
        Paint()..color = AppColors.coral..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _ChartIcon extends StatelessWidget {
  const _ChartIcon();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ChartIconPainter(), size: const Size(14, 14));
}

class _ChartIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = AppColors.teal
      ..strokeWidth = 1.5
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style      = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(0, h * 0.8)
          ..lineTo(w * 0.25, h * 0.5)
          ..lineTo(w * 0.55, h * 0.65)
          ..lineTo(w, h * 0.1),
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _HomeIconSvg extends StatelessWidget {
  const _HomeIconSvg();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HomeIconPainter(), size: const Size(14, 14));
}

class _HomeIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color      = _kOrange
      ..strokeWidth = 1.2
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style      = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.1, h * 0.5)
          ..lineTo(w * 0.5, h * 0.08)
          ..lineTo(w * 0.9, h * 0.5)
          ..lineTo(w * 0.9, h * 0.95)
          ..lineTo(w * 0.1, h * 0.95)
          ..close(),
        p);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.37, h * 0.65, w * 0.26, h * 0.3),
        p..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Ask AI CFO card ──────────────────────────────────────────────────────

class _AskAiCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/chat'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x157B2FFE), Color(0x0D00CFDE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: const Color(0x287B2FFE)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1C0A4A), Color(0xFF070D1F)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0xFF7B2FFE), width: 1),
              boxShadow: const [BoxShadow(color: Color(0x337B2FFE), blurRadius: 8)],
            ),
            alignment: Alignment.center,
            child: const AiBrainIcon(size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text(
                    'Ask your AI CFO',
                    style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0x1A7B2FFE),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: const Color(0x407B2FFE)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Chat', style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00CFDE))),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 10, color: Color(0xFF00CFDE)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Tax planning, investment advice, spending analysis — powered by your real data.',
                  style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 11,
                    color: AppColors.text3, height: 1.4),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
