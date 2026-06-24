import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/widgets/zt_card.dart';

class CashFlowScreen extends ConsumerWidget {
  const CashFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfAsync  = ref.watch(cashflowProvider);
    final now      = DateTime.now();
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final summaryAsync = ref.watch(txnSummaryProvider(monthKey));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: cfAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(
              child: Text('$e',
                  style: const TextStyle(color: AppColors.red))),
          data: (cfData) => RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(cashflowProvider),
            color: AppColors.accent,
            backgroundColor: AppColors.bg3,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ──────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        20, 16, 20, 16),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cash Flow',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: AppColors.text,
                          ),
                        ),
                        const Spacer(),
                        // X close button — goes back or to home
                        GestureDetector(
                          onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.bg3,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.border),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.close_rounded,
                                color: AppColors.text2, size: 16),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(
                                AppRadius.md),
                            border: Border.all(
                                color: AppColors.accent
                                    .withOpacity(0.2)),
                          ),
                          child: const Text(
                            'Last 6 months',
                            style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.accent2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Summary tiles ────────────────────
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: summaryAsync.when(
                      loading: () => const ZTShimmerBox(
                          width: double.infinity,
                          height: 82,
                          radius: 16),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (s) => Row(children: [
                        _SummaryTile(
                          label: 'Income',
                          value: formatInr(
                              s['totalIncome'] ?? 0),
                          color: AppColors.green,
                          iconType: 'in',
                        ),
                        const SizedBox(width: 10),
                        _SummaryTile(
                          label: 'Spent',
                          value: formatInr(
                              s['totalSpend'] ?? 0),
                          color: AppColors.coral,
                          iconType: 'out',
                        ),
                        const SizedBox(width: 10),
                        _SummaryTile(
                          label: 'Saved',
                          value: formatInr(
                            ((s['totalIncome'] ?? 0) -
                                    (s['totalSpend'] ?? 0))
                                .toDouble(),
                          ),
                          color: AppColors.teal,
                          iconType: 'save',
                        ),
                      ]),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                    child: SizedBox(height: 16)),

                // ── Bar chart ────────────────────────
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: AppDecorations.card(
                          radius: AppRadius.xl),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: AppColors.green,
                                    borderRadius:
                                        BorderRadius.circular(
                                            3))),
                            const SizedBox(width: 6),
                            const Text('Income',
                                style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 11,
                                    color: AppColors.text2)),
                            const SizedBox(width: 14),
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: AppColors.coral,
                                    borderRadius:
                                        BorderRadius.circular(
                                            3))),
                            const SizedBox(width: 6),
                            const Text('Spend',
                                style: TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 11,
                                    color: AppColors.text2)),
                          ]),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 130,
                            child: _BarChart(data: cfData),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                    child: SizedBox(height: 16)),

                // ── Category breakdown ───────────────
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: summaryAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (s) => _CategoryBreakdown(
                        byCategory: Map<String, double>.from(
                          (s['byCategory'] as Map? ?? {}).map(
                            (k, v) => MapEntry(
                                k as String,
                                (v as num).toDouble()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // ── Forward cash runway ──────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _RunwayCard(cfData: cfData),
                  ),
                ),

                const SliverPadding(
                    padding: EdgeInsets.only(bottom: 28)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Summary tile ──────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String iconType;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.iconType,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border:
                Border.all(color: color.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  iconType == 'in'
                      ? Icons.arrow_downward_rounded
                      : iconType == 'out'
                          ? Icons.arrow_upward_rounded
                          : Icons.savings_outlined,
                  size: 12,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Bar chart ─────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.fold(
      0.0,
      (m, d) => [
        m,
        (d['income'] as num).toDouble(),
        (d['spend'] as num).toDouble(),
      ].reduce((a, b) => a > b ? a : b),
    );

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length)
                  return const SizedBox.shrink();
                final month = data[i]['month'] as String;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    month.length >= 7 ? month.substring(5) : month,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 9,
                      color: AppColors.text3,
                    ),
                  ),
                );
              },
              reservedSize: 18,
            ),
          ),
        ),
        barGroups: List.generate(
          data.length,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (data[i]['income'] as num).toDouble(),
                color: AppColors.green.withOpacity(0.65),
                width: 9,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: (data[i]['spend'] as num).toDouble(),
                color: AppColors.coral.withOpacity(0.65),
                width: 9,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category breakdown ────────────────────────────────────

class _CategoryBreakdown extends StatelessWidget {
  final Map<String, double> byCategory;
  const _CategoryBreakdown({required this.byCategory});

  @override
  Widget build(BuildContext context) {
    if (byCategory.isEmpty) return const SizedBox.shrink();
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total =
        byCategory.values.fold(0.0, (s, v) => s + v);

    return Container(
      decoration:
          AppDecorations.card(radius: AppRadius.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'SPEND BY CATEGORY',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.10,
                color: AppColors.text3,
              ),
            ),
          ),
          ...sorted.take(6).map((e) {
            final pct =
                total > 0 ? e.value / total : 0.0;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius:
                            BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .spaceBetween,
                            children: [
                              Text(
                                categoryDisplayName(e.key),
                                style: const TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 13,
                                  fontWeight:
                                      FontWeight.w500,
                                  color: AppColors.text,
                                ),
                              ),
                              Text(
                                formatInr(e.value),
                                style: const TextStyle(
                                  fontFamily: 'DMMono',
                                  fontSize: 12,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 3,
                              backgroundColor:
                                  AppColors.bg4,
                              color: AppColors.accent
                                  .withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatPct(pct * 100, decimals: 0),
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                  color: AppColors.border,
                  height: 1,
                  indent: 31),
            ]);
          }),
        ],
      ),
    );
  }
}

