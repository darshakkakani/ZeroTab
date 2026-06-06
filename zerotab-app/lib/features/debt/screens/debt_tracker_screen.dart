import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/providers_refresh.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/zt_card.dart';
import 'dart:math' as math;

// ── Uniform FAB — shared across Spend / Invest / Debt ─────────
class _UniformFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _UniformFAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF0ECFF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B5FFF).withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.add_rounded,
          color: Color(0xFF2A1A6E),
          size: 24,
        ),
      ),
    );
  }
}

// ── Premium dark toast helper ─────────────────────────────────
void _showPremiumSnackBar(BuildContext context, String msg, {bool success = true}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: success ? AppColors.teal : AppColors.red,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 13,
          fontWeight: FontWeight.w500, color: AppColors.text))),
      ]),
      backgroundColor: const Color(0xFF1A1730),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(50),
        side: const BorderSide(color: Color(0xFF2A2545)),
      ),
      elevation: 12,
      duration: const Duration(seconds: 2),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
  );
}

// ── EMI math helpers ──────────────────────────────────────────

double _calculateEmi(double principal, double annualRate, int months) {
  if (months <= 0 || principal <= 0) return 0;
  if (annualRate <= 0) return principal / months;
  final r = annualRate / 12 / 100;
  final n = months.toDouble();
  return principal * r * math.pow(1 + r, n) / (math.pow(1 + r, n) - 1);
}

/// Returns a month-by-month amortization schedule.
/// Balance is rounded to 2 decimal places (paise) each period to prevent
/// floating-point residuals from adding a phantom near-zero final row.
List<Map<String, double>> _buildSchedule(double outstanding, double annualRate, int remainingMonths) {
  final schedule = <Map<String, double>>[];
  if (remainingMonths <= 0 || outstanding <= 0) return schedule;
  final emi = _calculateEmi(outstanding, annualRate, remainingMonths);
  double balance = outstanding;
  for (int m = 1; m <= remainingMonths && balance > 0.01; m++) {
    final interest  = annualRate > 0 ? balance * (annualRate / 12 / 100) : 0.0;
    final principal = math.min(emi - interest, balance);
    balance = ((balance - principal) * 100).roundToDouble() / 100; // paise precision
    balance = math.max(balance, 0);
    schedule.add({'month': m.toDouble(), 'principal': principal, 'interest': interest, 'balance': balance});
  }
  return schedule;
}

/// Compute whole calendar months elapsed between two dates.
/// Uses proper year/month arithmetic — inDays÷30 undercounts February months.
int _calendarMonthsElapsed(DateTime start, DateTime end) {
  final months = (end.year - start.year) * 12 + (end.month - start.month);
  return months.clamp(0, 1200);
}

/// Loan type detection from loan_name string
_LoanType _detectLoanType(String? loanName) {
  final name = (loanName ?? '').toLowerCase();
  if (name.contains('home') || name.contains('hous') || name.contains('mortgage')) return _LoanType.home;
  if (name.contains('car') || name.contains('vehicle') || name.contains('auto')) return _LoanType.car;
  if (name.contains('education') || name.contains('student') || name.contains('study')) return _LoanType.education;
  if (name.contains('personal')) return _LoanType.personal;
  if (name.contains('business')) return _LoanType.business;
  return _LoanType.other;
}

enum _LoanType { home, car, education, personal, business, other }

IconData _loanIcon(_LoanType t) {
  switch (t) {
    case _LoanType.home:      return Icons.home_outlined;
    case _LoanType.car:       return Icons.directions_car_outlined;
    case _LoanType.education: return Icons.school_outlined;
    case _LoanType.personal:  return Icons.person_outline_rounded;
    case _LoanType.business:  return Icons.business_outlined;
    case _LoanType.other:     return Icons.account_balance_outlined;
  }
}

// ── Main screen ───────────────────────────────────────────────

class DebtTrackerScreen extends ConsumerStatefulWidget {
  const DebtTrackerScreen({super.key});

  @override
  ConsumerState<DebtTrackerScreen> createState() => _DebtTrackerScreenState();
}

class _DebtTrackerScreenState extends ConsumerState<DebtTrackerScreen> {
  bool _loansExpanded = false;
  bool _cardsExpanded = false;

