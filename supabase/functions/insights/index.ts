import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

const ARCHETYPE_CONTEXT: Record<string, string> = {
  HIGH_INCOME_HIGH_EMI: "Focus on reducing EMI burden and optimising debt repayment order.",
  YOUNG_SAVER: "Encourage starting SIPs and index funds with clear first steps.",
  LIFESTYLE_INFLATED: "Highlight specific overspend categories with exact rupee amounts.",
  UNDERINVESTED: "Point out idle cash opportunity cost. Suggest specific MF categories.",
  CREDIT_STRESSED: "Address high credit utilization with a concrete paydown plan.",
  GOOD_INVESTOR: "Suggest portfolio rebalancing or next SIP increase milestone.",
  DEBT_FREE_SPENDER: "Nudge toward building an emergency fund and starting investments.",
  CONSERVATIVE_SAVER: "Gently challenge FD-only mindset with inflation-adjusted returns.",
  SIP_STARTER: "Celebrate progress, suggest next SIP step-up.",
  REAL_ESTATE_HEAVY: "Flag liquidity risk, suggest liquid fund buffer.",
  CASH_HOARDER: "Quantify the inflation erosion on idle savings.",
  EMI_JUGGLER: "Suggest a debt snowball or avalanche plan with exact numbers.",
  SUBSCRIPTIONS_HEAVY: "List top 3 subscriptions by cost and ask which adds real value.",
  FOOD_DELIVERY_ADDICT: "Show food delivery spend as % of income with benchmark.",
  TRAVEL_SPENDER: "Suggest travel budget and credit card reward optimisation.",
  INSURANCE_UNDERSERVED: "Flag under-insurance risk relative to income and loan.",
  HIGH_NET_WORTH: "Focus on asset allocation, tax optimisation, estate planning.",
  EMERGING_PROFESSIONAL: "Build wealth foundation — emergency fund, term insurance, SIP.",
  BUDGET_CONSCIOUS: "Celebrate discipline, suggest next wealth milestone.",
  BALANCED_WEALTH_BUILDER: "Highlight the single biggest lever to improve financial health.",
};

