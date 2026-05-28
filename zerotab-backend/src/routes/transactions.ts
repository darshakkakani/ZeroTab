import { FastifyInstance } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { z } from 'zod';

const MERCHANT_CATEGORY_MAP: Record<string, string> = {
  zomato: 'food_delivery', swiggy: 'food_delivery', dunzo: 'food_delivery',
  blinkit: 'food_delivery', zepto: 'food_delivery', instamart: 'food_delivery',
  ola: 'transport', uber: 'transport', rapido: 'transport', metro: 'transport',
  irctc: 'transport', auto: 'transport', rickshaw: 'transport',
  bpcl: 'fuel', 'indian oil': 'fuel', 'iocl': 'fuel', 'hp': 'fuel', shell: 'fuel',
  bescom: 'utilities', airtel: 'utilities', jio: 'utilities', bsnl: 'utilities',
  netflix: 'subscriptions', spotify: 'subscriptions', 'amazon prime': 'subscriptions',
  hotstar: 'subscriptions', 'disney': 'subscriptions', youtube: 'subscriptions',
  'big bazaar': 'grocery', dmart: 'grocery', bigbasket: 'grocery', jiomart: 'grocery',
  amazon: 'shopping', flipkart: 'shopping', myntra: 'shopping', meesho: 'shopping',
  nykaa: 'shopping', ajio: 'shopping',
  pvr: 'entertainment', inox: 'entertainment', bookmyshow: 'entertainment',
  apollo: 'health', medplus: 'health', '1mg': 'health', pharmeasy: 'health',
  lic: 'insurance', 'hdfc life': 'insurance', 'max life': 'insurance',
  sip: 'investment', groww: 'investment', zerodha: 'investment', upstox: 'investment',
  starbucks: 'food_delivery', dominos: 'food_delivery', kfc: 'food_delivery',
  decathlon: 'shopping', lenskart: 'health',
};

function autoCategory(merchant: string): string {
  const m = merchant.toLowerCase();
  for (const [keyword, cat] of Object.entries(MERCHANT_CATEGORY_MAP)) {
    if (m.includes(keyword)) return cat;
  }
  return 'others';
}

const QuerySchema = z.object({
  from:       z.string().optional(),
  to:         z.string().optional(),
  category:   z.string().optional(),
  account_id: z.string().uuid().optional(),
  search:     z.string().optional(),
  limit:      z.coerce.number().int().min(1).max(200).default(50),
  offset:     z.coerce.number().int().min(0).default(0),
});

