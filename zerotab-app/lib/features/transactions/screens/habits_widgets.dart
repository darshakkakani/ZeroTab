// ════════════════════════════════════════════════════════════════
//  ZeroTab Spend Intelligence — All-in-One Finance Companion
//
//  Features built:
//  1. Budget Brain        — Freely spendable money + pace bar
//  2. Flow Budgets        — Envelope-style category budget tracking
//  3. SettleUp            — Real social splits (Supabase + phone search)
//  4. Bill Radar          — Detect & surface all recurring drains
//  5. Patterns            — Merchant-level behavioral spending analysis
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
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
    // ── Use REAL transaction data (avoids broken emiRatio estimates) ──────
    // If we have live transactions, compute everything from them directly.
    // This is always accurate because it's what the user actually did.
    if (txns.isEmpty && (snapshot == null || snapshot!.monthlyIncome <= 0)) {
      return _NoIncomeCard(onImport: onImport, importing: importing);
    }

    final now         = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed  = now.day.clamp(1, daysInMonth);
    final monthFrac   = daysPassed / daysInMonth;

    // Income = credit transactions this period
    final creditTxns = txns.where((t) => t.isCredit).toList();
    final debitTxns  = txns.where((t) => t.isDebit).toList();

    // Prefer live txn income; fall back to snapshot
    final income = creditTxns.isNotEmpty
        ? creditTxns.fold(0.0, (s, t) => s + t.amount)
        : (snapshot?.monthlyIncome ?? 0);

    if (income <= 0) {
      return _NoIncomeCard(onImport: onImport, importing: importing);
    }

    // Fixed commitments = EMI transactions only (not all debits)
    final fixedCommit = debitTxns
        .where((t) => t.category == 'emi' || t.category == 'investment')
        .fold(0.0, (s, t) => s + t.amount)
        .clamp(0.0, income * 0.80); // cap at 80% of income

    // Variable spend = everything else debited
    final spent = debitTxns
        .where((t) => t.category != 'emi' && t.category != 'investment')
        .fold(0.0, (s, t) => s + t.amount);

    // Discretionary budget = income minus fixed commitments
    final budget   = (income - fixedCommit).clamp(income * 0.10, income);
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
//  2. FLOWCAST V2 — Zero-based budgeting + Age of Money
//
//  Core idea (same as YNAB, free for our users):
//  "Ready to Assign" = income − total budgeted
//  Goal: keep RTA at exactly ₹0 — every rupee has a job.
//
//  Age of Money = avg days between when income arrived and
//  when that money was spent (FIFO). <30d = paycheck-to-paycheck.
// ════════════════════════════════════════════════════════════════

// ── Age of Money calculation (simplified FIFO) ────────────────
double _calcAgeOfMoney(List<TransactionModel> txns) {
  final sorted = [...txns]..sort((a, b) => a.txnDate.compareTo(b.txnDate));
  final incomes  = sorted.where((t) => t.isCredit).toList();
  final outflows = sorted.where((t) => t.isDebit).toList().reversed.take(10).toList();
  if (incomes.isEmpty || outflows.isEmpty) return 0;
  double total = 0;
  int count = 0;
  for (final out in outflows) {
    final prior = incomes.where((i) => !i.txnDate.isAfter(out.txnDate)).toList();
    if (prior.isEmpty) continue;
    total += out.txnDate.difference(prior.last.txnDate).inDays.toDouble();
    count++;
  }
  return count == 0 ? 0 : total / count;
}

class EnvelopeBudgets extends StatefulWidget {
  final List<TransactionModel> txns;
  const EnvelopeBudgets({super.key, required this.txns});

  @override
  State<EnvelopeBudgets> createState() => _EnvelopeBudgetsState();
}