// ── Forward Cash Runway ───────────────────────────────────
//
// Uses the last 3 months of cashflow data to compute:
//   avgMonthlyIncome, avgMonthlyBurn → netMonthlyPosition
// Then projects forward to find the date when accumulated
// net position would go negative (overdraft warning), or
// shows "On track" if income > burn.

class _RunwayCard extends StatelessWidget {
  final List<Map<String, dynamic>> cfData;
  const _RunwayCard({required this.cfData});

  @override
  Widget build(BuildContext context) {
    if (cfData.isEmpty) return const SizedBox.shrink();

    // Use last 3 months for the projection baseline
    final recent = cfData.length > 3 ? cfData.sublist(cfData.length - 3) : cfData;
    final avgIncome = recent.fold(0.0, (s, m) => s + (m['income'] as num).toDouble()) / recent.length;
    final avgBurn   = recent.fold(0.0, (s, m) => s + (m['spend'] as num).toDouble())  / recent.length;
    final netMonthly = avgIncome - avgBurn;

    // Current month position: last entry may be partial
    final currentMonth = cfData.isNotEmpty ? cfData.last : <String, dynamic>{};
    final thisMonthIncome = (currentMonth['income'] as num? ?? 0).toDouble();
    final thisMonthSpend  = (currentMonth['spend']  as num? ?? 0).toDouble();
    final thisMonthNet    = thisMonthIncome - thisMonthSpend;

    // Days remaining this month
    final now = DateTime.now();
    final daysInMonth   = DateTime(now.year, now.month + 1, 0).day;
    final daysRemaining = daysInMonth - now.day;
    final monthFraction = daysRemaining / daysInMonth;

    // Projected end-of-month position from today
    final projectedEOM = thisMonthNet + netMonthly * monthFraction;

    final isOnTrack = netMonthly >= 0 || projectedEOM >= 0;

    // Days until projected zero crossing (only relevant when burning)
    int? daysToZero;
    if (!isOnTrack && netMonthly < 0) {
      // Assume cumulative current position approximated by thisMonthNet
      // zero crossing: thisMonthNet + netMonthly/30 * d = 0
      final dailyNet = netMonthly / 30;
      if (dailyNet < 0) {
        daysToZero = ((-thisMonthNet) / dailyNet.abs()).ceil();
        daysToZero = daysToZero! < 0 ? null : daysToZero;
      }
    }

    final accentColor = isOnTrack ? AppColors.green : AppColors.red;
    final bgColor     = accentColor.withOpacity(0.07);
    final borderColor = accentColor.withOpacity(0.20);

    // Build the overdraft date string
    String statusLine;
    String subLine;
    if (isOnTrack) {
      statusLine = 'Cash flow on track';
      subLine    = 'Saving ${formatInr(netMonthly)}/mo on average — keep it up!';
    } else if (daysToZero != null && daysToZero <= 31) {
      final crossDate = now.add(Duration(days: daysToZero));
      final label = '${_monthName(crossDate.month)} ${crossDate.day}';
      statusLine = 'Buffer warning — $label';
      subLine    = 'At current pace your monthly surplus runs out around $label. '
                   'Cut ${formatInr(-netMonthly)}/mo to break even.';
    } else {
      statusLine = 'Spending above income';
      subLine    = 'You\'re burning ${formatInr(-netMonthly)} more than you earn each month. '
                   'Review recurring charges.';
    }

    // Mini 6-bar projection
    final bars = _buildProjectionBars(cfData, netMonthly, 6);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              isOnTrack ? Icons.trending_up_rounded : Icons.warning_amber_rounded,
              color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(statusLine,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w700, color: accentColor)),
              const SizedBox(height: 2),
              Text('Forward Cash Runway',
                style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 11, color: AppColors.text3)),
            ],
          )),
        ]),

        const SizedBox(height: 14),

        // Projection bars
        SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bars.map((b) {
              final isFuture = b['future'] as bool;
              final frac    = b['frac'] as double;
              final isNeg   = frac < 0;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: (frac.abs() * 40).clamp(3.0, 40.0),
                      decoration: BoxDecoration(
                        color: isNeg
                            ? AppColors.red.withOpacity(isFuture ? 0.4 : 0.7)
                            : AppColors.green.withOpacity(isFuture ? 0.3 : 0.55),
                        borderRadius: BorderRadius.circular(3),
                        border: isFuture
                            ? Border.all(color: (isNeg ? AppColors.red : AppColors.green).withOpacity(0.5),
                                style: BorderStyle.solid)
                            : null,
                      ),
                    ),
                  ],
                ),
              ));
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Summary line
        Text(subLine,
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
              color: AppColors.text3, height: 1.45)),

        const SizedBox(height: 14),

        // Income vs burn stats
        Row(children: [
          _RunwayStat(label: 'Avg income',
              value: formatInr(avgIncome), color: AppColors.green),
          const SizedBox(width: 12),
          _RunwayStat(label: 'Avg spend',
              value: formatInr(avgBurn), color: AppColors.coral),
          const SizedBox(width: 12),
          _RunwayStat(
            label: netMonthly >= 0 ? 'Monthly save' : 'Monthly deficit',
            value: formatInr(netMonthly.abs()),
            color: netMonthly >= 0 ? AppColors.teal : AppColors.red,
          ),
        ]),
      ]),
    );
  }

  // Build projection bars: past months actual + future projected
  static List<Map<String, dynamic>> _buildProjectionBars(
      List<Map<String, dynamic>> cfData, double netMonthly, int totalBars) {
    final past = cfData.map((m) {
      final income = (m['income'] as num).toDouble();
      final spend  = (m['spend'] as num).toDouble();
      final net    = income - spend;
      final maxVal = [income, spend].reduce((a, b) => a > b ? a : b);
      return {'frac': maxVal > 0 ? net / maxVal : 0.0, 'future': false};
    }).toList();

    final pastCount   = past.length.clamp(0, totalBars - 2);
    final futureCount = totalBars - pastCount;
    final maxAbs      = netMonthly.abs().clamp(1.0, double.infinity);

    final future = List.generate(futureCount, (i) => {
      'frac': (netMonthly / (maxAbs * 1.2)).clamp(-1.0, 1.0),
      'future': true,
    });

    final result = [...past.sublist(past.length - pastCount), ...future];
    return result;
  }

  static String _monthName(int month) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][month];
}

class _RunwayStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RunwayStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
        style: const TextStyle(fontFamily: 'DMSans',
            fontSize: 10, color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(value,
        style: TextStyle(
          fontFamily: 'DMMono', fontSize: 12,
          fontWeight: FontWeight.w600, color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        )),
    ]),
  );
}
