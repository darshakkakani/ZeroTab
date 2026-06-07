import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/ai_brain_icon.dart';

// ── Session model ───────────────────────────────────────────────

class ChatSession {
  final String id;
  final String title;
  final DateTime lastMessageAt;

  const ChatSession({
    required this.id,
    required this.title,
    required this.lastMessageAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? 'New conversation',
    lastMessageAt: DateTime.parse(
      (j['last_message_at'] ?? j['created_at'] ?? DateTime.now().toIso8601String()) as String,
    ),
  );
}

// ── Sessions provider ───────────────────────────────────────────

final chatSessionsProvider = FutureProvider.autoDispose<List<ChatSession>>((ref) async {
  try {
    final res = await api.get(ApiConstants.aiChatSessions);
    final list = (res.data as List?) ?? [];
    return list.map((e) => ChatSession.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ── Expert-level prompt categories ──────────────────────────────

class _PromptCategory {
  final String emoji;
  final String label;
  final List<String> prompts;
  const _PromptCategory({required this.emoji, required this.label, required this.prompts});
}

const _promptCategories = [
  _PromptCategory(
    emoji: '🧠',
    label: 'AI Wealth Scan',
    prompts: [
      'Run a full financial health diagnostic on my accounts',
      'What\'s my biggest money leak right now?',
      'Am I on track to build ₹1Cr net worth? What\'s missing?',
    ],
  ),
  _PromptCategory(
    emoji: '💰',
    label: 'Tax & Savings',
    prompts: [
      'Show me exactly how much tax I can save this year — old vs new regime',
      'I have idle cash sitting in savings — where should I deploy it today?',
      'Calculate my optimal 80C + 80D + NPS strategy with exact amounts',
    ],
  ),
  _PromptCategory(
    emoji: '📊',
    label: 'Investment IQ',
    prompts: [
      'Audit my portfolio — is my asset allocation right for my age and risk?',
      'Should I increase my SIP or make a lumpsum now? Show me the math',
      'Compare my mutual fund returns vs a simple Nifty 50 index fund',
    ],
  ),
  _PromptCategory(
    emoji: '🏦',
    label: 'Debt Strategy',
    prompts: [
      'Build me a fastest-payoff plan for all my loans and credit cards',
      'Should I prepay my loan or invest that money instead? Break-even analysis',
      'What\'s my credit utilization and how is it affecting my credit score?',
    ],
  ),
  _PromptCategory(
    emoji: '🎯',
    label: 'Goal Planning',
    prompts: [
      'I want to retire by 45 — build me a realistic roadmap with my current numbers',
      'How much do I need for a ₹1Cr home down payment and when can I get there?',
      'Create a 6-month emergency fund plan from my current cash flow',
    ],
  ),
];

// ── Chat Hub Screen ─────────────────────────────────────────────
// Converted to StatefulWidget so we can detect return from sub-routes
// and auto-refresh the sessions list without a manual refresh button.

class ChatHubScreen extends ConsumerStatefulWidget {
  const ChatHubScreen({super.key});

  @override
  ConsumerState<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends ConsumerState<ChatHubScreen> {

  // Navigate to a route and refresh sessions list on return.
  Future<void> _pushAndRefresh(String path) async {
    await context.push(path);
    if (!mounted) return;
    ref.invalidate(chatSessionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(chatSessionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────
            _HubHeader(),

            // ── Content ─────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero ─────────────────────────────────
                    _HeroSection(),
                    const SizedBox(height: 28),

                    // ── New chat CTA ────────────────────────
                    _NewChatButton(onTap: () => _pushAndRefresh('/chat/new')),
                    const SizedBox(height: 28),

                    // ── Smart prompts ───────────────────────
                    const Text(
                      'Ask your AI CFO',
                      style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 16,
                        fontWeight: FontWeight.w700, color: AppColors.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Expert prompts powered by your real financial data',
                      style: TextStyle(
                        fontFamily: 'DMSans', fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._promptCategories.map((cat) => _PromptCategoryCard(
                      category: cat,
                      onPromptTap: (prompt) => _pushAndRefresh(
                          '/chat/new?q=${Uri.encodeComponent(prompt)}'),
                    )),

                    const SizedBox(height: 28),

                    // ── Chat history ────────────────────────
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent Conversations',
                        style: TextStyle(
                          fontFamily: 'DMSans', fontSize: 16,
                          fontWeight: FontWeight.w700, color: AppColors.text,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    sessionsAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                              color: AppColors.teal, strokeWidth: 1.5),
                        ),
                      ),
                      error: (_, __) => _EmptyHistory(),
                      data: (sessions) => sessions.isEmpty
                          ? _EmptyHistory()
                          : Column(
                              children: sessions.map((s) => _SessionTile(
                                session: s,
                                onTap: () => _pushAndRefresh(
                                    '/chat/session/${s.id}'),
                                onDelete: () => _deleteSession(s.id),
                              )).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSession(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete conversation?',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 16,
                fontWeight: FontWeight.w600, color: AppColors.text)),
        content: const Text('This will permanently remove this chat session.',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: 'DMSans', color: AppColors.text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(fontFamily: 'DMSans', color: AppColors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await api.delete('${ApiConstants.aiChatSessions}/$id');
        if (mounted) ref.invalidate(chatSessionsProvider);
      } catch (_) {}
    }
  }
}

// ── Header ──────────────────────────────────────────────────────

class _HubHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1C0A4A), Color(0xFF070D1F)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFF7B2FFE), width: 1),
              boxShadow: const [
                BoxShadow(color: Color(0x337B2FFE), blurRadius: 8),
              ],
            ),
            alignment: Alignment.center,
            child: const AiBrainIcon(size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ZeroTab AI',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 15,
                        fontWeight: FontWeight.w600, color: AppColors.text)),
                Text('Your personal CFO',
                    style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                        color: Color(0xFF00CFDE))),
              ],
            ),
          ),
          // X close button on right
          GestureDetector(
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.text2, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero section ────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x147B2FFE), Color(0x0A00CFDE)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x287B2FFE)),
      ),
      child: Column(
        children: [
          // AI neural pulse animation instead of duplicate logo
          const _AiPulseAnimation(),
          const SizedBox(height: 16),
          const Text(
            'Your AI Financial Brain',
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 20, fontWeight: FontWeight.w700,
              color: AppColors.text, letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'I analyze your real accounts, spending patterns,\nand investments to give personalized insights',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 12.5,
              color: AppColors.text2, height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          // ── Capability pills ──
          Wrap(
            spacing: 8, runSpacing: 6,
            alignment: WrapAlignment.center,
            children: const [
              _CapPill(text: 'Tax Strategy', icon: '📋'),
              _CapPill(text: 'Portfolio Audit', icon: '📊'),
              _CapPill(text: 'Debt Payoff Plans', icon: '🏦'),
              _CapPill(text: 'Wealth Roadmaps', icon: '🎯'),
              _CapPill(text: 'Spending Insights', icon: '💡'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── AI Pulse Animation ──────────────────────────────────────────
// Concentric rings pulsing outward — "neural network thinking"
// Replaces duplicate logo in hero section

class _AiPulseAnimation extends StatefulWidget {
  const _AiPulseAnimation();

  @override
  State<_AiPulseAnimation> createState() => _AiPulseAnimationState();
}

class _AiPulseAnimationState extends State<_AiPulseAnimation>
    with TickerProviderStateMixin {
  late AnimationController _ctrl1;
  late AnimationController _ctrl2;
  late AnimationController _ctrl3;
  late AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl1 = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 2200))..repeat();
    _ctrl2 = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 2200))
      ..forward(from: 0.33)..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ctrl2.repeat();
      });
    _ctrl3 = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 2200))
      ..forward(from: 0.66)..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ctrl3.repeat();
      });
    _dotCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl1.dispose(); _ctrl2.dispose();
    _ctrl3.dispose(); _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80, height: 80,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl1, _ctrl2, _ctrl3, _dotCtrl]),
        builder: (_, __) => CustomPaint(
          painter: _PulsePainter(
            ring1: _ctrl1.value,
            ring2: _ctrl2.value,
            ring3: _ctrl3.value,
            dotPulse: _dotCtrl.value,
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double ring1, ring2, ring3, dotPulse;
  const _PulsePainter({
    required this.ring1, required this.ring2,
    required this.ring3, required this.dotPulse,
  });

  static const _violet = Color(0xFF7B2FFE);
  static const _cyan   = Color(0xFF00CFDE);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;

    // 3 concentric pulsing rings
    for (final (t, color) in [
      (ring1, _violet),
      (ring2, Color.lerp(_violet, _cyan, 0.5)!),
      (ring3, _cyan),
    ]) {
      final radius = 12.0 + 26.0 * t;
      final alpha  = (1.0 - t) * 0.55;
      canvas.drawCircle(
        Offset(cx, cy), radius,
        Paint()
          ..color       = color.withValues(alpha: alpha)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1 - t * 0.6),
      );
    }

    // 3 orbiting dots at 120° apart, rotating slowly
    final orbitR  = 20.0;
    final rotAngle = ring1 * 2 * math.pi;
    for (int i = 0; i < 3; i++) {
      final a = rotAngle + i * 2 * math.pi / 3;
      final dx = cx + orbitR * math.cos(a);
      final dy = cy + orbitR * math.sin(a);
      final c  = Color.lerp(_violet, _cyan, i / 2.0)!;
      canvas.drawCircle(Offset(dx, dy), 2.5,
          Paint()..color = c.withValues(alpha: 0.8));
    }

    // Central glowing core
    final coreR = 7.0 + dotPulse * 2.0;
    canvas.drawCircle(Offset(cx, cy), coreR * 1.8,
        Paint()
          ..color      = _cyan.withValues(alpha: 0.15 + dotPulse * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(Offset(cx, cy), coreR,
        Paint()..color = Color.lerp(_violet, _cyan, dotPulse)!);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => true;
}

// ── Cap pill ────────────────────────────────────────────────────

class _CapPill extends StatelessWidget {
  final String text;
  final String icon;
  const _CapPill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bg3,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(
            fontFamily: 'DMSans', fontSize: 11,
            fontWeight: FontWeight.w500, color: AppColors.text2,
          )),
        ],
      ),
    );
  }
}

