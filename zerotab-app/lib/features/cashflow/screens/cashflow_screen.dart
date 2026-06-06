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
