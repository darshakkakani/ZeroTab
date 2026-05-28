-- Migration: 003_edge_functions_support
-- Adds pg_cron extension, DB functions for archetype engine,
-- and service-role policies needed by Edge Functions.

-- ============================================================
-- Enable pg_cron for scheduled jobs
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Grant cron usage to postgres role (required by Supabase)
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

-- ============================================================
-- Add metadata column to users if not exists (for fcm_token)
-- ============================================================
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb;

-- ============================================================
-- RLS: Allow service_role full access on all tables
-- (Edge Functions use service_role key for admin operations)
-- ============================================================

DO $$ BEGIN
  DROP POLICY IF EXISTS "ai_insights_service_insert" ON public.ai_insights;
  CREATE POLICY "ai_insights_service_insert" ON public.ai_insights
    FOR INSERT WITH CHECK (true);

  DROP POLICY IF EXISTS "ai_insights_service_update" ON public.ai_insights;
  CREATE POLICY "ai_insights_service_update" ON public.ai_insights
    FOR UPDATE USING (true);

  DROP POLICY IF EXISTS "consents_service_update" ON public.consents;
  CREATE POLICY "consents_service_update" ON public.consents
    FOR UPDATE USING (true);

  DROP POLICY IF EXISTS "consents_service_insert" ON public.consents;
  CREATE POLICY "consents_service_insert" ON public.consents
    FOR INSERT WITH CHECK (true);

  DROP POLICY IF EXISTS "users_insert_service" ON public.users;
  CREATE POLICY "users_insert_service" ON public.users
    FOR INSERT WITH CHECK (true);

  DROP POLICY IF EXISTS "users_delete_service" ON public.users;
  CREATE POLICY "users_delete_service" ON public.users
    FOR DELETE USING (true);
END $$;

-- ============================================================
-- DB Function: auto_categorize_merchant
-- Used by transaction insert/update to classify merchants
-- ============================================================
CREATE OR REPLACE FUNCTION public.auto_categorize_merchant(merchant_name text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  m text := lower(merchant_name);
BEGIN
  IF m ~ '(zomato|swiggy|blinkit|zepto|dunzo|starbucks|dominos|kfc)' THEN RETURN 'food_delivery'; END IF;
  IF m ~ '(ola|uber|rapido|metro|irctc|auto|rickshaw)' THEN RETURN 'transport'; END IF;
  IF m ~ '(bpcl|indian oil|iocl|hp|shell)' THEN RETURN 'fuel'; END IF;
  IF m ~ '(bescom|airtel|jio|bsnl)' THEN RETURN 'utilities'; END IF;
  IF m ~ '(netflix|spotify|amazon prime|hotstar|disney|youtube)' THEN RETURN 'subscriptions'; END IF;
  IF m ~ '(big bazaar|dmart|bigbasket|jiomart)' THEN RETURN 'grocery'; END IF;
  IF m ~ '(amazon|flipkart|myntra|meesho|nykaa|ajio|decathlon)' THEN RETURN 'shopping'; END IF;
  IF m ~ '(pvr|inox|bookmyshow)' THEN RETURN 'entertainment'; END IF;
  IF m ~ '(apollo|medplus|1mg|pharmeasy|lenskart)' THEN RETURN 'health'; END IF;
  IF m ~ '(lic|hdfc life|max life)' THEN RETURN 'insurance'; END IF;
  IF m ~ '(sip|groww|zerodha|upstox)' THEN RETURN 'investment'; END IF;
  RETURN 'others';
END;
$$;

-- ============================================================
-- pg_net for HTTP calls from pg_cron
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
