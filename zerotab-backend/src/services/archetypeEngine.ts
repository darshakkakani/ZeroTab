/**
 * ZeroTab — Financial Archetype Engine v1 (rule-based)
 * Classifies each user into one of 20 archetypes based on
 * the last 3 months of transaction + balance data.
 *
 * Recomputed weekly via BullMQ cron (Sunday midnight).
 */
import { supabaseAdmin } from '../lib/supabase.js';
import { FinancialSnapshot, ArchetypeCode } from '../types/index.js';

// ── Archetype definitions ─────────────────────────────────

interface ArchetypeDef {
  code: ArchetypeCode;
  label: string;
  insight_focus: string;
  test: (s: FinancialSnapshot) => boolean;
}

const ARCHETYPES: ArchetypeDef[] = [
  {
    code: 'HIGH_INCOME_HIGH_EMI',
    label: 'High Income, High EMI',
    insight_focus: 'debt_optimisation',
    test: (s) => s.monthlyIncome > 100_000 && s.emiRatio > 0.40,
  },
  {
    code: 'YOUNG_SAVER',
    label: 'Young Saver',
    insight_focus: 'investment_start',
    test: (s) => s.savingsRate > 0.20 && s.netWorth < 1_000_000,
  },
  {
    code: 'LIFESTYLE_INFLATED',
    label: 'Lifestyle Inflated',
    insight_focus: 'spend_awareness',
    // discretionary = food_delivery + dining + shopping + travel + subscriptions
    test: (s) => {
      const discretionary = s.monthlySpend * 0.6; // approx — refined by category data
      return discretionary > 0.40 * s.monthlyIncome;
    },
  },
  {
    code: 'UNDERINVESTED',
    label: 'Underinvested',
    insight_focus: 'idle_cash_alert',
    test: (s) => s.bankBalance > 500_000 && s.mfValue < 0.10 * s.bankBalance,
  },
  {
    code: 'CREDIT_STRESSED',
    label: 'Credit Stressed',
    insight_focus: 'credit_health',
    test: (s) => s.creditUtil > 0.70,
  },
  {
    code: 'GOOD_INVESTOR',
    label: 'Good Investor',
    insight_focus: 'portfolio_optimisation',
    test: (s) => s.mfValue > 0 && s.savingsRate > 0.15 && s.mfXIRR > 0,
  },
  {
    code: 'DEBT_FREE_SPENDER',
    label: 'Debt-Free Spender',
    insight_focus: 'savings_nudge',
    test: (s) => s.emiRatio < 0.05 && s.creditUtil < 0.20 && s.savingsRate < 0.10,
  },
  {
    code: 'CONSERVATIVE_SAVER',
    label: 'Conservative Saver',
    insight_focus: 'diversification',
    test: (s) => s.bankBalance > 200_000 && s.mfValue === 0 && s.savingsRate > 0.15,
  },
  {
    code: 'SIP_STARTER',
    label: 'SIP Starter',
    insight_focus: 'sip_increase',
    test: (s) => s.mfValue > 0 && s.mfValue < 100_000 && s.savingsRate > 0.10,
  },
  {
    code: 'REAL_ESTATE_HEAVY',
    label: 'Real Estate Heavy',
    insight_focus: 'liquidity_balance',
    test: (s) => s.emiRatio > 0.30 && s.emiRatio < 0.50 && s.bankBalance < 100_000,
  },
  {
    code: 'CASH_HOARDER',
    label: 'Cash Hoarder',
    insight_focus: 'idle_cash_invest',
    test: (s) => s.bankBalance > 1_000_000 && s.mfValue < 0.05 * s.bankBalance,
  },
  {
    code: 'EMI_JUGGLER',
    label: 'EMI Juggler',
    insight_focus: 'debt_consolidation',
    test: (s) => s.emiRatio > 0.50,
  },
  {
    code: 'SUBSCRIPTIONS_HEAVY',
    label: 'Subscriptions Heavy',
    insight_focus: 'subscription_audit',
    // Flagged if > 5% income on subscriptions — approximated via spend pattern
    test: (s) => s.topCategories.includes('subscriptions') && s.savingsRate < 0.15,
  },
  {
    code: 'FOOD_DELIVERY_ADDICT',
    label: 'Food Delivery Addict',
    insight_focus: 'food_spend_control',
    test: (s) => s.topCategories[0] === 'food_delivery' && s.savingsRate < 0.20,
  },
  {
    code: 'TRAVEL_SPENDER',
    label: 'Travel Spender',
    insight_focus: 'travel_budget',
    test: (s) => s.topCategories.includes('travel') && s.creditUtil > 0.30,
  },
  {
    code: 'INSURANCE_UNDERSERVED',
    label: 'Insurance Underserved',
    insight_focus: 'insurance_nudge',
    test: (s) => s.netWorth > 500_000 && s.loanOutstanding > 0 && s.mfValue < 50_000,
  },
  {
    code: 'HIGH_NET_WORTH',
    label: 'High Net Worth',
    insight_focus: 'wealth_optimisation',
    test: (s) => s.netWorth > 10_000_000,
  },
  {
    code: 'EMERGING_PROFESSIONAL',
    label: 'Emerging Professional',
    insight_focus: 'wealth_foundation',
    test: (s) =>
      s.monthlyIncome > 50_000 &&
      s.monthlyIncome < 100_000 &&
      s.netWorth < 500_000 &&
      s.savingsRate > 0.10,
  },
  {
    code: 'BUDGET_CONSCIOUS',
    label: 'Budget Conscious',
    insight_focus: 'savings_maximise',
    test: (s) => s.savingsRate > 0.25 && s.monthlySpend < 0.60 * s.monthlyIncome,
  },
  {
    code: 'BALANCED_WEALTH_BUILDER',
    label: 'Balanced Wealth Builder',
    insight_focus: 'next_milestone',
    // Default / catch-all for well-balanced users
    test: (_s) => true,
  },
];

