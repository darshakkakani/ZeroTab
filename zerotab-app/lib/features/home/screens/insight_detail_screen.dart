import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/zt_card.dart';

class InsightDetailScreen extends ConsumerStatefulWidget {
  final String insightId;
  const InsightDetailScreen({super.key, required this.insightId});

  @override
  ConsumerState<InsightDetailScreen> createState() => _InsightDetailScreenState();
}

class _InsightDetailScreenState extends ConsumerState<InsightDetailScreen> {
  AIInsightModel? _insight;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('${ApiConstants.insights}/${widget.insightId}');
      setState(() {
        _insight = AIInsightModel.fromJson(res.data as Map<String, dynamic>);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('This week\'s insight'),
        backgroundColor: AppColors.bg,
        leading: const BackButton(color: AppColors.text2),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : _insight == null
          ? const Center(child: Text('Insight not found', style: TextStyle(color: AppColors.text2)))
          : _InsightBody(insight: _insight!),
    );
  }
}

class _InsightBody extends StatelessWidget {
  final AIInsightModel insight;
  const _InsightBody({required this.insight});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Container(width: 6, height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.teal)),
                  const SizedBox(width: 6),
                  const Text('AI CFO', style: TextStyle(fontFamily: 'DMSans',
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                ]),
              ),
              const SizedBox(width: 8),
              Text('Week of ${formatDate(insight.generatedAt)}',
                style: const TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3)),
              if (insight.insightType != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    insight.insightType!.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 9,
                        fontWeight: FontWeight.w600, color: AppColors.amber),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Insight text
          Text(insight.insightText,
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 15,
                color: AppColors.text, height: 1.6)),

          // Action items
          if (insight.actionItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Action items',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppColors.text2, letterSpacing: 0.05)),
            const SizedBox(height: 12),
            ...insight.actionItems.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ZTCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text('${a.step}', style: const TextStyle(
                          fontFamily: 'DMSans', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppColors.accent2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(a.text,
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
                          color: AppColors.text, height: 1.4))),
                  ],
                ),
              ),
            )),
          ],

          // Data used
          const SizedBox(height: 24),
          const Text('Data used to generate',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: const [
            _DataTag('Last 30 txns'),
            _DataTag('Food category'),
            _DataTag('Monthly income'),
            _DataTag('Savings rate'),
          ]),

          const SizedBox(height: 28),
          // Feedback buttons
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.thumb_up_outlined, size: 15),
              label: const Text('Helpful'),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 15),
              label: const Text('Not useful'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold),
            )),
          ]),
        ],
      ),
    );
  }
}

class _DataTag extends StatelessWidget {
  final String label;
  const _DataTag(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.bg3, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(label, style: const TextStyle(fontFamily: 'DMSans',
        fontSize: 11, color: AppColors.text2)),
  );
}
