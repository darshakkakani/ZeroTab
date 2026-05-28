import { FastifyInstance } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { buildFinancialSnapshot } from '../services/archetypeEngine.js';

export async function userRoutes(fastify: FastifyInstance) {
  // GET /users/me
  fastify.get('/me', { preHandler: authenticate }, async (req, reply) => {
    const { data, error } = await supabaseAdmin
      .from('users').select('*').eq('id', req.user!.id).single();
    if (error) return reply.status(404).send({ error: 'User not found' });
    return reply.send(data);
  });

  // PUT /users/me
  fastify.put('/me', { preHandler: authenticate }, async (req, reply) => {
    const { name } = req.body as { name?: string };
    const { data, error } = await supabaseAdmin
      .from('users').update({ name, last_active: new Date().toISOString() })
      .eq('id', req.user!.id).select().single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // GET /users/me/snapshot — full financial snapshot
  fastify.get('/me/snapshot', { preHandler: authenticate }, async (req, reply) => {
    const snapshot = await buildFinancialSnapshot(req.user!.id);
    return reply.send(snapshot);
  });

  // POST /users/me/register — upsert user record after OTP login (supports phone or email auth)
  fastify.post('/me/register', { preHandler: authenticate }, async (req, reply) => {
    const { phone, email, name } = req.body as { phone?: string; email?: string; name?: string };
    // 'email' is NOT a column in public.users (lives in auth.users only)
    // 'phone' is NOT NULL — use empty string for email-OTP users where phone is undefined
    const upsertPayload: Record<string, unknown> = {
      id:          req.user!.id,
      phone:       phone || req.user!.phone || '',  // satisfies NOT NULL constraint
      last_active: new Date().toISOString(),
    };
    if (name) upsertPayload['name'] = name;
    const { data, error } = await supabaseAdmin
      .from('users')
      .upsert(upsertPayload, { onConflict: 'id' })
      .select().single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // DELETE /users/me — GDPR delete
  fastify.delete('/me', { preHandler: authenticate }, async (req, reply) => {
    // Cascade deletes all related data via FK
    await supabaseAdmin.from('users').delete().eq('id', req.user!.id);
    await supabaseAdmin.auth.admin.deleteUser(req.user!.id);
    return reply.send({ ok: true });
  });

  // POST /users/me/fcm-token — store FCM token for push notifications
  fastify.post('/me/fcm-token', { preHandler: authenticate }, async (req, reply) => {
    const { token } = req.body as { token: string };
    await supabaseAdmin
      .from('users')
      .update({ metadata: { fcm_token: token } } as any)
      .eq('id', req.user!.id);
    return reply.send({ ok: true });
  });
}
