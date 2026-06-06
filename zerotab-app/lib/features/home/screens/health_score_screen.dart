import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/zt_card.dart';

class HealthScoreScreen extends ConsumerWidget {
  const HealthScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(snapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Health Score'),
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text2),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error:   (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppColors.red))),
        data:    (snap) => _HealthBody(snapshot: snap),
      ),
    );
  }
}

class _HealthBody extends StatelessWidget {
  final FinancialSnapshotModel? snapshot;
  const _HealthBody({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;

    // Sub-scores mirror the weights used in FinancialSnapshotModel.healthScore
    // so the breakdown bars sum to the overall score consistently.
    final savingsScore = s != null
        ? (s.savingsRate >= 0.20 ? 100 : ((s.savingsRate / 0.20) * 100).clamp(0, 100).toInt())
        : 50;
    final emiScore = s != null
        ? ((1 - s.emiRatio / 0.40) * 100).clamp(0, 100).toInt()
        : 50;
    // Investment scored against 6 months of income target (income-relative, not bank-relative)
    final _targetInv = s != null && s.monthlyIncome > 0 ? s.monthlyIncome * 6.0 : 50000.0;
    final investScore = s != null
        ? (s.mfValue >= _targetInv ? 100 : (s.mfValue / _targetInv * 100).clamp(0, 100).toInt())
        : 20;
    final creditScore = s != null
        ? ((1 - s.creditUtil / 0.75) * 100).clamp(0, 100).toInt()
        : 50;
    final spendScore = s != null && s.monthlyIncome > 0
        ? ((1 - s.monthlySpend / s.monthlyIncome) * 100).clamp(0, 100).toInt()
        : 50;

    // Use the single authoritative score from the model
    final totalScore = s?.healthScore.toInt() ??
        ((savingsScore + emiScore + investScore + creditScore + spendScore) / 5).round();

    final scoreLabel = totalScore >= 75 ? 'Excellent — keep it up!'
                     : totalScore >= 55 ? 'Good — room to grow'
                     : totalScore >= 35 ? 'Fair — let\'s improve'
                     : 'Needs attention';

    final scoreColor = totalScore >= 75 ? AppColors.green
                     : totalScore >= 45 ? AppColors.amber
                     : AppColors.red;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Score gauge
          _ScoreGauge(score: totalScore, color: scoreColor),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20),
            ),
            child: Text(scoreLabel,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w500, color: scoreColor)),
          ),
          const SizedBox(height: 24),

          // Score breakdown
          ZTCard(
            child: Column(children: [
              _ScoreRow('Savings rate',      savingsScore, AppColors.green,
                  hint: s != null ? '${formatPct(s.savingsRate * 100)} of income saved' : ''),
              const Divider(color: AppColors.border, height: 16),
              _ScoreRow('EMI burden',        emiScore,     AppColors.amber,
                  hint: s != null ? '${formatPct(s.emiRatio * 100)} of income in EMIs' : ''),
              const Divider(color: AppColors.border, height: 16),
              _ScoreRow('Investment health', investScore,  AppColors.accent,
                  hint: s != null ? 'MF: ${formatInr(s.mfValue, compact: true)}' : ''),
              const Divider(color: AppColors.border, height: 16),
              _ScoreRow('Credit health',     creditScore,  AppColors.green,
                  hint: s != null ? '${formatPct(s.creditUtil * 100)} utilization' : ''),
              const Divider(color: AppColors.border, height: 16),
              _ScoreRow('Spend control',     spendScore,   spendScore < 40 ? AppColors.red : AppColors.amber,
                  hint: s != null && s.monthlyIncome > 0 ? 'Spend: ${formatPct((s.monthlySpend / s.monthlyIncome) * 100)} of income' : ''),
            ]),
          ),
          const SizedBox(height: 16),

          // Top improvement tip
          if (s != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.amber.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.gold),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top improvement',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                            fontWeight: FontWeight.w600, color: AppColors.amber)),
                      const SizedBox(height: 4),
                      Text(_topImprovementTip(s),
                        style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                            color: AppColors.text, height: 1.4)),
                    ],
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _topImprovementTip(FinancialSnapshotModel s) {
    if (s.creditUtil > 0.5) {
      return 'Reduce credit card utilization from ${formatPct(s.creditUtil * 100)} to below 30% to boost your credit health score significantly.';
    }
    if (s.mfValue < 10000 && s.bankBalance > 100000) {
      return 'You have ${formatInr(s.bankBalance, compact: true)} in savings but only ${formatInr(s.mfValue, compact: true)} invested. Start a ₹5,000/mo SIP to grow wealth faster than inflation.';
    }
    if (s.emiRatio > 0.4) {
      return 'Your EMI burden is ${formatPct(s.emiRatio * 100)} — above the healthy 40% threshold. Consider prepaying the highest-interest loan first.';
    }
    if (s.savingsRate < 0.15) {
      return 'Your savings rate is ${formatPct(s.savingsRate * 100)}. Aim for 20%+ by automating ₹${formatInr(s.monthlyIncome * 0.05, compact: true)}/mo directly to a SIP on salary day.';
    }
    return 'You\'re in good shape! Consider increasing your SIP by 10% this year — even ₹500 more/month compounds significantly over a decade.';
  }
}

class _ScoreGauge extends StatelessWidget {
  final int score;
  final Color color;
  const _ScoreGauge({required this.score, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
    SizedBox(
      width: 180, height: 120,
      child: CustomPaint(
        painter: _GaugePainter(score: score, color: color),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score', style: const TextStyle(fontFamily: 'DMSans', fontSize: 40,
                  fontWeight: FontWeight.w700, color: AppColors.text)),
              const Text('out of 100', style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
            ]),
          ),
        ),
      ),
    ),
  ]);
}

class _GaugePainter extends CustomPainter {
  final int score;
  final Color color;
  const _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height * 0.85, r = size.width * 0.44;
    final bgPaint = Paint()..color = AppColors.bg4..strokeWidth = 12..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fgPaint = Paint()..color = color..strokeWidth = 12..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), math.pi, math.pi, false, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), math.pi, math.pi * score / 100, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.score != score;
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final String hint;
  const _ScoreRow(this.label, this.score, this.color, {this.hint = ''});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.text))),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: score / 100, minHeight: 5,
                backgroundColor: AppColors.bg4, color: color),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 28, child: Text('$score',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600, color: color),
          textAlign: TextAlign.right)),
      ]),
      if (hint.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(hint, style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
      ],
    ],
  );
}