// ── New chat button ─────────────────────────────────────────────

class _NewChatButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewChatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B2FFE), Color(0xFF00CFDE)],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x407B2FFE),
              blurRadius: 16, offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Start New Conversation',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w600, color: Colors.white,
                    letterSpacing: -0.2)),
          ],
        ),
      ),
    );
  }
}

// ── Prompt category card ────────────────────────────────────────

class _PromptCategoryCard extends StatefulWidget {
  final _PromptCategory category;
  final void Function(String) onPromptTap;
  const _PromptCategoryCard({required this.category, required this.onPromptTap});

  @override
  State<_PromptCategoryCard> createState() => _PromptCategoryCardState();
}

class _PromptCategoryCardState extends State<_PromptCategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // ── Category header ──
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Text(widget.category.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.category.label,
                          style: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
                              fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.text3, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            // ── Prompt list ──
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
                  ...widget.category.prompts.map((prompt) => GestureDetector(
                    onTap: () => widget.onPromptTap(prompt),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(44, 10, 14, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.border.withOpacity(0.3),
                            width: prompt == widget.category.prompts.last ? 0 : 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(prompt,
                                style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                                    color: AppColors.text2, height: 1.4)),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: AppColors.teal, size: 12),
                        ],
                      ),
                    ),
                  )),
                ],
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session tile ────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SessionTile({required this.session, required this.onTap, required this.onDelete});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.teal, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                          fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _timeAgo(session.lastMessageAt),
                      style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                          color: AppColors.text3),
                    ),
                  ],
                ),
              ),
              // ── Continue arrow ──
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.text3, size: 14),
              const SizedBox(width: 4),
              // ── Delete button ──
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      color: AppColors.red.withOpacity(0.6), size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty history placeholder ───────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined,
              color: AppColors.text3.withOpacity(0.4), size: 32),
          const SizedBox(height: 10),
          const Text('No conversations yet',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w500, color: AppColors.text3)),
          const SizedBox(height: 4),
          const Text('Start a chat to get personalized financial insights',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                  color: AppColors.text3)),
        ],
      ),
    );
  }
}
