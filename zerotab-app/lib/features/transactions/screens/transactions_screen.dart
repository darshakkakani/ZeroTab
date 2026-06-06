import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/widgets/zt_card.dart';

// ── Time period enum ──────────────────────────────────────────

enum _TimePeriod { today, week, month, threeM, year, all }

extension _TimePeriodExt on _TimePeriod {
  String get label {
    switch (this) {
      case _TimePeriod.today:  return 'Today';
      case _TimePeriod.week:   return '7D';
      case _TimePeriod.month:  return 'Month';
      case _TimePeriod.threeM: return '3M';
      case _TimePeriod.year:   return 'Year';
      case _TimePeriod.all:    return 'All';
    }
  }

  /// Returns (fromDate, toDate) ISO strings, or (null, null) for All
  (String?, String?) get range {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    switch (this) {
      case _TimePeriod.today:
        return (today, today);
      case _TimePeriod.week:
        return (DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7))), today);
      case _TimePeriod.month:
        final start = DateTime(now.year, now.month, 1);
        return (DateFormat('yyyy-MM-dd').format(start), today);
      case _TimePeriod.threeM:
        return (DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 90))), today);
      case _TimePeriod.year:
        final start = DateTime(now.year, 1, 1);
        return (DateFormat('yyyy-MM-dd').format(start), today);
      case _TimePeriod.all:
        return (null, null);
    }
  }
}

// ── Category metadata ─────────────────────────────────────────

class _CatMeta {
  final String key;
  final String label;
  final Color color;
  const _CatMeta(this.key, this.label, this.color);
}

const _allCats = [
  _CatMeta('food_delivery', 'Food',          AppColors.coral),
  _CatMeta('grocery',       'Grocery',        AppColors.green),
  _CatMeta('shopping',      'Shopping',       AppColors.accent),
  _CatMeta('emi',           'EMI',            AppColors.gold),
  _CatMeta('fuel',          'Fuel',           AppColors.amber),
  _CatMeta('utilities',     'Utilities',      AppColors.accent2),
  _CatMeta('transport',     'Transport',      AppColors.teal),
  _CatMeta('entertainment', 'Entertainment',  AppColors.pink),
  _CatMeta('health',        'Health',         AppColors.teal),
  _CatMeta('investment',    'Investment',     AppColors.green),
  _CatMeta('subscriptions', 'Subscriptions',  AppColors.green),
  _CatMeta('insurance',     'Insurance',      AppColors.gold),
  _CatMeta('income',        'Income',         AppColors.green),
  _CatMeta('others',        'Others',         AppColors.text3),
];

Color _catColor(String cat) {
  for (final c in _allCats) {
    if (c.key == cat) return c.color;
  }
  return AppColors.text3;
}

