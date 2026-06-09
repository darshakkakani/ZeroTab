import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_motion.dart';

/// Standard ZeroTab card — bg3 background with 1px border.
class ZTCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double radius;
  final Border? border;

  const ZTCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = AppRadius.md,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.bg3,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.border, width: 1),
      ),
      child: child,
    );
  }
}

/// Accent gradient card (e.g. net-worth card, insight card).
/// Defaults align to the canonical hero gradient + accent border.
class ZTAccentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final List<Color> gradientColors;
  final Color borderColor;
  final double radius;

  const ZTAccentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradientColors = const [Color(0xFF16133A), Color(0xFF0E0C25)],
    this.borderColor = const Color(0x337B5FFF),
    this.radius = AppRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
  }
}

/// Pill / badge widget. Text-only (no emoji) — use ZtIcon for symbols.
class ZTPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const ZTPill({
    super.key,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  const ZTPill.green({super.key, required this.label})
      : color = AppColors.green, bgColor = AppColors.greenSoft;

  const ZTPill.red({super.key, required this.label})
      : color = AppColors.red, bgColor = AppColors.redSoft;

  const ZTPill.amber({super.key, required this.label})
      : color = AppColors.gold, bgColor = AppColors.goldSoft;

  const ZTPill.accent({super.key, required this.label})
      : color = AppColors.accent2, bgColor = AppColors.accentSoft;

  const ZTPill.teal({super.key, required this.label})
      : color = AppColors.teal, bgColor = AppColors.tealSoft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Animated shimmer placeholder. API unchanged (width/height/radius) so every
/// existing skeleton call site is upgraded to a real moving shimmer for free.
class ZTShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ZTShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.bg4,
      highlightColor: const Color(0xFF2C2A4A),
      period: AppMotion.shimmer,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.bg4,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
