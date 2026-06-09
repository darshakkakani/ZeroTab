import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'zt_amount.dart';

/// A rounded-square icon in a soft tinted container — the standard "leading"
/// for list rows, section headers and tiles.
class ZtIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;      // container size
  final double iconSize;
  final double radius;
  const ZtIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 18,
    this.radius = AppRadius.md,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: iconSize, color: color),
      );
}

/// The canonical list / transaction row:
/// leading badge → title + subtitle → right-aligned tabular amount + caption,
/// with optional tap & chevron. Use everywhere a row of "thing + value" appears.
class ZtListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final num? amount;
  final bool amountColorBySign;
  final bool amountSigned;
  final bool amountCompact;
  final String? trailingCaption;
  final Widget? trailing; // custom trailing overrides the amount column
  final VoidCallback? onTap;
  final bool showChevron;
  final EdgeInsetsGeometry padding;

  const ZtListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.amount,
    this.amountColorBySign = false,
    this.amountSigned = false,
    this.amountCompact = false,
    this.trailingCaption,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          color: AppColors.text3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (trailing != null)
            trailing!
          else if (amount != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                ZtAmount(amount!,
                    size: 14,
                    weight: FontWeight.w700,
                    compact: amountCompact,
                    signed: amountSigned,
                    colorBySign: amountColorBySign),
                if (trailingCaption != null) ...[
                  const SizedBox(height: 2),
                  Text(trailingCaption!,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 11,
                          color: AppColors.text3)),
                ],
              ],
            ),
          if (showChevron) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.text3),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: row,
    );
  }
}
