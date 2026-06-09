import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

/// Section header — title + optional leading icon + optional trailing action
/// ("See all →"). Sits above a card/list section.
class ZtSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final Color iconColor;
  const ZtSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.iconColor = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: AppColors.text)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              Text(actionLabel!,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent2)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.accent2),
            ]),
          ),
      ],
    );
  }
}

/// Screen header — a consistent custom app bar (replaces the generic Material
/// AppBar): back chevron + title + optional trailing widget.
class ZtScreenHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool showBack;
  const ZtScreenHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
      child: Row(children: [
        if (showBack) ...[
          GestureDetector(
            onTap: onBack ?? () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: AppColors.text2),
            ),
          ),
          const SizedBox(width: 2),
        ],
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.text)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
