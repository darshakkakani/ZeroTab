import { FastifyInstance } from 'fastify';
import { authenticate } from '../middleware/auth.js';
import { supabaseAdmin } from '../lib/supabase.js';

/**
 * Demo data routes.
 *
 * Constraints discovered from live DB:
 *  - accounts.source_type  CHECK IN ('aa_bank','manual')
 *  - accounts.masked_number VARCHAR(10)
 *  - transactions.source   CHECK IN ('manual','sms')
 *  - users.phone           NOT NULL  (email-OTP users get empty string '')
 *
 * Demo identification strategy (since 'demo' source_type/source is forbidden):
 *  - accounts:    metadata = { "demo": true }   → delete via .contains()
 *  - transactions: raw_sms_text = 'ZEROTAB_DEMO' → delete via .eq()
 *  - mf_holdings: folio_number IN ('ZT-DEMO-001','ZT-DEMO-002','ZT-DEMO-003')
 */
export async function demoRoutes(fastify: FastifyInstance) {

  /** POST /demo/seed — insert realistic Indian demo data for the current user */
  fastify.post('/seed', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;

    try {
      // ── 1. Upsert user profile (FK: accounts.user_id → users.id) ───────────
      const { error: userErr } = await supabaseAdmin.from('users').upsert({
        id:                  userId,
        phone:               req.user!.phone || '',   // NOT NULL — empty string for email-OTP users
        financial_archetype: 'BALANCED_WEALTH_BUILDER',
        last_active:         new Date().toISOString(),
      }, { onConflict: 'id' });
      if (userErr) throw new Error(`users upsert failed: ${userErr.message}`);

      // ── 2. Clear any existing demo data ─────────────────────────────────────
      await supabaseAdmin.from('transactions')
        .delete().eq('user_id', userId).eq('raw_sms_text', 'ZEROTAB_DEMO');
      await supabaseAdmin.from('mf_holdings')
        .delete().eq('user_id', userId)
        .in('folio_number', ['ZT-DEMO-001', 'ZT-DEMO-002', 'ZT-DEMO-003']);
      await supabaseAdmin.from('accounts')
        .delete().eq('user_id', userId).contains('metadata', { demo: true });

      // ── 3. Accounts (source_type must be 'aa_bank'; mask ≤ 10 chars) ────────
      const { data: accounts, error: accErr } = await supabaseAdmin.from('accounts').insert([
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'State Bank of India',
          account_type: 'savings',     masked_number: '****4821',
          current_balance: 125480.50,  currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'HDFC Bank',
          account_type: 'savings',     masked_number: '****3302',
          current_balance: 42300.00,   currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'HDFC Bank',
          account_type: 'credit_card', masked_number: '****9944',
          current_balance: -38500.00,  credit_limit: 300000,
          currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'ICICI Bank',
          account_type: 'credit_card', masked_number: '****1122',
          current_balance: -12200.00,  credit_limit: 200000,
          currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'HDFC Bank',
          account_type: 'loan',        masked_number: 'HL-190042',   // ≤ 10 chars
          current_balance: -1850000.00, currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
        {
          user_id: userId, source_type: 'aa_bank',
          institution_name: 'SBI Mutual Fund',
          account_type: 'fd',          masked_number: 'FD-9214',
          current_balance: 100000.00,  currency: 'INR', is_active: true,
          metadata: { demo: true },
        },
      ]).select();
      if (accErr) throw new Error(`accounts insert failed: ${accErr.message}`);

      // ── 4. Transactions (source must be 'manual'; demo tagged via raw_sms_text) ─
      const aid = accounts![0].id; // primary SBI savings account

      const DEMO_TAG = 'ZEROTAB_DEMO';

      const debit = (date: string, merchant: string, amount: number, category: string, desc?: string) =>
        ({ user_id: userId, account_id: aid, txn_date: date,
           amount, type: 'debit', category, merchant,
           description: desc ?? merchant,
           source: 'manual', raw_sms_text: DEMO_TAG, is_recurring: false });

      const credit = (date: string, merchant: string, amount: number, category: string) =>
        ({ user_id: userId, account_id: aid, txn_date: date,
           amount, type: 'credit', category, merchant,
           description: merchant,
           source: 'manual', raw_sms_text: DEMO_TAG, is_recurring: false });

      const txns = [
        // ── May 2026 ──
        credit ('2026-05-01', 'Salary — Tata Consultancy Services', 95000,  'income'),
        debit  ('2026-05-02', 'HDFC Home Loan EMI',           22500,  'emi',           'Monthly home loan EMI'),
        debit  ('2026-05-02', 'SBI Life Insurance',            2800,   'insurance',     'Monthly premium'),
        debit  ('2026-05-03', 'Big Bazaar',                    4320,   'grocery',       'Monthly grocery run'),
        debit  ('2026-05-04', 'Zomato',                        680,    'food_delivery', 'Dinner - Biryani House'),
        debit  ('2026-05-05', 'Swiggy',                        420,    'food_delivery', 'Lunch order'),
        debit  ('2026-05-06', 'BPCL Fuel Station',             2800,   'fuel'),
        debit  ('2026-05-07', 'Netflix',                       649,    'subscriptions', 'Monthly plan'),
        debit  ('2026-05-08', 'Spotify',                       119,    'subscriptions'),
        debit  ('2026-05-09', 'Meesho',                        1299,   'shopping',      'Kurta set'),
        debit  ('2026-05-10', 'Myntra',                        2349,   'shopping',      'Nike shoes sale'),
        debit  ('2026-05-11', 'BESCOM Electricity',            1840,   'utilities',     'May electricity bill'),
        debit  ('2026-05-12', 'Airtel Postpaid',               699,    'utilities',     'Mobile + broadband'),
        debit  ('2026-05-13', 'Apollo Pharmacy',               870,    'health',        'Monthly medicines'),
        debit  ('2026-05-14', 'Starbucks',                     680,    'food_delivery', 'Team coffee'),
        debit  ('2026-05-15', 'PVR Cinemas',                   1360,   'entertainment', '2 tickets - Pushpa 3'),
        debit  ('2026-05-16', 'Ola Cabs',                      380,    'transport'),
        debit  ('2026-05-17', 'SIP — Parag Parikh Flexi Cap',  5000,   'investment',    'Monthly SIP auto-debit'),
        debit  ('2026-05-18', 'SIP — Axis Bluechip',           3000,   'investment',    'Monthly SIP auto-debit'),
        debit  ('2026-05-19', 'Nykaa',                         1490,   'shopping',      'Skincare products'),
        debit  ('2026-05-20', 'Zepto',                         860,    'grocery',       'Quick grocery'),

        // ── April 2026 ──
        credit ('2026-04-01', 'Salary — Tata Consultancy Services', 95000,  'income'),
        credit ('2026-04-15', 'Freelance Payment — Toptal',         18000,  'income'),
        debit  ('2026-04-02', 'HDFC Home Loan EMI',           22500,  'emi'),
        debit  ('2026-04-03', 'Big Bazaar',                    5100,   'grocery'),
        debit  ('2026-04-04', 'Swiggy',                        540,    'food_delivery'),
        debit  ('2026-04-05', 'Zomato',                        890,    'food_delivery'),
        debit  ('2026-04-06', 'BPCL Fuel Station',             3100,   'fuel'),
        debit  ('2026-04-07', 'Amazon',                        3499,   'shopping',      'Philips trimmer'),
        debit  ('2026-04-08', 'BESCOM Electricity',            2100,   'utilities'),
        debit  ('2026-04-09', 'Airtel Postpaid',               699,    'utilities'),
        debit  ('2026-04-10', 'Netflix',                       649,    'subscriptions'),
        debit  ('2026-04-11', 'Uber',                          220,    'transport'),
        debit  ('2026-04-12', 'Decathlon',                     2800,   'shopping',      'Running shoes'),
        debit  ('2026-04-13', 'Ola Cabs',                      460,    'transport'),
        debit  ('2026-04-14', 'HDFC Credit Card Bill',         42000,  'emi',           'April card bill payment'),
        debit  ('2026-04-17', 'SIP — Parag Parikh Flexi Cap',  5000,   'investment'),
        debit  ('2026-04-18', 'SIP — Axis Bluechip',           3000,   'investment'),
        debit  ('2026-04-20', 'BookMyShow',                    720,    'entertainment'),
        debit  ('2026-04-22', 'Lenskart',                      3200,   'health',        'New spectacles'),
        debit  ('2026-04-25', 'Zepto',                         1050,   'grocery'),

        // ── March 2026 ──
        credit ('2026-03-01', 'Salary — Tata Consultancy Services', 95000,  'income'),
        credit ('2026-03-31', 'Annual Bonus',                        50000,  'income'),
        debit  ('2026-03-02', 'HDFC Home Loan EMI',           22500,  'emi'),
        debit  ('2026-03-03', 'Big Bazaar',                    4800,   'grocery'),
        debit  ('2026-03-04', 'Swiggy',                        720,    'food_delivery'),
        debit  ('2026-03-05', 'BPCL Fuel Station',             2700,   'fuel'),
        debit  ('2026-03-06', 'Netflix',                       649,    'subscriptions'),
        debit  ('2026-03-07', 'Amazon Prime',                  1499,   'subscriptions', 'Annual renewal'),
        debit  ('2026-03-08', 'Flipkart',                      5299,   'shopping',      'Holi sale - clothing'),
        debit  ('2026-03-09', 'BESCOM Electricity',            1950,   'utilities'),
        debit  ('2026-03-10', 'Airtel Postpaid',               699,    'utilities'),
        debit  ('2026-03-11', 'Apollo Pharmacy',               1200,   'health'),
        debit  ('2026-03-15', 'SIP — Parag Parikh Flexi Cap',  5000,   'investment'),
        debit  ('2026-03-16', 'SIP — Axis Bluechip',           3000,   'investment'),
        debit  ('2026-03-20', 'Zomato',                        1100,   'food_delivery', 'Holi dinner'),
        debit  ('2026-03-22', 'HDFC Credit Card Bill',         39500,  'emi'),
        debit  ('2026-03-25', 'Uber',                          350,    'transport'),
      ];

      const { error: txnErr } = await supabaseAdmin.from('transactions').insert(txns);
      if (txnErr) throw new Error(`transactions insert failed: ${txnErr.message}`);

      // ── 5. MF Holdings ───────────────────────────────────────────────────────
      const { error: mfErr } = await supabaseAdmin.from('mf_holdings').insert([
        {
          user_id: userId, folio_number: 'ZT-DEMO-001',
          scheme_code: '122639', scheme_name: 'Parag Parikh Flexi Cap Fund - Direct Plan',
          amc_name: 'PPFAS Mutual Fund',   units: 142.456,
          avg_nav: 63.52,  current_nav: 78.34,
          invested_amount: 90000,  current_value: 111584.15,
          xirr: 18.4, last_updated: new Date().toISOString(),
        },
        {
          user_id: userId, folio_number: 'ZT-DEMO-002',
          scheme_code: '120503', scheme_name: 'Axis Bluechip Fund - Direct Plan',
          amc_name: 'Axis Mutual Fund',    units: 218.33,
          avg_nav: 45.80,  current_nav: 52.20,
          invested_amount: 60000,  current_value: 71552.82,
          xirr: 11.2, last_updated: new Date().toISOString(),
        },
        {
          user_id: userId, folio_number: 'ZT-DEMO-003',
          scheme_code: '119551', scheme_name: 'Mirae Asset Large Cap Fund - Direct Plan',
          amc_name: 'Mirae Asset',         units: 309.87,
          avg_nav: 80.25,  current_nav: 93.40,
          invested_amount: 42000,  current_value: 48942.00,
          xirr: 16.8, last_updated: new Date().toISOString(),
        },
      ]);
      if (mfErr) throw new Error(`mf_holdings insert failed: ${mfErr.message}`);

      return reply.send({
        ok: true,
        seeded: { accounts: 6, transactions: txns.length, mf_holdings: 3 },
      });

    } catch (err: any) {
      req.log.error({ err }, 'Demo seed failed');
      return reply.status(500).send({ ok: false, error: err?.message ?? String(err) });
    }
  });

  /** DELETE /demo/seed — wipe all demo data for current user */
  fastify.delete('/seed', { preHandler: authenticate }, async (req, reply) => {
    const userId = req.user!.id;
    try {
      await supabaseAdmin.from('transactions')
        .delete().eq('user_id', userId).eq('raw_sms_text', 'ZEROTAB_DEMO');
      await supabaseAdmin.from('mf_holdings')
        .delete().eq('user_id', userId)
        .in('folio_number', ['ZT-DEMO-001', 'ZT-DEMO-002', 'ZT-DEMO-003']);
      await supabaseAdmin.from('accounts')
        .delete().eq('user_id', userId).contains('metadata', { demo: true });
      return reply.send({ ok: true });
    } catch (err: any) {
      return reply.status(500).send({ ok: false, error: err?.message ?? String(err) });
    }
  });
}