// ── Build financial snapshot for a user ───────────────────

export async function buildFinancialSnapshot(userId: string): Promise<FinancialSnapshot> {
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  // 1. Accounts
  const { data: accounts } = await supabaseAdmin
    .from('accounts')
    .select('*')
    .eq('user_id', userId)
    .eq('is_active', true);

  const bankBalance      = (accounts ?? [])
    .filter((a) => ['savings', 'current', 'fd'].includes(a.account_type))
    .reduce((s, a) => s + (a.current_balance ?? 0), 0);

  const creditCardDebt   = (accounts ?? [])
    .filter((a) => a.account_type === 'credit_card')
    .reduce((s, a) => s + Math.abs(a.current_balance ?? 0), 0);

  const creditCardLimit  = (accounts ?? [])
    .filter((a) => a.account_type === 'credit_card')
    .reduce((s, a) => s + (a.credit_limit ?? 0), 0);

  const loanOutstanding  = (accounts ?? [])
    .filter((a) => a.account_type === 'loan')
    .reduce((s, a) => s + Math.abs(a.current_balance ?? 0), 0);

  const creditUtil = creditCardLimit > 0 ? creditCardDebt / creditCardLimit : 0;

  // 2. MF holdings
  const { data: mfHoldings } = await supabaseAdmin
    .from('mf_holdings')
    .select('current_value, xirr')
    .eq('user_id', userId);

  const mfValue = (mfHoldings ?? []).reduce((s, h) => s + (h.current_value ?? 0), 0);
  const mfXIRR  = mfHoldings?.length
    ? (mfHoldings.reduce((s, h) => s + (h.xirr ?? 0), 0) / mfHoldings.length) * 100
    : 0;

  // 3. Net worth
  const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;

  // 4. Transactions last 3 months
  const { data: txns } = await supabaseAdmin
    .from('transactions')
    .select('amount, type, category, txn_date')
    .eq('user_id', userId)
    .gte('txn_date', threeMonthsAgo.toISOString().split('T')[0]);

  const credits  = (txns ?? []).filter((t) => t.type === 'credit');
  const debits   = (txns ?? []).filter((t) => t.type === 'debit');

  const monthlyIncome = credits
    .filter((t) => ['income', 'salary', 'others'].includes(t.category ?? 'others'))
    .reduce((s, t) => s + t.amount, 0) / 3;

  const monthlySpend  = debits.reduce((s, t) => s + t.amount, 0) / 3;

  // ── EMI calculation: transactions categorised as 'emi' PLUS
  //    calculated monthly EMI from all active loan accounts.
  //    This ensures manually-added loans are always reflected even
  //    when the user hasn't logged individual EMI transactions.
  const txnEmiSpend = debits
    .filter((t) => t.category === 'emi')
    .reduce((s, t) => s + t.amount, 0) / 3;

  // Calculate monthly EMI for each active loan account
  function calcEmi(principal: number, annualRate: number, months: number): number {
    if (months <= 0 || principal <= 0) return 0;
    if (annualRate <= 0) return principal / months;
    const r = annualRate / 12 / 100;
    return principal * r * Math.pow(1 + r, months) / (Math.pow(1 + r, months) - 1);
  }

  const loanAccounts = (accounts ?? []).filter((a) => a.account_type === 'loan');
  let loanEmiMonthly = 0;
  const now = new Date();

  for (const loan of loanAccounts) {
    const outstanding = Math.abs(loan.current_balance ?? 0);
    if (outstanding <= 0) continue;

    const meta         = (loan.metadata as any) ?? {};
    const annualRate   = (meta.interest_rate  ?? 0) as number;
    const tenorMonths  = (meta.tenor_months   ?? 0) as number;
    const startDateStr = (meta.start_date     ?? null) as string | null;

    let remainingMonths = tenorMonths;
    if (startDateStr) {
      const start   = new Date(startDateStr);
      const elapsed = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24 * 30));
      remainingMonths = Math.max(0, tenorMonths - elapsed);
    }

    if (remainingMonths <= 0) continue;
    loanEmiMonthly += calcEmi(outstanding, annualRate, remainingMonths);
  }

  // Use the higher of: transaction-based EMI spend vs loan-account-based EMI.
  // If both exist, use loan-account EMI (more accurate for manually-added loans).
  // If only transactions exist (imported bank data), use that.
  const emiSpend = loanEmiMonthly > 0 ? loanEmiMonthly : txnEmiSpend;
  const emiRatio = monthlyIncome > 0 ? emiSpend / monthlyIncome : 0;

  const savingsRate = monthlyIncome > 0
    ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome)
    : 0;

  // 5. Top spending categories
  const catTotals: Record<string, number> = {};
  for (const t of debits) {
    const cat = t.category ?? 'others';
    catTotals[cat] = (catTotals[cat] ?? 0) + t.amount;
  }
  const topCategories = Object.entries(catTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([cat]) => cat);

  // 6. Biggest change vs last month
  const lastMonthStart = new Date();
  lastMonthStart.setMonth(lastMonthStart.getMonth() - 1);
  const prevMonthStart = new Date();
  prevMonthStart.setMonth(prevMonthStart.getMonth() - 2);

  const lastMonthSpend = (txns ?? [])
    .filter((t) => t.type === 'debit' && t.txn_date >= lastMonthStart.toISOString().split('T')[0])
    .reduce((s, t) => s + t.amount, 0);

  const prevMonthSpend = (txns ?? [])
    .filter(
      (t) =>
        t.type === 'debit' &&
        t.txn_date >= prevMonthStart.toISOString().split('T')[0] &&
        t.txn_date < lastMonthStart.toISOString().split('T')[0]
    )
    .reduce((s, t) => s + t.amount, 0);

  const spendDelta  = lastMonthSpend - prevMonthSpend;
  const spendChange = prevMonthSpend > 0 ? ((spendDelta / prevMonthSpend) * 100).toFixed(0) : '0';
  const biggestChange =
    spendDelta >= 0
      ? `Spending up ₹${Math.abs(spendDelta).toLocaleString('en-IN')} (${spendChange}%) vs prev month`
      : `Spending down ₹${Math.abs(spendDelta).toLocaleString('en-IN')} (${spendChange}%) vs prev month`;

  // 7. Get stored archetype
  const { data: user } = await supabaseAdmin
    .from('users')
    .select('financial_archetype')
    .eq('id', userId)
    .single();

  return {
    netWorth,
    monthlyIncome,
    monthlySpend,
    savingsRate,
    emiRatio,
    mfValue,
    mfXIRR: Math.round(mfXIRR * 100) / 100,
    creditUtil,
    topCategories,
    biggestChange,
    archetype: user?.financial_archetype ?? 'BALANCED_WEALTH_BUILDER',
    bankBalance,
    creditCardDebt,
    loanOutstanding,
  };
}

// ── Compute archetype ─────────────────────────────────────

export function computeArchetype(snapshot: FinancialSnapshot): ArchetypeCode {
  for (const archetype of ARCHETYPES) {
    if (archetype.test(snapshot)) return archetype.code;
  }
  return 'BALANCED_WEALTH_BUILDER';
}

/** Compute archetype for a user and persist it */
export async function computeAndStoreArchetype(userId: string): Promise<ArchetypeCode> {
  const snapshot  = await buildFinancialSnapshot(userId);
  const archetype = computeArchetype(snapshot);

  await supabaseAdmin
    .from('users')
    .update({ financial_archetype: archetype, last_active: new Date().toISOString() })
    .eq('id', userId);

  return archetype;
}

/** Recompute archetypes for ALL users (called by weekly cron) */
export async function recomputeAllArchetypes(): Promise<void> {
  const { data: users } = await supabaseAdmin
    .from('users')
    .select('id')
    .not('last_active', 'is', null);

  if (!users?.length) return;

  for (const user of users) {
    try {
      await computeAndStoreArchetype(user.id);
    } catch (err) {
      console.error(`[Archetype] Failed for user ${user.id}:`, err);
    }
  }
}

export { ARCHETYPES };
