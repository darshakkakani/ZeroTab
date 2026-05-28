import { FastifyInstance, FastifyRequest } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { generateWeeklyInsight } from '../services/insightService.js';

export async function insightRoutes(fastify: FastifyInstance) {
  // GET /insights — get latest insight for authenticated user
  fastify.get('/', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data, error } = await supabaseAdmin
      .from('ai_insights')
      .select('*')
      .eq('user_id', userId)
      .order('generated_at', { ascending: false })
      .limit(10);
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // GET /insights/latest
  fastify.get('/latest', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data, error } = await supabaseAdmin
      .from('ai_insights')
      .select('*')
      .eq('user_id', userId)
      .order('generated_at', { ascending: false })
      .limit(1)
      .single();
    if (error) return reply.status(404).send({ error: 'No insight found' });
    return reply.send(data);
  });

  // POST /insights/generate — manual trigger (dev/testing)
  fastify.post('/generate', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const result = await generateWeeklyInsight(userId);
    return reply.send(result);
  });
}
