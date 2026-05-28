import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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

/// Accent gradient card (e.g. net-worth card, insight card)
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
    this.borderColor = const Color(0x337B6FFF),
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

/// Pill / badge widget
class ZTPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final String? prefixEmoji;

  const ZTPill({
    super.key,
    required this.label,
    required this.color,
    required this.bgColor,
    this.prefixEmoji,
  });

  const ZTPill.green({super.key, required this.label, this.prefixEmoji})
    : color = AppColors.green, bgColor = AppColors.greenSoft;

  const ZTPill.red({super.key, required this.label, this.prefixEmoji})
    : color = AppColors.red, bgColor = AppColors.redSoft;

  const ZTPill.amber({super.key, required this.label, this.prefixEmoji})
    : color = AppColors.amber, bgColor = AppColors.amberSoft;

  const ZTPill.accent({super.key, required this.label, this.prefixEmoji})
    : color = AppColors.accent2, bgColor = AppColors.accentSoft;

  const ZTPill.teal({super.key, required this.label, this.prefixEmoji})
    : color = AppColors.teal, bgColor = AppColors.tealSoft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefixEmoji != null) ...[
            Text(prefixEmoji!, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer loading placeholder
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg4,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
