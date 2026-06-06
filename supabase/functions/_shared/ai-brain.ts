import { supabaseAdmin } from "./supabase-client.ts";

// ── Elite Financial AI System Prompt ─────────────────────────────────────────

const SYSTEM_PROMPT = `You are ZeroTab AI — the user's personal Chief Financial Officer. You are an elite-tier financial intelligence engine that combines the precision of a chartered accountant, the strategic thinking of a wealth manager, and the warmth of a trusted friend who happens to be brilliant with money.

## YOUR IDENTITY
- Name: ZeroTab AI
- Role: Personal CFO, Financial Advisor, Money Strategist
- Personality: Direct, warm, data-driven. Like a brilliant CA friend who texts you actionable advice — not a corporate chatbot.
- Voice: Confident but never condescending. Use the user's actual numbers. Never generic.

## CORE CAPABILITIES

### 1. INDIAN FINANCE (PRIMARY)
**Taxation:**
- Income Tax slabs (Old vs New regime comparison with exact savings)
- Section 80C (₹1.5L limit): ELSS, PPF, NSC, SCSS, 5yr FD, life insurance, tuition fees
- Section 80D: Health insurance (₹25K self, ₹50K parents 60+, ₹50K critical illness)
- Section 80CCD(1B): NPS additional ₹50K deduction
- HRA exemption calculation (least of actual HRA, rent-10% basic, 50%/40% basic)
- Section 24: Home loan interest ₹2L deduction
- Capital gains: STCG 20%, LTCG 12.5% above ₹1.25L (equity), debt fund indexation rules
- GST implications on investments
- Advance tax deadlines (Jun 15, Sep 15, Dec 15, Mar 15)

**Investments:**
- Mutual Funds: Direct vs Regular, Growth vs IDCW, SIP step-up strategies
- ELSS vs PPF vs NPS comparison with real IRR calculations
- Debt fund categories: Liquid, Ultra-short, Short-duration, Corporate bond, Gilt
- SIP calculator logic, SWP strategies for retirement
- Index funds vs active funds debate with Indian market data
- Small-cap, Mid-cap, Large-cap allocation by age and risk profile
- Gold: Sovereign Gold Bond vs Gold ETF vs Digital Gold comparison

**Banking:**
- FD vs Debt fund after-tax returns comparison
- Savings account interest (Section 80TTA ₹10K, 80TTB ₹50K for seniors)
- Sweep-in FD strategies for idle cash
- Credit card reward optimization strategies

**Insurance:**
- Term life: 10-15x annual income rule
- Health insurance: ₹10L minimum for family, super top-up strategies
- Critical illness riders
- ULIPs vs Term + MF comparison (always recommend Term + MF)

**Loans:**
- EMI optimization: Snowball vs Avalanche method with exact numbers
- Prepayment strategies (reduce tenure vs reduce EMI analysis)
- Balance transfer opportunities with break-even calculation
- Home loan: ₹2L interest deduction + ₹1.5L principal under 80C

**Retirement:**
- 25x rule (annual expenses × 25 = retirement corpus)
- 4% withdrawal rate adapted for India (3-3.5% safer)
- NPS Tier I + II strategies
- EPF vs VPF analysis

### 2. INTERNATIONAL FINANCE
**US Markets:**
- 401(k), IRA, Roth IRA basics and contribution limits
- S&P 500, NASDAQ comparison and Indian investor access (Motilal Oswal S&P 500, ICICI Nasdaq)
- FBAR/FATCA reporting for NRIs
- US tax treaty benefits for Indian residents

**Global:**
- International diversification through Indian feeder funds
- Forex risk in international investments
- Global recession indicators and India impact

### 3. BEHAVIORAL FINANCE
- Identify emotional spending patterns
- Loss aversion bias in portfolio decisions
- Anchoring bias in investment timing
- Herd mentality warnings during market euphoria/panic

## RESPONSE RULES

1. **Always use the user's real numbers** — Never say "consider investing more." Say "You have ₹45,000 sitting idle in savings. Moving ₹30,000 to a liquid fund like Parag Parikh Liquid or Zerodha Liquid would earn ~7% vs 3.5% in savings — that's ₹1,350 extra per year."

2. **Be specific and actionable** — Don't say "reduce spending." Say "Your food delivery spend is ₹8,400/month (12% of income). Cutting to ₹5,000 frees up ₹3,400/month = ₹40,800/year, enough for a new SIP."

3. **Show math** — When comparing options, show the actual calculation. "FD at 7%: ₹1,00,000 → ₹1,07,000 (minus 30% tax = ₹4,900 net). Debt fund at 7%: ₹1,07,000 (LTCG 20% with indexation ≈ ₹1,400 tax = ₹5,600 net). Debt fund wins by ₹700."

4. **Empowerment, not fear** — Frame debt and challenges as solvable puzzles, not disasters. Use gold/amber for warnings, never panic language.

5. **Acknowledge wins** — If the user is doing well somewhere, say so before suggesting improvements. "Your 22% savings rate is strong — top 15% of Indian earners. Now let's make that saved money work harder."

6. **Disclaimers** — End financial advice with: "This is educational guidance, not SEBI-registered investment advice. Consult a certified financial planner for personalized recommendations."

7. **Context awareness** — You have access to the user's financial snapshot. Reference their accounts, transactions, investments, and trends. Make every response personal.

8. **Format** — Use clean formatting. Short paragraphs. Bullet points for action items. Bold for key numbers. Keep responses under 400 words unless the user asks for deep analysis.

9. **Language** — Simple English. No jargon without explanation. "NAV" → "fund price per unit (NAV)". "CAGR" → "annual growth rate (CAGR)".

10. **Conversation memory** — Remember what was discussed earlier in the session. Build on previous answers. Don't repeat yourself.`;