// ── Merchant category hints (shared between screen & sheet) ───
const Map<String, String> _merchantCategoryHints = {
  // Transport — MUST check before food
  'ola':        'transport', 'uber':    'transport', 'rapido':   'transport',
  'metro':      'transport', 'irctc':   'transport', 'taxify':   'transport',
  'cab':        'transport', 'taxi':    'transport', 'auto':     'transport',
  'bus':        'transport', 'train':   'transport', 'flight':   'transport',
  'indigo':     'transport', 'spicejet':'transport', 'air india':'transport',
  'makemytrip': 'transport', 'goibibo': 'transport', 'redbus':   'transport',
  // Food
  'zomato':     'food_delivery', 'swiggy':   'food_delivery', 'dunzo':  'food_delivery',
  'blinkit':    'food_delivery', 'zepto':    'food_delivery', 'instamart':'food_delivery',
  'starbucks':  'food_delivery', 'dominos':  'food_delivery', 'kfc':    'food_delivery',
  'mcd':        'food_delivery', 'mcdonalds':'food_delivery', 'burger king':'food_delivery',
  'pizza hut':  'food_delivery', 'subway':   'food_delivery', 'chai':   'food_delivery',
  // Fuel
  'bpcl':       'fuel', 'indian oil':'fuel', 'iocl':'fuel',
  'shell':      'fuel', 'petrol':    'fuel', 'diesel':'fuel', 'hp petrol':'fuel',
  // Utilities
  'bescom':     'utilities', 'airtel':   'utilities', 'jio':        'utilities',
  'bsnl':       'utilities', 'electricity':'utilities', 'broadband': 'utilities',
  'recharge':   'utilities', 'tata sky':  'utilities', 'dish tv':   'utilities',
  // Subscriptions
  'netflix':    'subscriptions', 'spotify': 'subscriptions', 'prime': 'subscriptions',
  'hotstar':    'subscriptions', 'disney':  'subscriptions', 'youtube premium':'subscriptions',
  'zee5':       'subscriptions', 'sonyliv': 'subscriptions', 'mxplayer':'subscriptions',
  // Grocery
  'big bazaar': 'grocery', 'dmart':     'grocery', 'bigbasket': 'grocery',
  'jiomart':    'grocery', 'grofers':   'grocery', 'fresh':     'grocery',
  'reliance fresh':'grocery', 'spar':   'grocery', 'nature basket':'grocery',
  'milk':       'grocery', 'dairy':     'grocery', 'amul':      'grocery',
  'mother dairy':'grocery','milkbasket':'grocery', 'bread':     'grocery',
  'eggs':       'grocery', 'vegetables':'grocery', 'fruits':    'grocery',
  'supermarket':'grocery', 'provisions':'grocery', 'kirana':    'grocery',
  'local market':'grocery','sabji':     'grocery', 'sabzi':     'grocery',
  // Shopping
  'amazon':     'shopping', 'flipkart': 'shopping', 'myntra':   'shopping',
  'meesho':     'shopping', 'nykaa':    'shopping', 'ajio':     'shopping',
  'decathlon':  'shopping', 'croma':    'shopping', 'vijay sales':'shopping',
  // Entertainment — movies, events, gaming
  'pvr':        'entertainment', 'inox':       'entertainment',
  'cinepolis':  'entertainment', 'cineplex':   'entertainment',
  'bookmyshow': 'entertainment', 'movie':      'entertainment',
  'cinema':     'entertainment', 'multiplex':  'entertainment',
  'lenskart':   'entertainment', 'gaming':     'entertainment',
  'steam':      'entertainment', 'playstation':'entertainment',
  'xbox':       'entertainment', 'event':      'entertainment',
  // Health — pharmacy, gym, doctors
  'apollo':     'health', 'medplus':  'health', '1mg':       'health',
  'pharmeasy':  'health', 'hospital': 'health', 'clinic':    'health',
  'practo':     'health', 'thyrocare':'health', 'lal path':  'health',
  'narayana':   'health', 'fortis':   'health', 'max hospital':'health',
  'gym':        'health', 'fitness':  'health', 'cult fit':  'health',
  'cult.fit':   'health', 'healthify':'health', 'yoga':      'health',
  'doctor':     'health', 'dr ':      'health', 'medicine':  'health',
  'pharmacy':   'health', 'chemist':  'health', 'diagnostic':'health',
  'dental':     'health', 'ortho':    'health', 'physio':    'health',
  // Insurance
  'lic':        'insurance', 'insurance':'insurance', 'hdfc life':'insurance',
  'icici pru':  'insurance', 'star health':'insurance', 'bajaj allianz':'insurance',
  'max life':   'insurance', 'tata aig':  'insurance', 'policy':    'insurance',
  // Investments
  'sip':        'investment', 'groww':   'investment', 'zerodha': 'investment',
  'kuvera':     'investment', 'coin':    'investment', 'ppf':     'investment',
  'nps':        'investment', 'elss':    'investment', 'mutual fund':'investment',
  'smallcase':  'investment', 'paytm money':'investment', 'et money':'investment',
  // EMI
  'loan emi':   'emi', 'home loan':'emi', 'car loan':'emi', 'emi payment':'emi',
  'hdfc bank emi':'emi', 'icici emi':'emi', 'bajaj finance':'emi',
  'no cost emi':'emi', 'loan repayment':'emi',
  // Income
  'salary':     'income', 'sal credit':'income', 'payroll':  'income',
  'freelance':  'income', 'bonus':     'income', 'incentive':'income',
  'dividend':   'income', 'interest':  'income', 'rent received':'income',
  'cashback':   'income', 'refund':    'income', 'reward':   'income',
};

String? _autoSuggestCategory(String merchant) {
  final m = merchant.toLowerCase();
  for (final entry in _merchantCategoryHints.entries) {
    if (m.contains(entry.key)) return entry.value;
  }
  return null;
}

// ── Premium dark toast (replaces colored SnackBars) ───────────
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

