import { FastifyRequest, FastifyReply } from 'fastify';
import { supabase } from '../lib/supabase.js';

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return reply.status(401).send({ error: 'Missing or invalid Authorization header' });
  }

  const token = authHeader.split(' ')[1];
  const { data, error } = await supabase.auth.getUser(token);

  if (error || !data.user) {
    return reply.status(401).send({ error: 'Invalid or expired token' });
  }

  request.user = {
    id:    data.user.id,
    phone: data.user.phone,
    email: data.user.email,
  };
}

// Extend FastifyRequest type globally
declare module 'fastify' {
  interface FastifyRequest {
    user?: {
      id:     string;
      phone?: string;
      email?: string;
    };
  }
}
