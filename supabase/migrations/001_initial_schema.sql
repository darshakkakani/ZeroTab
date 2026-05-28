-- ============================================================
-- ZeroTab — Supabase Initial Schema
-- Migration: 001_initial_schema
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================================
-- TABLE: users
-- ============================================================
CREATE TABLE IF NOT EXISTS public.users (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone               varchar(15) UNIQUE NOT NULL,
  name                varchar(100),
  financial_archetype varchar(50),
  created_at          timestamptz DEFAULT now(),
  last_active         timestamptz
);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can read/update only their own record
CREATE POLICY "users_select_own" ON public.users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_update_own" ON public.users
  FOR UPDATE USING (auth.uid() = id);

-- Service role can do everything
CREATE POLICY "users_service_all" ON public.users
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================
-- TABLE: accounts
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accounts (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source_type      varchar(20) NOT NULL CHECK (source_type IN ('aa_bank','aa_fd','sms_card','manual','mf_cas')),
  institution_name varchar(100),
  account_type     varchar(30) CHECK (account_type IN ('savings','current','credit_card','loan','mf','demat','fd','epf','insurance')),
  masked_number    varchar(10),
  current_balance  numeric(14,2),
  credit_limit     numeric(14,2),
  currency         varchar(3)  DEFAULT 'INR',
  last_synced_at   timestamptz,
  is_active        boolean     DEFAULT true,
  metadata         jsonb
);

CREATE INDEX idx_accounts_user_id ON public.accounts(user_id);
CREATE INDEX idx_accounts_source_type ON public.accounts(source_type);

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accounts_select_own" ON public.accounts
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "accounts_insert_own" ON public.accounts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "accounts_update_own" ON public.accounts
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "accounts_delete_own" ON public.accounts
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- TABLE: transactions
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid        NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  user_id      uuid        NOT NULL REFERENCES public.users(id)    ON DELETE CASCADE,
  txn_date     date        NOT NULL,
  amount       numeric(12,2) NOT NULL,
  type         varchar(10) NOT NULL CHECK (type IN ('debit','credit')),
  category     varchar(50),
  merchant     varchar(100),
  description  text,
  source       varchar(20) CHECK (source IN ('aa','sms','email','manual')),
  raw_sms_text text,
  is_recurring boolean     DEFAULT false,
  created_at   timestamptz DEFAULT now()
);

CREATE INDEX idx_transactions_user_id    ON public.transactions(user_id);
CREATE INDEX idx_transactions_account_id ON public.transactions(account_id);
CREATE INDEX idx_transactions_txn_date   ON public.transactions(txn_date DESC);
CREATE INDEX idx_transactions_category   ON public.transactions(category);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "transactions_select_own" ON public.transactions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "transactions_insert_own" ON public.transactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "transactions_update_own" ON public.transactions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "transactions_delete_own" ON public.transactions
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- TABLE: mf_holdings
-- ============================================================
CREATE TABLE IF NOT EXISTS public.mf_holdings (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  folio_number     varchar(30),
  scheme_code      varchar(10),
  scheme_name      varchar(200),
  amc_name         varchar(100),
  units            numeric(12,4),
  avg_nav          numeric(10,4),
  current_nav      numeric(10,4),
  invested_amount  numeric(14,2),
  current_value    numeric(14,2),
  xirr             numeric(6,4),
  last_updated     timestamptz
);

CREATE INDEX idx_mf_holdings_user_id    ON public.mf_holdings(user_id);
CREATE INDEX idx_mf_holdings_scheme_code ON public.mf_holdings(scheme_code);

ALTER TABLE public.mf_holdings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mf_holdings_select_own" ON public.mf_holdings
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "mf_holdings_insert_own" ON public.mf_holdings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "mf_holdings_update_own" ON public.mf_holdings
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "mf_holdings_delete_own" ON public.mf_holdings
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- TABLE: ai_insights
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ai_insights (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  week_number   integer     NOT NULL,
  year          integer     NOT NULL,
  archetype     varchar(50),
  insight_text  text        NOT NULL,
  insight_type  varchar(30) CHECK (insight_type IN ('spend_alert','savings_opportunity','debt_warning','investment_nudge','lifestyle_inflated','credit_health')),
  action_items  jsonb,
  data_snapshot jsonb,
  generated_at  timestamptz DEFAULT now(),
  UNIQUE(user_id, week_number, year)
);