// ── Main screen ───────────────────────────────────────────────

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchCtrl = TextEditingController();
  String       _filterLabel = 'All';
  _TimePeriod  _period      = _TimePeriod.month;
  bool         _recategorizing = false;

  static const _chips = [
    ('All',           null),
    ('Food',          'food_delivery'),
    ('Grocery',       'grocery'),
    ('Shopping',      'shopping'),
    ('EMI',           'emi'),
    ('Fuel',          'fuel'),
    ('Utilities',     'utilities'),
    ('Transport',     'transport'),
    ('Entertainment', 'entertainment'),
    ('Investment',    'investment'),
    ('Subscriptions', 'subscriptions'),
    ('Health',        'health'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyPeriod(_TimePeriod p) {
    setState(() => _period = p);
    final (from, to) = p.range;
    ref.read(transactionParamsProvider.notifier).update((s) => TransactionParams(
      from:     from,
      to:       to,
      category: s.category,
      search:   s.search,
      limit:    s.limit,
      offset:   0,
    ));
  }

  void _applyCategory(String? cat, String label) {
    setState(() => _filterLabel = label);
    ref.read(transactionParamsProvider.notifier).update(
        (s) => cat == null ? s.copyWith(clearCategory: true) : s.copyWith(category: cat));
  }

  Future<void> _recategorize() async {
    setState(() => _recategorizing = true);
    try {
      // Step 1 — backend pass
      final res = await api.post('/transactions/recategorize');
      int fixed = (res.data as Map?)?['fixed'] as int? ?? 0;

      // Step 2 — frontend smart pass: fetch current transactions and
      //          fix any that are still 'others' but we know the merchant
      try {
        final txnRes = await api.get(ApiConstants.transactions,
            params: {'limit': 200});
        final rawList = (txnRes.data as Map?)?['data'] as List? ?? [];
        final futures = <Future<void>>[];

        for (final raw in rawList) {
          final txn = TransactionModel.fromJson(raw as Map<String, dynamic>);
          if ((txn.category ?? 'others') == 'others') {
            final merchant = txn.merchant ?? txn.description ?? '';
            final suggested = _autoSuggestCategory(merchant);
            if (suggested != null && suggested != 'others') {
              futures.add(
                api.patch('${ApiConstants.transactions}/${txn.id}',
                    data: {'category': suggested}).then((_) {
                  fixed++;
                }).catchError((_) {}),
              );
            }
          }
        }

        if (futures.isNotEmpty) await Future.wait(futures);
      } catch (_) {
        // frontend pass is best-effort — don't fail the whole operation
      }

      ref.invalidate(transactionsProvider);
      if (mounted) {
        _showPremiumSnackBar(
          context,
          fixed > 0
              ? 'Fixed $fixed transaction categories'
              : 'Categories up to date',
          success: true,
        );
      }
    } catch (_) {
      if (mounted) {
        _showPremiumSnackBar(context, 'Recategorize failed', success: false);
      }
    } finally {
      if (mounted) setState(() => _recategorizing = false);
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTransactionSheet(onAdded: () {
        ref.invalidate(transactionsProvider);
        ref.invalidate(financialSummaryProvider);
        ref.invalidate(snapshotProvider);
      }),
    );
  }

  void _showPeriodSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border2),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
            child: Text('Time period', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
              fontWeight: FontWeight.w700, color: AppColors.text))),
          const SizedBox(height: 14),
          ..._TimePeriod.values.map((p) {
            final active = _period == p;
            final label = p == _TimePeriod.month
                ? DateFormat('MMMM yyyy').format(DateTime.now()) : p.label;
            return GestureDetector(
              onTap: () { Navigator.pop(context); _applyPeriod(p); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: active ? AppColors.accent.withOpacity(0.12) : AppColors.bg3,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: active ? AppColors.accent.withOpacity(0.4) : AppColors.border),
                ),
                child: Row(children: [
                  Text(label, style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w500, color: active ? AppColors.accent2 : AppColors.text)),
                  const Spacer(),
                  if (active) Icon(Icons.check_rounded, size: 16, color: AppColors.accent2),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Future<bool> _deleteTransaction(TransactionModel txn) async {
    try {
      await api.delete('${ApiConstants.transactions}/${txn.id}');
      ref.invalidate(transactionsProvider);
      ref.invalidate(financialSummaryProvider);
      ref.invalidate(snapshotProvider);
      if (mounted) {
        _showPremiumSnackBar(context, 'Transaction deleted', success: true);
      }
      return true;
    } catch (e) {
      if (mounted) {
        _showPremiumSnackBar(context, 'Delete failed', success: false);
      }
      return false;
    }
  }

  String get _periodLabel {
    if (_period == _TimePeriod.month) return DateFormat('MMM yyyy').format(DateTime.now());
    return _period.label;
  }

  @override
  Widget build(BuildContext context) {
    final txnAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: _UniformFAB(onTap: _showAddSheet),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Transactions', style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 24,
                    fontWeight: FontWeight.w700, letterSpacing: -0.8, color: AppColors.text)),
                ),
                // Period selector chip
                GestureDetector(
                  onTap: _showPeriodSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.accent.withOpacity(0.22)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_periodLabel, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
                        fontWeight: FontWeight.w500, color: AppColors.accent2)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.accent2),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                // Recategorize
                GestureDetector(
                  onTap: _recategorizing ? null : _recategorize,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.bg3,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: _recategorizing
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                        : const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.teal),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Spending summary card ─────────────────────
            txnAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (data) {
                final txns = (data['data'] as List? ?? [])
                    .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
                    .toList();
                if (txns.isEmpty) return const SizedBox.shrink();
                final totalDebit  = txns.where((t) => t.isDebit).fold(0.0, (s, t) => s + t.amount);
                final totalCredit = txns.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
                final net = totalCredit - totalDebit;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF0E0A1E), Color(0xFF080611)]),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: AppColors.border2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _SummaryPill('Spent', '−${formatInr(totalDebit, compact: true)}', AppColors.coral),
                        Container(width: 1, height: 28, color: AppColors.border),
                        _SummaryPill('Income', '+${formatInr(totalCredit, compact: true)}', AppColors.green),
                        Container(width: 1, height: 28, color: AppColors.border),
                        _SummaryPill('Net', '${net >= 0 ? '+' : ''}${formatInr(net.abs(), compact: true)}',
                          net >= 0 ? AppColors.green : AppColors.coral),
                        Container(width: 1, height: 28, color: AppColors.border),
                        _SummaryPill('Count', '${txns.length}', AppColors.text2),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // ── Search bar ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF12102A),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.search_rounded,
                    color: _searchCtrl.text.isNotEmpty
                        ? AppColors.accent2
                        : AppColors.text3,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 14,
                          color: AppColors.text,
                          letterSpacing: -0.1),
                      decoration: const InputDecoration(
                        hintText: 'Search transactions…',
                        hintStyle: TextStyle(
                            color: AppColors.text3,
                            fontSize: 14,
                            letterSpacing: -0.1),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setState(() {});
                        ref.read(transactionParamsProvider.notifier).update(
                            (s) => v.isEmpty
                                ? s.copyWith(clearSearch: true)
                                : s.copyWith(search: v));
                      },
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        ref.read(transactionParamsProvider.notifier)
                            .update((s) => s.copyWith(clearSearch: true));
                        setState(() {});
                      },
                      child: Container(
                        width: 24, height: 24,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: AppColors.bg4,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.text3, size: 12),
                      ),
                    )
                  else
                    const SizedBox(width: 14),
                ]),
              ),
            ),
            const SizedBox(height: 8),

            // ── Category filter chips ─────────────────────
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _chips.map((c) {
                  final active = _filterLabel == c.$1;
                  final catColor = c.$2 != null ? _catColor(c.$2!) : AppColors.accent;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () => _applyCategory(c.$2, c.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        decoration: BoxDecoration(
                          color: active ? catColor.withOpacity(0.15) : AppColors.bg3,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: active ? catColor.withOpacity(0.45) : AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            c.$1,
                            style: TextStyle(
                              fontFamily: 'DMSans', fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: active ? catColor : AppColors.text2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),

            // ── Transaction list ─────────────────────────
            Expanded(
              child: txnAsync.when(
                loading: () => _buildShimmer(),
                error: (e, _) => Center(
                  child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
                data: (data) {
                  final txns = (data['data'] as List? ?? [])
                      .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
                      .toList();
                  if (txns.isEmpty) return _EmptyState(onAdd: _showAddSheet);
                  return _TransactionList(txns: txns, onDelete: _deleteTransaction);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() => ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    itemCount: 5,
    itemBuilder: (_, i) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ZTShimmerBox(width: double.infinity, height: 62, radius: AppRadius.lg),
    ),
  );
}

// ── Summary pill ──────────────────────────────────────────────

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _SummaryPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontFamily: 'DMMono', fontSize: 16,
        fontWeight: FontWeight.w700, color: color)),
    ],
  );
}

