import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_motion.dart';

enum ZtButtonStyle { filled, tonal, ghost }

/// Primary button with idle → pressed (scale) → loading states + a light haptic.
class ZtButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final ZtButtonStyle style;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final Color? color;
  const ZtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = ZtButtonStyle.filled,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color,
  });

  @override
  State<ZtButton> createState() => _ZtButtonState();
}

class _ZtButtonState extends State<ZtButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? AppColors.accent;
    final enabled = widget.onPressed != null && !widget.loading;

    late final Color bg;
    late final Color fg;
    Border? border;
    switch (widget.style) {
      case ZtButtonStyle.filled:
        bg = accent;
        fg = Colors.white;
        break;
      case ZtButtonStyle.tonal:
        bg = accent.withValues(alpha: 0.14);
        fg = accent;
        break;
      case ZtButtonStyle.ghost:
        bg = Colors.transparent;
        fg = AppColors.text;
        border = Border.all(color: AppColors.border2);
        break;
    }

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              Haptics.light();
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: AppMotion.fast,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: AppMotion.fast,
          child: Container(
            width: widget.expand ? double.infinity : null,
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: border,
            ),
            child: widget.loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Text(widget.label,
                          style: TextStyle(
                              fontFamily: 'DMSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: fg)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Filter / choice chip.
class ZtChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const ZtChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              Haptics.light();
              onTap!();
            },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.bg3,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14, color: selected ? Colors.white : AppColors.text2),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.text2)),
        ]),
      ),
    );
  }
}

/// Segmented control (period selector / 2–4 mutually-exclusive options).
class ZtSegmented extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const ZtSegmented({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: List.generate(segments.length, (i) {
        final sel = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              Haptics.light();
              onChanged(i);
            },
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(segments[i],
                  style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.text2)),
            ),
          ),
        );
      })),
    );
  }
}
