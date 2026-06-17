// MarketPulseStrip — Discover's hero "what's the market doing right now" row.
//
// Position: first item inside the Discover rails ListView. NOT sticky — it
// scrolls away with the rest of the content. Sticky pulse strips are an
// anti-pattern on a tab that already has a sticky outer tab bar.
//
// Anatomy:
//   • 88 dp horizontal carousel of 4 compact AnimatedStatCards
//     (NIFTY 50, SENSEX, S&P 500, BTC) + a 5th "+ Add index" stub tile.
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

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

MFHoldingModel _stubHolding() => MFHoldingModel(
      id: 'discover',
      userId: '',
      investedAmount: 0,
      currentValue: 0,
    );
