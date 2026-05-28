import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';

class SparklineChart extends StatelessWidget {
  final double height;
  const SparklineChart({super.key, this.height = 48});

  // Mock 30-day sparkline data — replace with real data from API
  static const _data = [
    16.2, 16.5, 16.1, 16.8, 17.0, 16.9, 17.2, 17.5, 17.3, 17.8,
    18.0, 17.7, 18.2, 18.5, 18.1, 18.4, 18.7, 18.3, 18.6, 18.9,
    18.5, 18.8, 19.1, 18.7, 19.0, 19.3, 18.9, 19.2, 19.5, 18.4,
  ];

  @override
  Widget build(BuildContext context) {
    final spots = List.generate(
      _data.length,
      (i) => FlSpot(i.toDouble(), _data[i]),
    );

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData:       const FlGridData(show: false),
          titlesData:     const FlTitlesData(show: false),
          borderData:     FlBorderData(show: false),
          lineTouchData:  const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots:        spots,
              isCurved:     true,
              curveSmoothness: 0.35,
              color:        AppColors.accent.withOpacity(0.8),
              barWidth:     2,
              dotData:      const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [
                    AppColors.accent.withOpacity(0.15),
                    AppColors.accent.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