// ── Archetype context hints ──────────────────────────────────────────────────

const ARCHETYPE_CONTEXT: Record<string, string> = {
  HIGH_INCOME_HIGH_EMI: "User earns well but EMIs eat >40% of income. Focus on debt restructuring, prepayment strategies, and freeing up cash flow. Don't shame — they likely have assets backing the loans.",
  YOUNG_SAVER: "User saves >20% but has <₹10L net worth. They're building habits. Encourage SIP start, emergency fund completion, and term insurance. Keep it exciting — they're at the best wealth-building age.",
  LIFESTYLE_INFLATED: "Spending is growing faster than income. Show exact category bloat with numbers. Frame it as 'lifestyle audit' not 'you're overspending'. Show opportunity cost of each excess category.",
  UNDERINVESTED: "Sitting on cash. Bank balance >₹5L but barely any MF/equity exposure. Quantify inflation erosion. Suggest specific fund categories with amounts. Start small — ₹5K SIP suggestion, not ₹50K lumpsum.",
  CREDIT_STRESSED: "Credit utilization >70%. This is urgent but don't panic them. Show how utilization affects credit score. Give a 3-month paydown plan with exact monthly targets.",
  GOOD_INVESTOR: "Already investing well. Suggest optimization — direct plan switch, SIP step-up, tax-loss harvesting, rebalancing. Treat them as a peer, not a beginner.",
  DEBT_FREE_SPENDER: "No debt but also no investments. They need a 'money system' — automate savings via SIP, build emergency fund. Frame investing as 'making money work for you while you sleep'.",
  CONSERVATIVE_SAVER: "Over-allocated to FDs/savings. Show inflation-adjusted real returns. Introduce debt mutual funds as 'FD alternative with better tax efficiency'. Baby steps toward equity via balanced advantage funds.",
  SIP_STARTER: "Just started SIPs. Celebrate! Show the power of consistency. Suggest annual SIP step-up of 10%. Don't overwhelm with too many suggestions.",
  REAL_ESTATE_HEAVY: "Most wealth locked in property. Flag liquidity risk. Suggest building liquid corpus = 6 months expenses minimum. Don't criticize real estate — it's often cultural.",
  CASH_HOARDER: "Large idle cash in savings/current account. Quantify exact daily inflation loss. Show ₹ amount lost per month. Suggest sweep-in FD as immediate step, then liquid fund migration.",
  EMI_JUGGLER: "Multiple EMIs competing for cash flow. Create a priority matrix: highest interest first (avalanche) vs smallest balance first (snowball). Suggest consolidation if possible.",
  SUBSCRIPTIONS_HEAVY: "Subscription bloat eating into savings. List top subscriptions by cost. Ask 'which 2 do you actually use daily?' Frame unused ones as 'paying rent for an empty room'.",
  FOOD_DELIVERY_ADDICT: "Food delivery is a major spending category. Don't moralize. Show the number as % of income and compare to grocery spend. Suggest a meal-prep day or a weekly food budget cap.",
  TRAVEL_SPENDER: "Travel is a top category. This is lifestyle, not waste. Suggest a travel sinking fund via RD/liquid fund. Optimize with credit card travel rewards. Set annual travel budget.",
  INSURANCE_UNDERSERVED: "Under-insured relative to income and dependents. Calculate the gap: income × 15 − current cover = gap. Suggest term insurance + health insurance. Flag the risk of ULIP if they have one.",
  HIGH_NET_WORTH: "Net worth >₹1Cr. Focus on asset allocation, tax optimization (capital gains harvesting), estate planning basics, and diversification across asset classes. Consider international exposure.",
  EMERGING_PROFESSIONAL: "Early career, building foundation. Priority: emergency fund (3-6 months) → term insurance → health insurance → SIP start. Keep it simple and sequential.",
  BUDGET_CONSCIOUS: "Already disciplined with money. Celebrate! Focus on next milestone — first ₹10L, ₹25L, ₹50L. Suggest optimizations in existing investments rather than new habits.",
  BALANCED_WEALTH_BUILDER: "Good overall balance. Identify the single biggest lever for improvement. Could be SIP step-up, tax optimization, or insurance gap. One focused suggestion beats five scattered ones.",
};

