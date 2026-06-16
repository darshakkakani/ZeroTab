// Pure-Dart technical indicators — fed into the chart as overlay series.
// All inputs are aligned to the chart's primary timeline; outputs use the
// same time keys so TradingView Lightweight Charts can render them in-place.

import 'chart_data_service.dart';

class IndicatorPoint {
  final int time;
  final double value;
  const IndicatorPoint(this.time, this.value);
  Map<String, dynamic> toJson() => {'time': time, 'value': value};
}

class Indicators {
  /// Simple Moving Average of `closes` over `period`. Output length matches
  /// input; positions before the warm-up window are omitted (NOT zero-padded).
  static List<IndicatorPoint> sma(List<Candle> bars, int period) {
    if (bars.length < period) return const [];
    final out = <IndicatorPoint>[];
    double sum = 0;
    for (int i = 0; i < bars.length; i++) {
      sum += bars[i].close;
      if (i >= period) sum -= bars[i - period].close;
      if (i >= period - 1) {
        out.add(IndicatorPoint(bars[i].timeSec, sum / period));
      }
    }
    return out;
  }

  /// Exponential Moving Average — α = 2/(period+1). Seeded with the
  /// period-window SMA, then standard recursive EMA from there.
  static List<IndicatorPoint> ema(List<Candle> bars, int period) {
    if (bars.length < period) return const [];
    final k = 2.0 / (period + 1);
    // Seed EMA with the first `period` SMA.
    double seed = 0;
    for (int i = 0; i < period; i++) seed += bars[i].close;
    seed /= period;
    final out = <IndicatorPoint>[
      IndicatorPoint(bars[period - 1].timeSec, seed),
    ];
    double prev = seed;
    for (int i = period; i < bars.length; i++) {
      prev = bars[i].close * k + prev * (1 - k);
      out.add(IndicatorPoint(bars[i].timeSec, prev));
    }
    return out;
  }

  /// RSI(period) using Wilder's smoothing (the textbook formula —
  /// matches what TradingView, Dhan, Groww display).
  static List<IndicatorPoint> rsi(List<Candle> bars, int period) {
    if (bars.length <= period) return const [];
    double avgGain = 0, avgLoss = 0;
    for (int i = 1; i <= period; i++) {
      final diff = bars[i].close - bars[i - 1].close;
      if (diff >= 0) avgGain += diff; else avgLoss -= diff;
    }
    avgGain /= period;
    avgLoss /= period;
    final out = <IndicatorPoint>[];
    double rs = avgLoss == 0 ? double.infinity : avgGain / avgLoss;
    out.add(IndicatorPoint(bars[period].timeSec,
        100 - 100 / (1 + (rs.isFinite ? rs : 1e9))));
    for (int i = period + 1; i < bars.length; i++) {
      final diff = bars[i].close - bars[i - 1].close;
      final gain = diff > 0 ? diff : 0.0;
      final loss = diff < 0 ? -diff : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
      rs = avgLoss == 0 ? double.infinity : avgGain / avgLoss;
      out.add(IndicatorPoint(bars[i].timeSec,
          100 - 100 / (1 + (rs.isFinite ? rs : 1e9))));
    }
    return out;
  }
}