class _EnvelopeBudgetsState extends State<EnvelopeBudgets> {
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
  bool _showGoalTip = false;

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
    } else {
      // Smart default: suggest budgets based on 3-month avg spend
      _autoSuggestBudgets();
    }
    setState(() => _loaded = true);
  }

  void _autoSuggestBudgets() {
    final spent = _spent;
    for (final cat in _budgets.keys) {
      if (spent.containsKey(cat) && spent[cat]! > 0) {
        // Suggest 20% more than actual spend as budget headroom
        _budgets[cat] = (spent[cat]! * 1.20).roundToDouble();
      }
    }
  }

  Future<void> _saveBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('envelope_budgets', json.encode(_budgets));
  }

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

    // ── Zero-based core computation ─────────────────────────────
    final income       = widget.txns.where((t) => t.isCredit)
        .fold(0.0, (s, t) => s + t.amount);
    final totalBudgeted = _budgets.values.fold(0.0, (s, v) => s + v);
    // "Ready to Assign" = the #1 YNAB insight — income not yet given a job
    final rta          = income - totalBudgeted;
    // Age of Money
    final aom          = _calcAgeOfMoney(widget.txns);

    final entries = _budgets.entries.toList()
      ..sort((a, b) {
        final af = (spent[a.key] ?? 0) / a.value;
        final bf = (spent[b.key] ?? 0) / b.value;
        return bf.compareTo(af);
      });

    // RTA color
    final Color rtaColor;
    final String rtaLabel;
    if (rta.abs() < 1) {
      rtaColor = AppColors.green;
      rtaLabel = '✓ Every rupee has a job';
    } else if (rta > 0) {
      rtaColor = const Color(0xFF7B2FFE);
      rtaLabel = '${formatInr(rta, compact: true)} unassigned — assign it!';
    } else {
      rtaColor = AppColors.red;
      rtaLabel = 'Over-assigned by ${formatInr(rta.abs(), compact: true)}';
    }

    // AoM tier
    final aomColor = aom < 10 ? AppColors.red
        : aom < 30 ? AppColors.gold
        : AppColors.green;
    final aomLabel = aom < 10 ? 'Paycheck to paycheck'
        : aom < 30 ? 'Building a buffer'
        : aom < 60 ? 'Buffer established'
        : 'Financially healthy';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Ready to Assign hero card ─────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: rtaColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: rtaColor.withValues(alpha: 0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('READY TO ASSIGN', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 9.5,
              fontWeight: FontWeight.w600, letterSpacing: 0.5,
              color: rtaColor.withValues(alpha: 0.75))),
            const Spacer(),
            Text('FLOWCAST', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 9.5,
              fontWeight: FontWeight.w600, letterSpacing: 0.4,
              color: AppColors.text3)),
          ]),
          const SizedBox(height: 6),
          Text(rta.abs() < 1 ? '₹0' : formatInr(rta.abs(), compact: true),
            style: TextStyle(fontFamily: 'DMMono', fontSize: 28,
              fontWeight: FontWeight.w800, color: rtaColor, letterSpacing: -1)),
          const SizedBox(height: 3),
          Text(rtaLabel, style: TextStyle(fontFamily: 'DMSans',
              fontSize: 11, color: rtaColor.withValues(alpha: 0.80))),
          const SizedBox(height: 12),
          // Income / Budgeted row
          if (income > 0) Row(children: [
            _RtaStat('Income', formatInr(income, compact: true), AppColors.green),
            const SizedBox(width: 8),
            _RtaStat('Budgeted', formatInr(totalBudgeted, compact: true),
                const Color(0xFF7B2FFE)),
          ]),
          if (income > 0) const SizedBox(height: 12),
          // Age of Money
          if (aom > 0) ...[
            Row(children: [
              Text('Age of Money: ', style: const TextStyle(
                fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
              Text('${aom.round()} days',
                style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
                    fontWeight: FontWeight.w700, color: aomColor)),
              const SizedBox(width: 6),
              Text('· $aomLabel',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                    color: aomColor.withValues(alpha: 0.75))),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (aom / 60).clamp(0.0, 1.0), minHeight: 5,
                backgroundColor: AppColors.bg4, color: aomColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0d', style: const TextStyle(fontFamily: 'DMMono',
                      fontSize: 8, color: AppColors.text3)),
                  Text('Goal: 30d', style: const TextStyle(fontFamily: 'DMMono',
                      fontSize: 8, color: AppColors.text3)),
                  Text('60d+', style: const TextStyle(fontFamily: 'DMMono',
                      fontSize: 8, color: AppColors.text3)),
                ],
              ),
            ),
          ],
        ]),
      ),

      const SizedBox(height: 10),

      // ── Envelope list ─────────────────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Row(children: [
              const Text('ENVELOPES',
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
            final pct    = (frac * 100).toStringAsFixed(0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _editBudget(e.key),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  SizedBox(width: 60, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(catEmoji(e.key), style: TextStyle(
                          fontFamily: 'DMSans', fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: over ? const Color(0xFFEF4444) : AppColors.text2)),
                      Text('$pct%', style: TextStyle(
                          fontFamily: 'DMMono', fontSize: 9.5,
                          color: over ? const Color(0xFFEF4444) : AppColors.text3)),
                    ],
                  )),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac, minHeight: 7,
                          backgroundColor: AppColors.bg4,
                          color: over ? const Color(0xFFEF4444) : color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatInr(s, compact: true),
                            style: TextStyle(fontFamily: 'DMMono', fontSize: 10,
                                color: over
                                    ? const Color(0xFFEF4444)
                                    : AppColors.text2)),
                          Text('of ${formatInr(budget, compact: true)}',
                            style: const TextStyle(fontFamily: 'DMMono',
                                fontSize: 10, color: AppColors.text3)),
                        ],
                      ),
                    ],
                  )),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (over ? const Color(0xFFEF4444) : color)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      over ? 'OVER'
                          : '${formatInr(budget - s, compact: true)} left',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: over
                              ? const Color(0xFFEF4444) : color)),
                  ),
                ]),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Text(
              income > 0
                  ? 'Goal: assign all ₹${formatInr(income, compact: true)} income so Ready to Assign = ₹0'
                  : 'Add an income transaction to unlock zero-based budgeting',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                  color: AppColors.text3, height: 1.4)),
          ),
        ]),
      ),
    ]);
  }
}

