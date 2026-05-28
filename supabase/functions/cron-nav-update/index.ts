import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { jsonResponse, errorResponse } from "../_shared/cors.ts";

async function fetchCurrentNav(schemeCode: string): Promise<number | null> {
  try {
    const res = await fetch(`https://api.mfapi.in/mf/${schemeCode}`, {
      headers: { "User-Agent": "ZeroTab/1.0" },
      signal: AbortSignal.timeout(8000),
    });
    const json = await res.json();
    const latest = json?.data?.[0]?.nav;
    return latest ? parseFloat(latest) : null;
  } catch { return null; }
}

serve(async (req: Request) => {
  // Verify this is called by pg_cron or with service key
  const authHeader = req.headers.get("Authorization");
  const serviceKey = Deno.env.get("CRON_SECRET") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (authHeader !== `Bearer ${serviceKey}`) {
    return errorResponse("Unauthorized", 401);
  }

  console.log("[NAV Cron] Starting daily NAV update...");

  const { data: holdings } = await supabaseAdmin
    .from("mf_holdings").select("id, user_id, scheme_code, units, invested_amount")
    .not("scheme_code", "is", null);

  if (!holdings?.length) return jsonResponse({ ok: true, updated: 0 });

  const schemeMap = new Map<string, number>();
  const uniqueCodes = [...new Set(holdings.map((h: any) => h.scheme_code).filter(Boolean))];

  for (let i = 0; i < uniqueCodes.length; i += 20) {
    const batch = uniqueCodes.slice(i, i + 20);
    await Promise.all(batch.map(async (code: string) => {
      const nav = await fetchCurrentNav(code);
      if (nav) schemeMap.set(code, nav);
    }));
    await new Promise((r) => setTimeout(r, 500));
  }

  let updated = 0;
  for (const holding of holdings) {
    const nav = schemeMap.get(holding.scheme_code);
    if (!nav) continue;
    const currentValue = (holding.units ?? 0) * nav;
    await supabaseAdmin.from("mf_holdings").update({
      current_nav: nav, current_value: currentValue, last_updated: new Date().toISOString(),
    }).eq("id", holding.id);
    updated++;
  }

  console.log(`[NAV Cron] Updated ${updated} holdings`);
  return jsonResponse({ ok: true, updated });
});