export async function transactionRoutes(fastify: FastifyInstance) {
  // GET /transactions
  fastify.get('/', { preHandler: authenticate }, async (req, reply) => {
    const q = QuerySchema.safeParse(req.query);
    if (!q.success) return reply.status(400).send({ error: q.error.flatten() });

    let query = supabaseAdmin
      .from('transactions')
      .select('*', { count: 'exact' })
      .eq('user_id', req.user!.id)
      .order('txn_date', { ascending: false })
      .range(q.data.offset, q.data.offset + q.data.limit - 1);

    if (q.data.from)       query = query.gte('txn_date', q.data.from);
    if (q.data.to)         query = query.lte('txn_date', q.data.to);
    if (q.data.category)   query = query.eq('category', q.data.category);
    if (q.data.account_id) query = query.eq('account_id', q.data.account_id);
    if (q.data.search)     query = query.ilike('merchant', `%${q.data.search}%`);

    const { data, error, count } = await query;
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send({ data, total: count, limit: q.data.limit, offset: q.data.offset });
  });

  // GET /transactions/summary — category totals for current month
  fastify.get('/summary', { preHandler: authenticate }, async (req, reply) => {
    const { month, year } = req.query as { month?: string; year?: string };
    const now  = new Date();
    const m    = month ? parseInt(month) : now.getMonth() + 1;
    const y    = year  ? parseInt(year)  : now.getFullYear();
    const from = `${y}-${String(m).padStart(2,'0')}-01`;
    const to   = new Date(y, m, 0).toISOString().split('T')[0];

    const { data } = await supabaseAdmin
      .from('transactions')
      .select('category, amount, type')
      .eq('user_id', req.user!.id)
      .gte('txn_date', from)
      .lte('txn_date', to);

    const byCategory: Record<string, number> = {};
    let totalSpend = 0, totalIncome = 0;
    for (const t of data ?? []) {
      if (t.type === 'debit') {
        byCategory[t.category ?? 'others'] = (byCategory[t.category ?? 'others'] ?? 0) + t.amount;
        totalSpend += t.amount;
      } else {
        totalIncome += t.amount;
      }
    }
    return reply.send({ byCategory, totalSpend, totalIncome, month: m, year: y });
  });

  // GET /transactions/cashflow — monthly income vs spend for last N months
  fastify.get('/cashflow', { preHandler: authenticate }, async (req, reply) => {
    const months = parseInt((req.query as any).months ?? '6');
    const result: { month: string; income: number; spend: number }[] = [];

    for (let i = months - 1; i >= 0; i--) {
      const d    = new Date();
      d.setMonth(d.getMonth() - i);
      const y    = d.getFullYear();
      const m    = d.getMonth() + 1;
      const from = `${y}-${String(m).padStart(2,'0')}-01`;
      const to   = new Date(y, m, 0).toISOString().split('T')[0];

      const { data } = await supabaseAdmin
        .from('transactions')
        .select('amount, type')
        .eq('user_id', req.user!.id)
        .gte('txn_date', from)
        .lte('txn_date', to);

      const income = (data ?? []).filter(t => t.type==='credit').reduce((s,t) => s+t.amount, 0);
      const spend  = (data ?? []).filter(t => t.type==='debit').reduce((s,t)  => s+t.amount, 0);
      result.push({ month: `${y}-${String(m).padStart(2,'0')}`, income, spend });
    }
    return reply.send(result);
  });

  // POST /transactions/recategorize — re-run autoCategory on all user transactions
  // and update only rows where the suggested category differs from stored category
  fastify.post('/recategorize', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;

    const { data: transactions, error: fetchErr } = await supabaseAdmin
      .from('transactions')
      .select('id, merchant, category')
      .eq('user_id', userId);

    if (fetchErr) return reply.status(500).send({ error: fetchErr.message });

    let fixed = 0;
    for (const txn of transactions ?? []) {
      if (!txn.merchant) continue;
      const suggested = autoCategory(txn.merchant);
      if (suggested !== txn.category) {
        const { error: updateErr } = await supabaseAdmin
          .from('transactions')
          .update({ category: suggested })
          .eq('id', txn.id)
          .eq('user_id', userId);
        if (!updateErr) fixed++;
      }
    }

    return reply.send({ fixed });
  });

  // POST /transactions — manual entry
  fastify.post('/', { preHandler: authenticate }, async (req, reply) => {
    const body    = req.body as any;
    const userId  = req.user!.id;

    // ── Resolve account_id (NOT NULL in DB) ──────────────────────────────
    // If caller didn't provide one (new user with no connected accounts),
    // find or auto-create a "Manual Wallet" account so the insert succeeds.
    let accountId: string = body.account_id;

    if (!accountId) {
      // Ensure user exists in public.users first (FK: accounts.user_id → users.id)
      // phone NOT NULL — use empty string for email-OTP users
      await supabaseAdmin.from('users').upsert({
        id:          userId,
        phone:       req.user!.phone || '',
        last_active: new Date().toISOString(),
      }, { onConflict: 'id' });

      // Look for an existing manual wallet
      const { data: existing } = await supabaseAdmin
        .from('accounts')
        .select('id')
        .eq('user_id', userId)
        .eq('source_type', 'manual')
        .maybeSingle();

      if (existing) {
        accountId = existing.id;
      } else {
        // First manual entry ever — create a wallet account on the fly
        const { data: wallet, error: walletErr } = await supabaseAdmin
          .from('accounts')
          .insert({
            user_id:          userId,
            source_type:      'manual',
            institution_name: 'Manual Wallet',
            account_type:     'savings',
            masked_number:    'MANUAL',
            current_balance:  0,
            currency:         'INR',
            is_active:        true,
          })
          .select('id')
          .single();

        if (walletErr) {
          req.log.error({ walletErr }, 'Could not create manual wallet');
          return reply.status(500).send({ error: `Could not create wallet: ${walletErr.message}` });
        }
        accountId = wallet.id;
      }
    }

    // ── Build insert payload with safe defaults ───────────────────────────
    const payload: any = {
      ...body,
      account_id:   accountId,
      user_id:      userId,
      source:       'manual',
      is_recurring: body.is_recurring ?? false,
      description:  body.description  ?? body.merchant ?? '',
      merchant:     body.merchant     ?? body.description ?? 'Manual entry',
    };

    // Auto-categorize if category is missing
    if (!payload.category && payload.merchant) {
      payload.category = autoCategory(payload.merchant);
    }

    const { data, error } = await supabaseAdmin
      .from('transactions')
      .insert(payload)
      .select()
      .single();

    if (error) {
      req.log.error({ error }, 'POST /transactions failed');
      return reply.status(500).send({ error: error.message, details: error.details });
    }

    // ── Update account balance ───────────────────────────
    try {
      const { data: acc } = await supabaseAdmin
        .from('accounts').select('current_balance').eq('id', accountId).single();
      if (acc) {
        const delta = payload.type === 'credit' ? payload.amount : -payload.amount;
        await supabaseAdmin.from('accounts')
          .update({ current_balance: (acc.current_balance ?? 0) + delta })
          .eq('id', accountId);
      }
    } catch { /* non-fatal — transaction was saved */ }

    return reply.status(201).send(data);
  });

  // PATCH /transactions/:id — update a transaction
  fastify.patch('/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const body = req.body as any;
    const userId = req.user!.id;

    // Verify ownership
    const { data: existing, error: fetchErr } = await supabaseAdmin
      .from('transactions')
      .select('*')
      .eq('id', id)
      .eq('user_id', userId)
      .single();

    if (fetchErr || !existing) {
      return reply.status(404).send({ error: 'Transaction not found' });
    }

    // Update the transaction
    const { data, error } = await supabaseAdmin
      .from('transactions')
      .update(body)
      .eq('id', id)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) {
      req.log.error({ error }, 'PATCH /transactions/:id failed');
      return reply.status(500).send({ error: error.message });
    }

    return reply.send(data);
  });

  // DELETE /transactions/:id — delete a transaction
  fastify.delete('/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const userId = req.user!.id;

    // Verify ownership and get transaction details for balance update
    const { data: existing, error: fetchErr } = await supabaseAdmin
      .from('transactions')
      .select('*')
      .eq('id', id)
      .eq('user_id', userId)
      .single();

    if (fetchErr || !existing) {
      return reply.status(404).send({ error: 'Transaction not found' });
    }

    // Delete the transaction
    const { error } = await supabaseAdmin
      .from('transactions')
      .delete()
      .eq('id', id)
      .eq('user_id', userId);

    if (error) {
      req.log.error({ error }, 'DELETE /transactions/:id failed');
      return reply.status(500).send({ error: error.message });
    }

    // Update account balance (reverse the transaction)
    try {
      const { data: acc } = await supabaseAdmin
        .from('accounts')
        .select('current_balance')
        .eq('id', existing.account_id)
        .single();
      
      if (acc) {
        const delta = existing.type === 'credit' ? -existing.amount : existing.amount;
        await supabaseAdmin
          .from('accounts')
          .update({ current_balance: (acc.current_balance ?? 0) + delta })
          .eq('id', existing.account_id);
      }
    } catch (err) {
      req.log.warn({ err }, 'Failed to update account balance after delete');
      // non-fatal — transaction was deleted
    }

    return reply.status(204).send();
  });
}
