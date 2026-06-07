// ignore_for_file: use_build_context_synchronously
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

// ── Supabase client shorthand ─────────────────────────────────
final _db = Supabase.instance.client;

// ── Currency helpers (paise ↔ rupees) ─────────────────────────
int toP(double rupees) => (rupees * 100).round();
double toR(int paise)  => paise / 100.0;
String fmtP(int paise) => formatInr(toR(paise), compact: true);
String fmtPFull(int paise) => '₹${toR(paise).toStringAsFixed(2)}';

// ════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════

class SettleGroup {
  final String id, name, currency, category, coverColor;
  final String? description, createdBy;
  final bool isArchived;
  final DateTime createdAt;
  const SettleGroup({
    required this.id, required this.name, required this.currency,
    required this.category, required this.coverColor,
    this.description, this.createdBy, this.isArchived = false,
    required this.createdAt,
  });
  factory SettleGroup.fromJson(Map<String, dynamic> j) => SettleGroup(
    id: j['id'] as String,
    name: j['name'] as String,
    currency: (j['currency'] as String?) ?? 'INR',
    category: (j['category'] as String?) ?? 'general',
    coverColor: (j['cover_color'] as String?) ?? '#7B2FFE',
    description: j['description'] as String?,
    createdBy: j['created_by'] as String?,
    isArchived: (j['is_archived'] as bool?) ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class GroupMember {
  final String id, groupId;
  final String? userId, displayName, phone;
  const GroupMember({
    required this.id, required this.groupId,
    this.userId, this.displayName, this.phone,
  });
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    userId: j['user_id'] as String?,
    displayName: j['display_name'] as String?,
    phone: j['phone'] as String?,
  );
  String get name => displayName ?? phone ?? 'Unknown';
  String get initials => name.isNotEmpty ? name[0].toUpperCase() : '?';
}

class SettleExpense {
  final String id, groupId, title, category, splitMode;
  final int amount;
  final String? paidBy, notes;
  final bool isSettlement;
  final DateTime expenseDate, createdAt;
  final List<ExpenseShare> shares;
  const SettleExpense({
    required this.id, required this.groupId, required this.title,
    required this.amount, required this.category, required this.splitMode,
    this.paidBy, this.notes, this.isSettlement = false,
    required this.expenseDate, required this.createdAt,
    this.shares = const [],
  });
  factory SettleExpense.fromJson(Map<String, dynamic> j) => SettleExpense(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    title: j['title'] as String,
    amount: (j['amount'] as int?) ?? 0,
    category: (j['category'] as String?) ?? 'general',
    splitMode: (j['split_mode'] as String?) ?? 'EQUAL',
    paidBy: j['paid_by'] as String?,
    notes: j['notes'] as String?,
    isSettlement: (j['is_settlement'] as bool?) ?? false,
    expenseDate: DateTime.parse(
        (j['expense_date'] as String?) ?? DateTime.now().toIso8601String()),
    createdAt: DateTime.parse(
        (j['created_at'] as String?) ?? DateTime.now().toIso8601String()),
    shares: ((j['shares'] as List?) ?? [])
        .map((s) => ExpenseShare.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

class ExpenseShare {
  final String id, expenseId;
  final String? memberId, displayName;
  final int amount;
  const ExpenseShare({
    required this.id, required this.expenseId, required this.amount,
    this.memberId, this.displayName,
  });
  factory ExpenseShare.fromJson(Map<String, dynamic> j) => ExpenseShare(
    id: j['id'] as String,
    expenseId: j['expense_id'] as String,
    amount: (j['amount'] as int?) ?? 0,
    memberId: j['member_id'] as String?,
    displayName: j['display_name'] as String?,
  );
}

class IndividualSplit {
  final String id;
  final String? participantUserId, participantPhone;
  final String participantName, createdBy;
  final int amount;
  final String description;
  final DateTime splitDate;
  final bool youOwe, isSettled;
  const IndividualSplit({
    required this.id, required this.participantName, required this.createdBy,
    required this.amount, required this.description,
    required this.splitDate, required this.youOwe, required this.isSettled,
    this.participantUserId, this.participantPhone,
  });
  factory IndividualSplit.fromJson(Map<String, dynamic> j, String currentUserId) {
    final isCreator = (j['created_by'] as String?) == currentUserId;
    final rawYouOwe = (j['you_owe'] as bool?) ?? false;
    return IndividualSplit(
      id: j['id'] as String,
      createdBy: (j['created_by'] as String?) ?? '',
      participantUserId: j['participant_user_id'] as String?,
      participantPhone: j['participant_phone'] as String?,
      participantName: (j['participant_name'] as String?) ?? 'Friend',
      amount: (j['amount'] as int?) ?? 0,
      description: (j['description'] as String?) ?? '',
      splitDate: DateTime.parse(
          (j['split_date'] as String?) ?? DateTime.now().toIso8601String()),
      youOwe: isCreator ? rawYouOwe : !rawYouOwe,
      isSettled: (j['is_settled'] as bool?) ?? false,
    );
  }
}

class SettlementResult {
  final String fromId, fromName, toId, toName;
  final int amount;
  const SettlementResult({
    required this.fromId, required this.fromName,
    required this.toId, required this.toName, required this.amount,
  });
}

// ════════════════════════════════════════════════════════════════
//  DEBT SIMPLIFICATION — Greedy O(n log n) algorithm
//  (Same approach as Splitwise & Spliit open-source)
// ════════════════════════════════════════════════════════════════

List<SettlementResult> simplifyDebts(
  Map<String, int> netBalances,
  Map<String, String> names,
) {
  final entries = netBalances.entries
      .where((e) => e.value.abs() > 1) // ignore <1 paise rounding
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  if (entries.isEmpty) return [];

  final List<MapEntry<String, int>> list = List.from(entries);
  final settlements = <SettlementResult>[];
  int l = 0, r = list.length - 1;

  while (l < r) {
    final creditor = list[l];
    final debtor   = list[r];
    if (creditor.value <= 0 || debtor.value >= 0) break;

    final transfer = min(creditor.value, -debtor.value);
    settlements.add(SettlementResult(
      fromId:   debtor.key,
      fromName: names[debtor.key] ?? 'Unknown',
      toId:     creditor.key,
      toName:   names[creditor.key] ?? 'Unknown',
      amount:   transfer,
    ));

    list[l] = MapEntry(creditor.key, creditor.value - transfer);
    list[r] = MapEntry(debtor.key,   debtor.value   + transfer);

    if (list[l].value == 0) l++;
    if (list[r].value == 0) r--;
  }
  return settlements;
}

// ════════════════════════════════════════════════════════════════
//  MAIN SETTLEUP SCREEN
// ════════════════════════════════════════════════════════════════

class SettleUpScreen extends ConsumerStatefulWidget {
  const SettleUpScreen({super.key});
  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<SettleGroup>    _groups = [];
  List<IndividualSplit> _splits = [];
  bool _loading = true;

  RealtimeChannel? _groupsChannel;
  RealtimeChannel? _splitsChannel;

  String get _uid => _db.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tab.dispose();
    if (_groupsChannel != null) _db.removeChannel(_groupsChannel!);
    if (_splitsChannel  != null) _db.removeChannel(_splitsChannel!);
    super.dispose();
  }

  // ── Initial data load ─────────────────────────────────────────
  Future<void> _loadAll() async {
    await Future.wait([_loadGroups(), _loadSplits()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadGroups() async {
    try {
      // Get groups where user is a member
      final memberRows = await _db
          .from('settle_group_members')
          .select('group_id')
          .eq('user_id', _uid);
      final groupIds = (memberRows as List)
          .map((r) => r['group_id'] as String)
          .toList();
      if (groupIds.isEmpty) { _groups = []; return; }

      final groupRows = await _db
          .from('settle_groups')
          .select()
          .inFilter('id', groupIds)
          .eq('is_archived', false)
          .order('created_at', ascending: false);

      _groups = (groupRows as List)
          .map((r) => SettleGroup.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('loadGroups error: $e');
    }
  }

  Future<void> _loadSplits() async {
    try {
      final rows = await _db
          .from('settle_splits')
          .select()
          .or('created_by.eq.$_uid,participant_user_id.eq.$_uid')
          .eq('is_settled', false)
          .order('created_at', ascending: false);
      _splits = (rows as List)
          .map((r) => IndividualSplit.fromJson(r as Map<String, dynamic>, _uid))
          .toList();
    } catch (e) {
      debugPrint('loadSplits error: $e');
    }
  }

  // ── Supabase Realtime subscriptions ───────────────────────────
  void _subscribeRealtime() {
    // Subscribe to group member changes (new groups added)
    _groupsChannel = _db
        .channel('settleup-groups-$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settle_group_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _uid,
          ),
          callback: (_) => _loadGroups().then((_) {
            if (mounted) setState(() {});
          }),
        )
        .subscribe();

    // Subscribe to individual splits
    _splitsChannel = _db
        .channel('settleup-splits-$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settle_splits',
          callback: (payload) {
            _loadSplits().then((_) {
              if (mounted) setState(() {});
            });
            // Show in-app banner for new splits from others
            if (payload.eventType == PostgresChangeEvent.insert) {
              final rec = payload.newRecord;
              if (rec['created_by'] != _uid) {
                _showInAppBanner(
                  rec['participant_name'] as String? ?? 'Someone',
                  (rec['amount'] as int?) ?? 0,
                  rec['description'] as String? ?? 'an expense',
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _showInAppBanner(String fromName, int amount, String desc) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Container(width: 6, height: 6,
            decoration: const BoxDecoration(
                color: Color(0xFF22C55E), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text('$fromName added ${fmtP(amount)} for $desc',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 13,
                color: AppColors.text))),
        ]),
        backgroundColor: const Color(0xFF1A1730),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
          side: const BorderSide(color: Color(0xFF2A2545)),
        ),
        duration: const Duration(seconds: 4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }

  // ── Net balances for individual splits ────────────────────────
  Map<String, int> get _netBalances {
    final map = <String, int>{};
    for (final s in _splits) {
      final key = s.participantName;
      map[key] = (map[key] ?? 0) + (s.youOwe ? -s.amount : s.amount);
    }
    return map;
  }

  int get _totalOwed => _netBalances.values
      .where((v) => v > 0).fold(0, (s, v) => s + v);
  int get _totalOwe => _netBalances.values
      .where((v) => v < 0).fold(0, (s, v) => s + v.abs());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.text2, size: 22),
              ),
              const SizedBox(width: 14),
              const Text('SettleUp', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 22,
                fontWeight: FontWeight.w700, letterSpacing: -0.6,
                color: AppColors.text)),
              const Spacer(),
              GestureDetector(
                onTap: _tab.index == 0 ? _showCreateGroup : _showAddSplit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF22C55E), Color(0xFF00C4A8)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(_tab.index == 0 ? 'Group' : 'Split',
                      style: const TextStyle(fontFamily: 'DMSans',
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 14),

          // ── Tab bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                controller: _tab,
                onTap: (_) => setState(() {}),
                indicator: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(17),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 12, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 12),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.text2,
                tabs: const [
                  Tab(text: 'Groups'),
                  Tab(text: 'Friends'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Tab views ───────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF22C55E)))
                : TabBarView(
                    controller: _tab,
                    children: [
                      _GroupsTab(
                        groups: _groups,
                        onRefresh: _loadAll,
                        currentUid: _uid,
                      ),
                      _FriendsTab(
                        splits: _splits,
                        netBalances: _netBalances,
                        totalOwed: _totalOwed,
                        totalOwe: _totalOwe,
                        onRefresh: _loadSplits,
                        onSettle: _settleAll,
                        onAddSplit: _showAddSplit,
                        currentUid: _uid,
                      ),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  // ── Create group ──────────────────────────────────────────────
  void _showCreateGroup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        currentUid: _uid,
        onCreated: () => _loadAll().then((_) {
          if (mounted) setState(() {});
        }),
      ),
    );
  }

  // ── Add individual split ──────────────────────────────────────
  void _showAddSplit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSplitSheet(
        currentUid: _uid,
        onAdded: () => _loadSplits().then((_) {
          if (mounted) setState(() {});
        }),
      ),
    );
  }

  Future<void> _settleAll(String friendName) async {
    try {
      final ids = _splits
          .where((s) => s.participantName.toLowerCase() == friendName.toLowerCase())
          .map((s) => s.id)
          .toList();
      for (final id in ids) {
        await _db.from('settle_splits').update({
          'is_settled': true,
          'settled_at': DateTime.now().toIso8601String(),
        }).eq('id', id);
      }
      await _loadSplits();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('settle error: $e');
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  GROUPS TAB
// ════════════════════════════════════════════════════════════════

class _GroupsTab extends StatelessWidget {
  final List<SettleGroup> groups;
  final VoidCallback onRefresh;
  final String currentUid;
  const _GroupsTab({
    required this.groups, required this.onRefresh, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.group_outlined,
              color: Color(0xFF22C55E), size: 36),
        ),
        const SizedBox(height: 18),
        const Text('No groups yet', style: TextStyle(
          fontFamily: 'DMSans', fontSize: 17,
          fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 8),
        const Text('Create a group for trips, home, couple\nor any shared expense.',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
              color: AppColors.text3, height: 1.5),
          textAlign: TextAlign.center),
      ]);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: groups.length,
      itemBuilder: (_, i) => _GroupTile(
        group: groups[i],
        currentUid: currentUid,
        onRefresh: onRefresh,
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final SettleGroup group;
  final String currentUid;
  final VoidCallback onRefresh;
  const _GroupTile({
    required this.group, required this.currentUid, required this.onRefresh});

  Color get _color {
    try {
      final hex = group.coverColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF7B2FFE);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          group: group, currentUid: currentUid, onUpdate: onRefresh),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _color.withValues(alpha: 0.20)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(_categoryEmoji(group.category),
              style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: TextStyle(
                fontFamily: 'DMSans', fontSize: 14,
                fontWeight: FontWeight.w700, color: _color)),
              if (group.description?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(group.description!,
                  style: const TextStyle(fontFamily: 'DMSans',
                      fontSize: 11, color: AppColors.text3),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          )),
          Icon(Icons.chevron_right_rounded, color: _color, size: 18),
        ]),
      ),
    );
  }
}

