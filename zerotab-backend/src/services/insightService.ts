/**
 * ZeroTab — AI Insight Generator
 * Generates one personalised weekly insight per user using Claude claude-sonnet-4-5.
 * Runs every Monday 9 AM IST via BullMQ cron.
 */
import Anthropic from '@anthropic-ai/sdk';
import { getISOWeek, getYear } from 'date-fns';
import { supabaseAdmin } from '../lib/supabase.js';
import { buildFinancialSnapshot } from './archetypeEngine.js';
import { FinancialSnapshot, AIInsight } from '../types/index.js';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// ── Archetype-specific system prompt adjuncts ─────────────

const ARCHETYPE_CONTEXT: Record<string, string> = {
  HIGH_INCOME_HIGH_EMI:    'Focus on reducing EMI burden and optimising debt repayment order.',
  YOUNG_SAVER:             'Encourage starting SIPs and index funds with clear first steps.',
  LIFESTYLE_INFLATED:      'Highlight specific overspend categories with exact rupee amounts.',
  UNDERINVESTED:           'Point out idle cash opportunity cost. Suggest specific MF categories.',
  CREDIT_STRESSED:         'Address high credit utilization with a concrete paydown plan.',
  GOOD_INVESTOR:           'Suggest portfolio rebalancing or next SIP increase milestone.',
  DEBT_FREE_SPENDER:       'Nudge toward building an emergency fund and starting investments.',
  CONSERVATIVE_SAVER:      'Gently challenge FD-only mindset with inflation-adjusted returns.',
  SIP_STARTER:             'Celebrate progress, suggest next SIP step-up.',
  REAL_ESTATE_HEAVY:       'Flag liquidity risk, suggest liquid fund buffer.',
  CASH_HOARDER:            'Quantify the inflation erosion on idle savings.',
  EMI_JUGGLER:             'Suggest a debt snowball or avalanche plan with exact numbers.',
  SUBSCRIPTIONS_HEAVY:     'List top 3 subscriptions by cost and ask which adds real value.',
  FOOD_DELIVERY_ADDICT:    'Show food delivery spend as % of income with benchmark.',
  TRAVEL_SPENDER:          'Suggest travel budget and credit card reward optimisation.',
  INSURANCE_UNDERSERVED:   'Flag under-insurance risk relative to income and loan.',
  HIGH_NET_WORTH:          'Focus on asset allocation, tax optimisation, estate planning.',
  EMERGING_PROFESSIONAL:   'Build wealth foundation — emergency fund, term insurance, SIP.',
  BUDGET_CONSCIOUS:        'Celebrate discipline, suggest next wealth milestone.',
  BALANCED_WEALTH_BUILDER: 'Highlight the single biggest lever to improve financial health.',
};

// ── Build system prompt ───────────────────────────────────

function buildSystemPrompt(archetype: string): string {
  const archetypeHint = ARCHETYPE_CONTEXT[archetype] ?? ARCHETYPE_CONTEXT.BALANCED_WEALTH_BUILDER;
  return `You are a personal CFO for an Indian user — their trusted financial advisor who knows their actual numbers.

Your job: give ONE specific, actionable financial insight based on their real data this week.

Tone: Direct, warm, like a CA friend texting you — not a bank chatbot.
Language: Simple English, zero jargon. Never say "portfolio diversification" — say "spread your money across different types of funds".
Format: 3–4 sentences of insight, then exactly 2 action items as bullet points starting with "•".
Rules:
- Every sentence MUST reference their actual numbers (₹ amounts, %, counts)
- Never give generic advice like "save more" — always say HOW MUCH MORE and WHERE
- Reference what changed vs last month
- If they're doing well in one area, acknowledge it in one sentence before the insight
- Keep total response under 280 words

Archetype context: ${archetypeHint}`;
}

// ── Build user prompt ─────────────────────────────────────