// ── RTA stat chip ─────────────────────────────────────────────
class _RtaStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _RtaStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
          color: color.withValues(alpha: 0.70))),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
          fontWeight: FontWeight.w700, color: color)),
    ]),
  ));
}

// ════════════════════════════════════════════════════════════════
//  3. SETTLEUP LAUNCHER — routes to the full SettleUp screen
//     Full implementation: settleup_screen.dart
//     Groups, real-time sync, push notifications, debt simplify
// ════════════════════════════════════════════════════════════════

class SettleUpLedger extends StatefulWidget {
  const SettleUpLedger({super.key});

  @override
  State<SettleUpLedger> createState() => _SettleUpLedgerState();
}

class _SettleUpLedgerState extends State<SettleUpLedger> {
  List<SplitEntry> _entries = [];
  bool _loaded = false;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Load: try Supabase first, fall back to SharedPreferences ──
  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        final data = await client
            .from('splits')
            .select()
            .or('created_by.eq.$userId,participant_user_id.eq.$userId')
            .eq('is_settled', false)
            .order('created_at', ascending: false);

        final list = (data as List).map<SplitEntry>((e) {
          final isCreator = e['created_by'] == userId;
          return SplitEntry(
            id:          e['id'] as String,
            friendName:  (e['participant_name'] as String?) ?? 'Friend',
            amount:      (e['amount'] as num).toDouble(),
            description: (e['description'] as String?) ?? '',
            date:        (e['split_date'] as String?) ??
                         DateTime.now().toIso8601String().split('T').first,
            youOwe:      isCreator
                ? (e['you_owe'] as bool? ?? false)
                : !(e['you_owe'] as bool? ?? false),
          );
        }).toList();