  // ── FAB: shows chooser sheet (Loan or Credit Card) ──────
  void _showAddChooser() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            const Text('What would you like to add?', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _AddTypeBtn(
                icon: Icons.account_balance_outlined,
                label: 'Loan',
                subtitle: 'Home, car, personal\nor any term loan',
                color: AppColors.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddLoan();
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _AddTypeBtn(
                icon: Icons.credit_card_rounded,
                label: 'Credit Card',
                subtitle: 'Track bills, limits\n& due dates',
                color: AppColors.coral,
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddCreditCard();
                },
              )),
            ]),
          ],
        ),
      ),
    );
  }

  void _showAddLoan() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddLoanSheet(onAdded: () => refreshAllFinancialData(ref)),
    );
  }

  void _showAddCreditCard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCreditCardSheet(onAdded: () => refreshAllFinancialData(ref)),
    );
  }

  void _showAmortization(AccountModel a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AmortizationSheet(account: a),
    );
  }

  void _showPrepay(AccountModel a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrepaySheet(account: a),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final snapshotAsync = ref.watch(snapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: _UniformFAB(onTap: _showAddChooser),
      ),
      body: SafeArea(
        child: accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppColors.red))),
          data: (accounts) {
            final loans = accounts.where((a) => a.accountType == 'loan').toList();
            final cards = accounts.where((a) => a.accountType == 'credit_card').toList();
            final snap  = snapshotAsync.value;

            final totalDebt    = (snap?.creditCardDebt ?? 0) + (snap?.loanOutstanding ?? 0);
            final totalLimit   = cards.fold(0.0, (s, c) => s + (c.creditLimit ?? 0));
            final totalCardDebt = snap?.creditCardDebt ?? 0;
            final creditUtil   = totalLimit > 0 ? totalCardDebt / totalLimit : 0.0;
            final emiRatio     = snap?.emiRatio ?? 0;
            final monthlyIncome = snap?.monthlyIncome ?? 0;
            final estimatedEmi = monthlyIncome * emiRatio;

            // Balance-weighted average interest rate across manual loans.
            // Simple (unweighted) mean is misleading when loan balances differ significantly.
            double avgRate = 0;
            final ratedLoans = loans.where((a) => (a.interestRate ?? 0) > 0).toList();
            if (ratedLoans.isNotEmpty) {
              final totalBalance = ratedLoans.fold(0.0, (s, a) => s + (a.currentBalance?.abs() ?? 0));
              if (totalBalance > 0) {
                avgRate = ratedLoans.fold(0.0, (s, a) =>
                    s + (a.interestRate ?? 0) * (a.currentBalance?.abs() ?? 0)) / totalBalance;
              } else {
                avgRate = ratedLoans.fold(0.0, (s, a) => s + (a.interestRate ?? 0)) / ratedLoans.length;
              }
            }

            return RefreshIndicator(
              onRefresh: () async => refreshAllFinancialData(ref),
              color: AppColors.accent,
              backgroundColor: AppColors.bg3,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [

                  // ── Header ──────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                      child: Row(children: [
                        const Expanded(
                          child: Text('Liabilities', style: TextStyle(
                            fontFamily: 'DMSans', fontSize: 24,
                            fontWeight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.text)),
                        ),
                        if (totalDebt > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.coral.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: AppColors.coral.withOpacity(0.25)),
                            ),
                            child: Text(
                              '${formatInr(totalDebt, compact: true)} owed',
                              style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                                fontWeight: FontWeight.w600, color: AppColors.coral),
                            ),
                          ),
                      ]),
                    ),
                  ),

                  // ── Hero overview card ───────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [Color(0xFF0E0A1E), Color(0xFF080611)],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xxl),
                          border: Border.all(color: AppColors.coral.withOpacity(0.20)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('TOTAL OUTSTANDING', style: TextStyle(
                                fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w500,
                                letterSpacing: 0.8, color: AppColors.text3)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.coral.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                  border: Border.all(color: AppColors.coral.withOpacity(0.22)),
                                ),
                                child: Text('${loans.length + cards.length} liabilities',
                                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 10,
                                    fontWeight: FontWeight.w500, color: AppColors.coral)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              totalDebt > 0 ? formatInr(totalDebt) : '₹0',
                              style: const TextStyle(
                                fontFamily: 'DMMono', fontSize: 26, fontWeight: FontWeight.w700,
                                letterSpacing: -1.0, color: AppColors.text, height: 1.0),
                            ),
                            const SizedBox(height: 12),

                            // ── 3-column summary strip ──
                            IntrinsicHeight(
                              child: Row(children: [
                                Expanded(child: _StatPill('Monthly EMI',
                                  estimatedEmi > 0 ? formatInr(estimatedEmi, compact: true) : '—')),
                                Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), color: AppColors.border),
                                Expanded(child: _StatPill('EMI / Income',
                                  emiRatio > 0 ? formatPct(emiRatio * 100) : '—',
                                  valueColor: emiRatio > 0.5 ? AppColors.red : emiRatio > 0.3 ? const Color(0xFFFF8C42) : AppColors.green)),
                                Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), color: AppColors.border),
                                Expanded(child: _StatPill('Avg Rate',
                                  avgRate > 0 ? '${avgRate.toStringAsFixed(1)}%' : '—',
                                  valueColor: avgRate > 15 ? AppColors.red : avgRate > 10 ? const Color(0xFFFF8C42) : AppColors.text2)),
                              ]),
                            ),

                            if (cards.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              // Credit utilization meter
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Credit utilization', style: TextStyle(
                                    fontFamily: 'DMSans', fontSize: 12, color: AppColors.text2)),
                                  Text(
                                    formatPct(creditUtil * 100),
                                    style: TextStyle(
                                      fontFamily: 'DMMono', fontSize: 12, fontWeight: FontWeight.w600,
                                      color: creditUtil > 0.7 ? AppColors.red
                                          : creditUtil > 0.4 ? const Color(0xFFFF8C42)
                                          : AppColors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: creditUtil.clamp(0.0, 1.0),
                                  minHeight: 5,
                                  backgroundColor: AppColors.bg4,
                                  color: creditUtil > 0.7 ? AppColors.red
                                      : creditUtil > 0.4 ? const Color(0xFFFF8C42)
                                      : AppColors.green,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Text('Healthy < 30%', style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.green)),
                                  Text('High risk > 70%', style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 20)),

                  // ── Liabilities list ─────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ACTIVE LIABILITIES', style: TextStyle(
                            fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w600,
                            letterSpacing: 0.2, color: AppColors.text3)),
                          const SizedBox(height: 10),

                          if (loans.isEmpty && cards.isEmpty)
                            // ── Debt-free empty state — centered ──
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.45,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(32),
                                  decoration: AppDecorations.card(radius: AppRadius.xl),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Container(
                                      width: 56, height: 56,
                                      decoration: BoxDecoration(
                                        color: AppColors.greenSoft,
                                        borderRadius: BorderRadius.circular(AppRadius.lg),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.check_circle_outline_rounded,
                                        color: AppColors.green, size: 28),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text('You\'re debt-free!', style: TextStyle(
                                      fontFamily: 'DMSans', fontSize: 16,
                                      fontWeight: FontWeight.w700, color: AppColors.green)),
                                    const SizedBox(height: 4),
                                    const Text('No loans or credit card debt found', style: TextStyle(
                                      fontFamily: 'DMSans', fontSize: 13, color: AppColors.text3)),
                                    const SizedBox(height: 4),
                                    const Text('Tap + to add a loan or credit card', style: TextStyle(
                                      fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3)),
                                  ]),
                                ),
                              ),
                            )
                          else
                            Column(children: [
                              // ── Loans accordion ──
                              if (loans.isNotEmpty) ...[
                                _LoansSectionCard(
                                  loans: loans,
                                  isExpanded: _loansExpanded,
                                  onToggle: () => setState(() => _loansExpanded = !_loansExpanded),
                                  onAmortization: _showAmortization,
                                  onPrepay: _showPrepay,
                                ),
                                const SizedBox(height: 10),
                              ],

                              // ── Credit cards accordion ──
                              if (cards.isNotEmpty)
                                _CardsSectionCard(
                                  cards: cards,
                                  totalLimit: totalLimit,
                                  isExpanded: _cardsExpanded,
                                  onToggle: () => setState(() => _cardsExpanded = !_cardsExpanded),
                                ),
                            ]),
                        ],
                      ),
                    ),
                  ),

                  const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Loans section accordion card ─────────────────────────────

