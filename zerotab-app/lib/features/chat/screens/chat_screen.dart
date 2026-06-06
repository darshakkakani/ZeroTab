import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/ai_brain_icon.dart';

// ── Chat state ───────────────────────────────────────────────

class ChatState {
  final List<ChatMessage> messages;
  final String? sessionId;
  final bool isSending;
  final bool isLoadingHistory;

  const ChatState({
    this.messages = const [],
    this.sessionId,
    this.isSending = false,
    this.isLoadingHistory = false,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? sessionId,
    bool? isSending,
    bool? isLoadingHistory,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        sessionId: sessionId ?? this.sessionId,
        isSending: isSending ?? (this.isSending == true),
        isLoadingHistory: isLoadingHistory ?? (this.isLoadingHistory == true),
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  /// Load an existing session's history
  Future<void> loadSession(String sessionId) async {
    state = ChatState(sessionId: sessionId, isLoadingHistory: true);
    try {
      final res = await api.get(
        ApiConstants.aiChatHistory,
        params: {'session_id': sessionId},
      );
      final list = (res.data as List?) ?? [];
      final messages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      state = ChatState(sessionId: sessionId, messages: messages);
    } catch (_) {
      state = ChatState(sessionId: sessionId);
    }
  }

  /// Start fresh (no session yet — will be created on first message)
  void startNew() {
    state = const ChatState();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isSending) return;

    final userMsg = ChatMessage(
      role: 'user',
      content: text.trim(),
      createdAt: DateTime.now(),
    );
    final loadingMsg = ChatMessage(
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isLoading: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, loadingMsg],
      isSending: true,
    );

    try {
      final res = await api.post(ApiConstants.aiChatMessage, data: {
        'session_id': state.sessionId,
        'message': text.trim(),
      });

      final data = res.data as Map<String, dynamic>;
      final aiResponse = data['response'] as String;
      final sessionId = data['session_id'] as String;

      final assistantMsg = ChatMessage(
        role: 'assistant',
        content: aiResponse,
        createdAt: DateTime.now(),
      );

      final updatedMessages = List<ChatMessage>.from(state.messages);
      updatedMessages.removeLast();
      updatedMessages.add(assistantMsg);

      state = state.copyWith(
        messages: updatedMessages,
        sessionId: sessionId,
        isSending: false,
      );
    } catch (e) {
      final errorMsg = ChatMessage(
        role: 'assistant',
        content: 'Sorry, I couldn\'t process that. ${apiErrorMessage(e)}',
        createdAt: DateTime.now(),
      );

      final updatedMessages = List<ChatMessage>.from(state.messages);
      updatedMessages.removeLast();
      updatedMessages.add(errorMsg);

      state = state.copyWith(
        messages: updatedMessages,
        isSending: false,
      );
    }
  }

  void clearChat() {
    state = const ChatState();
  }
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatState>((_) => ChatNotifier());

// ── Quick suggestions (shown in empty new chat) ─────────────────

const _quickSuggestions = [
  '🔍  Run a full financial health scan',
  '💰  Where is my money leaking?',
  '📊  Audit my portfolio allocation',
  '🧾  Old vs New tax regime — which saves more?',
  '🏦  Build a debt payoff strategy',
  '🎯  Am I on track for ₹1Cr net worth?',
];

String _cleanPrompt(String s) => s.replaceAll(RegExp(r'^[^\s]+\s+'), '');

// ── Chat Screen ──────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final String? sessionId;     // null = new chat
  final String? initialQuery;  // from hub prompt tap

  const ChatScreen({super.key, this.sessionId, this.initialQuery});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;

    final notifier = ref.read(chatProvider.notifier);