String _categoryEmoji(String cat) {
  switch (cat) {
    case 'trip':    return '✈️';
    case 'home':    return '🏠';
    case 'couple':  return '💑';
    case 'food':    return '🍕';
    default:        return '👥';
  }
}

// ════════════════════════════════════════════════════════════════
//  FRIENDS TAB (individual splits)
// ════════════════════════════════════════════════════════════════

class _FriendsTab extends StatelessWidget {
  final List<IndividualSplit> splits;
  final Map<String, int> netBalances;
  final int totalOwed, totalOwe;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String friendName) onSettle;
  final VoidCallback onAddSplit;
  final String currentUid;
  const _FriendsTab({
    required this.splits, required this.netBalances,
    required this.totalOwed, required this.totalOwe,
    required this.onRefresh, required this.onSettle,
    required this.onAddSplit, required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    if (netBalances.isEmpty) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.balance_outlined,
              color: Color(0xFF22C55E), size: 36),
        ),
        const SizedBox(height: 18),
        const Text('All settled up!', style: TextStyle(
          fontFamily: 'DMSans', fontSize: 17,
          fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 8),
        const Text('Add a friend by phone or email\nto start splitting expenses.',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 13,
              color: AppColors.text3, height: 1.5),
          textAlign: TextAlign.center),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onAddSplit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF00C4A8)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Add a Split',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                  fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        // Summary bar
        if (totalOwed > 0 || totalOwe > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (totalOwed > 0) Column(children: [
                  const Text('You\'re owed', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 10.5,
                      color: AppColors.text3)),
                  const SizedBox(height: 3),
                  Text(fmtP(totalOwed), style: const TextStyle(
                    fontFamily: 'DMMono', fontSize: 17,
                    fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
                ]),
                if (totalOwed > 0 && totalOwe > 0)
                  Container(width: 1, height: 30, color: AppColors.border),
                if (totalOwe > 0) Column(children: [
                  const Text('You owe', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 10.5,
                      color: AppColors.text3)),
                  const SizedBox(height: 3),
                  Text(fmtP(totalOwe), style: const TextStyle(
                    fontFamily: 'DMMono', fontSize: 17,
                    fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                ]),
              ],
            ),
          ),

        // Friend balance cards
        ...netBalances.entries.map((e) {
          final theyOweYou = e.value > 0;
          final color = theyOweYou
              ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
          final relatedSplits = splits
              .where((s) => s.participantName.toLowerCase()
                  == e.key.toLowerCase())
              .toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    color.withValues(alpha: 0.20),
                    color.withValues(alpha: 0.10),
                  ]),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.30)),
                ),
                alignment: Alignment.center,
                child: Text(e.key[0].toUpperCase(), style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 16,
                  fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.key, style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 14,
                    fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(
                    theyOweYou
                        ? 'owes you · ${relatedSplits.length} split${relatedSplits.length > 1 ? "s" : ""}'
                        : 'you owe · ${relatedSplits.length} split${relatedSplits.length > 1 ? "s" : ""}',
                    style: TextStyle(fontFamily: 'DMSans',
                        fontSize: 11, color: color)),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtP(e.value.abs()), style: TextStyle(
                  fontFamily: 'DMMono', fontSize: 17,
                  fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => onSettle(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: color.withValues(alpha: 0.30)),
                    ),
                    child: Text('Settle', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 10.5,
                      fontWeight: FontWeight.w600, color: color)),
                  ),
                ),
              ]),
            ]),
          );
        }),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  GROUP DETAIL SCREEN
