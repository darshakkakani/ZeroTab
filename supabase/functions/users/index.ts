import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

async function buildFinancialSnapshot(userId: string) {
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const { data: accounts } = await supabaseAdmin
    .from("accounts").select("*").eq("user_id", userId).eq("is_active", true);

  const bankBalance = (accounts ?? [])
    .filter((a: any) => ["savings", "current", "fd"].includes(a.account_type))
    .reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
  const creditCardDebt = (accounts ?? [])
    .filter((a: any) => a.account_type === "credit_card")
    .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditCardLimit = (accounts ?? [])
    .filter((a: any) => a.account_type === "credit_card")
    .reduce((s: number, a: any) => s + (a.credit_limit ?? 0), 0);
  const loanOutstanding = (accounts ?? [])
    .filter((a: any) => a.account_type === "loan")
    .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
  const creditUtil = creditCardLimit > 0 ? creditCardDebt / creditCardLimit : 0;

  const { data: mfHoldings } = await supabaseAdmin
    .from("mf_holdings").select("current_value, xirr").eq("user_id", userId);
  const mfValue = (mfHoldings ?? []).reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);
  const mfXIRR = mfHoldings?.length
    ? (mfHoldings.reduce((s: number, h: any) => s + (h.xirr ?? 0), 0) / mfHoldings.length) * 100
    : 0;

  const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;

  const { data: txns } = await supabaseAdmin
    .from("transactions").select("amount, type, category, txn_date")
    .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0]);

  const credits = (txns ?? []).filter((t: any) => t.type === "credit");
  const debits = (txns ?? []).filter((t: any) => t.type === "debit");

  const monthlyIncome = credits
    .filter((t: any) => ["income", "salary", "others"].includes(t.category ?? "others"))
    .reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = debits.reduce((s: number, t: any) => s + t.amount, 0) / 3;

  const txnEmiSpend = debits
    .filter((t: any) => t.category === "emi")
    .reduce((s: number, t: any) => s + t.amount, 0) / 3;

  function calcEmi(principal: number, annualRate: number, months: number): number {
    if (months <= 0 || principal <= 0) return 0;
    if (annualRate <= 0) return principal / months;
    const r = annualRate / 12 / 100;
    return principal * r * Math.pow(1 + r, months) / (Math.pow(1 + r, months) - 1);
  }

  const loanAccounts = (accounts ?? []).filter((a: any) => a.account_type === "loan");
  let loanEmiMonthly = 0;
  const now = new Date();
  for (const loan of loanAccounts) {
    const outstanding = Math.abs(loan.current_balance ?? 0);
    if (outstanding <= 0) continue;
    const meta = (loan.metadata as any) ?? {};
    const annualRate = (meta.interest_rate ?? 0) as number;
    const tenorMonths = (meta.tenor_months ?? 0) as number;
    const startDateStr = (meta.start_date ?? null) as string | null;
    let remainingMonths = tenorMonths;
    if (startDateStr) {
      const start = new Date(startDateStr);
      const elapsed = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24 * 30));
      remainingMonths = Math.max(0, tenorMonths - elapsed);
    }
    if (remainingMonths <= 0) continue;
    loanEmiMonthly += calcEmi(outstanding, annualRate, remainingMonths);
  }

  const emiSpend = loanEmiMonthly > 0 ? loanEmiMonthly : txnEmiSpend;
  const emiRatio = monthlyIncome > 0 ? emiSpend / monthlyIncome : 0;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;

  const catTotals: Record<string, number> = {};
  for (const t of debits) {
    const cat = t.category ?? "others";
    catTotals[cat] = (catTotals[cat] ?? 0) + t.amount;
  }
  const topCategories = Object.entries(catTotals)
    .sort((a, b) => b[1] - a[1]).slice(0, 5).map(([cat]) => cat);

  const lastMonthStart = new Date();
  lastMonthStart.setMonth(lastMonthStart.getMonth() - 1);
  const prevMonthStart = new Date();
  prevMonthStart.setMonth(prevMonthStart.getMonth() - 2);

  const lastMonthSpend = (txns ?? [])
    .filter((t: any) => t.type === "debit" && t.txn_date >= lastMonthStart.toISOString().split("T")[0])
    .reduce((s: number, t: any) => s + t.amount, 0);
  const prevMonthSpend = (txns ?? [])
    .filter((t: any) => t.type === "debit" &&
      t.txn_date >= prevMonthStart.toISOString().split("T")[0] &&
      t.txn_date < lastMonthStart.toISOString().split("T")[0])
    .reduce((s: number, t: any) => s + t.amount, 0);

  const spendDelta = lastMonthSpend - prevMonthSpend;
  const spendChange = prevMonthSpend > 0 ? ((spendDelta / prevMonthSpend) * 100).toFixed(0) : "0";
  const biggestChange = spendDelta >= 0
    ? `Spending up ${Math.abs(spendDelta).toLocaleString("en-IN")} (${spendChange}%) vs prev month`
    : `Spending down ${Math.abs(spendDelta).toLocaleString("en-IN")} (${spendChange}%) vs prev month`;

  const { data: userRow } = await supabaseAdmin
    .from("users").select("financial_archetype").eq("id", userId).single();

  return {
    netWorth, monthlyIncome, monthlySpend, savingsRate, emiRatio,
    mfValue, mfXIRR: Math.round(mfXIRR * 100) / 100, creditUtil,
    topCategories, biggestChange,
    archetype: userRow?.financial_archetype ?? "BALANCED_WEALTH_BUILDER",
    bankBalance, creditCardDebt, loanOutstanding,
  };
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/users\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // GET /users/me
  if (method === "GET" && pathParts[0] === "me" && pathParts.length === 1) {
    const { data, error } = await supabaseAdmin
      .from("users").select("*").eq("id", user.id).single();
    if (error) return errorResponse("User not found", 404);
    return jsonResponse(data);
  }

  // GET /users/me/snapshot
  if (method === "GET" && pathParts[0] === "me" && pathParts[1] === "snapshot") {
    const snapshot = await buildFinancialSnapshot(user.id);
    return jsonResponse(snapshot);
  }

  // PUT /users/me
  if (method === "PUT" && pathParts[0] === "me" && pathParts.length === 1) {
    const { name } = await req.json();
    const { data, error } = await supabaseAdmin
      .from("users").update({ name, last_active: new Date().toISOString() })
      .eq("id", user.id).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // POST /users/me/register
  if (method === "POST" && pathParts[0] === "me" && pathParts[1] === "register") {
    const { phone, name } = await req.json();
    const upsertPayload: Record<string, unknown> = {
      id: user.id, phone: phone || user.phone || "", last_active: new Date().toISOString(),
    };
    if (name) upsertPayload.name = name;
    const { data, error } = await supabaseAdmin
      .from("users").upsert(upsertPayload, { onConflict: "id" }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // DELETE /users/me — GDPR delete
  if (method === "DELETE" && pathParts[0] === "me") {
    await supabaseAdmin.from("users").delete().eq("id", user.id);
    await supabaseAdmin.auth.admin.deleteUser(user.id);
    return jsonResponse({ ok: true });
  }

  // POST /users/me/fcm-token
  if (method === "POST" && pathParts[0] === "me" && pathParts[1] === "fcm-token") {
    const { token } = await req.json();
    await supabaseAdmin
      .from("users").update({ metadata: { fcm_token: token } } as any)
      .eq("id", user.id);
    return jsonResponse({ ok: true });
  }

  return errorResponse("Not found", 404);
});

export { buildFinancialSnapshot };
