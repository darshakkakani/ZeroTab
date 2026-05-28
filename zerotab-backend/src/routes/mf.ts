import { FastifyInstance, FastifyRequest } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { parseCasPdf, storeCasHoldings, searchSchemes } from '../services/mfService.js';
import { supabaseAdmin } from '../lib/supabase.js';
import https from 'https';

async function fetchLatestNav(schemeCode: string): Promise<number | null> {
  return new Promise((resolve) => {
    const options = {
      hostname: 'api.mfapi.in',
      port: 443,
      path: `/mf/${schemeCode}/latest`,
      method: 'GET',
      headers: { 'User-Agent': 'ZeroTab/1.0' },
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (d) => body += d);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.status === 'SUCCESS' && json.data?.[0]?.nav) {
            resolve(parseFloat(json.data[0].nav));
          } else {
            resolve(null);
          }
        } catch { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.end();
  });
}

export async function mfRoutes(fastify: FastifyInstance) {
  // GET /mf/holdings — list user's MF holdings
  fastify.get('/holdings', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .select('*')
      .eq('user_id', userId)
      .order('current_value', { ascending: false });
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // POST /mf/cas-upload — upload CAMS/KFintech CAS PDF
  fastify.post('/cas-upload', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const data   = await req.file();
    if (!data) return reply.status(400).send({ error: 'No file uploaded' });

    const chunks: Buffer[] = [];
    for await (const chunk of data.file) chunks.push(chunk);
    const buffer = Buffer.concat(chunks);

    const holdings = await parseCasPdf(buffer);
    if (holdings.length === 0) {
      return reply.status(422).send({ error: 'Could not parse any holdings from PDF' });
    }

    await storeCasHoldings(userId, holdings);
    return reply.send({ imported: holdings.length });
  });

  // GET /mf/search?q= — search AMFI scheme list
  fastify.get('/search', async (req, reply) => {
    const { q } = req.query as { q?: string };
    if (!q) return reply.status(400).send({ error: 'q param required' });
    const results = await searchSchemes(q);
    return reply.send(results.slice(0, 20));
  });

  // POST /mf/holdings — manual add (no PDF needed)
  fastify.post('/holdings', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const body = req.body as any;

    const { data, error } = await supabaseAdmin.from('mf_holdings').insert({
      user_id:         userId,
      folio_number:    body.folio_number || `MF-MANUAL-${Date.now()}`,
      scheme_code:     body.scheme_code ?? '',
      scheme_name:     body.scheme_name ?? '',
      amc_name:        body.amc_name ?? '',
      units:           Number(body.units) || 0,
      avg_nav:         Number(body.avg_nav) || 0,
      current_nav:     Number(body.current_nav) || Number(body.avg_nav) || 0,
      invested_amount: Number(body.invested_amount) || (Number(body.units) * Number(body.avg_nav)),
      current_value:   Number(body.current_value) || (Number(body.units) * (Number(body.current_nav) || Number(body.avg_nav))),
      xirr:            Number(body.xirr) || 0,
      last_updated:    new Date().toISOString(),
    }).select().single();

    if (error) return reply.status(500).send({ error: error.message });
    return reply.status(201).send(data);
  });

  // PATCH /mf/holdings/:id — update holding
  fastify.patch('/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const updates = { ...(req.body as any), last_updated: new Date().toISOString() };
    // Recalculate value if units or nav changed
    if (updates.units != null || updates.current_nav != null) {
      const { data: existing } = await supabaseAdmin.from('mf_holdings').select('units,current_nav,avg_nav').eq('id', id).single();
      const units = updates.units       ?? existing?.units       ?? 0;
      const nav   = updates.current_nav ?? existing?.current_nav ?? existing?.avg_nav ?? 0;
      updates.current_value = units * nav;
      if (updates.units != null && updates.avg_nav != null) {
        updates.invested_amount = units * updates.avg_nav;
      }
    }
    const { data, error } = await supabaseAdmin.from('mf_holdings')
      .update(updates).eq('id', id).eq('user_id', req.user!.id).select().single();
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // DELETE /mf/holdings/:id
  fastify.delete('/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    await supabaseAdmin.from('mf_holdings').delete().eq('id', id).eq('user_id', req.user!.id);
    return reply.send({ ok: true });
  });

  // POST /mf/refresh-nav — refresh NAV from mfapi.in (free AMFI-sourced API)
  fastify.post('/refresh-nav', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data: holdings } = await supabaseAdmin
      .from('mf_holdings').select('id,scheme_code,units')
      .eq('user_id', userId)
      .not('folio_number', 'like', 'STOCK-%'); // only MF, not stocks

    let updated = 0;
    for (const h of holdings ?? []) {
      if (!h.scheme_code) continue;
      try {
        const nav = await fetchLatestNav(h.scheme_code);
        if (nav != null) {
          await supabaseAdmin.from('mf_holdings').update({
            current_nav:   nav,
            current_value: (h.units ?? 0) * nav,
            last_updated:  new Date().toISOString(),
          }).eq('id', h.id);
          updated++;
        }
      } catch { /* skip */ }
    }
    return reply.send({ ok: true, updated });
  });
}
