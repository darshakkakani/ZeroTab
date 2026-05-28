import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../middleware/auth.js';
import { createConsent, fetchAAData, handleConsentCallback } from '../services/aaService.js';
import { supabaseAdmin } from '../lib/supabase.js';

const ConsentCreateSchema = z.object({
  phoneNumber: z.string().regex(/^\+91\d{10}$/),
  fiTypes: z.array(z.string()).optional(),
});

const CallbackSchema = z.object({
  consentHandle: z.string(),
  status: z.enum(['ACTIVE', 'REJECTED', 'REVOKED']),
  consentId: z.string().optional(),
});

async function triggerAaFetch(userId: string | undefined, consentHandle: string) {
  if (!userId) {
    throw new Error('Cannot trigger AA fetch without a userId');
  }

  if (process.env.SKIP_WORKERS === 'true') {
    await fetchAAData(userId, consentHandle);
    return { queued: false };
  }

  const { aaFetchQueue } = await import('../jobs/queues.js');
  await aaFetchQueue.add(
    'fetchAAData',
    { userId, consentHandle },
    {
      attempts: 3,
      backoff: { type: 'exponential', delay: 5000 },
    }
  );
  return { queued: true };
}

export async function aaRoutes(fastify: FastifyInstance) {
  // POST /aa/consent/create — authenticated
  fastify.post('/consent/create', {
    preHandler: authenticate,
  }, async (req: FastifyRequest, reply: FastifyReply) => {
    const body = ConsentCreateSchema.safeParse(req.body);
    if (!body.success) {
      return reply.status(400).send({ error: body.error.flatten() });
    }

    const userId = req.user!.id;
    const result = await createConsent({
      userId,
      phoneNumber: body.data.phoneNumber,
      fiTypes: body.data.fiTypes,
    });

    return reply.send(result);
  });

  // POST /aa/consent/callback — called by Finvu after user approves
  // This is an unauthenticated endpoint called by Finvu's servers
  fastify.post('/consent/callback', async (req: FastifyRequest, reply: FastifyReply) => {
    const body = CallbackSchema.safeParse(req.body);
    if (!body.success) {
      return reply.status(400).send({ error: 'Invalid callback payload' });
    }

    const { consentHandle, status } = body.data;
    await handleConsentCallback(consentHandle, status);

    if (status === 'ACTIVE') {
      // Look up userId from consent record so the worker has it
      const { data: consent } = await supabaseAdmin
        .from('consents')
        .select('user_id')
        .eq('consent_handle', consentHandle)
        .single();

      await triggerAaFetch(consent?.user_id, consentHandle);
    }

    return reply.send({ ok: true });
  });

  // POST /aa/sync — manual trigger
  fastify.post('/sync', {
    preHandler: authenticate,
  }, async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = req.user!.id;
    const { consentHandle } = req.body as { consentHandle: string };

    const result = await triggerAaFetch(userId, consentHandle);
    return reply.send(result);
  });

  // POST /aa/consent/revoke — revoke active consent
  fastify.post('/consent/revoke', {
    preHandler: authenticate,
  }, async (req: FastifyRequest, reply: FastifyReply) => {
    const userId = req.user!.id;

    // Get active consents for this user
    const { data: consents } = await supabaseAdmin
      .from('consents')
      .select('*')
      .eq('user_id', userId)
      .eq('consent_status', 'active');

    for (const consent of consents ?? []) {
      await handleConsentCallback(consent.consent_handle, 'REVOKED');
    }

    // Deactivate all AA accounts
    await supabaseAdmin
      .from('accounts')
      .update({ is_active: false })
      .eq('user_id', userId)
      .eq('source_type', 'aa_bank');

    return reply.send({ revoked: consents?.length ?? 0 });
  });
}
