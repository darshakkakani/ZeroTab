// ════════════════════════════════════════════════════════════════
//  ZeroTab Spend Intelligence — All-in-One Finance Companion
//
//  Features built:
//  1. Budget Brain        — Freely spendable money + pace bar
//  2. Envelope Budgets    — YNAB-style category budget tracking
//  3. Split Expense       — Splitwise-like friend expense splitting
//  4. Subscription Radar  — Auto-detect recurring payments
//  5. Money Habits        — Merchant-level pattern detection
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';

// ── Category color ────────────────────────────────────────────
Color catColor(String cat) {
  const map = <String, Color>{
    'food_delivery': AppColors.coral,
    'grocery':       AppColors.green,
    'shopping':      AppColors.accent,
    'emi':           AppColors.gold,
    'fuel':          AppColors.amber,
    'utilities':     AppColors.accent2,
    'transport':     AppColors.teal,
    'entertainment': Color(0xFFFF6B9D),
    'health':        Color(0xFF22C55E),
    'investment':    Color(0xFF22C55E),
    'subscriptions': Color(0xFF7B2FFE),
    'insurance':     AppColors.gold,
    'income':        Color(0xFF22C55E),
    'others':        AppColors.text3,
  };
  return map[cat] ?? AppColors.text3;
}

String catEmoji(String cat) {
  const map = <String, String>{
    'food_delivery': 'Food', 'grocery': 'Grocery', 'shopping': 'Shopping',
    'emi': 'EMI', 'fuel': 'Fuel', 'utilities': 'Bills',
    'transport': 'Travel', 'entertainment': 'Fun', 'health': 'Health',
    'investment': 'Invest', 'subscriptions': 'Subs', 'insurance': 'Insurance',
    'others': 'Others',
  };
  return map[cat] ?? cat;
}

// ════════════════════════════════════════════════════════════════
//  Models
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
    count: count ?? this.count, total: total ?? this.total);
  double get annualCost => total * 12;
}

class SplitEntry {
  final String id;
  final String friendName;
  final double amount;
  final String description;
  final String date;
  final bool   youOwe; // true = you owe them, false = they owe you
  const SplitEntry({required this.id, required this.friendName,
      required this.amount, required this.description,
      required this.date, required this.youOwe});

  Map<String, dynamic> toJson() => {
    'id': id, 'friendName': friendName, 'amount': amount,
    'description': description, 'date': date, 'youOwe': youOwe,
  };
  factory SplitEntry.fromJson(Map<String, dynamic> j) => SplitEntry(
    id: j['id'], friendName: j['friendName'],
    amount: (j['amount'] as num).toDouble(),
    description: j['description'], date: j['date'], youOwe: j['youOwe'],
  );
}

// ════════════════════════════════════════════════════════════════
//  1. BUDGET BRAIN — Fixed: handles income=0 gracefully
// ════════════════════════════════════════════════════════════════

class BudgetBrainCard extends StatelessWidget {
  final FinancialSnapshotModel? snapshot;
  final VoidCallback onImport;
  final bool         importing;
  final List<TransactionModel> txns; // current period txns for live calc

  const BudgetBrainCard({
    super.key,
    required this.snapshot,
    required this.onImport,
    required this.importing,
    this.txns = const [],
  });

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;

    // ── No income data: show helpful setup prompt ───────────────
    if (snap == null || snap.monthlyIncome <= 0) {
      return _NoIncomeCard(onImport: onImport, importing: importing);
    }

    final now          = DateTime.now();
    final daysInMonth  = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed   = now.day.clamp(1, daysInMonth);
    final monthFrac    = daysPassed / daysInMonth;

    final income       = snap.monthlyIncome;

    // Fixed commitments = EMI ratio × income (rent, EMIs, SIPs)
    final fixedCommit  = income * snap.emiRatio;

    // Use live txn spend if available, else snapshot spend
    final spent = txns.isNotEmpty
        ? txns.where((t) => t.isDebit).fold(0.0, (s, t) => s + t.amount)
        : snap.monthlySpend;

    // Discretionary budget = income - fixed commitments
    final budget   = (income - fixedCommit).clamp(1.0, income);
    final freeLeft = (budget - spent).clamp(0.0, budget);

    // Burn rate & projection
    final burnRate  = daysPassed > 0 ? spent / daysPassed : 0.0;
    final projected = burnRate * daysInMonth;
    final onTrack   = projected <= budget;