class _LoansSectionCard extends StatelessWidget {
  final List<AccountModel> loans;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(AccountModel) onAmortization;
  final void Function(AccountModel) onPrepay;

  const _LoansSectionCard({
    required this.loans,
    required this.isExpanded,
    required this.onToggle,
    required this.onAmortization,
    required this.onPrepay,
  });

  double get _totalOutstanding =>
      loans.fold(0.0, (s, a) => s + (a.currentBalance?.abs() ?? 0));

  double get _avgRate {
    final rated = loans.where((a) => (a.interestRate ?? 0) > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.fold(0.0, (s, a) => s + (a.interestRate ?? 0)) / rated.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary header (always visible) ──
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: AppDecorations.card(radius: AppRadius.xl),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.account_balance_outlined,
                    color: AppColors.accent2, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('LOANS', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 10,
                      fontWeight: FontWeight.w600, letterSpacing: 0.5,
                      color: AppColors.text3)),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('${loans.length}', style: const TextStyle(
                        fontFamily: 'DMSans', fontSize: 9,
                        fontWeight: FontWeight.w600, color: AppColors.accent2)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(
                      formatInr(_totalOutstanding, compact: true),
                      style: const TextStyle(
                        fontFamily: 'DMMono', fontSize: 16,
                        fontWeight: FontWeight.w700, color: AppColors.coral),
                    ),
                    if (_avgRate > 0) ...[
                      const SizedBox(width: 10),
                      Text('${_avgRate.toStringAsFixed(1)}% avg rate',
                        style: const TextStyle(fontFamily: 'DMSans',
                            fontSize: 11, color: AppColors.text3)),
                    ],
                  ]),
                ]),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.text3, size: 22),
              ),
            ]),
          ),
        ),

        // ── Expanded loan cards ──
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          child: isExpanded
              ? Column(children: [
                  const SizedBox(height: 8),
                  ...loans.map((a) => _LoanCard(
                        account: a,
                        onAmortization: () => onAmortization(a),
                        onPrepay: () => onPrepay(a),
                      )),
                ])
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Credit Cards section accordion card ──────────────────────

class _CardsSectionCard extends StatelessWidget {
  final List<AccountModel> cards;
  final double totalLimit;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CardsSectionCard({
    required this.cards,
    required this.totalLimit,
    required this.isExpanded,
    required this.onToggle,
  });

  double get _totalOutstanding =>
      cards.fold(0.0, (s, a) => s + (a.currentBalance?.abs() ?? 0));

  @override
  Widget build(BuildContext context) {
    final outstanding = _totalOutstanding;
    final util = totalLimit > 0 ? (outstanding / totalLimit).clamp(0.0, 1.0) : 0.0;
    final utilColor = util > 0.75 ? AppColors.red
        : util > 0.40 ? const Color(0xFFFF8C42)
        : AppColors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary header (always visible) ──
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A0E2E), Color(0xFF110A22)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.coral.withOpacity(0.25)),
            ),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.coral.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.credit_card_rounded,
                      color: AppColors.coral, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('CREDIT CARDS', style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5,
                        color: AppColors.text3)),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.coral.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('${cards.length}', style: const TextStyle(
                          fontFamily: 'DMSans', fontSize: 9,
                          fontWeight: FontWeight.w600, color: AppColors.coral)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(
                        formatInr(outstanding, compact: true),
                        style: const TextStyle(
                          fontFamily: 'DMMono', fontSize: 16,
                          fontWeight: FontWeight.w700, color: AppColors.coral),
                      ),
                      if (totalLimit > 0) ...[
                        const SizedBox(width: 10),
                        Text('/ ${formatInr(totalLimit, compact: true)} limit',
                          style: const TextStyle(fontFamily: 'DMSans',
                              fontSize: 11, color: AppColors.text3)),
                      ],
                    ]),
                  ]),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.text3, size: 22),
                ),
              ]),
              if (totalLimit > 0) ...[
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Utilization', style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 11, color: AppColors.text2)),
                  Text(
                    '${(util * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontFamily: 'DMMono', fontSize: 11,
                        fontWeight: FontWeight.w600, color: utilColor),
                  ),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: util,
                    minHeight: 4,
                    backgroundColor: AppColors.bg4,
                    color: utilColor,
                  ),
                ),
              ],
            ]),
          ),
        ),

        // ── Expanded credit card detail cards ──
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          child: isExpanded
              ? Column(children: [
                  const SizedBox(height: 8),
                  ...cards.map((a) => _CreditCardDetailCard(account: a)),
                ])
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Loan Card (per loan with progress + action buttons) ───────

