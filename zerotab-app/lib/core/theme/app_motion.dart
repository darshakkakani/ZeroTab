import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion tokens — one place for every duration & curve so the whole app
/// animates with a single, consistent rhythm. Use these instead of inline
/// `Duration(milliseconds: ...)` literals.
class AppMotion {
  AppMotion._();

  // ── Durations ──
  static const Duration fast    = Duration(milliseconds: 120); // taps, toggles
  static const Duration base    = Duration(milliseconds: 220); // most transitions
  static const Duration slow    = Duration(milliseconds: 360); // sheets, hero moves
  static const Duration count   = Duration(milliseconds: 700); // number count-up
  static const Duration shimmer = Duration(milliseconds: 1400); // skeleton loop

  // ── Curves ──
  static const Curve standard   = Curves.easeOutCubic;   // default ease
  static const Curve emphasized = Curves.easeOutQuart;   // hero / large moves
  static const Curve spring     = Curves.easeOutBack;    // gentle overshoot
  static const Curve decel      = Curves.fastOutSlowIn;  // material decel
}

/// Haptics — reserved for *meaningful* financial moments (settling a balance,
/// hitting a goal, crossing a milestone), never routine list taps. Wrapping the
/// platform channel here keeps call sites readable and lets us tune globally.
class Haptics {
  Haptics._();

  /// Light tick — selection, chip, toggle.
  static void light() => HapticFeedback.selectionClick();

  /// Medium — a primary action confirmed (settle, save, add).
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy — a celebratory milestone (goal reached, all settled up).
  static void heavy() => HapticFeedback.heavyImpact();
}
