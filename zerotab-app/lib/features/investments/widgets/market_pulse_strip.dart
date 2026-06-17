// MarketPulseStrip — Discover's hero "what's the market doing right now" row.
//
// Position: first item inside the Discover rails ListView. NOT sticky — it
// scrolls away with the rest of the content. Sticky pulse strips are an
// anti-pattern on a tab that already has a sticky outer tab bar.
//
// Anatomy (top → bottom):
//   1. NSE/BSE market status bar — green dot + "MARKET OPEN · closes in
//      4h 23m" when the cash market is open (IST weekday 09:15–15:30), or
//      red dot + "MARKET CLOSED · opens Mon 09:15" otherwise. Computed
//      live from `DateTime.now().toUtc().add(IST offset)` — no API call.
//   2. 88 dp horizontal carousel of 4 compact AnimatedStatCards
//      (NIFTY 50, SENSEX, S&P 500, BTC) + a 5th "+ Add index" stub tile.
//
// One-shot mount fade-in: the strip fades + slides 12 dp from the top on
// first build. "Reduce Motion" respected.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../screens/holding_chart_screen.dart';
import '../services/chart_data_service.dart' show HoldingKind;
import '../../../shared/models/models.dart';
import 'animated_stat_card.dart';

class MarketPulseStrip extends ConsumerStatefulWidget {
  /// Generation int — bump on pull-to-refresh to force re-mount of the
  /// child cards and trigger a fresh fetch.
  final int generation;
  const MarketPulseStrip({super.key, this.generation = 0});

  @override
  ConsumerState<MarketPulseStrip> createState() => _MarketPulseStripState();
}

class _MarketPulseStripState extends ConsumerState<MarketPulseStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _mountCtrl;

  // Hardcoded for v1 — Add-index UI hook is a "Coming soon" stub.
  static const _tiles = <_PulseTile>[
    _PulseTile(ticker: '^NSEI', name: 'Nifty 50', exchange: 'NSI'),
    _PulseTile(ticker: '^BSESN', name: 'Sensex', exchange: 'BSE'),
    _PulseTile(ticker: '^GSPC', name: 'S&P 500', exchange: 'NMS'),
    _PulseTile(ticker: 'BTC-USD', name: 'Bitcoin', exchange: 'CCC'),
  ];

  @override
  void initState() {
    super.initState();
    _mountCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mountCtrl.forward();
    });
  }

  @override
  void dispose() {
    _mountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final status = _computeMarketStatus(DateTime.now().toUtc());

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── NSE/BSE status bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (status.isOpen ? AppColors.green : AppColors.red)
                  .withOpacity(0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: status.isOpen ? AppColors.green : AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: status.isOpen ? AppColors.green : AppColors.red,
                    letterSpacing: 0.4,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Hero strip — 4 compact cards + 1 add-index stub ──
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
          child: SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount: _tiles.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                if (i == _tiles.length) {
                  return _AddIndexStub(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coming soon'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                }
                final t = _tiles[i];
                return AnimatedStatCard(
                  key: ValueKey('pulse-${t.ticker}-${widget.generation}'),
                  ticker: t.ticker,
                  name: t.name,
                  exchange: t.exchange,
                  kind: HoldingKind.commodity,
                  compact: true,
                  mountIndex: i,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HoldingChartScreen(
                        holding: _stubHolding(),
                        kind: HoldingKind.commodity,
                        overrideSymbol: t.ticker,
                        overrideExchange: t.exchange,
                        overrideName: t.name,
                      ),
                    ));
                  },
                );
              },
            ),
          ),
        ),
      ],
    );

    if (reduceMotion) return body;
    return AnimatedBuilder(
      animation: _mountCtrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_mountCtrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -12),
            child: child,
          ),
        );
      },
      child: body,
    );
  }
}

class _AddIndexStub extends StatelessWidget {
  final VoidCallback onTap;
  const _AddIndexStub({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
            width: 0.5,
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_rounded,
                  size: 16, color: AppColors.accent),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add\nindex',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────

class _PulseTile {
  final String ticker;
  final String name;
  final String exchange;
  const _PulseTile({
    required this.ticker,
    required this.name,
    required this.exchange,
  });
}

class _MarketStatus {
  final bool isOpen;
  final String label;
  const _MarketStatus({required this.isOpen, required this.label});
}

// Compute NSE/BSE cash-market status (09:15–15:30 IST, Mon–Fri).
//
// We deliberately do this client-side, no API: the schedule is fixed,
// holidays aren't worth pulling a feed for, and the user gets a tiny
// reassurance bar that updates the instant they tap into Discover.
_MarketStatus _computeMarketStatus(DateTime nowUtc) {
  // IST = UTC+05:30 — fixed offset, no DST.
  final ist = nowUtc.add(const Duration(hours: 5, minutes: 30));
  // weekday: Mon=1 … Sun=7
  final isWeekday = ist.weekday >= DateTime.monday && ist.weekday <= DateTime.friday;
  final mins = ist.hour * 60 + ist.minute;
  const openMins = 9 * 60 + 15;
  const closeMins = 15 * 60 + 30;
  final isOpen = isWeekday && mins >= openMins && mins < closeMins;

  if (isOpen) {
    final remaining = closeMins - mins;
    final h = remaining ~/ 60;
    final m = remaining % 60;
    final timeStr =
        h > 0 ? '${h}h ${m}m' : '${m}m';
    return _MarketStatus(
      isOpen: true,
      label: 'MARKET OPEN · closes in $timeStr',
    );
  }
  // Find next opening day. Sat/Sun and after-hours weekday both fall here.
  var next = DateTime(ist.year, ist.month, ist.day, 9, 15);
  if (mins >= openMins) {
    // After close today — start from tomorrow.
    next = next.add(const Duration(days: 1));
  }
  while (next.weekday == DateTime.saturday ||
      next.weekday == DateTime.sunday) {
    next = next.add(const Duration(days: 1));
  }
  // If it's tomorrow vs Monday-ish:
  final dayLabel = _dayLabel(ist, next);
  return _MarketStatus(
    isOpen: false,
    label: 'MARKET CLOSED · opens $dayLabel 09:15',
  );
}

String _dayLabel(DateTime now, DateTime next) {
  final isTomorrow = next.day == now.day + 1 && next.month == now.month;
  if (isTomorrow) return 'tomorrow';
  switch (next.weekday) {
    case DateTime.monday:
      return 'Mon';
    case DateTime.tuesday:
      return 'Tue';
    case DateTime.wednesday:
      return 'Wed';
    case DateTime.thursday:
      return 'Thu';
    case DateTime.friday:
      return 'Fri';
    case DateTime.saturday:
      return 'Sat';
    case DateTime.sunday:
      return 'Sun';
  }
  return '';
}

MFHoldingModel _stubHolding() => MFHoldingModel(
      id: 'discover',
      userId: '',
      investedAmount: 0,
      currentValue: 0,
    );