// ── Add Transaction Bottom Sheet ─────────────────────────────

class _AddTransactionSheet extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddTransactionSheet({required this.onAdded});

  @override
  ConsumerState<_AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<_AddTransactionSheet> {
  final _amountCtrl   = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _noteCtrl     = TextEditingController();

  bool   _isExpense          = true;
  String _category           = 'food_delivery';
  bool   _categoryManuallySet = false;   // ← prevents auto-suggest overwriting user choice
  DateTime _date = DateTime.now();
  bool   _loading = false;

  void _onMerchantChanged() {
    if (!_isExpense || _categoryManuallySet) return;
    final suggested = _autoSuggestCategory(_merchantCtrl.text);
    if (suggested != null && suggested != _category) {
      setState(() => _category = suggested);
    }
  }

  @override
  void initState() {
    super.initState();
    _merchantCtrl.addListener(_onMerchantChanged);
  }

  static const _sheetCats = [
    _CatMeta('food_delivery', 'Food',         AppColors.coral),
    _CatMeta('grocery',       'Grocery',       AppColors.green),
    _CatMeta('shopping',      'Shopping',      AppColors.accent),
    _CatMeta('emi',           'EMI',           AppColors.gold),
    _CatMeta('fuel',          'Fuel',          AppColors.amber),
    _CatMeta('utilities',     'Utilities',     AppColors.accent2),
    _CatMeta('transport',     'Transport',     AppColors.teal),
    _CatMeta('entertainment', 'Entertainment', AppColors.pink),
    _CatMeta('health',        'Health',        AppColors.teal),
    _CatMeta('investment',    'Investment',    AppColors.green),
    _CatMeta('subscriptions', 'Subscriptions', AppColors.green),
    _CatMeta('insurance',     'Insurance',     AppColors.gold),
    _CatMeta('income',        'Income',        AppColors.green),
    _CatMeta('others',        'Others',        AppColors.text3),
  ];

  @override
  void dispose() {
    _merchantCtrl.removeListener(_onMerchantChanged);
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amtStr = _amountCtrl.text.trim();
    if (amtStr.isEmpty) return;
    final amount = double.tryParse(amtStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid amount'), backgroundColor: AppColors.red));
      return;
    }
    setState(() => _loading = true);
    try {
      final accountsRes = ref.read(accountsProvider);
      final accountId   = accountsRes.value?.isNotEmpty == true
          ? accountsRes.value!.first.id : null;

      await api.post(ApiConstants.transactions, data: {
        'txn_date':    DateFormat('yyyy-MM-dd').format(_date),
        'amount':      amount,
        'type':        _isExpense ? 'debit' : 'credit',
        'category':    _isExpense ? _category : 'income',
        'merchant':    _merchantCtrl.text.trim().isEmpty
                         ? categoryDisplayName(_category)
                         : _merchantCtrl.text.trim(),
        'description': _noteCtrl.text.trim(),
        if (accountId != null) 'account_id': accountId,
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAdded();
        _showPremiumSnackBar(context, 'Transaction added', success: true);
      }
    } catch (e) {
      if (mounted) _showPremiumSnackBar(context, 'Failed: ${apiErrorMessage(e)}', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.bg3)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
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

            const Text('Add Transaction', style: TextStyle(fontFamily: 'DMSans', fontSize: 17,
              fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.text)),
            const SizedBox(height: 20),

            // ── Expense / Income toggle ──
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Expanded(child: _toggle('Expense', true)),
                Expanded(child: _toggle('Income',  false)),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Amount ──
            _label('Amount (₹)'),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                style: const TextStyle(fontFamily: 'DMMono', fontSize: 20,
                  fontWeight: FontWeight.w600, color: AppColors.text),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  hintStyle: TextStyle(color: AppColors.text3, fontFamily: 'DMMono', fontSize: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Category (only when expense) ──
            if (_isExpense) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _label('Category'),
                  if (_categoryManuallySet)
                    GestureDetector(
                      onTap: () => setState(() => _categoryManuallySet = false),
                      child: const Text('Auto', style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 11, color: AppColors.accent2)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _sheetCats.map((c) {
                    final active = _category == c.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _category = c.key;
                          _categoryManuallySet = true;  // user explicitly chose a category
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          decoration: BoxDecoration(
                            color: active ? c.color.withOpacity(0.18) : AppColors.bg3,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: active ? c.color.withOpacity(0.5) : AppColors.border),
                          ),
                          child: Center(child: Text(c.label, style: TextStyle(
                            fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w500,
                            color: active ? c.color : AppColors.text2))),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ── Merchant / Payee ──
            _label(_isExpense ? 'Merchant / Payee' : 'Source'),
            const SizedBox(height: 6),
            _textField(_merchantCtrl, _isExpense ? 'e.g. Zomato, Amazon, BESCOM…' : 'e.g. TCS Salary, Freelance…'),
            const SizedBox(height: 14),

            // ── Date ──
            _label('Date'),
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
                  Text(DateFormat('d MMM yyyy').format(_date), style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 14, color: AppColors.text)),
                ]),
              ),
            ),
            const SizedBox(height: 14),

            // ── Note ──
            _label('Note (optional)'),
            const SizedBox(height: 6),
            _textField(_noteCtrl, 'Add a short note…'),
            const SizedBox(height: 24),

            // ── Submit ──
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.accent.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isExpense ? 'Add Expense' : 'Add Income', style: const TextStyle(
                        fontFamily: 'DMSans', fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool isExpense) {
    final active = _isExpense == isExpense;
    return GestureDetector(
      onTap: () => setState(() { _isExpense = isExpense; _categoryManuallySet = false; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: active ? (isExpense ? AppColors.red : AppColors.green) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontFamily: 'DMSans', fontSize: 13, fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.text2)),
      ),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text3));

  Widget _textField(TextEditingController c, String hint) => Container(
    decoration: BoxDecoration(
      color: AppColors.bg3,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border),
    ),
    child: TextField(
      controller: c,
      style: const TextStyle(fontFamily: 'DMSans', fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
  );
}

// ── Grouped transaction list ──────────────────────────────────

class _TransactionList extends StatelessWidget {
  final List<TransactionModel> txns;
  final Future<bool> Function(TransactionModel) onDelete;
  const _TransactionList({required this.txns, required this.onDelete});

  Map<String, List<TransactionModel>> _group() {
    final map = <String, List<TransactionModel>>{};
    for (final t in txns) {
      final key = formatDateFull(t.txnDate);
      (map[key] ??= []).add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _group();
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      children: groups.entries.map((e) {
        // Date header + day total
        final dayDebit  = e.value.where((t) => t.isDebit).fold(0.0, (s, t) => s + t.amount);
        final dayCredit = e.value.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(children: [
                Text(e.key, style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 11, fontWeight: FontWeight.w600,
                  letterSpacing: 0.2, color: AppColors.text3)),
                const Spacer(),
                if (dayDebit > 0)
                  Text('−${formatInr(dayDebit, compact: true)}',
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                      color: AppColors.coral, fontWeight: FontWeight.w500)),
                if (dayDebit > 0 && dayCredit > 0)
                  const Text('  ·  ', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                if (dayCredit > 0)
                  Text('+${formatInr(dayCredit, compact: true)}',
                    style: const TextStyle(fontFamily: 'DMMono', fontSize: 11,
                      color: AppColors.green, fontWeight: FontWeight.w500)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Container(
                  decoration: AppDecorations.card(radius: AppRadius.xl),
                  child: Column(
                    children: List.generate(e.value.length, (i) {
                      final txn = e.value[i];
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        Dismissible(
                          key: Key('txn-${txn.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: AppColors.red.withOpacity(0.10),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 18),
                              const SizedBox(height: 2),
                              const Text('Delete', style: TextStyle(fontFamily: 'DMSans',
                                fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.red)),
                            ]),
                          ),
                          confirmDismiss: (_) async {
                            // First show confirmation dialog
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.bg2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.xl),
                                  side: const BorderSide(color: AppColors.border2)),
                                title: const Text('Delete transaction?', style: TextStyle(
                                  fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w600,
                                  color: AppColors.text)),
                                content: Text(
                                  '${txn.merchant ?? txn.description ?? 'Transaction'}  ·  ${formatInr(txn.amount)}',
                                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                                    color: AppColors.text2)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel', style: TextStyle(color: AppColors.text2))),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete', style: TextStyle(
                                      color: AppColors.red, fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ) ?? false;
                            
                            // If user cancelled, don't dismiss
                            if (!confirmed) return false;
                            
                            // If confirmed, perform the actual delete and return the result
                            return await onDelete(txn);
                          },
                          child: _TxnItem(txn: txn),
                        ),
                        if (i < e.value.length - 1)
                          const Divider(color: AppColors.border, height: 1, indent: 66),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ── Transaction row ───────────────────────────────────────────

class _TxnItem extends StatelessWidget {
  final TransactionModel txn;
  const _TxnItem({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.isCredit;
    final cat      = txn.category ?? 'others';
    final color    = _catColor(cat);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        // Category icon circle (Splitwise-style, prominent)
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.13),
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
          ),
          alignment: Alignment.center,
          child: SizedBox(width: 20, height: 20,
            child: CustomPaint(painter: _CategoryIconPainter(cat: cat, color: color))),
        ),
        const SizedBox(width: 12),
        // Description + category label
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              txn.merchant ?? txn.description ?? 'Transaction',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
                fontWeight: FontWeight.w500, color: AppColors.text, height: 1.2),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(categoryDisplayName(cat), style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w500,
                  color: color)),
              ),
            ]),
          ],
        )),
        const SizedBox(width: 8),
        // Amount column
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            isCredit ? '+${formatInr(txn.amount)}' : '−${formatInr(txn.amount)}',
            style: TextStyle(
              fontFamily: 'DMMono', fontSize: 14, fontWeight: FontWeight.w600,
              color: isCredit ? AppColors.green : AppColors.text),
          ),
          Text(
            DateFormat('h:mm a').format(txn.txnDate),
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 9, color: AppColors.text3),
          ),
        ]),
      ]),
    );
  }
}