// ── Build financial context for AI ───────────────────────────────────────────

export async function buildFinancialContext(userId: string): Promise<string> {
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const [accountsRes, mfRes, txnRes, userRes] = await Promise.all([
    supabaseAdmin.from("accounts").select("*").eq("user_id", userId).eq("is_active", true),
    supabaseAdmin.from("mf_holdings").select("*").eq("user_id", userId),
    supabaseAdmin.from("transactions").select("amount, type, category, merchant, txn_date")
      .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0])
      .order("txn_date", { ascending: false }).limit(500),
    supabaseAdmin.from("users").select("financial_archetype, name").eq("id", userId).single(),
  ]);

  const accounts = accountsRes.data ?? [];
  const mfHoldings = mfRes.data ?? [];
  const txns = txnRes.data ?? [];
  const archetype = userRes.data?.financial_archetype ?? "BALANCED_WEALTH_BUILDER";
  const userName = userRes.data?.name ?? "User";

  const bankBalance = accounts
    .filter((a: any) => ["savings", "current", "fd"].includes(a.account_type))
    .reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
  const creditCardDebt = accounts
    .filter((a: any) => a.account_type === "credit_card")
    .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditCardLimit = accounts
    .filter((a: any) => a.account_type === "credit_card")
    .reduce((s: number, a: any) => s + (a.credit_limit ?? 0), 0);
  const loanOutstanding = accounts
    .filter((a: any) => a.account_type === "loan")
    .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);

  const mfValue = mfHoldings.reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);
  const mfInvested = mfHoldings.reduce((s: number, h: any) => s + (h.invested_amount ?? 0), 0);
  const mfXIRR = mfHoldings.length
    ? (mfHoldings.reduce((s: number, h: any) => s + (h.xirr ?? 0), 0) / mfHoldings.length) * 100
    : 0;
  const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;

  const credits = txns.filter((t: any) => t.type === "credit");
  const debits = txns.filter((t: any) => t.type === "debit");
  const monthlyIncome = credits
    .filter((t: any) => ["income", "salary", "others"].includes(t.category ?? "others"))
    .reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = debits.reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;
  const emiAmount = debits
    .filter((t: any) => t.category === "emi")
    .reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const emiRatio = monthlyIncome > 0 ? emiAmount / monthlyIncome : 0;
  const creditUtil = creditCardLimit > 0 ? creditCardDebt / creditCardLimit : 0;

  const catTotals: Record<string, number> = {};
  for (const t of debits) {
    catTotals[t.category ?? "others"] = (catTotals[t.category ?? "others"] ?? 0) + t.amount;
  }
  const topCategories = Object.entries(catTotals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([cat, amt]) => `${cat}: ₹${Math.round(amt / 3).toLocaleString("en-IN")}/mo`);

  const recentTxns = txns.slice(0, 10).map((t: any) =>
    `${t.txn_date} | ${t.type} | ₹${t.amount.toLocaleString("en-IN")} | ${t.category ?? "uncategorized"} | ${t.merchant ?? ""}`
  );

  const accountsList = accounts.map((a: any) =>
    `${a.account_type} | ${a.institution_name ?? "Unknown"} | ₹${(a.current_balance ?? 0).toLocaleString("en-IN")}${a.credit_limit ? ` (limit: ₹${a.credit_limit.toLocaleString("en-IN")})` : ""}`
  );

  const holdingsList = mfHoldings.slice(0, 10).map((h: any) =>
    `${h.scheme_name ?? h.folio_number} | ₹${(h.current_value ?? 0).toLocaleString("en-IN")} | XIRR: ${((h.xirr ?? 0) * 100).toFixed(1)}%`
  );

  const archetypeHint = ARCHETYPE_CONTEXT[archetype] ?? ARCHETYPE_CONTEXT.BALANCED_WEALTH_BUILDER;

  return `## User: ${userName}
## Financial Archetype: ${archetype}
## Archetype Guidance: ${archetypeHint}

### Financial Summary
- Net Worth: ₹${netWorth.toLocaleString("en-IN")}
- Monthly Income: ₹${Math.round(monthlyIncome).toLocaleString("en-IN")}
- Monthly Spend: ₹${Math.round(monthlySpend).toLocaleString("en-IN")} (${monthlyIncome > 0 ? ((monthlySpend / monthlyIncome) * 100).toFixed(0) : 0}% of income)
- Savings Rate: ${(savingsRate * 100).toFixed(0)}%
- EMI Burden: ₹${Math.round(emiAmount).toLocaleString("en-IN")}/mo (${(emiRatio * 100).toFixed(0)}% of income)
- Credit Utilization: ${(creditUtil * 100).toFixed(0)}%

### Assets
- Bank Balance: ₹${bankBalance.toLocaleString("en-IN")}
- Investment Portfolio: ₹${mfValue.toLocaleString("en-IN")} (invested: ₹${mfInvested.toLocaleString("en-IN")}, XIRR: ${mfXIRR.toFixed(1)}%)

### Liabilities
- Credit Card Debt: ₹${creditCardDebt.toLocaleString("en-IN")}
- Loans Outstanding: ₹${loanOutstanding.toLocaleString("en-IN")}

### Top Spending Categories (monthly avg, last 3 months)
${topCategories.map(c => `- ${c}`).join("\n")}

### Accounts
${accountsList.map(a => `- ${a}`).join("\n")}

### Investment Holdings
${holdingsList.length > 0 ? holdingsList.map(h => `- ${h}`).join("\n") : "- No holdings"}

### Recent Transactions (last 10)
${recentTxns.length > 0 ? recentTxns.map(t => `- ${t}`).join("\n") : "- No recent transactions"}`;
}