    // Progress fraction (how much of budget is spent)
    final spendFrac = (spent / budget).clamp(0.0, 1.0);

    // Color: green until 80%, amber 80-100%, red above 100%
    final Color accent;
    if (spendFrac < 0.80)      accent = const Color(0xFF22C55E);
    else if (spendFrac < 1.0)  accent = const Color(0xFFF59E0B);
    else                       accent = const Color(0xFFEF4444);

    // Days remaining until money runs out at current pace
    final daysLeft = burnRate > 0 ? (freeLeft / burnRate).floor() : 99;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.10), const Color(0xFF0C0A1E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Row 1: Free money + Import ──────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FREELY SPENDABLE',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5,
                  color: accent.withValues(alpha: 0.80))),
            const SizedBox(height: 3),
            Text(formatInr(freeLeft, compact: true),
              style: TextStyle(fontFamily: 'DMMono', fontSize: 26,
                  fontWeight: FontWeight.w800, color: accent, letterSpacing: -1.0)),
            const SizedBox(height: 2),
            Text(
              onTrack
                ? 'On track · ${formatInr(burnRate, compact: true)}/day · ${daysLeft}d left'
                : 'Over pace · projected overspend ${formatInr((projected - budget).abs(), compact: true)}',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  color: accent.withValues(alpha: 0.80))),
          ])),
          const SizedBox(width: 10),
          _ImportBtn(onImport: onImport, importing: importing),
        ]),

        const SizedBox(height: 12),

        // ── Row 2: 3 stat chips ─────────────────────────────────
        Row(children: [
          _MiniStat('Income', formatInr(income, compact: true), const Color(0xFF22C55E)),
          const SizedBox(width: 6),
          _MiniStat('Fixed', formatInr(fixedCommit, compact: true), const Color(0xFFF59E0B)),
          const SizedBox(width: 6),
          _MiniStat('Spent', formatInr(spent, compact: true), const Color(0xFFEF4444)),
        ]),

        const SizedBox(height: 10),

        // ── Row 3: Day progress bar ─────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Day $daysPassed / $daysInMonth',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
                color: AppColors.text3)),
          Text('${(spendFrac * 100).toStringAsFixed(0)}% of budget used',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
                color: AppColors.text3)),
        ]),
        const SizedBox(height: 4),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: spendFrac, minHeight: 7,
              backgroundColor: AppColors.bg4,
              color: accent,
            ),
          ),
          // Day-of-month marker
          Positioned(
            left: (monthFrac * (MediaQuery.of(context).size.width - 72))
                .clamp(0.0, double.infinity),
            top: 0, bottom: 0,
            child: Container(width: 2, color: Colors.white54),
          ),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(formatInr(spent, compact: true),
            style: TextStyle(fontFamily: 'DMMono', fontSize: 9, color: accent)),
          Text(formatInr(budget, compact: true),
            style: const TextStyle(fontFamily: 'DMMono', fontSize: 9, color: AppColors.text3)),
        ]),
      ]),
    );
  }
}

class _NoIncomeCard extends StatelessWidget {
  final VoidCallback onImport;
  final bool         importing;
  const _NoIncomeCard({required this.onImport, required this.importing});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      border: Border.all(color: const Color(0xFF7B2FFE).withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF7B2FFE).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.psychology_outlined, color: Color(0xFF7B2FFE), size: 22),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Budget Brain needs income data',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
              fontWeight: FontWeight.w600, color: AppColors.text)),
        SizedBox(height: 2),
        Text('Add a salary transaction (income type) to unlock real-time budget tracking.',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
              color: AppColors.text3, height: 1.4)),
      ])),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onImport,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF7B2FFE).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: importing
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7B2FFE)))
            : const Icon(Icons.upload_file_rounded, size: 16, color: Color(0xFF7B2FFE)),
        ),
      ),
    ]),
  );
}

class _ImportBtn extends StatelessWidget {
  final VoidCallback onImport;
  final bool         importing;
  const _ImportBtn({required this.onImport, required this.importing});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: importing ? null : onImport,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: importing
        ? const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent2))
        : const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file_rounded, size: 15, color: AppColors.accent2),
            SizedBox(height: 2),
            Text('Import\nPDF', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 8,
                  fontWeight: FontWeight.w600, color: AppColors.accent2, height: 1.2)),
          ]),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 8.5,
          color: color.withValues(alpha: 0.70))),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
          fontWeight: FontWeight.w700, color: color)),
    ]),
  ));
}