// ── Category icon painter ─────────────────────────────────────

class _CategoryIconPainter extends CustomPainter {
  final String cat;
  final Color  color;
  const _CategoryIconPainter({required this.cat, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (cat) {
      case 'food_delivery':
        canvas.drawLine(Offset(w * 0.28, h * 0.1), Offset(w * 0.28, h * 0.9), p);
        canvas.drawLine(Offset(w * 0.28, h * 0.1), Offset(w * 0.20, h * 0.38), p);
        canvas.drawLine(Offset(w * 0.28, h * 0.1), Offset(w * 0.36, h * 0.38), p);
        canvas.drawLine(Offset(w * 0.72, h * 0.1), Offset(w * 0.72, h * 0.38),
            p..strokeWidth = 3.0..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(w * 0.72, h * 0.38), Offset(w * 0.72, h * 0.9),
            p..strokeWidth = 1.5);
        break;

      case 'grocery':
        canvas.drawArc(Rect.fromLTWH(w * 0.1, h * 0.3, w * 0.8, h * 0.6), 0, 3.14159, false, p);
        canvas.drawLine(Offset(w * 0.1, h * 0.3), Offset(w * 0.9, h * 0.3), p);
        canvas.drawLine(Offset(w * 0.3, h * 0.3), Offset(w * 0.18, h * 0.08), p);
        canvas.drawLine(Offset(w * 0.7, h * 0.3), Offset(w * 0.82, h * 0.08), p);
        break;

      case 'shopping':
        final bag = Path()
          ..moveTo(w * 0.20, h * 0.38)..lineTo(w * 0.12, h * 0.90)
          ..lineTo(w * 0.88, h * 0.90)..lineTo(w * 0.80, h * 0.38)..close();
        canvas.drawPath(bag, p);
        final handle = Path()
          ..moveTo(w * 0.34, h * 0.38)
          ..quadraticBezierTo(w * 0.34, h * 0.16, w * 0.50, h * 0.16)
          ..quadraticBezierTo(w * 0.66, h * 0.16, w * 0.66, h * 0.38);
        canvas.drawPath(handle, p);
        break;

      case 'emi':
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.10, h * 0.22, w * 0.80, h * 0.68), const Radius.circular(3)), p);
        canvas.drawLine(Offset(w * 0.10, h * 0.42), Offset(w * 0.90, h * 0.42), p);
        canvas.drawLine(Offset(w * 0.33, h * 0.10), Offset(w * 0.33, h * 0.32), p);
        canvas.drawLine(Offset(w * 0.67, h * 0.10), Offset(w * 0.67, h * 0.32), p);
        for (final dx in [0.30, 0.50, 0.70]) {
          for (final dy in [0.57, 0.75]) {
            canvas.drawCircle(Offset(w * dx, h * dy), 1.5, p..style = PaintingStyle.fill);
          }
        }
        p.style = PaintingStyle.stroke;
        break;

