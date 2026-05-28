-- Migration: 002_add_email_support
-- Adds email column to users and makes phone nullable for email-based auth

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS email varchar(255) UNIQUE;

ALTER TABLE public.users
  ALTER COLUMN phone DROP NOT NULL;

-- Index for email lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
