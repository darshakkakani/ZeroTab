import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabaseUrl  = process.env.SUPABASE_URL!;
const supabaseAnon = process.env.SUPABASE_ANON_KEY!;
const supabaseSvc  = process.env.SUPABASE_SERVICE_KEY!;

// Client for user-scoped operations (respects RLS)
export const supabase = createClient(supabaseUrl, supabaseAnon);

// Service-role client for backend jobs (bypasses RLS)
export const supabaseAdmin = createClient(supabaseUrl, supabaseSvc, {
  auth: { autoRefreshToken: false, persistSession: false }
});