        if (mounted) setState(() { _entries = list; _loaded = true; });
        return;
      }
    } catch (_) {}

    // Fallback: local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('settle_up_entries') ??
                prefs.getString('split_entries'); // legacy key
    if (raw != null) {
      try {
        _entries = (json.decode(raw) as List)
            .map((e) => SplitEntry.fromJson(e)).toList();
      } catch (_) {}
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settle_up_entries',
        json.encode(_entries.map((e) => e.toJson()).toList()));
  }

  // Debt simplification: collapse all IOUs per friend into net balance
  Map<String, double> get _netBalances {
    final map = <String, double>{};
    for (final e in _entries) {
      map[e.friendName] = (map[e.friendName] ?? 0) +
          (e.youOwe ? -e.amount : e.amount);
    }
    return map;
  }

  // ── Add split via Supabase (or locally if unavailable) ────────
  Future<void> _addEntry(String phoneOrName, double amount,
      String desc, bool youOwe) async {
    if (mounted) setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        // Attempt to look up registered user by phone
        String? participantUserId;
        String displayName = phoneOrName;
        try {
          final isPhone = !phoneOrName.contains('@');
          final col = isPhone ? 'phone' : 'email';
          final userData = await client
              .from('users')
              .select('id, name')
              .eq(col, phoneOrName)
              .maybeSingle();
          participantUserId = userData?['id'] as String?;
          displayName = (userData?['name'] as String?) ?? phoneOrName;
        } catch (_) {}

        await client.from('splits').insert({
          'created_by':            userId,
          'participant_user_id':   participantUserId,
          'participant_name':      displayName,
          'participant_phone':     phoneOrName,
          'amount':                amount,
          'description':           desc.isEmpty ? 'Shared expense' : desc,
          'split_date':            DateTime.now().toIso8601String().split('T').first,
          'you_owe':               youOwe,
          'is_settled':            false,
        });
        await _load();
        return;
      }
    } catch (_) {}

    // Fallback: local only
    if (mounted) {
      setState(() {
        _entries.add(SplitEntry(
          id:          DateTime.now().millisecondsSinceEpoch.toString(),
          friendName:  phoneOrName,
          amount:      amount,
          description: desc.isEmpty ? 'Shared expense' : desc,
          date:        DateTime.now().toIso8601String().split('T').first,
          youOwe:      youOwe,
        ));
      });
    }
    await _saveLocal();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _settle(String friendName) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        final ids = _entries
            .where((e) => e.friendName.toLowerCase() == friendName.toLowerCase())
            .map((e) => e.id)
            .toList();
        for (final id in ids) {
          await client.from('splits')
              .update({'is_settled': true,
                       'settled_at': DateTime.now().toIso8601String()})
              .eq('id', id);
        }
        await _load();
        return;
      }
    } catch (_) {}

    // Local fallback
    if (mounted) {
      setState(() => _entries.removeWhere(
          (e) => e.friendName.toLowerCase() == friendName.toLowerCase()));
    }
    await _saveLocal();
  }

  void _showAddSheet() {
    final contactCtrl = TextEditingController();
    final amountCtrl  = TextEditingController();
    final descCtrl    = TextEditingController();
    bool youOwe = false;

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
              // Header
              Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.balance_outlined,
                      color: Color(0xFF22C55E), size: 18),
                ),
                const SizedBox(width: 12),
                const Text('Split an Expense',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 16,
                      fontWeight: FontWeight.w700, color: AppColors.text)),
              ]),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Enter phone, email, or just a name',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
                      color: AppColors.text3)),
              ),
              const SizedBox(height: 16),

              _settleField(contactCtrl, 'Friend (phone / email / name)',
                  '+91 9876543210 or Rahul'),
              const SizedBox(height: 10),
              _settleField(descCtrl, 'What for?', 'Dinner, trip, rent…'),
              const SizedBox(height: 10),
              _settleField(amountCtrl, 'Amount (₹)', '500', number: true),
              const SizedBox(height: 14),

              // Who owes toggle
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setS(() => youOwe = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                          color: !youOwe
                              ? const Color(0xFF22C55E) : AppColors.text3)),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: GestureDetector(
                  onTap: () => setS(() => youOwe = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                          color: youOwe
                              ? const Color(0xFFEF4444) : AppColors.text3)),
                  ),
                )),
              ]),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: () {
                  final contact = contactCtrl.text.trim();
                  final amount  = double.tryParse(amountCtrl.text) ?? 0;
                  final desc    = descCtrl.text.trim();
                  if (contact.isEmpty || amount <= 0) return;
                  Navigator.pop(ctx);
                  _addEntry(contact, amount, desc, youOwe);
                },
                child: Container(
                  width: double.infinity, height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF00C4A8)]),
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

  Widget _settleField(TextEditingController c, String label, String hint,
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
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    ]);

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2,
                  color: Color(0xFF22C55E))),
        ),
      );
    }
    final balances = _netBalances;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF22C55E), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('SETTLEUP',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 0.5,
                  color: AppColors.text3)),
            const Spacer(),
            if (_saving)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF22C55E)))
            else
              GestureDetector(
                onTap: _showAddSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.30)),
                  ),
                  child: const Text('+ Split',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22C55E))),
                ),
              ),
          ]),
        ),
        const Divider(color: AppColors.border, height: 1),

        // ── Empty state ──────────────────────────────────
        if (balances.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.balance_outlined,
                    color: Color(0xFF22C55E), size: 28),
              ),
              const SizedBox(height: 12),
              const Text('No open splits',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 6),
              const Text(
                'Add a friend by phone, email, or name.\nThey\'ll see the split in their ZeroTab too.',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
                    color: AppColors.text3, height: 1.5),
                textAlign: TextAlign.center),
            ]),
          )
        else
          // ── Balance list ──────────────────────────────
          ...balances.entries.map((e) {
            final theyOweYou = e.value > 0;
            final color = theyOweYou
                ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
            final relatedEntries = _entries
                .where((en) =>
                    en.friendName.toLowerCase() == e.key.toLowerCase())
                .toList();

            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        color.withValues(alpha: 0.20),
                        color.withValues(alpha: 0.10),
                      ]),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: 0.30)),
                    ),
                    alignment: Alignment.center,
                    child: Text(e.key[0].toUpperCase(),
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 15,
                          fontWeight: FontWeight.w700, color: color)),
                  ),
                  const SizedBox(width: 12),
                  // Name + status
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key, style: const TextStyle(fontFamily: 'DMSans',
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                      Text(
                        theyOweYou
                            ? 'owes you · ${relatedEntries.length} split${relatedEntries.length > 1 ? 's' : ''}'
                            : 'you owe · ${relatedEntries.length} split${relatedEntries.length > 1 ? 's' : ''}',
                        style: TextStyle(fontFamily: 'DMSans',
                            fontSize: 10.5, color: color)),
                    ],
                  )),
                  // Amount
                  Text(formatInr(e.value.abs(), compact: true),
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 16,
                        fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(width: 10),
                  // Settle button
                  GestureDetector(
                    onTap: () => _settle(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: color.withValues(alpha: 0.30)),
                      ),
                      child: Text('Settle',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                            fontWeight: FontWeight.w600, color: color)),
                    ),
                  ),
                ]),
              ),
              if (e.key != balances.keys.last)
                const Divider(color: AppColors.border, height: 1, indent: 64),
            ]);
          }),

        // ── Footer: total owed / receivable ──────────────
        if (balances.isNotEmpty) ...[
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Builder(builder: (_) {
              final toReceive = balances.values
                  .where((v) => v > 0).fold(0.0, (s, v) => s + v);
              final toPay = balances.values
                  .where((v) => v < 0).fold(0.0, (s, v) => s + v.abs());
              return Row(children: [
                if (toReceive > 0) Text(
                  'To receive: ${formatInr(toReceive, compact: true)}',
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 10,
                      color: Color(0xFF22C55E))),
                if (toReceive > 0 && toPay > 0)
                  const Text('  ·  ',
                      style: TextStyle(color: AppColors.text3, fontSize: 10)),
                if (toPay > 0) Text(
                  'To pay: ${formatInr(toPay, compact: true)}',
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 10,
                      color: Color(0xFFEF4444))),
              ]);
            }),
          ),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4. BILL RADAR V2 — Cancel Score + Next Renewal + Annual Drain
