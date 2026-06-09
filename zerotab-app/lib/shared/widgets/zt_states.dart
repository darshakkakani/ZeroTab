import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'zt_buttons.dart';

/// Reusable frosted-glass surface. Use SURGICALLY (bottom nav, hero overlay,
/// sheet header) — never as an ambient full-screen layer.
class ZtGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Color tint;
  const ZtGlass({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.06,
    this.borderRadius,
    this.tint = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(AppRadius.xl);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: opacity),
            borderRadius: br,
            border: Border.all(color: AppColors.border2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Empty state — line icon, title, message, single CTA. Earns trust instead of
/// presenting a blank screen.
class ZtEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final IconData? ctaIcon;
  final Color accent;
  const ZtEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.ctaLabel,
    this.onCta,
    this.ctaIcon = Icons.add_rounded,
    this.accent = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.20)),
              ),
              child: Icon(icon, size: 30, color: accent),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.text3)),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 22),
              ZtButton(
                label: ctaLabel!,
                onPressed: onCta,
                expand: false,
                icon: ctaIcon,
                color: accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Monogram avatar with a deterministic brand gradient (replaces emoji avatars).
class ZtAvatar extends StatelessWidget {
  final String name;
  final double size;
  final int gradientIndex; // -1 → derive deterministically from the name
  const ZtAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.gradientIndex = -1,
  });

  static const List<List<Color>> gradients = [
    [Color(0xFF9B7FFF), Color(0xFF5A3FCC)], // violet
    [Color(0xFF00C4A8), Color(0xFF0B7E6E)], // teal
    [Color(0xFFE8A422), Color(0xFFB47712)], // gold
    [Color(0xFFFF6B5B), Color(0xFFC2453A)], // coral
    [Color(0xFF4F9DF7), Color(0xFF2E63B0)], // blue
    [Color(0xFF1EBF7A), Color(0xFF128253)], // green
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'U';
    final idx = gradientIndex >= 0
        ? gradientIndex % gradients.length
        : letter.codeUnitAt(0) % gradients.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradients[idx],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}
