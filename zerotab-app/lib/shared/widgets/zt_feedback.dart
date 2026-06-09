import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'zt_buttons.dart';

/// Bottom-sheet shell — consistent grabber, rounded surface, safe-area, keyboard
/// inset handling. Use: `showZtSheet(context, child: ...)`.
Future<T?> showZtSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => ZtSheetContainer(child: child),
  );
}

class ZtSheetContainer extends StatelessWidget {
  final Widget child;
  const ZtSheetContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg2,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
          border: Border(
            top: BorderSide(color: AppColors.border2),
            left: BorderSide(color: AppColors.border2),
            right: BorderSide(color: AppColors.border2),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Themed confirm dialog (replaces generic Material AlertDialog). Returns
/// true on confirm, false/null on cancel.
Future<bool?> showZtDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (destructive ? AppColors.red : AppColors.accent)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: destructive ? AppColors.red : AppColors.accent,
                    size: 22),
              ),
              const SizedBox(height: 14),
            ],
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
                    color: AppColors.text2)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: ZtButton(
                  label: cancelLabel,
                  style: ZtButtonStyle.ghost,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ZtButton(
                  label: confirmLabel,
                  color: destructive ? AppColors.red : AppColors.accent,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}

/// Themed switch — brand colours, no track outline.
class ZtSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const ZtSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.text3),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.bg4),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    );
  }
}

/// Themed toast (replaces ad-hoc SnackBars) — floating bordered pill.
void showZtToast(BuildContext context, String message,
    {IconData? icon, Color? accent}) {
  final c = accent ?? AppColors.accent;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppColors.bg4,
    elevation: 0,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: const BorderSide(color: AppColors.border2),
    ),
    content: Row(children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(message,
            style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text)),
      ),
    ]),
  ));
}