//
//  Cancel Score = how likely this subscription should be cut:
//    daysSinceLastPay × (amount / 30)
//  Higher = bigger priority to review.
//
//  Next renewal: predicted from lastDate + avg gap between payments.
// ════════════════════════════════════════════════════════════════

class BillRadar extends StatelessWidget {
  final List<TransactionModel> allTxns;
  const BillRadar({super.key, required this.allTxns});

  List<_SubEntry> _detect() {
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

      final amounts = txns.map((t) => t.amount).toList()..sort();
      final base    = amounts.first;
      if (!amounts.every((a) => (a - base).abs() / base.clamp(1, double.infinity) < 0.08)) continue;

      final dates = txns.map((t) => t.txnDate).toList()..sort();
      int? gapDays;
      for (int i = 1; i < dates.length; i++) {
        final diff = dates[i].difference(dates[i - 1]).inDays;
        if ((diff >= 25 && diff <= 35) || (diff >= 6 && diff <= 8) ||
            (diff >= 85 && diff <= 95)) {
          gapDays = diff;
          break;
        }
      }
      if (gapDays == null) continue;

      final name = txns.first.merchant ?? txns.first.description ?? entry.key;
      // Next renewal = last payment date + avg gap
      final nextRenewal = dates.last.add(Duration(days: gapDays));
      subs.add(_SubEntry(
        name:         name.length > 22 ? '${name.substring(0, 20)}…' : name,
        amount:       base,
        category:     txns.first.category ?? 'subscriptions',
        lastDate:     dates.last,
        nextRenewal:  nextRenewal,
        gapDays:      gapDays,
        count:        txns.length,
      ));
    }

