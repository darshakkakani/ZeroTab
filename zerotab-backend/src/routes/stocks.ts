import { FastifyInstance } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';
import https from 'https';

// ── Yahoo Finance free API (no key needed) ────────────────────────────────────
async function fetchStockPrice(
  symbol: string,
  exchange: 'NSE' | 'BSE' = 'NSE',
): Promise<number | null> {
  const suffix = exchange === 'BSE' ? '.BO' : '.NS';
  const ticker = encodeURIComponent(`${symbol.toUpperCase()}${suffix}`);
  const path   = `/v8/finance/chart/${ticker}?interval=1d&range=1d`;

  return new Promise((resolve) => {
    const options = {
      hostname: 'query1.finance.yahoo.com',
      port: 443,
      path,
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; ZeroTab/1.0)',
        'Accept': 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          const price = json?.chart?.result?.[0]?.meta?.regularMarketPrice as number | undefined;
          resolve(price ?? null);
        } catch {
          resolve(null);
        }
      });
    });
    req.on('error', () => resolve(null));
    req.setTimeout(8000, () => { req.destroy(); resolve(null); });
    req.end();
  });
}

// ── Commodity ticker map (Yahoo Finance futures tickers) ─────────────────────
const COMMODITY_TICKER_MAP: Record<string, string> = {
  GOLD:       'GC=F',
  SILVER:     'SI=F',
  CRUDEOIL:   'CL=F',
  NATURALGAS: 'NG=F',
  COPPER:     'HG=F',
  ALUMINIUM:  'ALI=F',
  GOLDPETAL:  'GC=F',
};

// Fetch USD/INR conversion rate from Yahoo Finance
async function fetchUSDINR(): Promise<number> {
  return new Promise((resolve) => {
    const options = {
      hostname: 'query1.finance.yahoo.com',
      port: 443,
      path: '/v8/finance/chart/USDINR=X?interval=1d&range=1d',
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; ZeroTab/1.0)',
        'Accept': 'application/json',
      },
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          const rate = json?.chart?.result?.[0]?.meta?.regularMarketPrice as number | undefined;
          resolve(rate ?? 83.5); // fallback to approximate rate
        } catch {
          resolve(83.5);
        }
      });
    });
    req.on('error', () => resolve(83.5));
    req.setTimeout(8000, () => { req.destroy(); resolve(83.5); });
    req.end();
  });
}

// Fetch commodity price in INR using Yahoo Finance futures ticker
async function fetchCommodityPrice(symbol: string): Promise<number | null> {
  const ticker = COMMODITY_TICKER_MAP[symbol.toUpperCase()];
  if (!ticker) return null;

  return new Promise((resolve) => {
    const options = {
      hostname: 'query1.finance.yahoo.com',
      port: 443,
      path: `/v8/finance/chart/${encodeURIComponent(ticker)}?interval=1d&range=1d`,
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; ZeroTab/1.0)',
        'Accept': 'application/json',
      },
    };
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', async () => {
        try {
          const json = JSON.parse(body);
          const usdPrice = json?.chart?.result?.[0]?.meta?.regularMarketPrice as number | undefined;
          if (usdPrice == null) { resolve(null); return; }
          const usdInr = await fetchUSDINR();
          resolve(usdPrice * usdInr);
        } catch {
          resolve(null);
        }
      });
    });
    req.on('error', () => resolve(null));
    req.setTimeout(10000, () => { req.destroy(); resolve(null); });
    req.end();
  });
}