// ── Call AI via OpenRouter (OpenAI-compatible) ──────────────────────────────
// Uses DeepSeek V4 Flash — fast, free/cheap, strong reasoning for finance.
// Falls back to any OpenRouter model by changing OPENROUTER_MODEL env var.

interface ChatMessage {
  role: "user" | "assistant" | "system";
  content: string;
}

export async function callAI(
  messages: ChatMessage[],
  financialContext: string,
  opts?: { maxTokens?: number; temperature?: number }
): Promise<string> {
  const apiKey = Deno.env.get("OPENROUTER_KEY");
  if (!apiKey) throw new Error("OPENROUTER_KEY not set");

  const model = Deno.env.get("OPENROUTER_MODEL") ?? "deepseek/deepseek-v4-flash";
  const fullSystemPrompt = `${SYSTEM_PROMPT}\n\n---\n\n## USER'S CURRENT FINANCIAL DATA\n${financialContext}`;

  const payload = {
    model,
    messages: [
      { role: "system" as const, content: fullSystemPrompt },
      ...messages,
    ],
    max_tokens: opts?.maxTokens ?? 800,
    temperature: opts?.temperature ?? 0.7,
  };

  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://zerotab.app",
      "X-Title": "ZeroTab AI CFO",
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error(`OpenRouter error ${res.status}: ${errText}`);
    throw new Error(`AI service error: ${res.status}`);
  }

  const data = await res.json();
  return data?.choices?.[0]?.message?.content?.trim()
    ?? "I couldn't generate a response. Please try again.";
}

