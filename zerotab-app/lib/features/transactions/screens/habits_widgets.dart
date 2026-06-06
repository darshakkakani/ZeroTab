// Habit model and Budget Brain / Money Habits widgets
// These are imported by transactions_screen.dart

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';

// ── Category color helper (duplicated here for independence) ──
Color _catColor(String cat) {
  const map = {
    'food_delivery': AppColors.coral,
    'grocery':       AppColors.green,
    'shopping':      AppColors.accent,
    'emi':           AppColors.gold,
    'fuel':          AppColors.amber,
    'utilities':     AppColors.accent2,
    'transport':     AppColors.teal,
    'entertainment': Color(0xFFFF6B9D),
    'health':        AppColors.teal,
    'investment':    AppColors.green,
    'subscriptions': AppColors.green,
    'insurance':     AppColors.gold,
    'income':        AppColors.green,
    'others':        AppColors.text3,
  };
  return map[cat] ?? AppColors.text3;
}

// ════════════════════════════════════════════════════════════════
//  Habit model
// ════════════════════════════════════════════════════════════════

class SpendHabit {
  final String name;
  final int    count;
  final double total;
  final String category;
  const SpendHabit({required this.name, required this.count,
      required this.total, required this.category});

  SpendHabit copyWith({int? count, double? total}) => SpendHabit(
    name: name, category: category,
    count: count ?? this.count,
    total: total ?? this.total,
  );

  double get annualCost => total * 12;
}

// ════════════════════════════════════════════════════════════════
//  Budget Brain Card
// ════════════════════════════════════════════════════════════════

class BudgetBrainCard extends StatelessWidget {
  final FinancialSnapshotModel? snapshot;
  final VoidCallback onImport;
  final bool         importing;
  const BudgetBrainCard({
    super.key,
    required this.snapshot,
    required this.onImport,
    required this.importing,
  });

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    if (snap == null || snap.monthlyIncome <= 0) {
      return _buildImportOnlyCard(context);
    }

    final now         = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed  = now.day.clamp(1, daysInMonth);
    final monthFrac   = daysPassed / daysInMonth;

    final income      = snap.monthlyIncome;
    final spent       = snap.monthlySpend;
    final emiFixed    = income * snap.emiRatio;
    final budget      = (income - emiFixed).clamp(0.0, income);
    final freeLeft    = (budget - spent).clamp(0.0, budget);
    final burnRate    = daysPassed > 0 ? spent / daysPassed : 0.0;
    final projected   = burnRate * daysInMonth;
    final onTrack     = projected <= budget;
    final projFree    = (budget - projected).clamp(0.0, budget);

    final accent = onTrack ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.09), const Color(0xFF0C0A1E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FREELY SPENDABLE',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5,
                  color: accent.withValues(alpha: 0.80))),
            const SizedBox(height: 4),
            Text(formatInr(freeLeft, compact: true),
              style: TextStyle(fontFamily: 'DMMono', fontSize: 26,
                  fontWeight: FontWeight.w800, color: accent, letterSpacing: -1.0)),
            const SizedBox(height: 2),
            Text(
              onTrack
                ? 'On track — save ${formatInr(projFree, compact: true)} by month-end'
                : 'Over pace — projected overspend ${formatInr((projected - budget).abs(), compact: true)}',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                  color: accent.withValues(alpha: 0.80))),
          ])),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: importing ? null : onImport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
              ),
              child: importing
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent2))
                : const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.upload_file_rounded, size: 16, color: AppColors.accent2),
                    SizedBox(height: 3),
                    Text('Import\nStatement', textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 8.5,
                          fontWeight: FontWeight.w600, color: AppColors.accent2, height: 1.3)),
                  ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Day $daysPassed of $daysInMonth',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9.5, color: AppColors.text3)),
          Text('${formatInr(burnRate, compact: true)}/day burn',
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5, color: AppColors.text3)),
        ]),
        const SizedBox(height: 5),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (spent / (budget + 1)).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.bg4,
              color: accent,
            ),
          ),
          Positioned(
            left: (monthFrac * (MediaQuery.of(context).size.width - 72)).clamp(0, double.infinity),
            top: 0, bottom: 0,
            child: Container(width: 2, color: AppColors.text2),
          ),
        ]),
        const SizedBox(height: 5),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Spent ${formatInr(spent, compact: true)}',
            style: TextStyle(fontFamily: 'DMMono', fontSize: 9.5, color: accent)),
          Text('Budget ${formatInr(budget, compact: true)}',
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5, color: AppColors.text3)),
        ]),
      ]),
    );
  }

  Widget _buildImportOnlyCard(BuildContext context) => GestureDetector(
    onTap: onImport,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: importing
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent2))
            : const Icon(Icons.upload_file_rounded, color: AppColors.accent2, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Import Bank Statement',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.text)),
          SizedBox(height: 2),
          Text('PDF from HDFC, SBI, ICICI, Axis, Kotak',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.text3),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
//  Money Habits Strip
// ════════════════════════════════════════════════════════════════

class MoneyHabitsStrip extends StatelessWidget {
  final List<SpendHabit> habits;
  final bool             expanded;
  final VoidCallback     onToggle;
  const MoneyHabitsStrip({
    super.key,
    required this.habits,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final top3 = habits.take(3).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('MONEY HABITS',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 0.4,
                    color: AppColors.text3)),
              const Spacer(),
              Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14, color: AppColors.text3),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(color: AppColors.border, height: 1),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: top3.length,
              itemBuilder: (_, i) => _HabitChip(habit: top3[i]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _HabitChip extends StatelessWidget {
  final SpendHabit habit;
  const _HabitChip({required this.habit});

  @override
  Widget build(BuildContext context) {
    final color = _catColor(habit.category);
    return Container(
      width: 138,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Expanded(child: Text(habit.name,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                fontWeight: FontWeight.w600, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 5),
        Text(formatInr(habit.total, compact: true),
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 13,
              fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 1),
        Text('${habit.count}× this period',
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: AppColors.text3)),
        Text('≈ ${formatInr(habit.annualCost, compact: true)}/yr',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: color.withValues(alpha: 0.70), fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
