import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

/// Call this after ANY data mutation (add account, transaction, etc.)
/// Invalidates ALL financial providers so every screen updates instantly.
///
/// This is the global "sync signal" — one call keeps the entire app fresh.
void refreshAllFinancialData(WidgetRef ref) {
  ref.invalidate(financialSummaryProvider);
  ref.invalidate(snapshotProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(latestInsightProvider);
  ref.invalidate(mfHoldingsProvider);
  ref.invalidate(insightsFeedProvider);
  ref.invalidate(userProfileProvider);
  ref.invalidate(cashflowProvider);
}