function buildUserPrompt(snapshot: FinancialSnapshot, weekLabel: string): string {
  const spendPct = snapshot.monthlyIncome > 0
    ? ((snapshot.monthlySpend / snapshot.monthlyIncome) * 100).toFixed(0)
    : '0';

  return `Financial snapshot — ${weekLabel}:

Net worth: ₹${snapshot.netWorth.toLocaleString('en-IN')}
Monthly income: ₹${snapshot.monthlyIncome.toLocaleString('en-IN')}
Monthly spend: ₹${snapshot.monthlySpend.toLocaleString('en-IN')} (${spendPct}% of income)
Top 3 spending categories: ${snapshot.topCategories.slice(0, 3).join(', ')}
EMI burden: ${(snapshot.emiRatio * 100).toFixed(0)}% of income
Savings rate: ${(snapshot.savingsRate * 100).toFixed(0)}%
MF portfolio value: ₹${snapshot.mfValue.toLocaleString('en-IN')} (XIRR: ${snapshot.mfXIRR.toFixed(1)}%)
Credit utilization: ${(snapshot.creditUtil * 100).toFixed(0)}%
Bank balance: ₹${snapshot.bankBalance.toLocaleString('en-IN')}
Biggest change vs last month: ${snapshot.biggestChange}
Financial archetype: ${snapshot.archetype}

Generate this week's insight.`;
}

// ── Classify insight type ─────────────────────────────────

function classifyInsightType(snapshot: FinancialSnapshot): string {
  if (snapshot.creditUtil > 0.60) return 'debt_warning';
  if (snapshot.emiRatio > 0.40)    return 'debt_warning';
  if (snapshot.savingsRate < 0.10) return 'savings_opportunity';
  if (snapshot.mfValue < 10_000 && snapshot.bankBalance > 200_000) return 'investment_nudge';
  return 'spend_alert';
}

// ── Main insight generator ────────────────────────────────

export async function generateWeeklyInsight(userId: string): Promise<{ text: string; generatedAt: Date }> {
  const now         = new Date();
  const weekNumber  = getISOWeek(now);
  const year        = getYear(now);
  const weekLabel   = `Week ${weekNumber}, ${year}`;

  // Skip if already generated this week
  const { data: existing } = await supabaseAdmin
    .from('ai_insights')
    .select('id, insight_text')
    .eq('user_id', userId)
    .eq('week_number', weekNumber)
    .eq('year', year)
    .single();

  if (existing) {
    return { text: existing.insight_text, generatedAt: now };
  }

  // Build snapshot
  const snapshot     = await buildFinancialSnapshot(userId);
  const systemPrompt = buildSystemPrompt(snapshot.archetype);
  const userPrompt   = buildUserPrompt(snapshot, weekLabel);

  // Call Claude — correct model ID: claude-sonnet-4-5
  const response = await anthropic.messages.create({
    model:      'claude-sonnet-4-5',
    max_tokens: 350,
    system:     systemPrompt,
    messages:   [{ role: 'user', content: userPrompt }],
  });

  const insightText = (response.content[0] as { type: 'text'; text: string }).text.trim();

  // Parse action items (lines starting with •)
  const actionLines = insightText.split('\n').filter((l) => l.trim().startsWith('•'));
  const actionItems = actionLines.map((l, i) => ({
    step: i + 1,
    text: l.replace(/^[•\-]\s*/, '').trim(),
  }));

  // Persist
  await supabaseAdmin.from('ai_insights').insert({
    user_id:       userId,
    week_number:   weekNumber,
    year,
    archetype:     snapshot.archetype,
    insight_text:  insightText,
    insight_type:  classifyInsightType(snapshot),
    action_items:  actionItems,
    data_snapshot: snapshot,
    generated_at:  now.toISOString(),
  });

  // Push notification (non-fatal)
  sendInsightPushNotification(userId, insightText).catch(() => {});

  return { text: insightText, generatedAt: now };
}

/** Generate insights for ALL active users (called by Monday cron) */
export async function generateInsightsForAllUsers(): Promise<void> {
  const { data: users } = await supabaseAdmin
    .from('users')
    .select('id')
    .not('last_active', 'is', null);

  if (!users?.length) return;
  console.log(`[InsightGen] Generating for ${users.length} users`);

  for (const user of users) {
    try {
      await generateWeeklyInsight(user.id);
      await new Promise((r) => setTimeout(r, 1200)); // ~50 req/min safety margin
    } catch (err) {
      console.error(`[InsightGen] Failed for user ${user.id}:`, err);
    }
  }
}

// ── Push notification ─────────────────────────────────────
async function sendInsightPushNotification(userId: string, insightText: string): Promise<void> {
  const { sendPushToUser } = await import('./notificationService.js');
  await sendPushToUser(userId, {
    title: '📊 Your weekly financial insight is ready',
    body:  insightText.slice(0, 100) + '…',
    data:  { screen: 'InsightDetail' },
  });
}