// ════════════════════════════════════════════════════════════════

class GroupDetailScreen extends ConsumerStatefulWidget {
  final SettleGroup group;
  final String currentUid;
  final VoidCallback onUpdate;
  const GroupDetailScreen({
    super.key, required this.group,
    required this.currentUid, required this.onUpdate,
  });
  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<SettleExpense> _expenses = [];
  List<GroupMember>   _members  = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tab.dispose();
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadExpenses(), _loadMembers()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadExpenses() async {
    try {
      final rows = await _db
          .from('settle_expenses')
          .select()
          .eq('group_id', widget.group.id)
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false);
      _expenses = (rows as List)
          .map((r) => SettleExpense.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('loadExpenses: $e');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final rows = await _db
          .from('settle_group_members')
          .select()
          .eq('group_id', widget.group.id);
      _members = (rows as List)
          .map((r) => GroupMember.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('loadMembers: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = _db
        .channel('group-${widget.group.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'settle_expenses',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: widget.group.id,
          ),
          callback: (payload) {
            _loadExpenses().then((_) {
              if (mounted) setState(() {});
            });
          },
        )
        .subscribe();
  }

  // ── Compute net balances for this group ───────────────────────
  Map<String, int> get _groupNetBalances {
    final map = <String, int>{};
    for (final exp in _expenses) {
      if (exp.paidBy == null) continue;
      // The payer gets credited the full amount
      map[exp.paidBy!] = (map[exp.paidBy!] ?? 0) + exp.amount;
      // Each member gets debited their share equally
      final perMember = exp.amount ~/ _members.length;
      for (final m in _members) {
        if (m.userId == null) continue;
        map[m.userId!] = (map[m.userId!] ?? 0) - perMember;
      }
    }
    return map;
  }

  Map<String, String> get _memberNames => {
    for (final m in _members) if (m.userId != null) m.userId!: m.name,
  };

  Color get _groupColor {
    try {
      final hex = widget.group.coverColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) { return const Color(0xFF7B2FFE); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: GestureDetector(
          onTap: _showAddExpense,
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _groupColor, _groupColor.withValues(alpha: 0.70)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: _groupColor.withValues(alpha: 0.35),
                blurRadius: 16, offset: const Offset(0, 5))],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.text2, size: 22),
              ),
              const SizedBox(width: 14),
              Text(_categoryEmoji(widget.group.category),
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.group.name, style: const TextStyle(
                fontFamily: 'DMSans', fontSize: 20,
                fontWeight: FontWeight.w700, letterSpacing: -0.5,
                color: AppColors.text),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _groupColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_members.length} members',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                      fontWeight: FontWeight.w600, color: _groupColor)),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Tab bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.bg3,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: _groupColor,
                  borderRadius: BorderRadius.circular(17),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontFamily: 'DMSans',
                    fontSize: 11.5, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 11.5),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.text2,
                tabs: const [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Balances'),
                  Tab(text: 'Members'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(
                    strokeWidth: 2, color: _groupColor))
                : TabBarView(
                    controller: _tab,
                    children: [
                      _ExpensesTab(
                          expenses: _expenses, members: _members,
                          currentUid: widget.currentUid,
                          groupColor: _groupColor,
                          onDelete: _deleteExpense),
                      _BalancesTab(
                          netBalances: _groupNetBalances,
                          memberNames: _memberNames,
                          currentUid: widget.currentUid,
                          groupColor: _groupColor,
                          onSettle: _recordSettlement),
                      _MembersTab(
                          members: _members, groupId: widget.group.id,
                          groupColor: _groupColor, onAdded: _loadMembers),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  void _showAddExpense() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        group: widget.group,
        members: _members,
        currentUid: widget.currentUid,
        groupColor: _groupColor,
        onAdded: _loadExpenses,
      ),
    );
  }

