import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ZtIcons — the single source of truth for iconography.
///
/// Every category / group / status icon resolves through here so that
/// (a) an emoji is NEVER used as an icon, and (b) the visual family stays
/// consistent. We use Material's *outlined* set (clean line-art) for content
/// icons; bespoke brand marks (bottom-nav glyphs, the AI orb) remain custom
/// painters in their own files.
class ZtIcons {
  ZtIcons._();

  /// Transaction / spend category → line icon.
  static IconData category(String cat) {
    switch (cat.toLowerCase()) {
      case 'food_delivery':
      case 'food':          return Icons.fastfood_outlined;
      case 'dining':        return Icons.restaurant_outlined;
      case 'grocery':       return Icons.shopping_cart_outlined;
      case 'shopping':      return Icons.shopping_bag_outlined;
      case 'subscriptions': return Icons.subscriptions_outlined;
      case 'transport':     return Icons.directions_bus_outlined;
      case 'travel':        return Icons.flight_takeoff_outlined;
      case 'health':        return Icons.favorite_border;
      case 'utilities':     return Icons.lightbulb_outline;
      case 'investments':
      case 'investment':    return Icons.insights_outlined;
      case 'emi':           return Icons.account_balance_outlined;
      case 'income':        return Icons.payments_outlined;
      case 'education':     return Icons.school_outlined;
      case 'housing':       return Icons.home_outlined;
      case 'fuel':          return Icons.local_gas_station_outlined;
      case 'insurance':     return Icons.shield_outlined;
      case 'entertainment': return Icons.movie_outlined;
      case 'others':
      default:              return Icons.category_outlined;
    }
  }

  /// A stable accent colour per category (from the harmonious palette) so the
  /// same category always reads the same colour across every screen.
  static Color categoryColor(String cat) {
    const map = <String, Color>{
      'food_delivery': AppColors.gold,   'food': AppColors.gold,
      'dining':        AppColors.coral,
      'grocery':       AppColors.green,
      'shopping':      AppColors.accent,
      'subscriptions': AppColors.dataETF,
      'transport':     AppColors.teal,
      'travel':        AppColors.dataETF,
      'health':        AppColors.coral,
      'utilities':     AppColors.gold,
      'investments':   AppColors.teal,   'investment': AppColors.teal,
      'emi':           AppColors.dataOther,
      'income':        AppColors.green,
      'education':     AppColors.accent,
      'housing':       AppColors.accent2,
      'fuel':          AppColors.gold,
      'insurance':     AppColors.teal,
      'entertainment': AppColors.coral,
    };
    return map[cat.toLowerCase()] ?? AppColors.dataOther;
  }

  /// SettleUp group type → line icon (replaces ✈️🏠💑🍕💼).
  static IconData groupType(String type) {
    switch (type.toLowerCase()) {
      case 'trip':
      case 'travel':    return Icons.flight_takeoff_outlined;
      case 'flatmates':
      case 'home':
      case 'apartment': return Icons.home_outlined;
      case 'couple':    return Icons.favorite_border;
      case 'dining':
      case 'food':      return Icons.restaurant_outlined;
      case 'office':
      case 'work':      return Icons.work_outline;
      case 'event':
      case 'party':     return Icons.celebration_outlined;
      default:          return Icons.groups_outlined;
    }
  }
}

/// ZtIcon — renders an icon with a consistent default size & themed colour.
class ZtIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const ZtIcon(this.icon, {super.key, this.size = 18, this.color});

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size, color: color ?? AppColors.text2);
}