class _LoanCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onAmortization;
  final VoidCallback onPrepay;

  const _LoanCard({
    required this.account,
    required this.onAmortization,
    required this.onPrepay,
  });

  @override
  Widget build(BuildContext context) {
    final a        = account;
    final loanType = _detectLoanType(a.loanName);
    final icon     = _loanIcon(loanType);

    final outstanding     = a.currentBalance?.abs() ?? 0;
    final originalPrincipal = a.originalPrincipal ?? outstanding;
    final paidOff        = originalPrincipal > 0 && originalPrincipal >= outstanding
        ? (originalPrincipal - outstanding) / originalPrincipal
        : 0.0;

    // Amortization details
    double? monthlyEmi;
    String? remainingInfo;
    int?    remainingMonths;

    final rate  = a.interestRate;
    final tenor = a.tenorMonths;
    final startDateStr = a.loanStartDate;

    if (rate != null && tenor != null && startDateStr != null) {
      final startDate = DateTime.tryParse(startDateStr);
      if (startDate != null) {
        final elapsed = DateTime.now().difference(startDate).inDays ~/ 30;
        final rem = (tenor - elapsed).clamp(0, tenor);
        remainingMonths = rem;
        if (rem > 0) {
          monthlyEmi = _calculateEmi(outstanding, rate, rem);
          final years  = rem ~/ 12;
          final months = rem % 12;
          remainingInfo = years > 0
              ? (months > 0 ? '$years yr $months mo' : '$years yr')
              : '$months mo';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecorations.card(radius: AppRadius.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Loan header row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.accent2, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.loanName ?? '${a.institutionName ?? 'Loan'} Loan',
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  if (a.institutionName != null && a.institutionName != a.loanName)
                    Text(a.institutionName!, style: const TextStyle(
                      fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
                  if (a.maskedNumber != null)
                    Text('Account ••${a.maskedNumber}', style: const TextStyle(
                      fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3)),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatInr(outstanding), style: const TextStyle(
                  fontFamily: 'DMMono', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.coral)),
                const Text('outstanding', style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
              ]),
            ]),
          ),

          // ── Paid-off progress bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(paidOff * 100).toStringAsFixed(0)}% paid off',
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3),
                    ),
                    if (rate != null)
                      Text('${rate.toStringAsFixed(1)}% p.a.', style: const TextStyle(
                        fontFamily: 'DMMono', fontSize: 11, color: AppColors.text3)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: paidOff.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.bg4,
                    color: paidOff > 0.7 ? AppColors.green
                        : paidOff > 0.3 ? AppColors.teal
                        : AppColors.coral,
                  ),
                ),
              ],
            ),
          ),

          // ── EMI + remaining strip ──
          if (monthlyEmi != null || remainingInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (monthlyEmi != null)
                      _MiniStat('EMI / mo', formatInr(monthlyEmi, compact: true), AppColors.teal),
                    if (remainingInfo != null)
                      _MiniStat('Remaining', remainingInfo, AppColors.text2),
                    if (originalPrincipal > 0)
                      _MiniStat('Original', formatInr(originalPrincipal, compact: true), AppColors.text3),
                  ],
                ),
              ),
            ),

          // ── Action buttons ──
          if (remainingMonths != null && remainingMonths > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onAmortization,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.bg3,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.table_rows_outlined, size: 13, color: AppColors.text2),
                          SizedBox(width: 5),
                          Text('Schedule', style: TextStyle(fontFamily: 'DMSans',
                            fontSize: 12, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onPrepay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.accent.withOpacity(0.25)),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 14, color: AppColors.accent2),
                          SizedBox(width: 4),
                          Text('Prepay impact', style: TextStyle(fontFamily: 'DMSans',
                            fontSize: 12, color: AppColors.accent2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── Mini stat widget (used inside loan cards) ─────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
        fontWeight: FontWeight.w500, color: color)),
    ],
  );
}

// ── Amortization Schedule Sheet ───────────────────────────────

class _AmortizationSheet extends StatefulWidget {
  final AccountModel account;
  const _AmortizationSheet({required this.account});

  @override
  State<_AmortizationSheet> createState() => _AmortizationSheetState();
}

class _AmortizationSheetState extends State<_AmortizationSheet> {
  bool _showAll = false;
  static const _previewCount = 12;

  @override
  Widget build(BuildContext context) {
    final a   = widget.account;
    final outstanding = a.currentBalance?.abs() ?? 0;
    final rate  = a.interestRate ?? 0;
    final tenor = a.tenorMonths ?? 0;
    final startDateStr = a.loanStartDate;

    int remainingMonths = tenor;
    if (startDateStr != null) {
      final start = DateTime.tryParse(startDateStr);
      if (start != null) {
        final elapsed = _calendarMonthsElapsed(start, DateTime.now());
        remainingMonths = (tenor - elapsed).clamp(0, tenor);
      }
    }

    final schedule = _buildSchedule(outstanding, rate, remainingMonths);
    final display  = _showAll ? schedule : schedule.take(_previewCount).toList();

    final totalInterest  = schedule.fold(0.0, (s, m) => s + m['interest']!);
    final totalPayable   = outstanding + totalInterest;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(children: [
              Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(
                  a.loanName ?? '${a.institutionName ?? 'Loan'} Schedule',
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 16,
                    fontWeight: FontWeight.w700, color: AppColors.text),
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                  ),
                  child: Text('${remainingMonths} mo left', style: const TextStyle(
                    fontFamily: 'DMMono', fontSize: 11, color: AppColors.accent2)),
                ),
              ]),
              const SizedBox(height: 12),
              // Summary row
              Row(children: [
                Expanded(child: _SummaryTile('Outstanding', formatInr(outstanding, compact: true), AppColors.coral)),
                Expanded(child: _SummaryTile('Total Interest', formatInr(totalInterest, compact: true), AppColors.coral)),
                Expanded(child: _SummaryTile('Total Payable', formatInr(totalPayable, compact: true), AppColors.text)),
              ]),
              const SizedBox(height: 14),
              // Column headers
              Row(children: const [
                SizedBox(width: 36, child: Text('#', style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3))),
                Expanded(child: Text('Principal', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3))),
                Expanded(child: Text('Interest', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3))),
                Expanded(child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3))),
              ]),
              const SizedBox(height: 4),
              const Divider(color: AppColors.border, height: 1),
            ]),
          ),

          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: display.length + 1,
              itemBuilder: (_, i) {
                if (i == display.length) {
                  if (schedule.length <= _previewCount) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _showAll = !_showAll),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.bg3,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _showAll ? 'Show less' : 'Show all ${schedule.length} months',
                          style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: AppColors.accent2),
                        ),
                      ),
                    ),
                  );
                }
                final m = display[i];
                final isCurrentMonth = i == 0;
                return Container(
                  color: isCurrentMonth ? AppColors.accentSoft.withOpacity(0.5) : Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${m['month']!.toInt()}',
                          style: TextStyle(
                            fontFamily: 'DMMono', fontSize: 12,
                            color: isCurrentMonth ? AppColors.accent2 : AppColors.text3,
                          ),
                        ),
                      ),
                      Expanded(child: Text(
                        formatInr(m['principal']!, compact: true),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontFamily: 'DMMono', fontSize: 12, color: AppColors.green),
                      )),
                      Expanded(child: Text(
                        formatInr(m['interest']!, compact: true),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontFamily: 'DMMono', fontSize: 12, color: AppColors.coral),
                      )),
                      Expanded(child: Text(
                        formatInr(m['balance']!, compact: true),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontFamily: 'DMMono', fontSize: 12, color: AppColors.text),
                      )),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _SummaryTile(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 12,
        fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center),
    ],
  );
}

// ── Prepayment Impact Sheet ───────────────────────────────────

class _PrepaySheet extends StatefulWidget {
  final AccountModel account;
  const _PrepaySheet({required this.account});

  @override
  State<_PrepaySheet> createState() => _PrepaySheetState();
}

class _PrepaySheetState extends State<_PrepaySheet> {
  final _amtCtrl = TextEditingController();
  List<_PrepayScenario> _scenarios = [];