  Future<void> _deleteExpense(String id) async {
    await _db.from('settle_expenses').delete().eq('id', id);
    await _loadExpenses();
    if (mounted) setState(() {});
  }

  Future<void> _recordSettlement(
      String fromId, String toId, int amount) async {
    await _db.from('settle_expenses').insert({
      'group_id':     widget.group.id,
      'title':        'Settlement',
      'amount':       amount,
      'paid_by':      fromId,
      'is_settlement': true,
      'created_by':   widget.currentUid,
      'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
    });
    await _loadExpenses();
    if (mounted) setState(() {});
  }
}

// ── Expenses tab ───────────────────────────────────────────────
class _ExpensesTab extends StatelessWidget {
  final List<SettleExpense> expenses;
  final List<GroupMember> members;
  final String currentUid;
  final Color groupColor;
  final Future<void> Function(String) onDelete;
  const _ExpensesTab({
    required this.expenses, required this.members,
    required this.currentUid, required this.groupColor,
    required this.onDelete,
  });

  String _memberName(String? uid) {
    if (uid == null) return '?';
    if (uid == currentUid) return 'You';
    final m = members.firstWhere((m) => m.userId == uid,
        orElse: () => const GroupMember(id: '', groupId: '', displayName: 'Unknown'));
    return m.name;
  }

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_outlined, color: groupColor, size: 36),
        const SizedBox(height: 12),
        const Text('No expenses yet',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 15,
              fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 6),
        const Text('Tap + to add the first expense',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
              color: AppColors.text3)),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final e = expenses[i];
        final paidByMe = e.paidBy == currentUid;
        return Dismissible(
          key: Key('exp-${e.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: AppColors.red, size: 20),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: ctx,
              builder: (dCtx) => AlertDialog(
                backgroundColor: AppColors.bg2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.border2)),
                title: const Text('Delete expense?',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 15,
                      fontWeight: FontWeight.w600, color: AppColors.text)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dCtx, false),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.text2))),
                  TextButton(onPressed: () => Navigator.pop(dCtx, true),
                    child: const Text('Delete',
                        style: TextStyle(color: AppColors.red,
                            fontWeight: FontWeight.w600))),
                ],
              ),
            ) ?? false;
          },
          onDismissed: (_) => onDelete(e.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: e.isSettlement
                  ? AppColors.bg3
                  : groupColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: e.isSettlement
                    ? AppColors.border
                    : groupColor.withValues(alpha: 0.18)),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: (e.isSettlement ? AppColors.green : groupColor)
                      .withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  e.isSettlement
                      ? Icons.check_circle_outline_rounded
                      : Icons.receipt_outlined,
                  color: e.isSettlement ? AppColors.green : groupColor,
                  size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 13.5,
                    fontWeight: FontWeight.w600, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    '${_memberName(e.paidBy)} paid · ${DateFormat('d MMM').format(e.expenseDate)}',
                    style: const TextStyle(fontFamily: 'DMSans',
                        fontSize: 10.5, color: AppColors.text3)),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtP(e.amount), style: TextStyle(
                  fontFamily: 'DMMono', fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: e.isSettlement ? AppColors.green : groupColor)),
                if (paidByMe && !e.isSettlement)
                  Text('you paid', style: TextStyle(
                    fontFamily: 'DMSans', fontSize: 9.5,
                    color: groupColor.withValues(alpha: 0.70))),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

