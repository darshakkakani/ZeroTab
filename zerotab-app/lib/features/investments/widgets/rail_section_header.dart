// RailSectionHeader — premium Discover-rail section header.
//
// Replaces the inline header rendered inside the old `_Section` widget.
// Lighter visual signature than the previous implementation:
//
//   • 28 dp tinted icon badge (per-section tint, NO new color tokens)
//   • Title (15 sp, w700, slightly tightened tracking)
//   • Count chip ("8" tabular figures)
//   • Right-aligned "See all" link with chevron
//
// No divider line — the 24 dp top padding does the visual separation. This
// is deliberately the single biggest "feels premium" change in the redesign.
//
// Section-header slide-in animation (one-shot, 320 ms on mount): the title
// and badge slide 8 dp from the left while fading in. Respects "Reduce
// Motion" — snaps to final state when MediaQuery.disableAnimations is true.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class RailSectionHeader extends StatefulWidget {
  /// Section title (e.g. "Trending in India").
  final String title;

  /// Material icon for the tinted badge.
  final IconData icon;

  /// Foreground colour of the icon (also informs `tintBg = fg × 10% opacity`
  /// unless `tintBg` is supplied explicitly).
  final Color tintFg;

  /// Optional override for the badge background. Defaults to
  /// `tintFg.withOpacity(0.10)`.
  final Color? tintBg;

  /// Item count for the chip ("8"). Pass `null` for the rail-loading state —
  /// the chip renders an em dash ("—") instead.
  final int? count;

  /// Tap handler for "See all" — `null` hides the button entirely.
  final VoidCallback? onSeeAll;

  /// Optional flag emoji to replace the icon badge (e.g. country flags for
  /// region rails). When supplied, `icon`/`tintFg` are ignored and the flag
  /// is wrapped in the same 28 dp soft-bg badge.
  final String? flagEmoji;

  const RailSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.tintFg,
    this.tintBg,
    this.count,
    this.onSeeAll,
    this.flagEmoji,
  });

  @override
  State<RailSectionHeader> createState() => _RailSectionHeaderState();
}

class _RailSectionHeaderState extends State<RailSectionHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tintBg = widget.tintBg ?? widget.tintFg.withOpacity(0.10);

    Widget badge;
    if (widget.flagEmoji != null) {
      badge = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bg3,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(widget.flagEmoji!,
            style: const TextStyle(fontSize: 14, height: 1.0)),
      );
    } else {
      badge = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tintBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(widget.icon, size: 16, color: widget.tintFg),
      );
    }

    final countLabel = widget.count == null ? '—' : '${widget.count}';

    final leftGroup = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        badge,
        const SizedBox(width: 8),
        Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: -0.1,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            countLabel,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.0,
            ),
          ),
        ),
      ],
    );

    final rightGroup = (widget.onSeeAll == null || widget.count == null)
        ? const SizedBox.shrink()
        : TextButton(
            onPressed: widget.onSeeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.accent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('See all',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    )),
                Icon(Icons.chevron_right_rounded,
                    size: 14, color: AppColors.accent),
              ],
            ),
          );

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: leftGroup),
          rightGroup,
        ],
      ),
    );

    if (reduceMotion) return row;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * -8, 0),
            child: child,
          ),
        );
      },
      child: row,
    );
  }
}