function getISOWeek(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil((((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

async function generateWeeklyInsight(userId: string) {
  const now = new Date();
  const weekNumber = getISOWeek(now);
  const year = now.getFullYear();
  const weekLabel = `Week ${weekNumber}, ${year}`;

  const { data: existing } = await supabaseAdmin
    .from("ai_insights").select("id, insight_text")
    .eq("user_id", userId).eq("week_number", weekNumber).eq("year", year).single();

  if (existing) return { text: existing.insight_text, generatedAt: now };

  // Build snapshot (inline to avoid cross-function import issues in Deno Deploy)
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const { data: accounts } = await supabaseAdmin.from("accounts").select("*").eq("user_id", userId).eq("is_active", true);
  const bankBalance = (accounts ?? []).filter((a: any) => ["savings", "current", "fd"].includes(a.account_type)).reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
  const creditCardDebt = (accounts ?? []).filter((a: any) => a.account_type === "credit_card").reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditCardLimit = (accounts ?? []).filter((a: any) => a.account_type === "credit_card").reduce((s: number, a: any) => s + (a.credit_limit ?? 0), 0);
  const loanOutstanding = (accounts ?? []).filter((a: any) => a.account_type === "loan").reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditUtil = creditCardLimit > 0 ? creditCardDebt / creditCardLimit : 0;

  const { data: mfHoldings } = await supabaseAdmin.from("mf_holdings").select("current_value, xirr").eq("user_id", userId);
  const mfValue = (mfHoldings ?? []).reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);
  const mfXIRR = mfHoldings?.length ? (mfHoldings.reduce((s: number, h: any) => s + (h.xirr ?? 0), 0) / mfHoldings.length) * 100 : 0;
  const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;

  const { data: txns } = await supabaseAdmin.from("transactions").select("amount, type, category, txn_date")
    .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0]);

  const credits = (txns ?? []).filter((t: any) => t.type === "credit");
  const debits = (txns ?? []).filter((t: any) => t.type === "debit");
  const monthlyIncome = credits.filter((t: any) => ["income", "salary", "others"].includes(t.category ?? "others")).reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = debits.reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const emiRatio = monthlyIncome > 0 ? (debits.filter((t: any) => t.category === "emi").reduce((s: number, t: any) => s + t.amount, 0) / 3) / monthlyIncome : 0;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;

  const catTotals: Record<string, number> = {};
  for (const t of debits) { catTotals[t.category ?? "others"] = (catTotals[t.category ?? "others"] ?? 0) + t.amount; }
  const topCategories = Object.entries(catTotals).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([cat]) => cat);

  const { data: userRow } = await supabaseAdmin.from("users").select("financial_archetype").eq("id", userId).single();
  const archetype = userRow?.financial_archetype ?? "BALANCED_WEALTH_BUILDER";

  const archetypeHint = ARCHETYPE_CONTEXT[archetype] ?? ARCHETYPE_CONTEXT.BALANCED_WEALTH_BUILDER;

  const systemPrompt = `You are a personal CFO for an Indian user — their trusted financial advisor who knows their actual numbers.

Your job: give ONE specific, actionable financial insight based on their real data this week.

Tone: Direct, warm, like a CA friend texting you — not a bank chatbot.
Language: Simple English, zero jargon. Never say "portfolio diversification" — say "spread your money across different types of funds".
Format: 3–4 sentences of insight, then exactly 2 action items as bullet points starting with "•".
Rules:
- Every sentence MUST reference their actual numbers (amounts, %, counts)
- Never give generic advice like "save more" — always say HOW MUCH MORE and WHERE
- Reference what changed vs last month
- If they're doing well in one area, acknowledge it in one sentence before the insight
- Keep total response under 280 words

Archetype context: ${archetypeHint}`;

  const spendPct = monthlyIncome > 0 ? ((monthlySpend / monthlyIncome) * 100).toFixed(0) : "0";
  const userPrompt = `Financial snapshot — ${weekLabel}:

Net worth: ${netWorth.toLocaleString("en-IN")}
Monthly income: ${monthlyIncome.toLocaleString("en-IN")}
Monthly spend: ${monthlySpend.toLocaleString("en-IN")} (${spendPct}% of income)
Top 3 spending categories: ${topCategories.join(", ")}
EMI burden: ${(emiRatio * 100).toFixed(0)}% of income
Savings rate: ${(savingsRate * 100).toFixed(0)}%
MF portfolio value: ${mfValue.toLocaleString("en-IN")} (XIRR: ${mfXIRR.toFixed(1)}%)
Credit utilization: ${(creditUtil * 100).toFixed(0)}%
Bank balance: ${bankBalance.toLocaleString("en-IN")}
Financial archetype: ${archetype}

Generate this week's insight.`;

  // Call AI via OpenRouter (DeepSeek V4 Flash — fast & free)
  const apiKey = Deno.env.get("OPENROUTER_KEY");
  if (!apiKey) throw new Error("OPENROUTER_KEY not set");

  const model = Deno.env.get("OPENROUTER_MODEL") ?? "deepseek/deepseek-v4-flash";
  const aiRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://zerotab.app",
      "X-Title": "ZeroTab AI Insights",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 350,
      temperature: 0.7,
    }),
  });

  const aiData = await aiRes.json();
  const insightText = aiData?.choices?.[0]?.message?.content?.trim() ?? "Unable to generate insight this week.";

  const actionLines = insightText.split("\n").filter((l: string) => l.trim().startsWith("•"));
  const actionItems = actionLines.map((l: string, i: number) => ({
    step: i + 1,
    text: l.replace(/^[•\-]\s*/, "").trim(),
  }));

  function classifyInsightType(): string {
    if (creditUtil > 0.60) return "debt_warning";
    if (emiRatio > 0.40) return "debt_warning";
    if (savingsRate < 0.10) return "savings_opportunity";
    if (mfValue < 10000 && bankBalance > 200000) return "investment_nudge";
    return "spend_alert";
  }

  await supabaseAdmin.from("ai_insights").insert({
    user_id: userId, week_number: weekNumber, year, archetype,
    insight_text: insightText, insight_type: classifyInsightType(),
    action_items: actionItems,
    data_snapshot: { netWorth, monthlyIncome, monthlySpend, savingsRate, emiRatio, mfValue, mfXIRR, creditUtil, topCategories, bankBalance, creditCardDebt, loanOutstanding, archetype },
    generated_at: now.toISOString(),
  });

  return { text: insightText, generatedAt: now };
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/insights\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // GET /insights
  if (method === "GET" && pathParts.length === 0) {
    const { data, error } = await supabaseAdmin
      .from("ai_insights").select("*").eq("user_id", user.id)
      .order("generated_at", { ascending: false }).limit(10);
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // GET /insights/latest
  if (method === "GET" && pathParts[0] === "latest") {
    const { data, error } = await supabaseAdmin
      .from("ai_insights").select("*").eq("user_id", user.id)
      .order("generated_at", { ascending: false }).limit(1).single();
    if (error) return errorResponse("No insight found", 404);
    return jsonResponse(data);
  }

  // POST /insights/generate
  if (method === "POST" && pathParts[0] === "generate") {
    try {
      const result = await generateWeeklyInsight(user.id);
      return jsonResponse(result);
    } catch (err: any) {
      return errorResponse(err.message ?? "Insight generation failed");
    }
  }

  return errorResponse("Not found", 404);
});

export { generateWeeklyInsight };
