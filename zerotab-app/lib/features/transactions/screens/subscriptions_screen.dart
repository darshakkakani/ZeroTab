import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/models/models.dart';

// ── Detected subscription ─────────────────────────────────

class _Sub {
  final String merchant;
  final String category;
  final double monthlyAmount;
  final DateTime lastCharge;
  final int occurrences;
  final String cadence; // 'monthly' | 'weekly' | 'quarterly'

  const _Sub({
    required this.merchant,
    required this.category,
    required this.monthlyAmount,
    required this.lastCharge,
    required this.occurrences,
    required this.cadence,
  });

  DateTime get nextCharge {
    if (cadence == 'weekly')    return lastCharge.add(const Duration(days: 7));
    if (cadence == 'quarterly') {
      return DateTime(lastCharge.year, lastCharge.month + 3, lastCharge.day);
    }
    return DateTime(lastCharge.year, lastCharge.month + 1, lastCharge.day);
  }

  bool get isDueSoon {
    final days = nextCharge.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }
}

// ── Detection logic ───────────────────────────────────────

List<_Sub> _detectSubscriptions(List<TransactionModel> txns) {
  final debits = txns.where((t) => t.isDebit).toList();
  final byMerchant = <String, List<TransactionModel>>{};

  for (final t in debits) {
    final key = (t.merchant ?? t.description ?? '').trim().toLowerCase();
    if (key.isEmpty) continue;
    byMerchant.putIfAbsent(key, () => []).add(t);
  }

  final subs = <_Sub>[];
  for (final entry in byMerchant.entries) {
    final group = entry.value..sort((a, b) => a.txnDate.compareTo(b.txnDate));
    if (group.length < 2) continue;

    final hasRecurringFlag =
        group.any((t) => t.isRecurring || t.category == 'subscriptions');
    if (!hasRecurringFlag && group.length < 3) continue;

    final gaps = <int>[];
    for (int i = 1; i < group.length; i++) {
      gaps.add(group[i].txnDate.difference(group[i - 1].txnDate).inDays);
    }
    final avgGap = gaps.fold(0, (s, g) => s + g) / gaps.length;

    String cadence;
    double monthlyAmount;
    if (avgGap <= 10) {
      cadence = 'weekly';
      monthlyAmount = group.last.amount * 4.33;
    } else if (avgGap <= 45) {
      cadence = 'monthly';
      monthlyAmount = group.last.amount;
    } else if (avgGap <= 100) {
      cadence = 'quarterly';
      monthlyAmount = group.last.amount / 3;
    } else {
      continue;
    }

    final display = (group.last.merchant ?? group.last.description ?? entry.key);
    subs.add(_Sub(
      merchant: display.length > 28 ? '${display.substring(0, 26)}…' : display,
      category: group.last.category ?? 'subscriptions',
      monthlyAmount: monthlyAmount,
      lastCharge: group.last.txnDate,
      occurrences: group.length,
      cadence: cadence,
    ));
  }

  subs.sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
  return subs;
}