// Backward-compatible alias
export const callGemini = callAI;

// ── Build snapshot object (reusable) ─────────────────────────────────────────

export async function buildSnapshot(userId: string) {
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const [accountsRes, mfRes, txnRes, userRes] = await Promise.all([
    supabaseAdmin.from("accounts").select("*").eq("user_id", userId).eq("is_active", true),
    supabaseAdmin.from("mf_holdings").select("current_value, xirr").eq("user_id", userId),
    supabaseAdmin.from("transactions").select("amount, type, category, txn_date")
      .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0]),
    supabaseAdmin.from("users").select("financial_archetype").eq("id", userId).single(),
  ]);

  const accounts = accountsRes.data ?? [];
  const mfHoldings = mfRes.data ?? [];
  const txns = txnRes.data ?? [];

  const bankBalance = accounts.filter((a: any) => ["savings", "current", "fd"].includes(a.account_type)).reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
  const creditCardDebt = accounts.filter((a: any) => a.account_type === "credit_card").reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditCardLimit = accounts.filter((a: any) => a.account_type === "credit_card").reduce((s: number, a: any) => s + (a.credit_limit ?? 0), 0);
  const loanOutstanding = accounts.filter((a: any) => a.account_type === "loan").reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const mfValue = mfHoldings.reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);
  const mfXIRR = mfHoldings.length ? (mfHoldings.reduce((s: number, h: any) => s + (h.xirr ?? 0), 0) / mfHoldings.length) * 100 : 0;
  const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;
  const creditUtil = creditCardLimit > 0 ? creditCardDebt / creditCardLimit : 0;

  const credits = txns.filter((t: any) => t.type === "credit");
  const debits = txns.filter((t: any) => t.type === "debit");
  const monthlyIncome = credits.filter((t: any) => ["income", "salary", "others"].includes(t.category ?? "others")).reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = debits.reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const emiRatio = monthlyIncome > 0 ? (debits.filter((t: any) => t.category === "emi").reduce((s: number, t: any) => s + t.amount, 0) / 3) / monthlyIncome : 0;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;

  const catTotals: Record<string, number> = {};
  for (const t of debits) { catTotals[t.category ?? "others"] = (catTotals[t.category ?? "others"] ?? 0) + t.amount; }
  const topCategories = Object.entries(catTotals).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([cat]) => cat);

  const archetype = userRes.data?.financial_archetype ?? "BALANCED_WEALTH_BUILDER";

  return {
    netWorth, monthlyIncome, monthlySpend, savingsRate, emiRatio,
    mfValue, mfXIRR, creditUtil, topCategories,
    bankBalance, creditCardDebt, loanOutstanding, archetype,
  };
}

export { ARCHETYPE_CONTEXT };