  @override
  void dispose() { _amtCtrl.dispose(); super.dispose(); }

  void _calculate() {
    final extra = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (extra <= 0) return;

    final a   = widget.account;
    final outstanding = a.currentBalance?.abs() ?? 0;
    final rate  = a.interestRate ?? 0;
    final tenor = a.tenorMonths ?? 0;
    final startDateStr = a.loanStartDate;

    int remainingMonths = tenor;
    if (startDateStr != null) {
      final start = DateTime.tryParse(startDateStr);
      if (start != null) {
        final elapsed = _calendarMonthsElapsed(start, DateTime.now());
        remainingMonths = (tenor - elapsed).clamp(0, tenor);
      }
    }
    if (remainingMonths <= 0 || outstanding <= 0) return;

    final baseSchedule = _buildSchedule(outstanding, rate, remainingMonths);
    final baseTotalInterest = baseSchedule.fold(0.0, (s, m) => s + m['interest']!);

    _scenarios = [
      _computeScenario(outstanding, rate, remainingMonths, extra, baseTotalInterest, 'One-time prepayment'),
      _computeScenario(outstanding - extra * 3, rate, remainingMonths, 0, baseTotalInterest, '3× bulk prepayment'),
      _computeScenario(outstanding, rate, remainingMonths, extra, baseTotalInterest, 'Monthly extra EMI',
          extraMonthly: true, extraPerMonth: extra * 0.5),
    ].where((s) => s != null).cast<_PrepayScenario>().toList();

    setState(() {});
  }

  _PrepayScenario? _computeScenario(
    double outstanding, double rate, int months,
    double lumpsum, double baseTotalInterest, String label,
    {bool extraMonthly = false, double extraPerMonth = 0}
  ) {
    if (outstanding <= 0) return null;
    final principal = math.max(outstanding - lumpsum, 0.0);
    if (principal <= 0) {
      return _PrepayScenario(
        label: label,
        savingsInterest: baseTotalInterest,
        newMonths: 0,
        savedMonths: months,
      );
    }
    final newSchedule = _buildSchedule(principal, rate, months);
    double totalInterest = newSchedule.fold(0.0, (s, m) => s + m['interest']!);
    int newMonths = newSchedule.length;

    if (extraMonthly && extraPerMonth > 0) {
      // Iterative simulation: start from the lump-sum-reduced principal,
      // not the original outstanding (Bug fix: previous code ignored lump sum).
      double balance = principal;
      final emi = _calculateEmi(principal, rate, months) + extraPerMonth;
      totalInterest = 0;
      newMonths = 0;
      while (balance > 0.01 && newMonths < months) {
        final interest = rate > 0 ? balance * (rate / 12 / 100) : 0.0;
        totalInterest += interest;
        balance -= math.max(emi - interest, 0);
        balance = math.max(balance, 0);
        newMonths++;
      }
    }

    return _PrepayScenario(
      label: label,
      savingsInterest: baseTotalInterest - totalInterest,
      newMonths: newMonths,
      savedMonths: months - newMonths,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final a = widget.account;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.border2),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.bolt_rounded, size: 18, color: AppColors.accent2),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Prepayment Impact — ${a.loanName ?? 'Loan'}',
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 16,
                  fontWeight: FontWeight.w700, color: AppColors.text),
              )),
            ]),
            const SizedBox(height: 6),
            const Text('See how much you save by paying extra',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 20),

            // ── Amount input ──
            const Text('Extra amount (₹)', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bg3,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 16, color: AppColors.text),
                    decoration: const InputDecoration(
                      hintText: '50,000',
                      hintStyle: TextStyle(color: AppColors.text3, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => _calculate(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _calculate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Text('Calculate', style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),

            if (_scenarios.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('SCENARIOS', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w500,
                letterSpacing: 0.1, color: AppColors.text3)),
              const SizedBox(height: 10),
              ..._scenarios.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppDecorations.card(radius: AppRadius.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                      fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ScenarioStat('Interest saved', formatInr(s.savingsInterest, compact: true), AppColors.green),
                        _ScenarioStat('Loan closed in', '${s.newMonths} mo', AppColors.teal),
                        _ScenarioStat('Months saved', '${s.savedMonths} mo', AppColors.accent2),
                      ],
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrepayScenario {
  final String label;
  final double savingsInterest;
  final int    newMonths;
  final int    savedMonths;
  const _PrepayScenario({
    required this.label,
    required this.savingsInterest,
    required this.newMonths,
    required this.savedMonths,
  });
}

class _ScenarioStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _ScenarioStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
        fontWeight: FontWeight.w600, color: color)),
    ],
  );
}

// ── Stat pill (hero card) ─────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatPill(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
        fontWeight: FontWeight.w500, letterSpacing: 0.3, color: AppColors.text3),
        textAlign: TextAlign.center),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 13,
        fontWeight: FontWeight.w600, color: valueColor ?? AppColors.text2)),
    ],
  );
}

// ── Add Loan Sheet ────────────────────────────────────────────

class _AddLoanSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddLoanSheet({required this.onAdded});

  @override
  State<_AddLoanSheet> createState() => _AddLoanSheetState();
}

class _AddLoanSheetState extends State<_AddLoanSheet> {
  final _nameCtrl        = TextEditingController();
  final _institutionCtrl = TextEditingController();
  final _principalCtrl   = TextEditingController();
  final _rateCtrl        = TextEditingController();
  final _tenorCtrl       = TextEditingController();
  final _outstandingCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();
  bool _loading = false;

  static const _loanTypes = ['Home Loan', 'Car Loan', 'Personal Loan', 'Education Loan', 'Business Loan', 'Custom'];
  String _selectedType = 'Personal Loan';

  @override
  void dispose() {
    _nameCtrl.dispose(); _institutionCtrl.dispose();
    _principalCtrl.dispose(); _rateCtrl.dispose();
    _tenorCtrl.dispose(); _outstandingCtrl.dispose();
    super.dispose();
  }

