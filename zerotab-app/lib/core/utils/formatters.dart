import 'package:intl/intl.dart';

/// Formats a number as Indian rupee currency: ₹18,43,720
String formatInr(num amount, {bool compact = false}) {
  if (compact) {
    if (amount.abs() >= 10000000) return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount.abs() >= 100000)   return '₹${(amount / 100000).toStringAsFixed(1)}L';
    if (amount.abs() >= 1000)     return '₹${(amount / 1000).toStringAsFixed(1)}K';
  }
  final formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  return formatter.format(amount);
}

/// +₹23,450 or -₹5,000
String formatInrDelta(num amount) {
  final prefix = amount >= 0 ? '+' : '';
  return '$prefix${formatInr(amount)}';
}

/// Format percentage: 38.2%
String formatPct(double value, {int decimals = 1}) =>
    '${value.toStringAsFixed(decimals)}%';

/// Format date: 18 May
String formatDate(DateTime date) =>
    DateFormat('d MMM').format(date);

/// Format date: 18 May 2025
String formatDateFull(DateTime date) =>
    DateFormat('d MMM yyyy').format(date);

/// Format month label: May 2025
String formatMonth(DateTime date) =>
    DateFormat('MMM yyyy').format(date);

/// Parse date string (yyyy-MM-dd)
DateTime parseDate(String s) => DateTime.parse(s);

/// Category display names (short labels used across all screens)
String categoryDisplayName(String cat) {
  const map = {
    'food_delivery':  'Food',
    'dining':         'Dining',
    'grocery':        'Grocery',
    'shopping':       'Shopping',
    'subscriptions':  'Subscriptions',
    'transport':      'Transport',
    'travel':         'Travel',
    'health':         'Health',
    'utilities':      'Utilities',
    'investments':    'Investments',
    'investment':     'Investment',
    'emi':            'EMI',
    'income':         'Income',
    'education':      'Education',
    'housing':        'Housing',
    'fuel':           'Fuel',
    'insurance':      'Insurance',
    'entertainment':  'Entertainment',
    'others':         'Others',
  };
  return map[cat] ?? (cat.isNotEmpty ? cat[0].toUpperCase() + cat.substring(1) : cat);
}

// categoryEmoji removed — replaced by SVG icon painters per category in UI layer