// ── Screen ────────────────────────────────────────────────

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnAsync = ref.watch(periodOnlyTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: txnAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(
              child: Text('$e',
                  style: const TextStyle(color: AppColors.red))),
          data: (txns) {
            final subs = _detectSubscriptions(txns);
            final totalMonthly = subs.fold(0.0, (s, sub) => s + sub.monthlyAmount);
            final dueSoon = subs.where((s) => s.isDueSoon).toList();

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go('/transactions'),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.bg3,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppColors.border),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: AppColors.text2, size: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Subscription Radar',
                          style: TextStyle(
                            fontFamily: 'DMSans', fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5, color: AppColors.text,
                          )),
                      ),
                    ]),
                  ),
                ),

                // Hero — total monthly burn
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.accent.withOpacity(0.15),
                            AppColors.accent2.withOpacity(0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.25)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.radar_rounded,
                              color: AppColors.accent, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Monthly Subscription Burn',
                              style: TextStyle(fontFamily: 'DMSans',
                                  fontSize: 12, color: AppColors.text3)),
                            const SizedBox(height: 4),
                            Text(formatInr(totalMonthly),
                              style: const TextStyle(
                                fontFamily: 'DMMono', fontSize: 26,
                                fontWeight: FontWeight.w700, color: AppColors.text,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                  FontFeature.liningFigures(),
                                ],
                              )),
                            const SizedBox(height: 2),
                            Text(
                              '${subs.length} recurring charge${subs.length == 1 ? '' : 's'} detected',
                              style: const TextStyle(fontFamily: 'DMSans',
                                  fontSize: 11, color: AppColors.text3)),
                          ],
                        )),
                      ]),
                    ),
                  ),
                ),

                // Due-soon alert
                if (dueSoon.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                              color: AppColors.gold.withOpacity(0.25)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.notifications_active_outlined,
                              color: AppColors.gold, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            '${dueSoon.length} charge${dueSoon.length > 1 ? 's' : ''} '
                                'due within 7 days: '
                                '${dueSoon.map((s) => s.merchant).take(2).join(', ')}'
                                '${dueSoon.length > 2 ? ' +${dueSoon.length - 2} more' : ''}',
                            style: const TextStyle(fontFamily: 'DMSans',
                                fontSize: 12, color: AppColors.gold, height: 1.4),
                          )),
                        ]),
                      ),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                if (subs.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.bg3,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border2),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.radar_rounded,
                                color: AppColors.text3, size: 28),
                          ),
                          const SizedBox(height: 16),
                          const Text('No recurring charges detected',
                            style: TextStyle(fontFamily: 'DMSans',
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: AppColors.text2)),
                          const SizedBox(height: 6),
                          const Text(
                            'Import more transactions to improve detection',
                            style: TextStyle(fontFamily: 'DMSans',
                                fontSize: 12, color: AppColors.text3)),
                        ]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.bg2,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: AppColors.border2),
                        ),
                        child: Column(
                          children: List.generate(subs.length, (i) {
                            final sub = subs[i];
                            final isLast = i == subs.length - 1;
                            return _SubRow(sub: sub, isLast: isLast);
                          }),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Subscription row ──────────────────────────────────────

class _SubRow extends StatelessWidget {
  final _Sub sub;
  final bool isLast;
  const _SubRow({super.key, required this.sub, required this.isLast});

  Color get _cadenceColor {
    switch (sub.cadence) {
      case 'weekly':    return AppColors.red;
      case 'quarterly': return AppColors.teal;
      default:          return AppColors.accent;
    }
  }

  IconData get _categoryIcon {
    switch (sub.category) {
      case 'subscriptions': return Icons.subscriptions_outlined;
      case 'entertainment': return Icons.movie_outlined;
      case 'food':          return Icons.restaurant_outlined;
      case 'health':        return Icons.favorite_border_rounded;
      case 'utilities':     return Icons.bolt_outlined;
      case 'education':     return Icons.school_outlined;
      case 'shopping':      return Icons.shopping_bag_outlined;
      default:              return Icons.repeat_rounded;
    }
  }

  static const _bbpsMap = {
    'netflix':   'https://www.netflix.com/account',
    'spotify':   'https://www.spotify.com/account/subscription',
    'amazon':    'https://www.amazon.in/gp/primecentral',
    'youtube':   'https://youtube.com/paid_memberships',
    'hotstar':   'https://www.hotstar.com/in/subscribe',
    'zee5':      'https://www.zee5.com/subscribenow',
    'sonyliv':   'https://www.sonyliv.com/settings',
    'jiocinema': 'https://jiocinema.com/',
  };

  Future<void> _openManage() async {
    final key = sub.merchant.toLowerCase();
    String? url;
    for (final entry in _bbpsMap.entries) {
      if (key.contains(entry.key)) {
        url = entry.value;
        break;
      }
    }
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysUntil = sub.nextCharge.difference(DateTime.now()).inDays;
    final dueText = daysUntil == 0
        ? 'Due today'
        : daysUntil < 0
            ? 'Overdue ${-daysUntil}d'
            : 'Due in ${daysUntil}d';
    final dueColor = daysUntil <= 0
        ? AppColors.red
        : daysUntil <= 7
            ? AppColors.gold
            : AppColors.text3;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(children: [
          // Category icon badge
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _cadenceColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cadenceColor.withOpacity(0.2)),
            ),
            alignment: Alignment.center,
            child: Icon(_categoryIcon, color: _cadenceColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sub.merchant,
                style: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.text)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _cadenceColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sub.cadence[0].toUpperCase() + sub.cadence.substring(1),
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                        fontWeight: FontWeight.w600, color: _cadenceColor)),
                ),
                const SizedBox(width: 6),
                Text(dueText,
                  style: TextStyle(fontFamily: 'DMSans',
                      fontSize: 11, color: dueColor)),
              ]),
            ],
          )),
          // Amount + manage
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatInr(sub.monthlyAmount),
              style: const TextStyle(
                fontFamily: 'DMMono', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.text,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
            const Text('/mo', style: TextStyle(fontFamily: 'DMSans',
                fontSize: 10, color: AppColors.text3)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _openManage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border2),
                ),
                child: const Text('Manage',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                      fontWeight: FontWeight.w600, color: AppColors.text3)),
              ),
            ),
          ]),
        ]),
      ),
      if (!isLast)
        const Divider(color: AppColors.border, height: 1, indent: 66),
    ]);
  }
}
