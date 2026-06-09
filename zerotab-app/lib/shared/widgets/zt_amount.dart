import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/formatters.dart';

/// ZtAmount — the canonical way to render a rupee amount anywhere in the app.
/// Always tabular + lining figures (digits never shift width). Optionally
/// colour-codes by sign (green ≥0 / red <0) and shows an explicit + sign.
class ZtAmount extends StatelessWidget {
  final num amount;
  final double size;
  final FontWeight weight;
  final Color? color;      // explicit colour overrides sign colouring
  final bool compact;      // ₹1.2L / ₹3.4Cr
  final bool signed;       // prefix '+' for positives
  final bool colorBySign;  // green when ≥0, red when <0

  const ZtAmount(
    this.amount, {
    super.key,
    this.size = 15,
    this.weight = FontWeight.w600,
    this.color,
    this.compact = false,
    this.signed = false,
    this.colorBySign = false,
  });

  @override
  Widget build(BuildContext context) {
    final neg = amount < 0;
    final base = formatInr(amount.abs(), compact: compact);
    final prefix = neg ? '-' : (signed ? '+' : '');
    final c = color ??
        (colorBySign ? (neg ? AppColors.red : AppColors.green) : AppColors.text);
    return Text(
      '$prefix$base',
      style: context.money(fontSize: size, weight: weight, color: c),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// AnimatedZtAmount — counts up/down to [amount] on first build and whenever the
/// value changes. Use for hero numbers (net worth, balances) — the "live" feel.
class AnimatedZtAmount extends StatelessWidget {
  final num amount;
  final double size;
  final FontWeight weight;
  final Color? color;
  final bool compact;
  final bool colorBySign;

  const AnimatedZtAmount(
    this.amount, {
    super.key,
    this.size = 34,
    this.weight = FontWeight.w700,
    this.color,
    this.compact = false,
    this.colorBySign = false,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount.toDouble()),
      duration: AppMotion.count,
      curve: AppMotion.standard,
      builder: (context, value, _) => ZtAmount(
        value,
        size: size,
        weight: weight,
        color: color,
        compact: compact,
        colorBySign: colorBySign,
      ),
    );
  }
}