export async function stockRoutes(fastify: FastifyInstance) {

  // GET /stocks/holdings — list all stock positions for the current user
  fastify.get('/holdings', { preHandler: authenticate }, async (req, reply) => {
    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .select('*')
      .eq('user_id', req.user!.id)
      .like('folio_number', 'STOCK-%')
      .order('current_value', { ascending: false });

    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data ?? []);
  });

  // POST /stocks/holdings — add a new stock position
  // Body: { symbol, exchange?, qty, avg_price, company_name? }
  fastify.post('/holdings', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const body   = req.body as any;

    const symbol   = (body.symbol as string)?.toUpperCase();
    const exchange = (body.exchange as string)?.toUpperCase() === 'BSE' ? 'BSE' : 'NSE';
    const qty      = Number(body.qty);
    const avgPrice = Number(body.avg_price);

    if (!symbol || !qty || !avgPrice) {
      return reply.status(400).send({ error: 'symbol, qty, avg_price are required' });
    }

    // Fetch current market price (best-effort — falls back to avg_price)
    const currentPrice = (await fetchStockPrice(symbol, exchange as 'NSE' | 'BSE')) ?? avgPrice;

    const invested    = qty * avgPrice;
    const currentVal  = qty * currentPrice;
    const folioNumber = `STOCK-${symbol}-${exchange}`;

    // If same symbol+exchange already exists, average the position
    const { data: existing } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, units, avg_nav, invested_amount')
      .eq('user_id', userId)
      .eq('folio_number', folioNumber)
      .maybeSingle();

    if (existing) {
      const totalQty  = (existing.units ?? 0) + qty;
      const totalCost = (existing.invested_amount ?? 0) + invested;
      const newAvg    = totalCost / totalQty;

      const { data, error } = await supabaseAdmin
        .from('mf_holdings')
        .update({
          units:           totalQty,
          avg_nav:         newAvg,
          current_nav:     currentPrice,
          invested_amount: totalCost,
          current_value:   totalQty * currentPrice,
          last_updated:    new Date().toISOString(),
        })
        .eq('id', existing.id)
        .select()
        .single();

      if (error) return reply.status(500).send({ error: error.message });
      return reply.status(200).send(data);
    }

    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .insert({
        user_id:         userId,
        folio_number:    folioNumber,
        scheme_code:     symbol,                        // ticker
        scheme_name:     body.company_name ?? symbol,   // display name
        amc_name:        exchange,                      // 'NSE' or 'BSE'
        units:           qty,
        avg_nav:         avgPrice,
        current_nav:     currentPrice,
        invested_amount: invested,
        current_value:   currentVal,
        xirr:            0,
        last_updated:    new Date().toISOString(),
      })
      .select()
      .single();

    if (error) return reply.status(500).send({ error: error.message });
    return reply.status(201).send(data);
  });

  // PATCH /stocks/holdings/:id — update qty or avg_price
  fastify.patch('/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const body   = req.body as any;

    const { data: existing, error: fetchErr } = await supabaseAdmin
      .from('mf_holdings')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .like('folio_number', 'STOCK-%')
      .single();

    if (fetchErr || !existing) return reply.status(404).send({ error: 'Holding not found' });

    const qty          = body.qty        != null ? Number(body.qty)        : existing.units;
    const avgPrice     = body.avg_price  != null ? Number(body.avg_price)  : existing.avg_nav;
    const currentPrice = existing.current_nav ?? avgPrice;

    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .update({
        units:           qty,
        avg_nav:         avgPrice,
        invested_amount: qty * avgPrice,
        current_value:   qty * currentPrice,
        last_updated:    new Date().toISOString(),
        ...(body.company_name ? { scheme_name: body.company_name } : {}),
      })
      .eq('id', id)
      .select()
      .single();

    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data);
  });

  // DELETE /stocks/holdings/:id
  fastify.delete('/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const { error } = await supabaseAdmin
      .from('mf_holdings')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .like('folio_number', 'STOCK-%');
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send({ ok: true });
  });

  // POST /stocks/refresh — bulk refresh live prices for all positions
  fastify.post('/refresh', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data: holdings } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, scheme_code, amc_name, units')
      .eq('user_id', userId)
      .like('folio_number', 'STOCK-%');

    let updated = 0;
    for (const h of holdings ?? []) {
      const exchange = (h.amc_name === 'BSE' ? 'BSE' : 'NSE') as 'NSE' | 'BSE';
      const price    = await fetchStockPrice(h.scheme_code, exchange);
      if (price !== null) {
        await supabaseAdmin.from('mf_holdings').update({
          current_nav:   price,
          current_value: (h.units ?? 0) * price,
          last_updated:  new Date().toISOString(),
        }).eq('id', h.id);
        updated++;
      }
    }
    return reply.send({ ok: true, updated });
  });

  // GET /stocks/quote?symbol=RELIANCE&exchange=NSE — live price lookup
  fastify.get('/quote', { preHandler: authenticate }, async (req, reply) => {
    const { symbol, exchange } = req.query as { symbol?: string; exchange?: string };
    if (!symbol) return reply.status(400).send({ error: 'symbol param required' });

    const exch  = (exchange?.toUpperCase() === 'BSE' ? 'BSE' : 'NSE') as 'NSE' | 'BSE';
    const price = await fetchStockPrice(symbol, exch);

    if (price === null) {
      return reply.status(404).send({
        error: `Could not fetch price for ${symbol.toUpperCase()} on ${exch}`,
      });
    }
    return reply.send({
      symbol:   symbol.toUpperCase(),
      exchange: exch,
      price,
      ts:       new Date().toISOString(),
    });
  });

  // ── ETF routes (/stocks/etf/*) ────────────────────────────────────────────

  // GET /stocks/etf/holdings
  fastify.get('/etf/holdings', { preHandler: authenticate }, async (req, reply) => {
    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .select('*')
      .eq('user_id', req.user!.id)
      .like('folio_number', 'ETF-%')
      .order('current_value', { ascending: false });

    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data ?? []);
  });

  // POST /stocks/etf/holdings — add a new ETF position
  // Body: { symbol, company_name?, units, avg_price }
  fastify.post('/etf/holdings', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const body   = req.body as any;

    const symbol   = (body.symbol as string)?.toUpperCase();
    const units    = Number(body.units);
    const avgPrice = Number(body.avg_price);

    if (!symbol || !units || !avgPrice) {
      return reply.status(400).send({ error: 'symbol, units, avg_price are required' });
    }

    // ETFs trade on NSE with .NS suffix
    const currentPrice = (await fetchStockPrice(symbol, 'NSE')) ?? avgPrice;
    const invested     = units * avgPrice;
    const currentVal   = units * currentPrice;
    const folioNumber  = `ETF-${symbol}-NSE`;

    const { data: existing } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, units, avg_nav, invested_amount')
      .eq('user_id', userId)
      .eq('folio_number', folioNumber)
      .maybeSingle();

    if (existing) {
      const totalUnits = (existing.units ?? 0) + units;
      const totalCost  = (existing.invested_amount ?? 0) + invested;
      const newAvg     = totalCost / totalUnits;

      const { data, error } = await supabaseAdmin
        .from('mf_holdings')
        .update({
          units:           totalUnits,
          avg_nav:         newAvg,
          current_nav:     currentPrice,
          invested_amount: totalCost,
          current_value:   totalUnits * currentPrice,
          last_updated:    new Date().toISOString(),
        })
        .eq('id', existing.id)
        .select()
        .single();

      if (error) return reply.status(500).send({ error: error.message });
      return reply.status(200).send(data);
    }

    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .insert({
        user_id:         userId,
        folio_number:    folioNumber,
        scheme_code:     symbol,
        scheme_name:     body.company_name ?? symbol,
        amc_name:        'NSE',
        units,
        avg_nav:         avgPrice,
        current_nav:     currentPrice,
        invested_amount: invested,
        current_value:   currentVal,
        xirr:            0,
        last_updated:    new Date().toISOString(),
      })
      .select()
      .single();

    if (error) return reply.status(500).send({ error: error.message });
    return reply.status(201).send(data);
  });

  // DELETE /stocks/etf/holdings/:id
  fastify.delete('/etf/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const { error } = await supabaseAdmin
      .from('mf_holdings')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .like('folio_number', 'ETF-%');
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send({ ok: true });
  });

  // POST /stocks/etf/refresh — bulk refresh ETF prices
  fastify.post('/etf/refresh', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data: holdings } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, scheme_code, units')
      .eq('user_id', userId)
      .like('folio_number', 'ETF-%');

    let updated = 0;
    for (const h of holdings ?? []) {
      const price = await fetchStockPrice(h.scheme_code, 'NSE');
      if (price !== null) {
        await supabaseAdmin.from('mf_holdings').update({
          current_nav:   price,
          current_value: (h.units ?? 0) * price,
          last_updated:  new Date().toISOString(),
        }).eq('id', h.id);
        updated++;
      }
    }
    return reply.send({ ok: true, updated });
  });

  // ── Commodity routes (/stocks/commodity/*) ────────────────────────────────

  // GET /stocks/commodity/holdings
  fastify.get('/commodity/holdings', { preHandler: authenticate }, async (req, reply) => {
    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .select('*')
      .eq('user_id', req.user!.id)
      .like('folio_number', 'COMM-%')
      .order('current_value', { ascending: false });

    if (error) return reply.status(500).send({ error: error.message });
    return reply.send(data ?? []);
  });

  // POST /stocks/commodity/holdings — add a commodity position
  // Body: { symbol, display_name?, qty, avg_price }
  fastify.post('/commodity/holdings', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const body   = req.body as any;

    const symbol   = (body.symbol as string)?.toUpperCase();
    const qty      = Number(body.qty);
    const avgPrice = Number(body.avg_price);

    if (!symbol || !qty || !avgPrice) {
      return reply.status(400).send({ error: 'symbol, qty, avg_price are required' });
    }

    if (!COMMODITY_TICKER_MAP[symbol]) {
      return reply.status(400).send({
        error: `Unknown commodity symbol. Supported: ${Object.keys(COMMODITY_TICKER_MAP).join(', ')}`,
      });
    }

    const currentPrice = (await fetchCommodityPrice(symbol)) ?? avgPrice;
    const invested     = qty * avgPrice;
    const currentVal   = qty * currentPrice;
    const folioNumber  = `COMM-${symbol}`;

    const { data: existing } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, units, avg_nav, invested_amount')
      .eq('user_id', userId)
      .eq('folio_number', folioNumber)
      .maybeSingle();

    if (existing) {
      const totalQty  = (existing.units ?? 0) + qty;
      const totalCost = (existing.invested_amount ?? 0) + invested;
      const newAvg    = totalCost / totalQty;

      const { data, error } = await supabaseAdmin
        .from('mf_holdings')
        .update({
          units:           totalQty,
          avg_nav:         newAvg,
          current_nav:     currentPrice,
          invested_amount: totalCost,
          current_value:   totalQty * currentPrice,
          last_updated:    new Date().toISOString(),
        })
        .eq('id', existing.id)
        .select()
        .single();

      if (error) return reply.status(500).send({ error: error.message });
      return reply.status(200).send(data);
    }

    const { data, error } = await supabaseAdmin
      .from('mf_holdings')
      .insert({
        user_id:         userId,
        folio_number:    folioNumber,
        scheme_code:     symbol,
        scheme_name:     body.display_name ?? symbol,
        amc_name:        'MCX',
        units:           qty,
        avg_nav:         avgPrice,
        current_nav:     currentPrice,
        invested_amount: invested,
        current_value:   currentVal,
        xirr:            0,
        last_updated:    new Date().toISOString(),
      })
      .select()
      .single();

    if (error) return reply.status(500).send({ error: error.message });
    return reply.status(201).send(data);
  });

  // DELETE /stocks/commodity/holdings/:id
  fastify.delete('/commodity/holdings/:id', { preHandler: authenticate }, async (req, reply) => {
    const { id } = req.params as { id: string };
    const { error } = await supabaseAdmin
      .from('mf_holdings')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.id)
      .like('folio_number', 'COMM-%');
    if (error) return reply.status(500).send({ error: error.message });
    return reply.send({ ok: true });
  });

  // POST /stocks/commodity/refresh — bulk refresh commodity prices
  fastify.post('/commodity/refresh', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    const { data: holdings } = await supabaseAdmin
      .from('mf_holdings')
      .select('id, scheme_code, units')
      .eq('user_id', userId)
      .like('folio_number', 'COMM-%');

    let updated = 0;
    for (const h of holdings ?? []) {
      const price = await fetchCommodityPrice(h.scheme_code);
      if (price !== null) {
        await supabaseAdmin.from('mf_holdings').update({
          current_nav:   price,
          current_value: (h.units ?? 0) * price,
          last_updated:  new Date().toISOString(),
        }).eq('id', h.id);
        updated++;
      }
    }
    return reply.send({ ok: true, updated });
  });

  // GET /stocks/commodity/quote?symbol=GOLD — live commodity price in INR
  fastify.get('/commodity/quote', { preHandler: authenticate }, async (req, reply) => {
    const { symbol } = req.query as { symbol?: string };
    if (!symbol) return reply.status(400).send({ error: 'symbol param required' });

    const sym = symbol.toUpperCase();
    if (!COMMODITY_TICKER_MAP[sym]) {
      return reply.status(400).send({
        error: `Unknown commodity symbol. Supported: ${Object.keys(COMMODITY_TICKER_MAP).join(', ')}`,
      });
    }

    const price = await fetchCommodityPrice(sym);
    if (price === null) {
      return reply.status(404).send({ error: `Could not fetch price for ${sym}` });
    }
    return reply.send({
      symbol: sym,
      ticker: COMMODITY_TICKER_MAP[sym],
      price_inr: price,
      ts:    new Date().toISOString(),
    });
  });
}