// ════════════════════════════════════════════════════════════════
//  2. ENVELOPE BUDGETS — YNAB-style category budget tracking
//     "Give every rupee a job"
// ════════════════════════════════════════════════════════════════

class EnvelopeBudgets extends StatefulWidget {
  final List<TransactionModel> txns;
  const EnvelopeBudgets({super.key, required this.txns});

  @override
  State<EnvelopeBudgets> createState() => _EnvelopeBudgetsState();
}

class _EnvelopeBudgetsState extends State<EnvelopeBudgets> {
  // Default budgets (₹) per category — user can edit
  Map<String, double> _budgets = {
    'food_delivery': 3000,
    'grocery':       5000,
    'transport':     2000,
    'entertainment': 2000,
    'subscriptions': 1000,
    'health':        1500,
    'shopping':      3000,
    'fuel':          2000,
  };
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('envelope_budgets');
    if (stored != null) {
      final map = json.decode(stored) as Map<String, dynamic>;
      setState(() => _budgets = map.map((k, v) => MapEntry(k, (v as num).toDouble())));
    }
    setState(() => _loaded = true);
  }

  Future<void> _saveBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('envelope_budgets', json.encode(_budgets));
  }

  // Compute spent per category from current period txns
  Map<String, double> get _spent {
    final map = <String, double>{};
    for (final t in widget.txns) {
      if (!t.isDebit) continue;
      final cat = t.category ?? 'others';
      map[cat] = (map[cat] ?? 0) + t.amount;
    }
    return map;
  }

  void _editBudget(String cat) {
    final ctrl = TextEditingController(text: _budgets[cat]?.toStringAsFixed(0) ?? '');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${catEmoji(cat)} Monthly Budget',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('₹', style: TextStyle(fontFamily: 'DMMono', fontSize: 18,
                      color: AppColors.text2))),
                Expanded(child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 18,
                      color: AppColors.text),
                  decoration: const InputDecoration(
                    border: InputBorder.none, hintText: '5000',
                    hintStyle: TextStyle(color: AppColors.text3),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                )),
              ]),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                final val = double.tryParse(ctrl.text) ?? 0;
                setState(() => _budgets[cat] = val);
                _saveBudgets();
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity, height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FFE), Color(0xFF00CFDE)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('Save Budget',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final spent = _spent;
    final entries = _budgets.entries.toList()
      ..sort((a, b) {
        final af = (spent[a.key] ?? 0) / a.value;
        final bf = (spent[b.key] ?? 0) / b.value;
        return bf.compareTo(af); // most over-budget first
      });

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF7B2FFE), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('BUDGET ENVELOPES',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 0.4,
                  color: AppColors.text3)),
            const Spacer(),
            const Text('Tap to edit', style: TextStyle(fontFamily: 'DMSans',
                fontSize: 9.5, color: AppColors.text3)),
          ]),
        ),
        const Divider(color: AppColors.border, height: 1),
        ...entries.map((e) {
          final s      = spent[e.key] ?? 0;
          final budget = e.value.clamp(1, double.infinity);
          final frac   = (s / budget).clamp(0.0, 1.0);
          final color  = catColor(e.key);
          final over   = s > budget;
          return GestureDetector(
            onTap: () => _editBudget(e.key),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              child: Row(children: [
                SizedBox(width: 56, child: Text(catEmoji(e.key),
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: over ? const Color(0xFFEF4444) : AppColors.text2))),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: frac, minHeight: 5,
                      backgroundColor: AppColors.bg4,
                      color: over ? const Color(0xFFEF4444) : color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(formatInr(s, compact: true),
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                          color: over ? const Color(0xFFEF4444) : AppColors.text2)),
                    Text('of ${formatInr(budget, compact: true)}',
                      style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                          color: AppColors.text3)),
                  ]),
                ])),
                const SizedBox(width: 10),
                Text(over ? 'OVER' : '${((1 - frac) * 100).toStringAsFixed(0)}% left',
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: over ? const Color(0xFFEF4444) : AppColors.text3)),
              ]),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Text(
            'YNAB method: give every rupee a job. Tap any category to set its monthly limit.',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                color: AppColors.text3, height: 1.4)),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  3. SPLIT WITH FRIENDS — Splitwise-like running balance
//     Uses Simplify Debts algorithm (graph theory)
// ════════════════════════════════════════════════════════════════

