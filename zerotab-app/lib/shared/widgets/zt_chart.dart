import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';

/// One data point in a categorical chart (donut / legend).
class ZtSeriesItem {
  final String label;
  final double value;
  final Color color;
  const ZtSeriesItem(this.label, this.value, this.color);
}

/// Donut chart for category / allocation breakdowns. Optional centre widget
/// (e.g. total amount). 5–7 slices read best; bucket the rest as "Other".
class ZtDonut extends StatelessWidget {
  final List<ZtSeriesItem> items;
  final double size;
  final Widget? center;
  const ZtDonut({
    super.key,
    required this.items,
    this.size = 160,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: size * 0.32,
          startDegreeOffset: -90,
          sections: [
            for (final it in items)
              PieChartSectionData(
                value: it.value <= 0 ? 0.0001 : it.value,
                color: it.color,
                radius: size * 0.16,
                showTitle: false,
              ),
          ],
        )),
        if (center != null) center!,
      ]),
    );
  }
}

/// Area / trend line (net worth, balance over time) with a gradient fill and
/// no chrome — premium and minimal.
class ZtAreaChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  const ZtAreaChart({
    super.key,
    required this.values,
    this.color = AppColors.accent,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);
    final spots = [
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])
    ];
    final minV = values.reduce((a, b) => a < b ? a : b);
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: minV * 0.96,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.32,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

/// A small dot + label legend entry for charts.
class ZtLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const ZtLegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
        ],
      );
}

/// Narrative caption under a chart — turns numbers into a one-line insight.
/// "Food: ₹847 — 23% over your average."
class ZtChartCaption extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const ZtChartCaption({
    super.key,
    required this.text,
    this.icon = Icons.auto_awesome_outlined,
    this.color = AppColors.teal,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 12,
                height: 1.4,
                color: AppColors.text2)),
      ),
    ]);
  }
}
