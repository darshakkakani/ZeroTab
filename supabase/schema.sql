-- ══════════════════════════════════════════════════════════════
-- ZeroTab SettleUp — Complete Supabase Schema
-- Run this entire file in Supabase SQL Editor (once)
-- ══════════════════════════════════════════════════════════════

-- ─── 1. Profiles (FCM token + display info) ─────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id         UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name       TEXT,
  phone      TEXT UNIQUE,
  avatar_url TEXT,
  fcm_token  TEXT,
  currency   TEXT DEFAULT 'INR',
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_self" ON public.profiles
  FOR ALL USING (auth.uid() = id);
-- Allow reading other users' names/phones for friend lookup
CREATE POLICY "profiles_read_others" ON public.profiles
  FOR SELECT USING (true);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, name)
  VALUES (new.id, COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── 2. Settle Groups ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_groups (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT,
  currency    TEXT DEFAULT 'INR',
  category    TEXT DEFAULT 'general',  -- trip/home/couple/general
  cover_color TEXT DEFAULT '#7B2FFE',
  created_by  UUID REFERENCES auth.users(id),
  is_archived BOOLEAN DEFAULT false,
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.settle_groups ENABLE ROW LEVEL SECURITY;

-- ─── 3. Group Members ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_group_members (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id     UUID REFERENCES public.settle_groups(id) ON DELETE CASCADE,
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,          -- fallback for non-registered users
  phone        TEXT,
  joined_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(group_id, user_id)
);
ALTER TABLE public.settle_group_members ENABLE ROW LEVEL SECURITY;

-- Helper: is current user a member of a group?
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.settle_group_members
    WHERE group_id = p_group_id AND user_id = auth.uid()
  );
$$;

-- Group RLS (members-only)
CREATE POLICY "groups_member_access" ON public.settle_groups
  FOR ALL USING (public.is_group_member(id));
CREATE POLICY "group_members_access" ON public.settle_group_members
  FOR ALL USING (public.is_group_member(group_id));

-- ─── 4. Group Expenses ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_expenses (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id     UUID REFERENCES public.settle_groups(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  amount       BIGINT NOT NULL,           -- paise (1 INR = 100 paise)
  paid_by      UUID REFERENCES auth.users(id),
  category     TEXT DEFAULT 'general',
  split_mode   TEXT DEFAULT 'EQUAL',      -- EQUAL/EXACT/PERCENTAGE/SHARES
  notes        TEXT,
  receipt_url  TEXT,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  is_settlement BOOLEAN DEFAULT false,
  created_by   UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.settle_expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "expenses_member_access" ON public.settle_expenses
  FOR ALL USING (public.is_group_member(group_id));
ALTER TABLE public.settle_expenses REPLICA IDENTITY FULL;

-- ─── 5. Expense Shares ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_expense_shares (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  expense_id   UUID REFERENCES public.settle_expenses(id) ON DELETE CASCADE,
  member_id    UUID REFERENCES auth.users(id),
  display_name TEXT,
  amount       BIGINT NOT NULL,           -- their share in paise
  percentage   NUMERIC(5,2),
  shares       INT DEFAULT 1,
  is_paid      BOOLEAN DEFAULT false
);
ALTER TABLE public.settle_expense_shares ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shares_member_access" ON public.settle_expense_shares
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.settle_expenses e
      WHERE e.id = expense_id AND public.is_group_member(e.group_id)
    )
  );

-- ─── 6. Individual Splits (friend-to-friend, no group) ──────
CREATE TABLE IF NOT EXISTS public.settle_splits (
  id                    UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_by            UUID REFERENCES auth.users(id),
  participant_user_id   UUID REFERENCES auth.users(id),
  participant_phone     TEXT,
  participant_name      TEXT NOT NULL,
  amount                BIGINT NOT NULL,   -- paise
  description           TEXT,
  split_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  you_owe               BOOLEAN NOT NULL DEFAULT false,
  is_settled            BOOLEAN DEFAULT false,
  settled_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.settle_splits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "splits_own" ON public.settle_splits
  FOR ALL USING (
    auth.uid() = created_by OR auth.uid() = participant_user_id
  );
ALTER TABLE public.settle_splits REPLICA IDENTITY FULL;

-- ─── 7. Activity Feed ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_activities (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id    UUID REFERENCES public.settle_groups(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES auth.users(id),
  action      TEXT NOT NULL,
  expense_id  UUID REFERENCES public.settle_expenses(id) ON DELETE SET NULL,
  metadata    JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.settle_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "activities_member_access" ON public.settle_activities
  FOR SELECT USING (public.is_group_member(group_id));

-- ─── 8. Push Notifications Queue ────────────────────────────
CREATE TABLE IF NOT EXISTS public.settle_notifications (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID REFERENCES auth.users(id) NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  data       JSONB DEFAULT '{}',
  is_read    BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.settle_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications_own" ON public.settle_notifications
  FOR ALL USING (auth.uid() = user_id);

-- ─── 9. Realtime publication ─────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.settle_expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE public.settle_splits;
ALTER PUBLICATION supabase_realtime ADD TABLE public.settle_group_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.settle_notifications;

-- ─── 10. Trigger: Notify group members on new expense ────────
CREATE OR REPLACE FUNCTION public.notify_group_on_expense()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  creator_name TEXT;
  amount_inr   NUMERIC;
BEGIN
  SELECT COALESCE(name, 'Someone') INTO creator_name
  FROM public.profiles WHERE id = NEW.created_by;

  amount_inr := NEW.amount / 100.0;

  INSERT INTO public.settle_notifications (user_id, title, body, data)
  SELECT
    gm.user_id,
    creator_name || ' added an expense',
    '₹' || to_char(amount_inr, 'FM99999999.00') || ' for ' || NEW.title,
    jsonb_build_object(
      'type',       'new_expense',
      'expense_id', NEW.id,
      'group_id',   NEW.group_id
    )
  FROM public.settle_group_members gm
  WHERE gm.group_id = NEW.group_id
    AND gm.user_id  != NEW.created_by;

  -- Activity log
  INSERT INTO public.settle_activities (group_id, user_id, action, expense_id, metadata)
  VALUES (NEW.group_id, NEW.created_by, 'added_expense', NEW.id,
    jsonb_build_object('title', NEW.title, 'amount', NEW.amount));

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_settle_expense_insert ON public.settle_expenses;
CREATE TRIGGER on_settle_expense_insert
  AFTER INSERT ON public.settle_expenses
  FOR EACH ROW WHEN (NOT NEW.is_settlement)
  EXECUTE FUNCTION public.notify_group_on_expense();

-- ─── 11. Trigger: Notify on individual split ─────────────────
CREATE OR REPLACE FUNCTION public.notify_on_split()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  creator_name TEXT;
  amount_inr   NUMERIC;
  recipient    UUID;
BEGIN
  SELECT COALESCE(name, 'Someone') INTO creator_name
  FROM public.profiles WHERE id = NEW.created_by;

  amount_inr := NEW.amount / 100.0;
  recipient  := NEW.participant_user_id;
  IF recipient IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.settle_notifications (user_id, title, body, data)
  VALUES (
    recipient,
    creator_name || ' added a split',
    CASE WHEN NEW.you_owe
      THEN 'You owe ₹' || to_char(amount_inr, 'FM99999999.00') || ' for ' || COALESCE(NEW.description, 'an expense')
      ELSE creator_name || ' owes you ₹' || to_char(amount_inr, 'FM99999999.00')
    END,
    jsonb_build_object('type', 'new_split', 'split_id', NEW.id)
  );
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_settle_split_insert ON public.settle_splits;
CREATE TRIGGER on_settle_split_insert
  AFTER INSERT ON public.settle_splits
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_split();

-- ─── 12. Database Webhook for push notifications ─────────────
-- Run this AFTER creating the push-notification Edge Function.
-- Replace <your-project-ref> and <your-service-role-key> with real values.
--
-- SELECT supabase_functions.http_request(
--   'https://<your-project-ref>.supabase.co/functions/v1/push-notification',
--   'POST',
--   '{"Content-Type":"application/json","Authorization":"Bearer <your-service-role-key>"}',
--   '{}', '5000'
-- );
--
-- Or set this up via Supabase Dashboard → Database → Webhooks:
--   Table: settle_notifications, Event: INSERT, Function: push-notification