class SplitLedger extends StatefulWidget {
  const SplitLedger({super.key});

  @override
  State<SplitLedger> createState() => _SplitLedgerState();
}

class _SplitLedgerState extends State<SplitLedger> {
  List<SplitEntry> _entries = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('split_entries');
    if (raw != null) {
      final list = json.decode(raw) as List;
      _entries = list.map((e) => SplitEntry.fromJson(e)).toList();
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('split_entries',
        json.encode(_entries.map((e) => e.toJson()).toList()));
  }

  // Simplify Debts: collapse all IOUs into minimum payments
  Map<String, double> get _netBalances {
    final map = <String, double>{};
    for (final e in _entries) {
      if (e.youOwe) {
        map[e.friendName] = (map[e.friendName] ?? 0) - e.amount;
      } else {
        map[e.friendName] = (map[e.friendName] ?? 0) + e.amount;
      }
    }
    return map;
  }

  void _showAddSplit() {
    final nameCtrl   = TextEditingController();
    final amountCtrl = TextEditingController();
    final descCtrl   = TextEditingController();
    bool youOwe      = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Add Split Expense',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15,
                    fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 16),
              _splitField(nameCtrl, 'Friend name', 'Rahul'),
              const SizedBox(height: 10),
              _splitField(descCtrl, 'What for?', 'Dinner, movie...'),
              const SizedBox(height: 10),
              _splitField(amountCtrl, 'Amount (₹)', '500',
                  number: true),
              const SizedBox(height: 12),
              // Who owes toggle
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setS(() => youOwe = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !youOwe
                            ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: !youOwe
                                ? const Color(0xFF22C55E).withValues(alpha: 0.50)
                                : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text('They owe you',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: !youOwe ? const Color(0xFF22C55E) : AppColors.text3)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setS(() => youOwe = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: youOwe
                            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: youOwe
                                ? const Color(0xFFEF4444).withValues(alpha: 0.50)
                                : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text('You owe them',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: youOwe ? const Color(0xFFEF4444) : AppColors.text3)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  final name   = nameCtrl.text.trim();
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  final desc   = descCtrl.text.trim();
                  if (name.isEmpty || amount <= 0) return;
                  setState(() {
                    _entries.add(SplitEntry(
                      id:          DateTime.now().millisecondsSinceEpoch.toString(),
                      friendName:  name,
                      amount:      amount,
                      description: desc.isEmpty ? 'Expense' : desc,
                      date:        DateTime.now().toIso8601String().split('T').first,
                      youOwe:      youOwe,
                    ));
                  });
                  _save();
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity, height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF7B2FFE), Color(0xFF00CFDE)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('Add Split',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                        fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _splitField(TextEditingController c, String label, String hint,
      {bool number = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
          color: AppColors.text3)),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(color: AppColors.bg3,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border)),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
              color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    ]);

  void _settle(String friend) {
    setState(() {
      _entries.removeWhere((e) => e.friendName.toLowerCase() == friend.toLowerCase());
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final balances = _netBalances;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF22C55E), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('SPLITS & BALANCES',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 0.4,
                  color: AppColors.text3)),
            const Spacer(),
            GestureDetector(
              onTap: _showAddSplit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2FFE).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('+ Split',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                      fontWeight: FontWeight.w600, color: Color(0xFF7B2FFE))),
              ),
            ),
          ]),
        ),
        const Divider(color: AppColors.border, height: 1),

        if (balances.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No splits yet. Tap "+ Split" to track shared expenses with friends, roommates, or family.',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
                  color: AppColors.text3, height: 1.4)),
          )
        else
          ...balances.entries.map((e) {
            final theyOweYou = e.value > 0;
            final color = theyOweYou
                ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(e.key[0].toUpperCase(),
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                        fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key, style: const TextStyle(fontFamily: 'DMSans',
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(theyOweYou ? 'owes you' : 'you owe',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: color)),
                ])),
                Text(formatInr(e.value.abs(), compact: true),
                  style: TextStyle(fontFamily: 'DMMono', fontSize: 14,
                      fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _settle(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bg3,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text('Settle',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                          color: AppColors.text3)),
                  ),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4. SUBSCRIPTION RADAR — Auto-detect recurring payments
//     "The subscription graveyard view no Indian app has"
// ════════════════════════════════════════════════════════════════

class SubscriptionRadar extends StatelessWidget {
  final List<TransactionModel> allTxns; // ideally last 90 days
  const SubscriptionRadar({super.key, required this.allTxns});

  List<_SubEntry> _detectSubscriptions() {
    // Group debits by merchant, look for same-amount repeats ~30 days apart
    final byMerchant = <String, List<TransactionModel>>{};
    for (final t in allTxns) {
      if (!t.isDebit) continue;
      final key = (t.merchant ?? t.description ?? '').toLowerCase().trim();
      if (key.isEmpty) continue;
      byMerchant.putIfAbsent(key, () => []).add(t);
    }

    final subs = <_SubEntry>[];
    for (final entry in byMerchant.entries) {
      final txns = entry.value;
      if (txns.length < 2) continue;

      // Check if amounts are similar (within 5%)
      final amounts = txns.map((t) => t.amount).toList()..sort();
      final base = amounts.first;
      final allSimilar = amounts.every((a) => (a - base).abs() / base < 0.05);
      if (!allSimilar) continue;

      // Check if dates are ~30 days apart
      final dates = txns.map((t) => t.txnDate).toList()..sort();
      bool isRecurring = false;
      for (int i = 1; i < dates.length; i++) {
        final diff = dates[i].difference(dates[i - 1]).inDays;
        if (diff >= 25 && diff <= 35) { isRecurring = true; break; }
        if (diff >= 6 && diff <= 8)   { isRecurring = true; break; } // weekly
      }
      if (!isRecurring) continue;

      final name = txns.first.merchant ?? txns.first.description ?? entry.key;
      subs.add(_SubEntry(
        name:      name.length > 24 ? '${name.substring(0, 22)}…' : name,
        amount:    base,
        category:  txns.first.category ?? 'subscriptions',
        lastDate:  dates.last,
        count:     txns.length,
      ));
    }

    subs.sort((a, b) => b.amount.compareTo(a.amount));
    return subs;
  }

  @override
  Widget build(BuildContext context) {
    final subs = _detectSubscriptions();
    if (subs.isEmpty) return const SizedBox.shrink();

    final totalMonthly = subs.fold(0.0, (s, e) => s + e.amount);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF7B2FFE), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('SUBSCRIPTION RADAR',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 0.4,
                  color: AppColors.text3)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2FFE).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${formatInr(totalMonthly, compact: true)}/mo total',
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 9.5,
                    color: Color(0xFF7B2FFE))),
            ),
          ]),
        ),
        const Divider(color: AppColors.border, height: 1),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: subs.length,
            itemBuilder: (_, i) => _SubChip(sub: subs[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(
            '${subs.length} recurring payments detected. That\'s ${formatInr(totalMonthly * 12, compact: true)}/year in fixed drains.',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                color: AppColors.text3, height: 1.3)),
        ),
      ]),
    );
  }
}

