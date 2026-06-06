// ── ZeroTab domain models ─────────────────────────────────

class UserModel {
  final String id;
  final String? phone;
  final String? email;
  final String? name;
  final String? financialArchetype;
  final DateTime createdAt;
  final DateTime? lastActive;

  const UserModel({
    required this.id,
    this.phone,
    this.email,
    this.name,
    this.financialArchetype,
    required this.createdAt,
    this.lastActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id:                  j['id'] as String,
    phone:               j['phone'] as String?,
    email:               j['email'] as String?,
    name:                j['name'] as String?,
    financialArchetype:  j['financial_archetype'] as String?,
    createdAt:           DateTime.parse(j['created_at'] as String),
    lastActive:          j['last_active'] != null ? DateTime.parse(j['last_active'] as String) : null,
  );
}

class AccountModel {
  final String id;
  final String userId;
  final String sourceType;
  final String? institutionName;
  final String? accountType;
  final String? maskedNumber;
  final double? currentBalance;
  final double? creditLimit;
  final String currency;
  final DateTime? lastSyncedAt;
  final bool isActive;
  final Map<String, dynamic>? metadata;

  const AccountModel({
    required this.id,
    required this.userId,
    required this.sourceType,
    this.institutionName,
    this.accountType,
    this.maskedNumber,
    this.currentBalance,
    this.creditLimit,
    this.currency = 'INR',
    this.lastSyncedAt,
    this.isActive = true,
    this.metadata,
  });

  factory AccountModel.fromJson(Map<String, dynamic> j) => AccountModel(
    id:              j['id'] as String,
    userId:          j['user_id'] as String,
    sourceType:      j['source_type'] as String,
    institutionName: j['institution_name'] as String?,
    accountType:     j['account_type'] as String?,
    maskedNumber:    j['masked_number'] as String?,
    currentBalance:  (j['current_balance'] as num?)?.toDouble(),
    creditLimit:     (j['credit_limit'] as num?)?.toDouble(),
    currency:        j['currency'] as String? ?? 'INR',
    lastSyncedAt:    j['last_synced_at'] != null ? DateTime.parse(j['last_synced_at'] as String) : null,
    isActive:        j['is_active'] as bool? ?? true,
    metadata:        j['metadata'] as Map<String, dynamic>?,
  );

  // Loan-specific helpers
  String? get loanName        => metadata?['loan_name'] as String?;
  double? get interestRate    => (metadata?['interest_rate'] as num?)?.toDouble();
  int?    get tenorMonths     => (metadata?['tenor_months'] as num?)?.toInt();
  String? get loanStartDate   => metadata?['start_date'] as String?;
  double? get originalPrincipal => (metadata?['original_principal'] as num?)?.toDouble();
}

class TransactionModel {
  final String id;
  final String accountId;
  final String userId;
  final DateTime txnDate;
  final double amount;
  final String type;
  final String? category;
  final String? merchant;
  final String? description;
  final String? source;
  final bool isRecurring;

  const TransactionModel({
    required this.id,
    required this.accountId,
    required this.userId,
    required this.txnDate,
    required this.amount,
    required this.type,
    this.category,
    this.merchant,
    this.description,
    this.source,
    this.isRecurring = false,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> j) => TransactionModel(
    id:          j['id'] as String,
    accountId:   j['account_id'] as String,
    userId:      j['user_id'] as String,
    txnDate:     DateTime.parse(j['txn_date'] as String),
    amount:      (j['amount'] as num).toDouble(),
    type:        j['type'] as String,
    category:    j['category'] as String?,
    merchant:    j['merchant'] as String?,
    description: j['description'] as String?,
    source:      j['source'] as String?,
    isRecurring: j['is_recurring'] as bool? ?? false,
  );

  bool get isDebit  => type == 'debit';
  bool get isCredit => type == 'credit';
}

class MFHoldingModel {
  final String id;
  final String userId;
  final String? folioNumber;
  final String? schemeCode;
  final String? schemeName;
  final String? amcName;
  final double? units;
  final double? avgNav;
  final double? currentNav;
  final double? investedAmount;
  final double? currentValue;
  final double? xirr;
  final DateTime? lastUpdated;

  const MFHoldingModel({
    required this.id,
    required this.userId,
    this.folioNumber,
    this.schemeCode,
    this.schemeName,
    this.amcName,
    this.units,
    this.avgNav,
    this.currentNav,
    this.investedAmount,
    this.currentValue,
    this.xirr,
    this.lastUpdated,
  });

