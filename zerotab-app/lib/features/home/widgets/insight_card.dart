import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../core/utils/formatters.dart';

class InsightCard extends StatelessWidget {
  final AIInsightModel insight;
  const InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/insight/${insight.id}'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF100820), Color(0xFF07060F)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: const Color(0x287B5FFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
              children: [
                _PulsingDot(),
                const SizedBox(width: 8),
                const Text(
                  'AI CFO',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.teal,
                    letterSpacing: 0.05,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Week of ${formatDate(insight.generatedAt)}',
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                ),
                const Spacer(),
                if (insight.insightType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.goldSoft,
                      borderRadius:
                          BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      insight.insightType!
                          .toUpperCase()
                          .replaceAll('_', ' '),
                      style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Insight body ──
            Text(
              _truncate(insight.insightText),
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 14),

            // ── CTA pill ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius:
                        BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                        color: AppColors.teal.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'See full breakdown',
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.teal,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 12, color: AppColors.teal),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String text) {
    final sentences = text.split('. ');
    if (sentences.length <= 2) return text;
    return '${sentences.take(2).join('. ')}.';
  }
}

// ── Pulsing live dot ──────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.4)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.teal.withOpacity(0.5),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