// ── Balances tab ───────────────────────────────────────────────
class _BalancesTab extends StatelessWidget {
  final Map<String, int> netBalances;
  final Map<String, String> memberNames;
  final String currentUid;
  final Color groupColor;
  final Future<void> Function(String, String, int) onSettle;
  const _BalancesTab({
    required this.netBalances, required this.memberNames,
    required this.currentUid, required this.groupColor,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final settlements = simplifyDebts(netBalances, memberNames);

    if (settlements.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.green, size: 32),
        ),
        const SizedBox(height: 14),
        const Text('All settled!', style: TextStyle(
          fontFamily: 'DMSans', fontSize: 16,
          fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 6),
        const Text('No outstanding balances in this group.',
          style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
              color: AppColors.text3)),
      ]));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${settlements.length} payment${settlements.length > 1 ? "s" : ""} to settle this group',
            style: const TextStyle(fontFamily: 'DMSans', fontSize: 11,
                color: AppColors.text3)),
        ),
        ...settlements.map((s) {
          final isCurrentPaying = s.fromId == currentUid;
          final isCurrentReceiving = s.toId == currentUid;
          final color = isCurrentPaying
              ? const Color(0xFFEF4444)
              : isCurrentReceiving
                  ? const Color(0xFF22C55E)
                  : AppColors.text2;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: Row(children: [
              Expanded(child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontFamily: 'DMSans', fontSize: 13.5,
                      color: AppColors.text),
                  children: [
                    TextSpan(
                      text: s.fromId == currentUid ? 'You' : s.fromName,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: color)),
                    const TextSpan(text: ' pays '),
                    TextSpan(
                      text: s.toId == currentUid ? 'You' : s.toName,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              )),
              Text(fmtP(s.amount), style: TextStyle(
                fontFamily: 'DMMono', fontSize: 16,
                fontWeight: FontWeight.w700, color: color)),
              if (isCurrentPaying) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => onSettle(s.fromId, s.toId, s.amount),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF22C55E)
                              .withValues(alpha: 0.30)),
                    ),
                    child: const Text('Mark paid',
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF22C55E))),
                  ),
                ),
              ],
            ]),
          );
        }),
      ],
    );
  }
}

