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

class ChatHubScreen extends ConsumerWidget {
  const ChatHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    _NewChatButton(onTap: () => context.go('/chat/new')),
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
                      onPromptTap: (prompt) => context.go('/chat/new?q=${Uri.encodeComponent(prompt)}'),
                    )),

                    const SizedBox(height: 28),

                    // ── Chat history ────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent Conversations',
                            style: TextStyle(
                              fontFamily: 'DMSans', fontSize: 16,
                              fontWeight: FontWeight.w700, color: AppColors.text,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (sessionsAsync.valueOrNull?.isNotEmpty == true)
                          GestureDetector(
                            onTap: () => ref.invalidate(chatSessionsProvider),
                            child: const Icon(Icons.refresh_rounded,
                                color: AppColors.text3, size: 18),
                          ),
                      ],
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
                                onTap: () => context.go('/chat/session/${s.id}'),
                                onDelete: () => _deleteSession(context, ref, s.id),
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

  Future<void> _deleteSession(BuildContext context, WidgetRef ref, String id) async {
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
        ref.invalidate(chatSessionsProvider);
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
          GestureDetector(
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.text2, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C4A8), Color(0xFF008B78)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        color: AppColors.teal)),
              ],
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
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00C4A8).withOpacity(0.08),
            const Color(0xFF006B5C).withOpacity(0.04),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.teal.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C4A8), Color(0xFF006B5C)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withOpacity(0.3),
                  blurRadius: 20, offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const AiBrainIcon(size: 28),
          ),
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
            colors: [Color(0xFF00C4A8), Color(0xFF008B78)],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.teal.withOpacity(0.25),
              blurRadius: 16, offset: const Offset(0, 4),
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