    // Sort by cancel score (highest = most worth reviewing)
    subs.sort((a, b) => b.cancelScore.compareTo(a.cancelScore));
    return subs;
  }

  @override
  Widget build(BuildContext context) {
    final subs         = _detect();
    final now          = DateTime.now();
    final renewingSoon = subs.where((s) =>
        s.nextRenewal.difference(now).inDays <= 7 &&
        s.nextRenewal.isAfter(now)).toList();

    if (subs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border2)),
        child: Column(children: [
          const Icon(Icons.wifi_tethering_rounded,
              color: Color(0xFF00CFDE), size: 28),
          const SizedBox(height: 10),
          const Text('No recurring drains detected',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.text),
            textAlign: TextAlign.center),
          const SizedBox(height: 6),
          const Text(
            'Switch to "3M" or "All" to find monthly subscriptions.\n'
            'Radar looks for any merchant charged 2+ times with the same amount.',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
                color: AppColors.text3, height: 1.4),
            textAlign: TextAlign.center),
        ]),
      );
    }

    final monthly = subs.fold(0.0, (s, e) => s + e.amount);
    final annual  = monthly * 12;

    return Column(children: [
      // ── Annual drain hero ─────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.20)),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ANNUAL DRAIN', style: TextStyle(fontFamily: 'DMSans',
                fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.4,
                color: AppColors.text3)),
            const SizedBox(height: 4),
            Text(formatInr(annual, compact: true), style: const TextStyle(
              fontFamily: 'DMMono', fontSize: 26, fontWeight: FontWeight.w800,
              color: Color(0xFFEF4444), letterSpacing: -0.8)),
            Text('leaving automatically · ${subs.length} recurring',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 10,
                  color: AppColors.text3)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatInr(monthly, compact: true) + '/mo',
              style: const TextStyle(fontFamily: 'DMMono', fontSize: 14,
                  fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
              child: Text(_annualCompare(annual),
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 9.5,
                    fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
            ),
          ]),
        ]),
      ),

      // ── Renewing soon alert ───────────────────────────────────
      if (renewingSoon.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.25))),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined,
                color: Color(0xFFF59E0B), size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Renewing in 7 days: ' +
                  renewingSoon.map((s) =>
                      '${s.name} (${s.nextRenewal.difference(now).inDays}d)').join(', '),
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                  color: Color(0xFFF59E0B), height: 1.3))),
          ]),
        ),
      ],

      const SizedBox(height: 8),

      // ── Subscription list sorted by cancel score ──────────────
      Container(
        decoration: BoxDecoration(color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border2)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Row(children: [
              const Text('BILL RADAR',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5,
                    color: AppColors.text3)),
              const Spacer(),
              const Text('sorted by priority',
                style: TextStyle(fontFamily: 'DMSans',
                    fontSize: 9.5, color: AppColors.text3)),
            ]),
          ),
          const Divider(color: AppColors.border, height: 1),
          ...subs.take(8).toList().asMap().entries.map((entry) {
            final i   = entry.key;
            final sub = entry.value;
            final color = catColor(sub.category);
            final cancelPriority = sub.cancelPriority;
            final daysLeft = sub.nextRenewal.difference(now).inDays;

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(children: [
                  // Cancel priority badge
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: cancelPriority == 'review'
                          ? const Color(0xFFEF4444)
                          : cancelPriority == 'check'
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF22C55E),
                      shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.name, style: const TextStyle(
                        fontFamily: 'DMSans', fontSize: 13,
                        fontWeight: FontWeight.w600, color: AppColors.text)),
                      Row(children: [
                        Text(
                          sub.nextRenewal.isAfter(now)
                              ? 'Renews in ${daysLeft}d'
                              : 'Last: ${sub.lastDate.difference(now).inDays.abs()}d ago',
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                              color: daysLeft <= 3
                                  ? const Color(0xFFEF4444) : AppColors.text3)),
                        const Text(' · ', style: TextStyle(
                            color: AppColors.text3, fontSize: 10)),
                        Text(catEmoji(sub.category),
                          style: const TextStyle(fontSize: 10)),
                      ]),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(formatInr(sub.amount, compact: true) + '/mo',
                      style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
                          fontWeight: FontWeight.w700, color: color)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (cancelPriority == 'review'
                            ? const Color(0xFFEF4444)
                            : cancelPriority == 'check'
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF22C55E))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        cancelPriority == 'review' ? '🔴 Review'
                            : cancelPriority == 'check' ? '🟡 Check'
                            : '✅ Active',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: cancelPriority == 'review'
                                ? const Color(0xFFEF4444)
                                : cancelPriority == 'check'
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF22C55E))),
                    ),
                  ]),
                ]),
              ),
              if (i < subs.take(8).length - 1)
                const Divider(color: AppColors.border, height: 1, indent: 32),
            ]);
          }),
        ]),
      ),
    ]);
  }

  String _annualCompare(double annual) {
    if (annual > 100000) return '${(annual / 100000).toStringAsFixed(1)}L/yr';
    if (annual > 50000)  return 'A scooter EMI/yr';
    if (annual > 24000)  return '${(annual / 2000).round()} months groceries';
    if (annual > 12000)  return 'A vacation trip/yr';
    if (annual > 5000)   return '${(annual / 500).round()} restaurant meals';
    return '${(annual / 100).round()} coffees/yr';
  }
}

class _SubEntry {
  final String   name, category;
  final double   amount;
  final DateTime lastDate, nextRenewal;
  final int      gapDays, count;
  const _SubEntry({
    required this.name, required this.amount, required this.category,
    required this.lastDate, required this.nextRenewal,
    required this.gapDays, required this.count,
  });

  // Cancel Score: days since last payment × daily cost
  // Higher = stronger cancel candidate
  double get cancelScore {
    final daysSince = DateTime.now().difference(lastDate).inDays;
    return daysSince * (amount / 30.0);
  }

  String get cancelPriority {
    if (cancelScore > 300) return 'review';
    if (cancelScore > 60)  return 'check';
    return 'active';
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
              const Text('PATTERNS',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5,
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