  factory MFHoldingModel.fromJson(Map<String, dynamic> j) => MFHoldingModel(
    id:             j['id'] as String,
    userId:         j['user_id'] as String,
    folioNumber:    j['folio_number'] as String?,
    schemeCode:     j['scheme_code'] as String?,
    schemeName:     j['scheme_name'] as String?,
    amcName:        j['amc_name'] as String?,
    units:          (j['units'] as num?)?.toDouble(),
    avgNav:         (j['avg_nav'] as num?)?.toDouble(),
    currentNav:     (j['current_nav'] as num?)?.toDouble(),
    investedAmount: (j['invested_amount'] as num?)?.toDouble(),
    currentValue:   (j['current_value'] as num?)?.toDouble(),
    xirr:           (j['xirr'] as num?)?.toDouble(),
    lastUpdated:    j['last_updated'] != null ? DateTime.parse(j['last_updated'] as String) : null,
  );

  double get gainLoss     => (currentValue ?? 0) - (investedAmount ?? 0);
  double get gainLossPct  => (investedAmount ?? 0) > 0 ? (gainLoss / investedAmount!) * 100 : 0;

  bool   get isStock           => (folioNumber ?? '').startsWith('STOCK-');
  bool   get isETF             => (folioNumber ?? '').startsWith('ETF-');
  bool   get isCommodity       => (folioNumber ?? '').startsWith('COMM-');
  bool   get isMF              => !isStock && !isETF && !isCommodity;
  String get stockSymbol       => isStock ? (schemeCode ?? '') : '';
  String get stockExchange     => isStock ? (amcName ?? 'NSE') : '';
  double get stockQty          => isStock ? (units ?? 0) : 0;
  double get stockCurrentPrice => isStock ? (currentNav ?? 0) : 0;
  String get etfSymbol         => isETF ? (schemeCode ?? '') : '';
  String get commoditySymbol   => isCommodity ? (schemeCode ?? '') : '';
}

class AIInsightModel {
  final String id;
  final String userId;
  final int weekNumber;
  final int year;
  final String? archetype;
  final String insightText;
  final String? insightType;
  final List<ActionItem> actionItems;
  final FinancialSnapshotModel? dataSnapshot;
  final DateTime generatedAt;
  final String priority;
  final bool isRead;
  final bool isDismissed;
  final String triggerType;

  const AIInsightModel({
    required this.id,
    required this.userId,
    required this.weekNumber,
    required this.year,
    this.archetype,
    required this.insightText,
    this.insightType,
    this.actionItems = const [],
    this.dataSnapshot,
    required this.generatedAt,
    this.priority = 'informational',
    this.isRead = false,
    this.isDismissed = false,
    this.triggerType = 'scheduled',
  });

  bool get isUrgent      => priority == 'urgent';
  bool get isActionable  => priority == 'actionable';

  factory AIInsightModel.fromJson(Map<String, dynamic> j) {
    final rawItems = j['action_items'];
    final items = rawItems is List
        ? rawItems.map((e) => ActionItem.fromJson(e as Map<String, dynamic>)).toList()
        : <ActionItem>[];

    FinancialSnapshotModel? snapshot;
    if (j['data_snapshot'] is Map) {
      try {
        snapshot = FinancialSnapshotModel.fromJson(j['data_snapshot'] as Map<String, dynamic>);
      } catch (_) {}
    }

    return AIInsightModel(
      id:           j['id'] as String,
      userId:       j['user_id'] as String,
      weekNumber:   j['week_number'] as int,
      year:         j['year'] as int,
      archetype:    j['archetype'] as String?,
      insightText:  j['insight_text'] as String,
      insightType:  j['insight_type'] as String?,
      actionItems:  items,
      dataSnapshot: snapshot,
      generatedAt:  DateTime.parse(j['generated_at'] as String),
      priority:     j['priority'] as String? ?? 'informational',
      isRead:       j['is_read'] as bool? ?? false,
      isDismissed:  j['is_dismissed'] as bool? ?? false,
      triggerType:  j['trigger_type'] as String? ?? 'scheduled',
    );
  }
}

class ActionItem {
  final int step;
  final String text;
  const ActionItem({required this.step, required this.text});
  factory ActionItem.fromJson(Map<String, dynamic> j) =>
      ActionItem(step: j['step'] as int, text: j['text'] as String);
}

/// Full financial snapshot from /users/me/snapshot
class FinancialSnapshotModel {
  final double netWorth;
  final double monthlyIncome;
  final double monthlySpend;
  final double savingsRate;
  final double emiRatio;
  final double mfValue;
  final double mfXirr;
  final double creditUtil;
  final List<String> topCategories;
  final String biggestChange;
  final String archetype;
  final double bankBalance;
  final double creditCardDebt;
  final double loanOutstanding;

  const FinancialSnapshotModel({
    required this.netWorth,
    required this.monthlyIncome,
    required this.monthlySpend,
    required this.savingsRate,
    required this.emiRatio,
    required this.mfValue,
    required this.mfXirr,
    required this.creditUtil,
    required this.topCategories,
    required this.biggestChange,
    required this.archetype,
    required this.bankBalance,
    required this.creditCardDebt,
    required this.loanOutstanding,
  });

