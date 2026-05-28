import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { jsonResponse, errorResponse } from "../_shared/cors.ts";

interface FinancialSnapshot {
  monthlyIncome: number;
  monthlySpend: number;
  savingsRate: number;
  emiRatio: number;
  netWorth: number;
  mfValue: number;
  mfXIRR: number;
  creditUtil: number;
  bankBalance: number;
  topCategories: string[];
  loanOutstanding: number;
}

type ArchetypeCode = string;

const ARCHETYPES: { code: ArchetypeCode; test: (s: FinancialSnapshot) => boolean }[] = [
  { code: "HIGH_INCOME_HIGH_EMI", test: (s) => s.monthlyIncome > 100000 && s.emiRatio > 0.40 },
  { code: "YOUNG_SAVER", test: (s) => s.savingsRate > 0.20 && s.netWorth < 1000000 },
  { code: "LIFESTYLE_INFLATED", test: (s) => s.monthlySpend * 0.6 > 0.40 * s.monthlyIncome },
  { code: "UNDERINVESTED", test: (s) => s.bankBalance > 500000 && s.mfValue < 0.10 * s.bankBalance },
  { code: "CREDIT_STRESSED", test: (s) => s.creditUtil > 0.70 },
  { code: "GOOD_INVESTOR", test: (s) => s.mfValue > 0 && s.savingsRate > 0.15 && s.mfXIRR > 0 },
  { code: "DEBT_FREE_SPENDER", test: (s) => s.emiRatio < 0.05 && s.creditUtil < 0.20 && s.savingsRate < 0.10 },
  { code: "CONSERVATIVE_SAVER", test: (s) => s.bankBalance > 200000 && s.mfValue === 0 && s.savingsRate > 0.15 },
  { code: "SIP_STARTER", test: (s) => s.mfValue > 0 && s.mfValue < 100000 && s.savingsRate > 0.10 },
  { code: "REAL_ESTATE_HEAVY", test: (s) => s.emiRatio > 0.30 && s.emiRatio < 0.50 && s.bankBalance < 100000 },
  { code: "CASH_HOARDER", test: (s) => s.bankBalance > 1000000 && s.mfValue < 0.05 * s.bankBalance },
  { code: "EMI_JUGGLER", test: (s) => s.emiRatio > 0.50 },
  { code: "SUBSCRIPTIONS_HEAVY", test: (s) => s.topCategories.includes("subscriptions") && s.savingsRate < 0.15 },
  { code: "FOOD_DELIVERY_ADDICT", test: (s) => s.topCategories[0] === "food_delivery" && s.savingsRate < 0.20 },
  { code: "HIGH_NET_WORTH", test: (s) => s.netWorth > 10000000 },
  { code: "EMERGING_PROFESSIONAL", test: (s) => s.monthlyIncome > 50000 && s.monthlyIncome < 100000 && s.netWorth < 500000 && s.savingsRate > 0.10 },
  { code: "BUDGET_CONSCIOUS", test: (s) => s.savingsRate > 0.25 && s.monthlySpend < 0.60 * s.monthlyIncome },
  { code: "BALANCED_WEALTH_BUILDER", test: () => true },
];

async function computeArchetypeForUser(userId: string) {
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

  const { data: txns } = await supabaseAdmin.from("transactions").select("amount, type, category")
    .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0]);
  const credits = (txns ?? []).filter((t: any) => t.type === "credit");
  const debits = (txns ?? []).filter((t: any) => t.type === "debit");
  const monthlyIncome = credits.filter((t: any) => ["income", "salary", "others"].includes(t.category ?? "others")).reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = debits.reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const emiRatio = monthlyIncome > 0 ? (debits.filter((t: any) => t.category === "emi").reduce((s: number, t: any) => s + t.amount, 0) / 3) / monthlyIncome : 0;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;

  const catTotals: Record<string, number> = {};
  for (const t of debits) { catTotals[t.category ?? "others"] = (catTotals[t.category ?? "others"] ?? 0) + t.amount; }
  const topCategories = Object.entries(catTotals).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([cat]) => cat);

  const snapshot: FinancialSnapshot = { monthlyIncome, monthlySpend, savingsRate, emiRatio, netWorth, mfValue, mfXIRR, creditUtil, bankBalance, topCategories, loanOutstanding };

  let archetype = "BALANCED_WEALTH_BUILDER";
  for (const a of ARCHETYPES) { if (a.test(snapshot)) { archetype = a.code; break; } }

  await supabaseAdmin.from("users").update({ financial_archetype: archetype, last_active: new Date().toISOString() }).eq("id", userId);
  return archetype;
}

serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  const serviceKey = Deno.env.get("CRON_SECRET") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (authHeader !== `Bearer ${serviceKey}`) return errorResponse("Unauthorized", 401);

  console.log("[Archetype Cron] Recomputing archetypes...");
  const { data: users } = await supabaseAdmin.from("users").select("id").not("last_active", "is", null);

  let computed = 0;
  for (const u of users ?? []) {
    try { await computeArchetypeForUser(u.id); computed++; } catch (e) { console.error(`Failed for ${u.id}:`, e); }
  }

  console.log(`[Archetype Cron] Computed for ${computed} users`);
  return jsonResponse({ ok: true, computed });
});