// ── Members tab ────────────────────────────────────────────────
class _MembersTab extends StatefulWidget {
  final List<GroupMember> members;
  final String groupId;
  final Color groupColor;
  final Future<void> Function() onAdded;
  const _MembersTab({
    required this.members, required this.groupId,
    required this.groupColor, required this.onAdded,
  });
  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  void _addMember() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Add Member', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 15,
              fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 14),
            _inputField(ctrl, 'Phone number or name', '+91 9876543210'),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                final val = ctrl.text.trim();
                if (val.isEmpty) return;
                Navigator.pop(ctx);
                await _doAddMember(val);
              },
              child: Container(
                width: double.infinity, height: 46,
                decoration: BoxDecoration(
                  color: widget.groupColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('Add to Group',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 14,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _doAddMember(String phoneOrName) async {
    String? userId;
    String displayName = phoneOrName;
    try {
      final isPhone = RegExp(r'^\+?[\d\s\-]{7,}$').hasMatch(phoneOrName);
      final col = isPhone ? 'phone' : 'name';
      final res = await _db.from('profiles')
          .select('id, name, phone')
          .eq(col, phoneOrName)
          .maybeSingle();
      if (res != null) {
        userId = res['id'] as String?;
        displayName = (res['name'] as String?) ?? phoneOrName;
      }
    } catch (_) {}

    try {
      await _db.from('settle_group_members').insert({
        'group_id':     widget.groupId,
        if (userId != null) 'user_id': userId,
        'display_name': displayName,
        'phone':        phoneOrName,
      });
      await widget.onAdded();
    } catch (_) {}
  }

  Widget _inputField(TextEditingController c, String label, String hint) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans',
          fontSize: 10.5, color: AppColors.text3)),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(color: AppColors.bg3,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border)),
        child: TextField(
          controller: c,
          style: const TextStyle(fontFamily: 'DMSans',
              fontSize: 13, color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
            border: InputBorder.none, enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none, filled: false,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
        ),
      ),
    ]);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        ...widget.members.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.groupColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: widget.groupColor.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: widget.groupColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(m.initials, style: TextStyle(
                fontFamily: 'DMSans', fontSize: 15,
                fontWeight: FontWeight.w700, color: widget.groupColor)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(
                  fontFamily: 'DMSans', fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppColors.text)),
                if (m.phone != null)
                  Text(m.phone!, style: const TextStyle(
                    fontFamily: 'DMSans', fontSize: 10.5,
                    color: AppColors.text3)),
              ],
            )),
            if (m.userId != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('ZeroTab',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.green)),
              ),
          ]),
        )),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _addMember,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.groupColor.withValues(alpha: 0.30)),
            ),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_add_outlined, color: widget.groupColor, size: 16),
              const SizedBox(width: 6),
              Text('Add Member', style: TextStyle(fontFamily: 'DMSans',
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: widget.groupColor)),
            ]),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ADD EXPENSE SHEET
// ════════════════════════════════════════════════════════════════

class _AddExpenseSheet extends StatefulWidget {
  final SettleGroup group;
  final List<GroupMember> members;
  final String currentUid;
  final Color groupColor;
  final Future<void> Function() onAdded;
  const _AddExpenseSheet({
    required this.group, required this.members,
    required this.currentUid, required this.groupColor,
    required this.onAdded,
  });
  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _titleCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  String _splitMode   = 'EQUAL';
  String? _paidBy;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _paidBy = widget.currentUid;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final amtStr = _amountCtrl.text.trim();
    if (title.isEmpty || amtStr.isEmpty) return;
    final amtRupees = double.tryParse(amtStr);
    if (amtRupees == null || amtRupees <= 0) return;