  factory FinancialSnapshotModel.fromJson(Map<String, dynamic> j) => FinancialSnapshotModel(
    netWorth:        (j['netWorth'] as num?)?.toDouble() ?? 0,
    monthlyIncome:   (j['monthlyIncome'] as num?)?.toDouble() ?? 0,
    monthlySpend:    (j['monthlySpend'] as num?)?.toDouble() ?? 0,
    savingsRate:     (j['savingsRate'] as num?)?.toDouble() ?? 0,
    emiRatio:        (j['emiRatio'] as num?)?.toDouble() ?? 0,
    mfValue:         (j['mfValue'] as num?)?.toDouble() ?? 0,
    mfXirr:          (j['mfXIRR'] as num?)?.toDouble() ?? 0,
    creditUtil:      (j['creditUtil'] as num?)?.toDouble() ?? 0,
    topCategories:   List<String>.from(j['topCategories'] as List? ?? []),
    biggestChange:   j['biggestChange'] as String? ?? '',
    archetype:       j['archetype'] as String? ?? 'BALANCED_WEALTH_BUILDER',
    bankBalance:     (j['bankBalance'] as num?)?.toDouble() ?? 0,
    creditCardDebt:  (j['creditCardDebt'] as num?)?.toDouble() ?? 0,
    loanOutstanding: (j['loanOutstanding'] as num?)?.toDouble() ?? 0,
  );

  /// Financial health score 0–100.
  /// Uses continuous piecewise-linear scoring so small changes don't cause
  /// cliff jumps, and poor finances can now score below 50 (down to ~10).
  ///
  /// Weights: Savings(25) + EMI burden(25) + Credit health(20) + Investment(15) + Spend control(15)
  double get healthScore {
    // ── Savings rate: 0 → 0 pts, 10% → 12.5, 20%+ → 25 pts ─────
    final savingsContrib = savingsRate >= 0.20
        ? 25.0
        : savingsRate > 0
            ? (savingsRate / 0.20) * 25
            : 0.0;

    // ── EMI ratio: 0% → 25 pts, 40% → 0 pts (lower = better) ────
    final emiContrib = ((1 - emiRatio / 0.40) * 25).clamp(0.0, 25.0);

    // ── Credit utilisation: 0% → 20 pts, 75% → 0 pts ─────────────
    final creditContrib = ((1 - creditUtil / 0.75) * 20).clamp(0.0, 20.0);

    // ── Investment: scored against 6 months income target ─────────
    final targetInv = monthlyIncome > 0 ? monthlyIncome * 6.0 : 50000.0;
    final investContrib = mfValue >= targetInv
        ? 15.0
        : (mfValue / targetInv * 15).clamp(0.0, 15.0);

    // ── Spend control: 0% spend → 15 pts, 100% → 0 pts ───────────
    final spendContrib = monthlyIncome > 0
        ? ((1 - monthlySpend / monthlyIncome) * 15).clamp(0.0, 15.0)
        : 7.5;

    return (savingsContrib + emiContrib + creditContrib + investContrib + spendContrib)
        .clamp(0.0, 100.0);
  }
}

// ── Chat models ──────────────────────────────────────────

class ChatSession {
  final String id;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final bool isActive;

  const ChatSession({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    this.isActive = true,
  });

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
    id:            j['id'] as String,
    userId:        j['user_id'] as String,
    title:         j['title'] as String? ?? 'New conversation',
    createdAt:     DateTime.parse(j['created_at'] as String),
    lastMessageAt: DateTime.parse(j['last_message_at'] as String),
    isActive:      j['is_active'] as bool? ?? true,
  );
}

class ChatMessage {
  final String? id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isLoading;

  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isLoading = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id:        j['id'] as String?,
    role:      j['role'] as String,
    content:   j['content'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  bool get isUser      => role == 'user';
  bool get isAssistant => role == 'assistant';
}

class FinancialSummary {
  final double netWorth;
  final double bankBalance;
  final double creditCardDebt;
  final double loanOutstanding;
  final double mfValue;
  final List<AccountModel> accounts;

  const FinancialSummary({
    required this.netWorth,
    required this.bankBalance,
    required this.creditCardDebt,
    required this.loanOutstanding,
    required this.mfValue,
    required this.accounts,
  });

  factory FinancialSummary.fromJson(Map<String, dynamic> j) => FinancialSummary(
    netWorth:        (j['netWorth'] as num).toDouble(),
    bankBalance:     (j['bankBalance'] as num).toDouble(),
    creditCardDebt:  (j['creditCardDebt'] as num).toDouble(),
    loanOutstanding: (j['loanOutstanding'] as num).toDouble(),
    mfValue:         (j['mfValue'] as num).toDouble(),
    accounts:        (j['accounts'] as List? ?? [])
                       .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
                       .toList(),
  );
}