  void _onTypeSelected(String t) {
    setState(() {
      _selectedType = t;
      if (t != 'Custom') _nameCtrl.text = t;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.bg3)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    final name        = _nameCtrl.text.trim();
    final institution = _institutionCtrl.text.trim();
    final principal   = double.tryParse(_principalCtrl.text) ?? 0;
    final rate        = double.tryParse(_rateCtrl.text) ?? 0;
    final tenor       = int.tryParse(_tenorCtrl.text) ?? 0;
    final outstanding = double.tryParse(_outstandingCtrl.text);

    if (name.isEmpty || principal <= 0 || tenor <= 0) {
      _showPremiumSnackBar(context, 'Please fill loan name, principal, and tenor', success: false);
      return;
    }

    setState(() => _loading = true);
    try {
      await api.post(ApiConstants.accounts, data: {
        'source_type':      'manual',
        'account_type':     'loan',
        'institution_name': institution.isEmpty ? name : institution,
        'current_balance':  -(outstanding ?? principal),
        'metadata': {
          'loan_name':           name,
          'original_principal':  principal,
          'interest_rate':       rate,
          'start_date':          _startDate.toIso8601String().split('T').first,
          'tenor_months':        tenor,
        },
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showPremiumSnackBar(context, 'Failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Live EMI preview
  Widget _emiPreview() {
    final principal = double.tryParse(_outstandingCtrl.text.isNotEmpty
        ? _outstandingCtrl.text : _principalCtrl.text) ?? 0;
    final rate  = double.tryParse(_rateCtrl.text) ?? 0;
    final tenor = int.tryParse(_tenorCtrl.text) ?? 0;
    if (principal <= 0 || tenor <= 0) return const SizedBox.shrink();
    final emi = _calculateEmi(principal, rate, tenor);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.accent.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.calculate_outlined, size: 14, color: AppColors.accent2),
        const SizedBox(width: 8),
        Text('Estimated EMI: ${formatInr(emi)}/mo',
          style: const TextStyle(fontFamily: 'DMMono', fontSize: 12, color: AppColors.accent2)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.border2),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add Loan', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
              fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 16),

            // Loan type quick-pick
            _label('Loan Type'),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _loanTypes.map((t) {
                  final active = _selectedType == t;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () => _onTypeSelected(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: active ? AppColors.accentSoft : AppColors.bg3,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: active ? AppColors.accent.withOpacity(0.45) : AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(t, style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: active ? AppColors.accent2 : AppColors.text2)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            _formField(_nameCtrl, 'Loan Name *', 'e.g. Home Loan, Car Loan'),
            const SizedBox(height: 12),
            _formField(_institutionCtrl, 'Institution', 'e.g. SBI, HDFC Bank'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _formField(_principalCtrl, 'Original Principal (₹) *', '0', number: true)),
              const SizedBox(width: 12),
              Expanded(child: _formField(_rateCtrl, 'Interest Rate (%)', '8.5', number: true)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _formField(_tenorCtrl, 'Tenor (months) *', '240', number: true, integer: true)),
              const SizedBox(width: 12),
              Expanded(child: _formField(_outstandingCtrl, 'Current Outstanding', 'Leave blank = principal', number: true)),
            ]),

            AnimatedBuilder(
              animation: Listenable.merge([_principalCtrl, _outstandingCtrl, _rateCtrl, _tenorCtrl]),
              builder: (_, __) => _emiPreview(),
            ),
            const SizedBox(height: 12),

            _label('Loan Start Date'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.text3),
                  const SizedBox(width: 10),
                  Text(
                    '${_startDate.day} ${_monthName(_startDate.month)} ${_startDate.year}',
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.text),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Loan', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  Widget _label(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3));

  Widget _formField(TextEditingController c, String label, String hint,
      {bool number = false, bool integer = false}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
          fontWeight: FontWeight.w500, color: AppColors.text3)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg3,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: c,
            keyboardType: integer ? TextInputType.number
                : number ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ],
    );
}

// ══════════════════════════════════════════════════════════════
// Add-type chooser button
// ══════════════════════════════════════════════════════════════

class _AddTypeBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   subtitle;
  final Color    color;
  final VoidCallback onTap;
  const _AddTypeBtn({
    required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(
          fontFamily: 'DMSans', fontSize: 14,
          fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 11,
            color: AppColors.text3, height: 1.4)),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// Credit Card Detail Card (in liabilities list)
// ══════════════════════════════════════════════════════════════

class _CreditCardDetailCard extends StatelessWidget {
  final AccountModel account;
  const _CreditCardDetailCard({required this.account});

  String _fmtDue(DateTime d) {
    final diff = d.difference(DateTime.now()).inDays;
    if (diff < 0)  return 'Overdue!';
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due in $diff days';
  }

  @override
  Widget build(BuildContext context) {
    final a           = account;
    final outstanding = a.currentBalance?.abs() ?? 0;
    final limit       = a.creditLimit ?? 0;
    final util        = limit > 0
        ? (outstanding / limit).clamp(0.0, 1.0) : 0.0;
    final masked      = a.maskedNumber;
    final bankName    = a.institutionName ?? 'Card';
    final cardName    = a.metadata?['card_name'] as String? ?? bankName;
    final network     = a.metadata?['card_network'] as String?;
    final expiryM     = a.metadata?['expiry_month'];
    final expiryY     = a.metadata?['expiry_year'];
    final billingDay  = a.metadata?['billing_day'];
    final annualFee   = (a.metadata?['annual_fee'] as num?)?.toDouble();
    final minDuePct   = (a.metadata?['minimum_due_pct'] as num?)?.toDouble() ?? 5.0;

    final dueDateStr  = a.metadata?['due_date'] as String?;
    final dueDate     = dueDateStr != null ? DateTime.tryParse(dueDateStr) : null;
    final isPastDue   = dueDate != null && dueDate.isBefore(DateTime.now());

    final utilColor = util > 0.75 ? AppColors.red
        : util > 0.40 ? const Color(0xFFFF8C42)
        : AppColors.green;

    final minDue = outstanding * minDuePct / 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0E2E), Color(0xFF110A22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isPastDue
              ? AppColors.red.withOpacity(0.5)
              : AppColors.coral.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header (like a physical card top) ───────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              // Card icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.coral.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.credit_card_rounded,
                    color: AppColors.coral, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(cardName, style: const TextStyle(
                        fontFamily: 'DMSans', fontSize: 14,
                        fontWeight: FontWeight.w600, color: AppColors.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (network != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.bg4,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(network, style: const TextStyle(
                          fontFamily: 'DMMono', fontSize: 9,
                          color: AppColors.text3)),
                      ),
                    ],
                  ]),
                  Text(
                    '${bankName}${masked != null ? '  ••••  ${masked.length > 4 ? masked.substring(masked.length - 4) : masked}' : ''}',
                    style: const TextStyle(
                      fontFamily: 'DMMono', fontSize: 11,
                      color: AppColors.text3)),
                  if (expiryM != null && expiryY != null)
                    Text('Expires $expiryM/$expiryY', style: const TextStyle(
                      fontFamily: 'DMSans', fontSize: 10,
                      color: AppColors.text3)),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatInr(outstanding), style: const TextStyle(
                  fontFamily: 'DMMono', fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.coral)),
                const Text('outstanding', style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 10, color: AppColors.text3)),
              ]),
            ]),
          ),

          // ── Utilization bar ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${(util * 100).toStringAsFixed(0)}% of limit used',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                          color: utilColor)),
                    if (limit > 0)
                      Text('Limit ${formatInr(limit, compact: true)}',
                        style: const TextStyle(fontFamily: 'DMSans',
                            fontSize: 10, color: AppColors.text3)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: util,
                    minHeight: 5,
                    backgroundColor: AppColors.bg4,
                    color: utilColor,
                  ),
                ),
              ],
            ),
          ),

          // ── Detail strip ────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg4,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CardStat(
                  label: 'Due Date',
                  value: dueDate != null ? _fmtDue(dueDate) : '—',
                  color: isPastDue ? AppColors.red
                      : dueDate != null &&
                              dueDate.difference(DateTime.now()).inDays <= 3
                          ? const Color(0xFFFF8C42)
                          : AppColors.text2,
                ),
                _vDivider(),
                _CardStat(
                  label: 'Min. Due',
                  value: minDue > 0 ? formatInr(minDue, compact: true) : '—',
                  color: AppColors.coral,
                ),
                if (billingDay != null) ...[
                  _vDivider(),
                  _CardStat(
                    label: 'Billing Day',
                    value: '$billingDay${_daySuffix(billingDay.toString())}',
                    color: AppColors.text2,
                  ),
                ],
                if (annualFee != null && annualFee > 0) ...[
                  _vDivider(),
                  _CardStat(
                    label: 'Annual Fee',
                    value: formatInr(annualFee, compact: true),
                    color: AppColors.text3,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
    width: 1, height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: AppColors.border,
  );

  String _daySuffix(String d) {
    final n = int.tryParse(d) ?? 1;
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}

class _CardStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _CardStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(
        fontFamily: 'DMSans', fontSize: 9,
        color: AppColors.text3)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(
        fontFamily: 'DMMono', fontSize: 11,
        fontWeight: FontWeight.w600, color: color)),
    ],
  );
}