    if (widget.sessionId != null) {
      // Continue existing session
      notifier.loadSession(widget.sessionId!);
    } else {
      // New chat
      notifier.startNew();
      // Auto-send initial query if provided
      if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          notifier.sendMessage(widget.initialQuery!);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _sendSuggestion(String text) {
    ref.read(chatProvider.notifier).sendMessage(_cleanPrompt(text));
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    ref.listen(chatProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            _ChatHeader(
              onBack: () => context.go('/chat'),
              onNewChat: () {
                ref.read(chatProvider.notifier).clearChat();
                context.go('/chat/new');
              },
            ),

            // ── Loading history indicator ───────────────────────
            if (chatState.isLoadingHistory)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppColors.teal)),
                    const SizedBox(width: 8),
                    Text('Loading conversation…',
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                            color: AppColors.text3)),
                  ],
                ),
              ),

            // ── Messages ────────────────────────────────────────
            Expanded(
              child: chatState.messages.isEmpty && !chatState.isLoadingHistory
                  ? _EmptyState(onSuggestionTap: _sendSuggestion)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: chatState.messages.length,
                      itemBuilder: (_, i) =>
                          _MessageBubble(message: chatState.messages[i]),
                    ),
            ),

            // ── Input bar ───────────────────────────────────────
            _InputBar(
              controller: _controller,
              focusNode: _focusNode,
              isSending: chatState.isSending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNewChat;
  const _ChatHeader({required this.onBack, required this.onNewChat});

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
          // ── Back to hub ──────────────────────────────────────
          GestureDetector(
            onTap: onBack,
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
          const SizedBox(width: 10),
          // ── AI brain icon ────────────────────────────────────
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
          GestureDetector(
            onTap: onNewChat,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppColors.text2, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state with suggestions ─────────────────────────────

class _EmptyState extends StatelessWidget {
  final void Function(String) onSuggestionTap;
  const _EmptyState({required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C4A8), Color(0xFF006B5C)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withOpacity(0.3),
                  blurRadius: 20, offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const AiBrainIcon(size: 30),
          ),
          const SizedBox(height: 18),
          const Text(
            'What can I help you with?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 19, fontWeight: FontWeight.w700,
              letterSpacing: -0.5, color: AppColors.text, height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'I have full access to your financial data.\nAsk me anything — I\'ll give you real numbers.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DMSans', fontSize: 13,
              color: AppColors.text2, height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          ...(_quickSuggestions.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SuggestionChip(text: s, onTap: () => onSuggestionTap(s)),
          ))),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                      fontWeight: FontWeight.w500, color: AppColors.text2)),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.teal, size: 12),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ───────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    if (message.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AiAvatar(),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.teal.withOpacity(0.1)),
              ),
              child: const _TypingIndicator(),
            ),
          ],
        ),
      );
    }

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 48),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 14,
                    color: AppColors.text, height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant message
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiAvatar(),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: AppColors.teal.withOpacity(0.1)),
              ),
              child: _SmartMarkdown(data: message.content),
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

// ── Smart Markdown — renders tables in scrollable containers ──

class _MdSegment {
  final String content;
  final bool isTable;
  const _MdSegment(this.content, this.isTable);
}

List<_MdSegment> _splitMarkdownSegments(String md) {
  final lines = md.split('\n');
  final segments = <_MdSegment>[];
  final buffer = StringBuffer();
  bool inTable = false;

  for (int i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    final isTableLine = trimmed.startsWith('|') && trimmed.contains('|', 1);

    if (isTableLine && !inTable) {
      // Flush text buffer before starting table
      final text = buffer.toString().trimRight();
      if (text.isNotEmpty) {
        segments.add(_MdSegment(text, false));
      }
      buffer.clear();
      inTable = true;
      buffer.writeln(lines[i]);
    } else if (isTableLine && inTable) {
      buffer.writeln(lines[i]);
    } else if (!isTableLine && inTable) {
      // End of table block
      final tableText = buffer.toString().trimRight();
      if (tableText.isNotEmpty) {
        segments.add(_MdSegment(tableText, true));
      }
      buffer.clear();
      inTable = false;
      buffer.writeln(lines[i]);
    } else {
      buffer.writeln(lines[i]);
    }
  }

  final remaining = buffer.toString().trimRight();
  if (remaining.isNotEmpty) {
    segments.add(_MdSegment(remaining, inTable));
  }

  return segments;
}

MarkdownStyleSheet _textStyleSheet() => MarkdownStyleSheet(
  p: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
      color: AppColors.text, height: 1.6),
  strong: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
      fontWeight: FontWeight.w700, color: Colors.white),
  em: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
      fontStyle: FontStyle.italic, color: AppColors.text2),
  h1: const TextStyle(fontFamily: 'DMSans', fontSize: 20,
      fontWeight: FontWeight.w700, color: Colors.white, height: 1.4),
  h2: const TextStyle(fontFamily: 'DMSans', fontSize: 17,
      fontWeight: FontWeight.w700, color: Colors.white, height: 1.4),
  h3: const TextStyle(fontFamily: 'DMSans', fontSize: 15,
      fontWeight: FontWeight.w600, color: AppColors.teal, height: 1.4),
  listBullet: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
      color: AppColors.teal),
  listIndent: 16,
  code: TextStyle(fontFamily: 'monospace', fontSize: 13,
      color: AppColors.accent2,
      backgroundColor: AppColors.bg4.withOpacity(0.5)),
  codeblockDecoration: BoxDecoration(
    color: AppColors.bg4,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: AppColors.border),
  ),
  codeblockPadding: const EdgeInsets.all(12),
  blockquoteDecoration: BoxDecoration(
    border: Border(left: BorderSide(
        color: AppColors.teal.withOpacity(0.5), width: 3)),
  ),
  blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
  horizontalRuleDecoration: BoxDecoration(
    border: Border(top: BorderSide(
        color: AppColors.border.withOpacity(0.3), width: 1)),
  ),
  a: const TextStyle(fontFamily: 'DMSans', fontSize: 14,
      color: AppColors.teal, decoration: TextDecoration.underline),
  pPadding: const EdgeInsets.only(bottom: 8),
  h1Padding: const EdgeInsets.only(bottom: 8, top: 4),
  h2Padding: const EdgeInsets.only(bottom: 6, top: 4),
  h3Padding: const EdgeInsets.only(bottom: 4, top: 4),
  blockSpacing: 8,
);

