import { FastifyInstance } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { z } from 'zod';

const ManualAccountSchema = z.object({
  institution_name: z.string().min(1),
  account_type:     z.enum(['savings','current','credit_card','loan','mf','demat','fd','epf','insurance']),
  masked_number:    z.string().max(10).optional(),
  current_balance:  z.number(),
  credit_limit:     z.number().optional(),
  source_type:      z.enum(['manual','mf_cas']).default('manual'),
  metadata:         z.record(z.unknown()).optional(),  // for loan: interest_rate, tenor_months, etc.
});

export async function accountRoutes(fastify: FastifyInstance) {
  // GET /accounts
  fastify.get('/', { preHandler: authenticate }, async (req, reply) => {
    const { data, error } = await supabaseAdmin
      .from('accounts')
      .select('*')
      .eq('user_id', req.user!.id)
      .eq('is_active', true)
      .order('account_type');
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // POST /accounts — add manual account
  fastify.post('/', { preHandler: authenticate }, async (req, reply) => {
    const body = ManualAccountSchema.safeParse(req.body);
    if (!body.success) return reply.status(400).send({ error: body.error.flatten() });

    const { data, error } = await supabaseAdmin
      .from('accounts')
      .insert({ ...body.data, user_id: req.user!.id, currency: 'INR' })
      .select()
      .single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.status(201).send(data);
  });

  // PATCH /accounts/:id
  fastify.patch('/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const updates = req.body as Record<string, unknown>;
    const { data, error } = await supabaseAdmin
      .from('accounts')
      .update(updates)
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .select()
      .single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // DELETE /accounts/:id — soft delete
  fastify.delete('/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    await supabaseAdmin
      .from('accounts')
      .update({ is_active: false })
      .eq('id', id)
      .eq('user_id', req.user!.id);
    return reply.send({ ok: true });
  });

  // POST /accounts/:id/adjust-balance — manual balance update
  fastify.post('/:id/adjust-balance', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const { balance } = req.body as { balance: number };
    const { data, error } = await supabaseAdmin
      .from('accounts')
      .update({ current_balance: balance, last_synced_at: new Date().toISOString() })
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .select().single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // GET /accounts/summary — net worth breakdown
  fastify.get('/summary', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data: accounts } = await supabaseAdmin
      .from('accounts').select('*').eq('user_id', userId).eq('is_active', true);
    const { data: mf } = await supabaseAdmin
      .from('mf_holdings').select('current_value').eq('user_id', userId);

    const bankBalance     = (accounts ?? []).filter(a => ['savings','current','fd'].includes(a.account_type)).reduce((s,a) => s+(a.current_balance??0), 0);
    const creditCardDebt  = (accounts ?? []).filter(a => a.account_type==='credit_card').reduce((s,a) => s+Math.abs(a.current_balance??0), 0);
    const loanOutstanding = (accounts ?? []).filter(a => a.account_type==='loan').reduce((s,a) => s+Math.abs(a.current_balance??0), 0);
    const mfValue         = (mf ?? []).reduce((s,h) => s+(h.current_value??0), 0);
    const netWorth        = bankBalance + mfValue - creditCardDebt - loanOutstanding;

    return reply.send({ netWorth, bankBalance, creditCardDebt, loanOutstanding, mfValue, accounts });
  });
}