// ══════════════════════════════════════════════════════════════
// Add Credit Card Sheet
// ══════════════════════════════════════════════════════════════

class _AddCreditCardSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddCreditCardSheet({required this.onAdded});

  @override
  State<_AddCreditCardSheet> createState() => _AddCreditCardSheetState();
}

class _AddCreditCardSheetState extends State<_AddCreditCardSheet> {
  final _cardNameCtrl    = TextEditingController();
  final _bankCtrl        = TextEditingController();
  final _lastFourCtrl    = TextEditingController();
  final _limitCtrl       = TextEditingController();
  final _outstandingCtrl = TextEditingController();
  final _annualFeeCtrl   = TextEditingController();

  String _network   = 'Visa';
  int    _expiryMonth = DateTime.now().month;
  int    _expiryYear  = DateTime.now().year + 3;
  int    _billingDay  = 1;
  int    _dueDays     = 18;   // days after billing cycle
  double _minDuePct   = 5.0;
  bool   _loading     = false;

  static const _networks  = ['Visa', 'Mastercard', 'Rupay', 'Amex', 'Diners'];
  static const _banks     = ['HDFC Bank', 'SBI', 'ICICI Bank', 'Axis Bank',
                              'Kotak Mahindra', 'IndusInd Bank', 'Yes Bank',
                              'Standard Chartered', 'Citi Bank', 'IDFC First', 'Other'];

  @override
  void dispose() {
    _cardNameCtrl.dispose(); _bankCtrl.dispose();
    _lastFourCtrl.dispose(); _limitCtrl.dispose();
    _outstandingCtrl.dispose(); _annualFeeCtrl.dispose();
    super.dispose();
  }