    setState(() => _loading = true);
    try {
      final amtPaise = toP(amtRupees);
      await _db.from('settle_expenses').insert({
        'group_id':     widget.group.id,
        'title':        title,
        'amount':       amtPaise,
        'paid_by':      _paidBy,
        'split_mode':   _splitMode,
        'notes':        _notesCtrl.text.trim().isEmpty
                          ? null : _notesCtrl.text.trim(),
        'created_by':   widget.currentUid,
        'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      });
      await widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('addExpense: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border2),
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: widget.groupColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.receipt_outlined,
                  color: widget.groupColor, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Add Expense', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
          const SizedBox(height: 16),
          _field('What was it for?', _titleCtrl, 'Dinner, groceries, taxi...'),
          const SizedBox(height: 12),
          _field('Amount (₹)', _amountCtrl, '0.00',
              type: TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 14),

          // Paid by
          const Text('Paid by', style: TextStyle(fontFamily: 'DMSans',
              fontSize: 11, color: AppColors.text3)),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: widget.members
                  .where((m) => m.userId != null)
                  .map((m) {
                final active = _paidBy == m.userId;
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: GestureDetector(
                    onTap: () => setState(() => _paidBy = m.userId),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      decoration: BoxDecoration(
                        color: active
                            ? widget.groupColor.withValues(alpha: 0.18)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? widget.groupColor.withValues(alpha: 0.50)
                              : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        m.userId == widget.currentUid ? 'You' : m.name,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active ? widget.groupColor
                                : AppColors.text2)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Split mode
          const Text('Split', style: TextStyle(fontFamily: 'DMSans',
              fontSize: 11, color: AppColors.text3)),
          const SizedBox(height: 6),
          Row(children: [
            for (final mode in ['EQUAL', 'EXACT', 'PERCENTAGE'])
              Expanded(child: Padding(
                padding: EdgeInsets.only(
                    right: mode != 'PERCENTAGE' ? 6 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _splitMode = mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 34,
                    decoration: BoxDecoration(
                      color: _splitMode == mode
                          ? widget.groupColor.withValues(alpha: 0.15)
                          : AppColors.bg3,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _splitMode == mode
                            ? widget.groupColor.withValues(alpha: 0.50)
                            : AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      mode == 'EQUAL' ? '÷ Equal' :
                      mode == 'EXACT' ? '₹ Exact' : '% Percent',
                      style: TextStyle(fontFamily: 'DMSans',
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: _splitMode == mode
                              ? widget.groupColor : AppColors.text2)),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 12),
          _field('Notes (optional)', _notesCtrl, 'Any details...'),
          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.groupColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: widget.groupColor.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add Expense', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      )),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {TextInputType? type}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'DMSans',
          fontSize: 11, color: AppColors.text3)),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(color: AppColors.bg3,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
        child: TextField(
          controller: c,
          keyboardType: type,
          style: const TextStyle(fontFamily: 'DMSans',
              fontSize: 14, color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
            border: InputBorder.none, enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none, filled: false,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ),
    ]);
}

// ════════════════════════════════════════════════════════════════
//  CREATE GROUP SHEET
// ════════════════════════════════════════════════════════════════

class _CreateGroupSheet extends StatefulWidget {
  final String currentUid;
  final VoidCallback onCreated;
  const _CreateGroupSheet({required this.currentUid, required this.onCreated});
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _memberCtrl  = TextEditingController();
  String _category   = 'general';
  String _coverColor = '#22C55E';
  List<String> _pendingMembers = [];
  bool _loading = false;

  static const _categories = [
    ('general', '👥', 'General'),
    ('trip',    '✈️', 'Trip'),
    ('home',    '🏠', 'Home'),
    ('couple',  '💑', 'Couple'),
    ('food',    '🍕', 'Food'),
  ];

  static const _colors = [
    ('#22C55E', Color(0xFF22C55E)),
    ('#7B2FFE', Color(0xFF7B2FFE)),
    ('#00CFDE', Color(0xFF00CFDE)),
    ('#F59E0B', Color(0xFFF59E0B)),
    ('#FF6B5B', Color(0xFFFF6B5B)),
    ('#FF6B9D', Color(0xFFFF6B9D)),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _memberCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      // 1. Create group
      final res = await _db.from('settle_groups').insert({
        'name':        name,
        'description': _descCtrl.text.trim().isEmpty
                         ? null : _descCtrl.text.trim(),
        'category':    _category,
        'cover_color': _coverColor,
        'created_by':  widget.currentUid,
        'currency':    'INR',
      }).select().single();

      final groupId = res['id'] as String;

      // 2. Add creator as member
      await _db.from('settle_group_members').insert({
        'group_id': groupId, 'user_id': widget.currentUid,
      });

      // 3. Add pending members
      for (final contact in _pendingMembers) {
        String? userId;
        String displayName = contact;
        try {
          final isPhone = RegExp(r'^\+?[\d\s\-]{7,}$').hasMatch(contact);
          final col = isPhone ? 'phone' : 'name';
          final p = await _db.from('profiles')
              .select('id, name').eq(col, contact).maybeSingle();
          if (p != null) {
            userId = p['id'] as String?;
            displayName = (p['name'] as String?) ?? contact;
          }
        } catch (_) {}
        await _db.from('settle_group_members').insert({
          'group_id':     groupId,
          if (userId != null) 'user_id': userId,
          'display_name': displayName,
          'phone':        contact,
        });
      }

      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('createGroup: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border2),
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Create a Group', style: TextStyle(
            fontFamily: 'DMSans', fontSize: 17,
            fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 16),
          _lbl('Group name'),
          const SizedBox(height: 5),
          _input(_nameCtrl, 'Trip to Goa, Flat 3B, Rahul\'s wedding...'),
          const SizedBox(height: 12),
          _lbl('Description (optional)'),
          const SizedBox(height: 5),
          _input(_descCtrl, 'What\'s this group for?'),
          const SizedBox(height: 14),

          // Category
          _lbl('Category'),
          const SizedBox(height: 6),
          SizedBox(height: 34, child: ListView(
            scrollDirection: Axis.horizontal,
            children: _categories.map((c) {
              final active = _category == c.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: GestureDetector(
                  onTap: () => setState(() => _category = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 0),
                    decoration: BoxDecoration(
                      color: active ? AppColors.accentSoft : AppColors.bg3,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active ? AppColors.accent.withValues(alpha: 0.50)
                            : AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text('${c.$2} ${c.$3}',
                      style: TextStyle(fontFamily: 'DMSans',
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: active ? AppColors.accent2
                              : AppColors.text2)),
                  ),
                ),
              );
            }).toList(),
          )),
          const SizedBox(height: 14),

          // Color
          _lbl('Color'),
          const SizedBox(height: 6),
          Row(children: _colors.map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _coverColor = c.$1),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: c.$2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _coverColor == c.$1
                        ? Colors.white : Colors.transparent,
                    width: 2.5),
                ),
                child: _coverColor == c.$1
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ),
          )).toList()),
          const SizedBox(height: 14),

          // Add members
          _lbl('Add members (phone or name)'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _input(_memberCtrl,
                '+91 9876543210 or Rahul...')),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final v = _memberCtrl.text.trim();
                if (v.isEmpty) return;
                setState(() {
                  _pendingMembers.add(v);
                  _memberCtrl.clear();
                });
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.30)),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add_rounded,
                    color: AppColors.accent, size: 20),
              ),
            ),
          ]),
          if (_pendingMembers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: _pendingMembers.map((m) =>
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(m, style: const TextStyle(fontFamily: 'DMSans',
                      fontSize: 11, color: AppColors.text)),
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () => setState(
                        () => _pendingMembers.remove(m)),
                    child: const Icon(Icons.close_rounded,
                        size: 13, color: AppColors.text3)),
                ]),
              )).toList()),
          ],
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create Group', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      )),
    );
  }

  Widget _lbl(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3));

  Widget _input(TextEditingController c, String hint) => Container(
    height: 42,
    decoration: BoxDecoration(color: AppColors.bg3,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border)),
    child: TextField(
      controller: c,
      style: const TextStyle(fontFamily: 'DMSans',
          fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
        border: InputBorder.none, enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none, filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        isDense: true,
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
//  ADD INDIVIDUAL SPLIT SHEET
// ════════════════════════════════════════════════════════════════

class _AddSplitSheet extends StatefulWidget {
  final String currentUid;
  final VoidCallback onAdded;
  const _AddSplitSheet({required this.currentUid, required this.onAdded});
  @override
  State<_AddSplitSheet> createState() => _AddSplitSheetState();
}

class _AddSplitSheetState extends State<_AddSplitSheet> {
  final _contactCtrl = TextEditingController();
  final _amountCtrl  = TextEditingController();
  final _descCtrl    = TextEditingController();
  bool _youOwe  = false;
  bool _loading = false;

  @override
  void dispose() {
    _contactCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final contact   = _contactCtrl.text.trim();
    final amtStr    = _amountCtrl.text.trim();
    final amtRupees = double.tryParse(amtStr);
    if (contact.isEmpty || amtRupees == null || amtRupees <= 0) return;

    setState(() => _loading = true);
    try {
      String? participantUserId;
      String participantName = contact;
      try {
        final isPhone = RegExp(r'^\+?[\d\s\-]{7,}$').hasMatch(contact);
        final col = isPhone ? 'phone' : 'name';
        final res = await _db.from('profiles')
            .select('id, name').eq(col, contact).maybeSingle();
        if (res != null) {
          participantUserId = res['id'] as String?;
          participantName = (res['name'] as String?) ?? contact;
        }
      } catch (_) {}

      await _db.from('settle_splits').insert({
        'created_by':          widget.currentUid,
        'participant_user_id': participantUserId,
        'participant_phone':   contact,
        'participant_name':    participantName,
        'amount':              toP(amtRupees),
        'description':         _descCtrl.text.trim().isEmpty
                                 ? null : _descCtrl.text.trim(),
        'split_date':          DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'you_owe':             _youOwe,
        'is_settled':          false,
      });

      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('addSplit: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border2),
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border2,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.balance_outlined,
                  color: Color(0xFF22C55E), size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Split with a Friend', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.text)),
          ]),
          const SizedBox(height: 4),
          const Text('Enter their phone, email, or any name',
            style: TextStyle(fontFamily: 'DMSans', fontSize: 11.5,
                color: AppColors.text3)),
          const SizedBox(height: 16),
          _lbl('Friend (phone / email / name)'),
          const SizedBox(height: 5),
          _input(_contactCtrl,
              '+91 9876543210  or  rahul@gmail.com  or  Rahul'),
          const SizedBox(height: 10),
          _lbl('What for?'),
          const SizedBox(height: 5),
          _input(_descCtrl, 'Dinner, movie, trip...'),
          const SizedBox(height: 10),
          _lbl('Amount (₹)'),
          const SizedBox(height: 5),
          _input(_amountCtrl, '0.00',
              type: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 14),

          // Who owes
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _youOwe = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 44,
                decoration: BoxDecoration(
                  color: !_youOwe
                      ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                      : AppColors.bg3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: !_youOwe
                        ? const Color(0xFF22C55E).withValues(alpha: 0.50)
                        : AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text('They owe you',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: !_youOwe
                          ? const Color(0xFF22C55E) : AppColors.text3)),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => setState(() => _youOwe = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 44,
                decoration: BoxDecoration(
                  color: _youOwe
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : AppColors.bg3,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _youOwe
                        ? const Color(0xFFEF4444).withValues(alpha: 0.50)
                        : AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text('You owe them',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _youOwe
                          ? const Color(0xFFEF4444) : AppColors.text3)),
              ),
            )),
          ]),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add Split', style: TextStyle(
                      fontFamily: 'DMSans', fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      )),
    );
  }

  Widget _lbl(String t) => Text(t, style: const TextStyle(
    fontFamily: 'DMSans', fontSize: 11, color: AppColors.text3));

  Widget _input(TextEditingController c, String hint,
      {TextInputType? type}) => Container(
    height: 42,
    decoration: BoxDecoration(color: AppColors.bg3,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border)),
    child: TextField(
      controller: c,
      keyboardType: type,
      style: const TextStyle(fontFamily: 'DMSans',
          fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
        border: InputBorder.none, enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none, filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        isDense: true,
      ),
    ),
  );
}
