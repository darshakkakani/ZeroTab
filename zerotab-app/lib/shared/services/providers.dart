import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'api_service.dart';
import '../../core/constants/api_constants.dart';

// ── Auth ──────────────────────────────────────────────────

final supabaseClientProvider = Provider((_) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

// ── Financial summary (net worth totals) ──────────────────

final financialSummaryProvider = FutureProvider<FinancialSummary?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final res = await api.get(ApiConstants.accountsSummary);
    return FinancialSummary.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    // Return a zero-value summary so the home screen shows empty state
    return const FinancialSummary(
      netWorth: 0, bankBalance: 0, creditCardDebt: 0,
      loanOutstanding: 0, mfValue: 0, accounts: [],
    );
  }
});

// ── Full financial snapshot (savings rate, EMI ratio, XIRR, etc.) ──
// This powers the real stat cards on the home screen and health score

final snapshotProvider = FutureProvider<FinancialSnapshotModel?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final res = await api.get(ApiConstants.userSnapshot);
    return FinancialSnapshotModel.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

// ── Latest AI insight ─────────────────────────────────────

final latestInsightProvider = FutureProvider<AIInsightModel?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final res = await api.get(ApiConstants.insightsLatest);
    return AIInsightModel.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

// ── Accounts list ─────────────────────────────────────────

final accountsProvider = FutureProvider<List<AccountModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  try {
    final res = await api.get(ApiConstants.accounts);
    return (res.data as List)
        .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

// ── Transaction filter state — supports ADDITIVE partial updates ──

class TransactionParams {
  final String? from;
  final String? to;
  final String? category;
  final String? search;
  final int limit;
  final int offset;

  const TransactionParams({
    this.from, this.to, this.category, this.search,
    this.limit = 50, this.offset = 0,
  });

  /// Additive copy — only replaces fields that are explicitly passed
  TransactionParams copyWith({
    String? from,
    String? to,
    String? category,
    String? search,
    bool clearCategory = false,
    bool clearSearch = false,
    int? limit,
    int? offset,
  }) {
    return TransactionParams(
      from:     from     ?? this.from,
      to:       to       ?? this.to,
      category: clearCategory ? null : (category ?? this.category),
      search:   clearSearch   ? null : (search   ?? this.search),
      limit:    limit   ?? this.limit,
      offset:   offset  ?? this.offset,
    );
  }
}

final transactionParamsProvider = StateProvider((_) => const TransactionParams());

final transactionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final user   = ref.watch(currentUserProvider);
  final params = ref.watch(transactionParamsProvider);
  if (user == null) return {};
  final res = await api.get(ApiConstants.transactions, params: {
    if (params.from     != null) 'from':     params.from,
    if (params.to       != null) 'to':       params.to,
    if (params.category != null) 'category': params.category,
    if (params.search   != null) 'search':   params.search,
    'limit':  params.limit,
    'offset': params.offset,
  });
  return res.data as Map<String, dynamic>;
});

// ── Transaction summary (category totals for current month) ──

final txnSummaryProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, monthYear) async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return {};
    final parts = monthYear.split('-');
    final res = await api.get(ApiConstants.txnSummary,
        params: {'month': parts[1], 'year': parts[0]});
    return res.data as Map<String, dynamic>;
  },
);

// ── Cash flow (6 months income vs spend) ─────────────────

final cashflowProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final res = await api.get(ApiConstants.cashflow, params: {'months': '6'});
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── MF holdings ───────────────────────────────────────────

final mfHoldingsProvider = FutureProvider<List<MFHoldingModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final res = await api.get(ApiConstants.mfHoldings);
  return (res.data as List)
      .map((e) => MFHoldingModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Stock holdings ────────────────────────────────────────

final stockHoldingsProvider = FutureProvider<List<MFHoldingModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final res = await api.get(ApiConstants.stockHoldings);
  return (res.data as List)
      .map((e) => MFHoldingModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── ETF holdings ──────────────────────────────────────────

final etfHoldingsProvider = FutureProvider<List<MFHoldingModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  try {
    final res = await api.get(ApiConstants.etfHoldings);
    return (res.data as List)
        .map((e) => MFHoldingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) { return []; }
});

// ── Commodity holdings ────────────────────────────────────

final commodityHoldingsProvider = FutureProvider<List<MFHoldingModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  try {
    final res = await api.get(ApiConstants.commodityHoldings);
    return (res.data as List)
        .map((e) => MFHoldingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) { return []; }
});

// ── AI Insights feed (all recent insights) ───────────────

final insightsFeedProvider = FutureProvider<List<AIInsightModel>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  try {
    final res = await api.get(ApiConstants.insights);
    return (res.data as List)
        .map((e) => AIInsightModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

// ── User profile ──────────────────────────────────────────

final userProfileProvider = FutureProvider<UserModel?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final res = await api.get(ApiConstants.userMe);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});