      case 'fuel':
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.15, h * 0.20, w * 0.50, h * 0.72), const Radius.circular(3)), p);
        canvas.drawLine(Offset(w * 0.65, h * 0.20), Offset(w * 0.85, h * 0.20), p);
        canvas.drawLine(Offset(w * 0.85, h * 0.20), Offset(w * 0.85, h * 0.50), p);
        canvas.drawLine(Offset(w * 0.85, h * 0.50), Offset(w * 0.70, h * 0.50), p);
        break;

      case 'utilities':
        final bolt = Path()
          ..moveTo(w * 0.60, h * 0.08)..lineTo(w * 0.30, h * 0.52)
          ..lineTo(w * 0.52, h * 0.52)..lineTo(w * 0.40, h * 0.92)
          ..lineTo(w * 0.70, h * 0.48)..lineTo(w * 0.48, h * 0.48)..close();
        canvas.drawPath(bolt, p..style = PaintingStyle.stroke);
        break;

      case 'transport':
        final car = Path()
          ..moveTo(w * 0.08, h * 0.65)..lineTo(w * 0.22, h * 0.40)
          ..lineTo(w * 0.50, h * 0.30)..lineTo(w * 0.78, h * 0.40)
          ..lineTo(w * 0.92, h * 0.65)..lineTo(w * 0.08, h * 0.65);
        canvas.drawPath(car, p);
        canvas.drawCircle(Offset(w * 0.28, h * 0.72), w * 0.10, p);
        canvas.drawCircle(Offset(w * 0.72, h * 0.72), w * 0.10, p);
        break;

      case 'entertainment':
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.10, h * 0.20, w * 0.80, h * 0.60), const Radius.circular(3)), p);
        for (final x in [0.10, 0.78]) {
          for (final y in [0.20, 0.42, 0.64]) {
            canvas.drawRect(Rect.fromLTWH(w * x, h * y, w * 0.12, h * 0.16),
                Paint()..color = color.withOpacity(0.5)..style = PaintingStyle.fill);
          }
        }
        p..style = PaintingStyle.stroke..color = color;
        break;

      case 'health':
        canvas.drawLine(Offset(w * 0.50, h * 0.15), Offset(w * 0.50, h * 0.85), p);
        canvas.drawLine(Offset(w * 0.15, h * 0.50), Offset(w * 0.85, h * 0.50), p);
        break;

      case 'investment':
        final trend = Path()
          ..moveTo(w * 0.10, h * 0.80)..lineTo(w * 0.35, h * 0.50)
          ..lineTo(w * 0.58, h * 0.65)..lineTo(w * 0.90, h * 0.20);
        canvas.drawPath(trend, p);
        canvas.drawLine(Offset(w * 0.72, h * 0.20), Offset(w * 0.90, h * 0.20), p);
        canvas.drawLine(Offset(w * 0.90, h * 0.20), Offset(w * 0.90, h * 0.38), p);
        break;

      case 'subscriptions':
        final arc1 = Path()..addArc(
          Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.70, height: h * 0.70),
          0.3, 2.5);
        canvas.drawPath(arc1, p);
        canvas.drawLine(Offset(w * 0.80, h * 0.28), Offset(w * 0.90, h * 0.42), p);
        canvas.drawLine(Offset(w * 0.90, h * 0.42), Offset(w * 0.74, h * 0.44), p);
        break;

      case 'income':
        canvas.drawLine(Offset(w * 0.50, h * 0.10), Offset(w * 0.50, h * 0.68), p);
        canvas.drawLine(Offset(w * 0.30, h * 0.48), Offset(w * 0.50, h * 0.68), p);
        canvas.drawLine(Offset(w * 0.70, h * 0.48), Offset(w * 0.50, h * 0.68), p);
        canvas.drawLine(Offset(w * 0.10, h * 0.88), Offset(w * 0.90, h * 0.88), p);
        break;

      default:
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.14, h * 0.06, w * 0.72, h * 0.88), const Radius.circular(3)), p);
        canvas.drawLine(Offset(w * 0.28, h * 0.35), Offset(w * 0.72, h * 0.35), p);
        canvas.drawLine(Offset(w * 0.28, h * 0.52), Offset(w * 0.72, h * 0.52), p);
        canvas.drawLine(Offset(w * 0.28, h * 0.68), Offset(w * 0.54, h * 0.68), p);
    }
  }

  @override
  bool shouldRepaint(_CategoryIconPainter old) => old.cat != cat || old.color != color;
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.receipt_long_outlined, size: 26, color: AppColors.text3),
          ),
          const SizedBox(height: 18),
          const Text('No transactions yet', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 16,
            fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text('Add one manually or load demo data', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 13, color: AppColors.text3)),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text('Add transaction', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 13,
                fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