class _SubEntry {
  final String   name, category;
  final double   amount;
  final DateTime lastDate;
  final int      count;
  const _SubEntry({required this.name, required this.amount,
      required this.category, required this.lastDate, required this.count});
}

class _SubChip extends StatelessWidget {
  final _SubEntry sub;
  const _SubChip({required this.sub});

  @override
  Widget build(BuildContext context) {
    final color = catColor(sub.category);
    return Container(
      width: 130,
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
          Expanded(child: Text(sub.name,
            style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                fontWeight: FontWeight.w600, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 5),
        Text(formatInr(sub.amount, compact: true),
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 13,
              fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 1),
        Text('${sub.count}× detected · recurring',
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: AppColors.text3)),
        Text('≈ ${formatInr(sub.amount * 12, compact: true)}/yr',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: color.withValues(alpha: 0.70), fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  5. MONEY HABITS — Merchant-level pattern detection
// ════════════════════════════════════════════════════════════════

class MoneyHabitsStrip extends StatelessWidget {
  final List<SpendHabit> habits;
  final bool             expanded;
  final VoidCallback     onToggle;
  const MoneyHabitsStrip({super.key,
      required this.habits, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final top = habits.take(5).toList();
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
              itemCount: top.length,
              itemBuilder: (_, i) => _HabitChip(habit: top[i]),
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
    final color = catColor(habit.category);
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
          style: const TextStyle(fontFamily: 'DMSans', fontSize: 9, color: AppColors.text3)),
        Text('≈ ${formatInr(habit.annualCost, compact: true)}/yr',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
              color: color.withValues(alpha: 0.70), fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