CREATE INDEX idx_ai_insights_user_id ON public.ai_insights(user_id);
CREATE INDEX idx_ai_insights_generated ON public.ai_insights(generated_at DESC);

ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_insights_select_own" ON public.ai_insights
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================================
-- TABLE: consents
-- ============================================================
CREATE TABLE IF NOT EXISTS public.consents (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  aa_provider     varchar(30) DEFAULT 'finvu',
  consent_handle  varchar(200),
  consent_status  varchar(20) CHECK (consent_status IN ('pending','active','revoked','expired')),
  fip_ids         jsonb,
  valid_from      timestamptz,
  valid_to        timestamptz,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX idx_consents_user_id ON public.consents(user_id);
CREATE INDEX idx_consents_status  ON public.consents(consent_status);

ALTER TABLE public.consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "consents_select_own" ON public.consents
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "consents_insert_own" ON public.consents
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "consents_update_own" ON public.consents
  FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- FUNCTION: updated_at trigger helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.last_active = now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- SEED DATA (sandbox demo)
-- ============================================================

-- Demo user (UUID matches Supabase Auth sandbox user)
INSERT INTO public.users (id, phone, name, financial_archetype)
VALUES (
  'a1b2c3d4-0000-0000-0000-000000000001',
  '+919876543210',
  'Arjun Rao',
  'UNDERINVESTED'
) ON CONFLICT DO NOTHING;

-- Demo bank account
INSERT INTO public.accounts (id, user_id, source_type, institution_name, account_type, masked_number, current_balance, is_active)
VALUES (
  'a1b2c3d4-0001-0000-0000-000000000001',
  'a1b2c3d4-0000-0000-0000-000000000001',
  'aa_bank', 'SBI', 'savings', '7711', 420000.00, true
) ON CONFLICT DO NOTHING;

-- Demo credit card
INSERT INTO public.accounts (id, user_id, source_type, institution_name, account_type, masked_number, current_balance, credit_limit, is_active)
VALUES (
  'a1b2c3d4-0002-0000-0000-000000000001',
  'a1b2c3d4-0000-0000-0000-000000000001',
  'sms_card', 'HDFC', 'credit_card', '4521', -28000.00, 200000.00, true
) ON CONFLICT DO NOTHING;

-- Demo MF holding
INSERT INTO public.mf_holdings (user_id, folio_number, scheme_code, scheme_name, amc_name, units, avg_nav, current_nav, invested_amount, current_value, xirr)
VALUES (
  'a1b2c3d4-0000-0000-0000-000000000001',
  'ZT123456', '119551', 'Mirae Asset Large Cap Fund - Direct Growth',
  'Mirae Asset', 1240.000, 74.50, 88.90, 92380.00, 110236.00, 0.2050
) ON CONFLICT DO NOTHING;

-- Demo AI insight
INSERT INTO public.ai_insights (user_id, week_number, year, archetype, insight_text, insight_type, action_items, data_snapshot)
VALUES (
  'a1b2c3d4-0000-0000-0000-000000000001',
  20, 2025, 'UNDERINVESTED',
  'Your Zomato spend jumped ₹3,200 (68%) this month to ₹7,800. At your income of ₹1L, you''re spending 7.8% on food delivery alone — double the healthy benchmark. Cooking 3 nights a week typically saves ₹1,500–2,000/month for your spending pattern.',
  'spend_alert',
  '[{"step": 1, "text": "Set a Zomato monthly budget of ₹4,000 in app settings"}, {"step": 2, "text": "Redirect ₹2,000 saved to your Axis Flexi Cap SIP"}]'::jsonb,
  '{"netWorth": 1843720, "monthlyIncome": 100000, "monthlySpend": 62400, "savingsRate": 0.376, "emiRatio": 0.228, "topCategories": ["Food & Dining", "Shopping", "Travel"]}'::jsonb
) ON CONFLICT DO NOTHING;
