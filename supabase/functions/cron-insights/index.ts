import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { jsonResponse, errorResponse } from "../_shared/cors.ts";

function getISOWeek(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil((((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

const ARCHETYPE_CONTEXT: Record<string, string> = {
  HIGH_INCOME_HIGH_EMI: "Focus on reducing EMI burden.",
  YOUNG_SAVER: "Encourage starting SIPs.",
  LIFESTYLE_INFLATED: "Highlight overspend categories.",
  UNDERINVESTED: "Point out idle cash opportunity cost.",
  CREDIT_STRESSED: "Address high credit utilization.",
  GOOD_INVESTOR: "Suggest portfolio rebalancing.",
  BALANCED_WEALTH_BUILDER: "Highlight the single biggest lever to improve financial health.",
};

async function generateInsightForUser(userId: string) {
  const now = new Date();
  const weekNumber = getISOWeek(now);
  const year = now.getFullYear();

  const { data: existing } = await supabaseAdmin.from("ai_insights").select("id")
    .eq("user_id", userId).eq("week_number", weekNumber).eq("year", year).maybeSingle();
  if (existing) return;

  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const { data: accounts } = await supabaseAdmin.from("accounts").select("*").eq("user_id", userId).eq("is_active", true);
  const bankBalance = (accounts ?? []).filter((a: any) => ["savings", "current", "fd"].includes(a.account_type)).reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
  const { data: mfHoldings } = await supabaseAdmin.from("mf_holdings").select("current_value").eq("user_id", userId);
  const mfValue = (mfHoldings ?? []).reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);

  const { data: txns } = await supabaseAdmin.from("transactions").select("amount, type, category")
    .eq("user_id", userId).gte("txn_date", threeMonthsAgo.toISOString().split("T")[0]);
  const monthlyIncome = (txns ?? []).filter((t: any) => t.type === "credit").reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const monthlySpend = (txns ?? []).filter((t: any) => t.type === "debit").reduce((s: number, t: any) => s + t.amount, 0) / 3;
  const savingsRate = monthlyIncome > 0 ? Math.max(0, (monthlyIncome - monthlySpend) / monthlyIncome) : 0;

  const { data: userRow } = await supabaseAdmin.from("users").select("financial_archetype").eq("id", userId).single();
  const archetype = userRow?.financial_archetype ?? "BALANCED_WEALTH_BUILDER";
  const archetypeHint = ARCHETYPE_CONTEXT[archetype] ?? ARCHETYPE_CONTEXT.BALANCED_WEALTH_BUILDER;

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) { console.error("GEMINI_API_KEY not set"); return; }

  const geminiRes = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: `You are a personal CFO for an Indian user. Give ONE specific financial insight. Format: 3-4 sentences + 2 action items with "•". Use their real numbers. Under 280 words. ${archetypeHint}` }] },
        contents: [{ parts: [{ text: `Net worth: ${(bankBalance + mfValue).toLocaleString("en-IN")}, Monthly income: ${monthlyIncome.toLocaleString("en-IN")}, Monthly spend: ${monthlySpend.toLocaleString("en-IN")}, Savings rate: ${(savingsRate * 100).toFixed(0)}%, MF value: ${mfValue.toLocaleString("en-IN")}, Bank balance: ${bankBalance.toLocaleString("en-IN")}. Generate insight.` }] }],
        generationConfig: { maxOutputTokens: 350, temperature: 0.7 },
      }),
    }
  );
  const geminiData = await geminiRes.json();
  const insightText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "Unable to generate insight.";

  const actionLines = insightText.split("\n").filter((l: string) => l.trim().startsWith("•"));
  const actionItems = actionLines.map((l: string, i: number) => ({ step: i + 1, text: l.replace(/^[•\-]\s*/, "").trim() }));

  await supabaseAdmin.from("ai_insights").insert({
    user_id: userId, week_number: weekNumber, year, archetype,
    insight_text: insightText, insight_type: "spend_alert",
    action_items: actionItems, generated_at: now.toISOString(),
  });
}

serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  const serviceKey = Deno.env.get("CRON_SECRET") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (authHeader !== `Bearer ${serviceKey}`) return errorResponse("Unauthorized", 401);

  console.log("[Insights Cron] Starting weekly insight generation...");
  const { data: users } = await supabaseAdmin.from("users").select("id").not("last_active", "is", null);

  let generated = 0;
  for (const u of users ?? []) {
    try {
      await generateInsightForUser(u.id);
      generated++;
      await new Promise((r) => setTimeout(r, 1200));
    } catch (e) { console.error(`Failed for ${u.id}:`, e); }
  }

  console.log(`[Insights Cron] Generated for ${generated} users`);
  return jsonResponse({ ok: true, generated });
});