MarkdownStyleSheet _tableStyleSheet() => MarkdownStyleSheet(
  // Table-specific — rendered in scrollable container
  tableHead: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
      fontWeight: FontWeight.w700, color: AppColors.teal),
  tableBody: const TextStyle(fontFamily: 'DMSans', fontSize: 12,
      color: AppColors.text, height: 1.4),
  tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  tableColumnWidth: const IntrinsicColumnWidth(),
  tableBorder: TableBorder(
    top: BorderSide(color: AppColors.teal.withOpacity(0.3), width: 1),
    bottom: BorderSide(color: AppColors.teal.withOpacity(0.3), width: 1),
    left: BorderSide(color: AppColors.teal.withOpacity(0.15), width: 1),
    right: BorderSide(color: AppColors.teal.withOpacity(0.15), width: 1),
    horizontalInside: BorderSide(color: AppColors.border.withOpacity(0.5), width: 1),
    verticalInside: BorderSide(color: AppColors.border.withOpacity(0.3), width: 1),
  ),
  tableHeadAlign: TextAlign.left,
  // Also include text styles for any text around the table
  p: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
      color: AppColors.text, height: 1.5),
  strong: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
      fontWeight: FontWeight.w700, color: Colors.white),
);

class _SmartMarkdown extends StatelessWidget {
  final String data;
  const _SmartMarkdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final segments = _splitMarkdownSegments(data);

    // No tables — render normally
    if (segments.every((s) => !s.isTable)) {
      return MarkdownBody(
        data: data,
        selectable: true,
        onTapLink: (_, href, __) {
          if (href != null) launchUrl(Uri.parse(href));
        },
        styleSheet: _textStyleSheet(),
      );
    }

    // Has tables — render in segments
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((seg) {
        if (seg.isTable) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Scrollable table ──
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bg4.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.teal.withOpacity(0.12)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(4),
                    child: MarkdownBody(
                      data: seg.content,
                      selectable: true,
                      shrinkWrap: true,
                      styleSheet: _tableStyleSheet(),
                    ),
                  ),
                ),
                // ── Scroll hint ──
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swipe_rounded,
                          color: AppColors.text3.withOpacity(0.5), size: 12),
                      const SizedBox(width: 4),
                      Text('Swipe to see full table',
                          style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                              color: AppColors.text3.withOpacity(0.5))),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Regular text segment
        if (seg.content.trim().isEmpty) return const SizedBox.shrink();
        return MarkdownBody(
          data: seg.content,
          selectable: true,
          onTapLink: (_, href, __) {
            if (href != null) launchUrl(Uri.parse(href));
          },
          styleSheet: _textStyleSheet(),
        );
      }).toList(),
    );
  }
}

class _AiAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C4A8), Color(0xFF008B78)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const AiBrainIcon(size: 14),
    );
  }
}

// ── Typing indicator ─────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _ctrls.map((ctrl) {
        return AnimatedBuilder(
          animation: ctrl,
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.teal.withOpacity(0.3 + ctrl.value * 0.7),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Input bar ────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.bg2,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                border: Border.all(color: AppColors.border2),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !isSending,
                maxLines: 4, minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 14, color: AppColors.text,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask your AI CFO…',
                  hintStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                      color: AppColors.text3),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isSending ? null : onSend,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: isSending ? null : const LinearGradient(
                    colors: [Color(0xFF00C4A8), Color(0xFF008B78)]),
                color: isSending ? AppColors.bg4 : null,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              alignment: Alignment.center,
              child: isSending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.teal))
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