  /// Clamp a day to the last valid day of the given month.
  /// e.g. day=31 in April (30 days) → 30. Prevents Dart from rolling over.
  int _clampDayToMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day.clamp(1, lastDay);
  }

  /// Compute next due date from billing day + due days.
  /// Billing day is clamped to the valid range of the target month so that
  /// _billingDay=31 in April doesn't silently shift to May 1.
  DateTime _nextDueDate() {
    final now = DateTime.now();
    final thisDay = _clampDayToMonth(now.year, now.month, _billingDay);
    var billing = DateTime(now.year, now.month, thisDay);
    if (!billing.isAfter(now)) {
      final nextMonth = now.month == 12 ? 1  : now.month + 1;
      final nextYear  = now.month == 12 ? now.year + 1 : now.year;
      billing = DateTime(nextYear, nextMonth, _clampDayToMonth(nextYear, nextMonth, _billingDay));
    }
    return billing.add(Duration(days: _dueDays));
  }

  Future<void> _submit() async {
    final cardName    = _cardNameCtrl.text.trim();
    final bank        = _bankCtrl.text.trim();
    final lastFour    = _lastFourCtrl.text.trim();
    final limit       = double.tryParse(_limitCtrl.text) ?? 0;
    final outstanding = double.tryParse(_outstandingCtrl.text) ?? 0;
    final annualFee   = double.tryParse(_annualFeeCtrl.text) ?? 0;

    if (cardName.isEmpty || limit <= 0) {
      _showPremiumSnackBar(context, 'Please fill card name and credit limit', success: false);
      return;
    }

    setState(() => _loading = true);
    try {
      final dueDate = _nextDueDate();
      await api.post(ApiConstants.accounts, data: {
        'source_type':      'manual',
        'account_type':     'credit_card',
        'institution_name': bank.isEmpty ? cardName : bank,
        'masked_number':    lastFour.length >= 4 ? lastFour.substring(lastFour.length - 4) : lastFour,
        'current_balance':  -outstanding,
        'credit_limit':     limit,
        'currency':         'INR',
        'metadata': {
          'card_name':       cardName,
          'card_network':    _network,
          'expiry_month':    _expiryMonth.toString().padLeft(2, '0'),
          'expiry_year':     _expiryYear.toString(),
          'billing_day':     _billingDay,
          'due_days':        _dueDays,
          'due_date':        dueDate.toIso8601String().split('T').first,
          'minimum_due_pct': _minDuePct,
          'annual_fee':      annualFee,
        },
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showPremiumSnackBar(context, 'Failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.border2),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            // Title
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.coral.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
                alignment: Alignment.center,
                child: const Icon(Icons.credit_card_rounded,
                    color: AppColors.coral, size: 16),
              ),
              const SizedBox(width: 10),
              const Text('Add Credit Card', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 17,
                fontWeight: FontWeight.w700, color: AppColors.text)),
            ]),
            const SizedBox(height: 18),

            // ── Card Name ─────────────────────────────────
            _cf(_cardNameCtrl, 'Card Name *', 'e.g. My HDFC Regalia'),
            const SizedBox(height: 12),

            // ── Bank picker ───────────────────────────────
            _label('Bank *'),
            const SizedBox(height: 7),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _banks.map((b) {
                  final active = _bankCtrl.text == b;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _bankCtrl.text = b),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          color: active ? AppColors.coral.withOpacity(0.12) : AppColors.bg3,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: active ? AppColors.coral.withOpacity(0.45) : AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(b, style: TextStyle(
                          fontFamily: 'DMSans', fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: active ? AppColors.coral : AppColors.text2)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // ── Card Network ──────────────────────────────
            _label('Card Network'),
            const SizedBox(height: 7),
            Row(
              children: _networks.map((n) {
                final active = _network == n;
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: GestureDetector(
                    onTap: () => setState(() => _network = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent.withOpacity(0.12) : AppColors.bg3,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: active ? AppColors.accent.withOpacity(0.4) : AppColors.border),
                      ),
                      child: Text(n, style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 11,
                        color: active ? AppColors.accent2 : AppColors.text2)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // ── Last 4 digits + Expiry ────────────────────
            Row(children: [
              Expanded(child: _cf(_lastFourCtrl, 'Last 4 Digits', 'XXXX',
                  number: true, integer: true)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Expiry (MM/YY)'),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(
                        child: _DropDown<int>(
                          value: _expiryMonth,
                          items: List.generate(12, (i) => i + 1),
                          display: (v) => v.toString().padLeft(2, '0'),
                          onChanged: (v) => setState(() => _expiryMonth = v),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DropDown<int>(
                          value: _expiryYear,
                          items: List.generate(10, (i) => DateTime.now().year + i),
                          display: (v) => v.toString().substring(2),
                          onChanged: (v) => setState(() => _expiryYear = v),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // ── Credit Limit + Outstanding ────────────────
            Row(children: [
              Expanded(child: _cf(_limitCtrl, 'Credit Limit (₹) *', '1,00,000',
                  number: true)),
              const SizedBox(width: 12),
              Expanded(child: _cf(_outstandingCtrl, 'Current Outstanding', '0',
                  number: true)),
            ]),
            const SizedBox(height: 14),

            // ── Billing Day + Due Days ────────────────────
            _label('Billing Cycle Settings'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Statement generates on day',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                          color: AppColors.text2)),
                    Row(children: [
                      GestureDetector(
                        onTap: () => setState(() =>
                            _billingDay = math.max(1, _billingDay - 1)),
                        child: Container(width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.bg4,
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.remove_rounded,
                              size: 14, color: AppColors.text2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$_billingDay', style: const TextStyle(
                          fontFamily: 'DMMono', fontSize: 15,
                          fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() =>
                            _billingDay = math.min(28, _billingDay + 1)),
                        child: Container(width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.bg4,
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.add_rounded,
                              size: 14, color: AppColors.text2)),
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment due after (days)',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                          color: AppColors.text2)),
                    Row(children: [
                      GestureDetector(
                        onTap: () => setState(() =>
                            _dueDays = math.max(5, _dueDays - 1)),
                        child: Container(width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.bg4,
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.remove_rounded,
                              size: 14, color: AppColors.text2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$_dueDays', style: const TextStyle(
                          fontFamily: 'DMMono', fontSize: 15,
                          fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() =>
                            _dueDays = math.min(60, _dueDays + 1)),
                        child: Container(width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.bg4,
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.add_rounded,
                              size: 14, color: AppColors.text2)),
                      ),
                    ]),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Due date preview ──────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.coral.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.coral.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 13, color: AppColors.coral),
                const SizedBox(width: 8),
                Text(
                  'Next due: ${_fmtDate(_nextDueDate())}',
                  style: const TextStyle(fontFamily: 'DMMono', fontSize: 12,
                      color: AppColors.coral)),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Min due % + Annual fee ────────────────────
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Min. Due %'),
                    const SizedBox(height: 5),
                    _DropDown<double>(
                      value: _minDuePct,
                      items: const [2.0, 3.0, 5.0, 10.0, 15.0, 20.0],
                      display: (v) => '${v.toStringAsFixed(0)}%',
                      onChanged: (v) => setState(() => _minDuePct = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _cf(_annualFeeCtrl, 'Annual Fee (₹)', '0',
                  number: true)),
            ]),
            const SizedBox(height: 24),

            // ── Submit ────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Add Credit Card', style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _label(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 12,
    fontWeight: FontWeight.w500, color: AppColors.text3));

  Widget _cf(TextEditingController c, String label, String hint,
      {bool number = false, bool integer = false}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'DMSans',
            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg3,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: c,
            keyboardType: integer ? TextInputType.number
                : number ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            style: const TextStyle(fontFamily: 'DMSans',
                fontSize: 14, color: AppColors.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ],
    );
}

// ── Generic dropdown ──────────────────────────────────────────

class _DropDown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) display;
  final ValueChanged<T> onChanged;
  const _DropDown({
    required this.value, required this.items,
    required this.display, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: AppColors.bg3,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: AppColors.bg3,
        style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 13, color: AppColors.text),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        icon: const Icon(Icons.keyboard_arrow_down_rounded,
            size: 18, color: AppColors.text3),
        items: items.map((i) => DropdownMenuItem(
          value: i,
          child: Text(display(i)),
        )).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    ),
  );
}
