import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

async function fetchLatestNav(schemeCode: string): Promise<number | null> {
  try {
    const res = await fetch(`https://api.mfapi.in/mf/${schemeCode}`, {
      headers: { "User-Agent": "ZeroTab/1.0" },
      signal: AbortSignal.timeout(8000),
    });
    const json = await res.json();
    if (json.status === "SUCCESS" && json.data?.[0]?.nav) {
      return parseFloat(json.data[0].nav);
    }
    return null;
  } catch {
    return null;
  }
}

async function searchSchemes(query: string) {
  try {
    const res = await fetch(`https://api.mfapi.in/mf/search?q=${encodeURIComponent(query)}`, {
      signal: AbortSignal.timeout(8000),
    });
    return await res.json();
  } catch {
    return [];
  }
}

async function matchSchemeCode(schemeName: string): Promise<string | null> {
  try {
    const results = await searchSchemes(schemeName.split(" ").slice(0, 4).join(" "));
    if (!results.length) return null;
    return String(results[0].schemeCode ?? results[0].id ?? null);
  } catch {
    return null;
  }
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/mf\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // GET /mf/search — public, no auth
  if (method === "GET" && pathParts[0] === "search") {
    const q = url.searchParams.get("q");
    if (!q) return errorResponse("q param required", 400);
    const results = await searchSchemes(q);
    return jsonResponse((results ?? []).slice(0, 20));
  }

  // All other routes require auth
  const user = await getUser(req);
  if (!user) return unauthorized();

  // GET /mf/holdings
  if (method === "GET" && pathParts[0] === "holdings" && pathParts.length === 1) {
    const { data, error } = await supabaseAdmin
      .from("mf_holdings").select("*").eq("user_id", user.id)
      .order("current_value", { ascending: false });
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // POST /mf/holdings — manual add
  if (method === "POST" && pathParts[0] === "holdings" && pathParts.length === 1) {
    const body = await req.json();
    const { data, error } = await supabaseAdmin.from("mf_holdings").insert({
      user_id: user.id,
      folio_number: body.folio_number || `MF-MANUAL-${Date.now()}`,
      scheme_code: body.scheme_code ?? "",
      scheme_name: body.scheme_name ?? "",
      amc_name: body.amc_name ?? "",
      units: Number(body.units) || 0,
      avg_nav: Number(body.avg_nav) || 0,
      current_nav: Number(body.current_nav) || Number(body.avg_nav) || 0,
      invested_amount: Number(body.invested_amount) || (Number(body.units) * Number(body.avg_nav)),
      current_value: Number(body.current_value) || (Number(body.units) * (Number(body.current_nav) || Number(body.avg_nav))),
      xirr: Number(body.xirr) || 0,
      last_updated: new Date().toISOString(),
    }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  // PATCH /mf/holdings/:id
  if (method === "PATCH" && pathParts[0] === "holdings" && pathParts.length === 2) {
    const id = pathParts[1];
    const updates: any = { ...(await req.json()), last_updated: new Date().toISOString() };
    if (updates.units != null || updates.current_nav != null) {
      const { data: existing } = await supabaseAdmin
        .from("mf_holdings").select("units,current_nav,avg_nav").eq("id", id).single();
      const units = updates.units ?? existing?.units ?? 0;
      const nav = updates.current_nav ?? existing?.current_nav ?? existing?.avg_nav ?? 0;
      updates.current_value = units * nav;
      if (updates.units != null && updates.avg_nav != null) {
        updates.invested_amount = units * updates.avg_nav;
      }
    }
    const { data, error } = await supabaseAdmin
      .from("mf_holdings").update(updates).eq("id", id).eq("user_id", user.id).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // DELETE /mf/holdings/:id
  if (method === "DELETE" && pathParts[0] === "holdings" && pathParts.length === 2) {
    const id = pathParts[1];
    await supabaseAdmin.from("mf_holdings").delete().eq("id", id).eq("user_id", user.id);
    return jsonResponse({ ok: true });
  }

  // POST /mf/refresh-nav
  if (method === "POST" && pathParts[0] === "refresh-nav") {
    const { data: holdings } = await supabaseAdmin
      .from("mf_holdings").select("id,scheme_code,units")
      .eq("user_id", user.id).not("folio_number", "like", "STOCK-%");

    let updated = 0;
    for (const h of holdings ?? []) {
      if (!h.scheme_code) continue;
      try {
        const nav = await fetchLatestNav(h.scheme_code);
        if (nav != null) {
          await supabaseAdmin.from("mf_holdings").update({
            current_nav: nav,
            current_value: (h.units ?? 0) * nav,
            last_updated: new Date().toISOString(),
          }).eq("id", h.id);
          updated++;
        }
      } catch { /* skip */ }
    }
    return jsonResponse({ ok: true, updated });
  }

  // POST /mf/cas-upload — CAS PDF parsing
  if (method === "POST" && pathParts[0] === "cas-upload") {
    const formData = await req.formData();
    const file = formData.get("file") as File | null;
    if (!file) return errorResponse("No file uploaded", 400);

    const buffer = new Uint8Array(await file.arrayBuffer());
    // Basic CAS PDF text extraction — simplified for edge function
    const textDecoder = new TextDecoder();
    const text = textDecoder.decode(buffer);

    // Try to extract holdings from text patterns
    const holdings: any[] = [];
    const folioBlocks = text.split(/Folio\s+No[.:]/i).slice(1);
    for (const block of folioBlocks) {
      const folioMatch = block.match(/^\s*([A-Z0-9\/\-]+)/);
      if (!folioMatch) continue;
      const folioNumber = folioMatch[1].trim();
      const amcMatch = block.match(/([A-Z][a-zA-Z\s]+(?:Mutual Fund|MF))/);
      const amcName = amcMatch ? amcMatch[1].trim() : "Unknown AMC";
      const schemeMatches = block.matchAll(
        /Scheme[:\s]+([^\n]+)\n[\s\S]*?Units\s*:\s*([\d,.]+)[\s\S]*?Avg[.\s]*Cost\s*:\s*([\d,.]+)[\s\S]*?Market\s*Value\s*:\s*([\d,.]+)/gi
      );
      for (const m of schemeMatches) {
        const units = parseFloat(m[2].replace(/,/g, ""));
        const avgNav = parseFloat(m[3].replace(/,/g, ""));
        const currentValue = parseFloat(m[4].replace(/,/g, ""));
        holdings.push({ folioNumber, schemeName: m[1].trim(), amcName, units, avgNav, currentValue, investedAmount: units * avgNav });
      }
    }

    if (holdings.length === 0) {
      return errorResponse("Could not parse any holdings from PDF", 422);
    }

    for (const h of holdings) {
      const schemeCode = await matchSchemeCode(h.schemeName);
      const currentNav = schemeCode ? await fetchLatestNav(schemeCode) : null;
      const cv = currentNav ? h.units * currentNav : h.currentValue;
      await supabaseAdmin.from("mf_holdings").upsert({
        user_id: user.id, folio_number: h.folioNumber, scheme_code: schemeCode ?? null,
        scheme_name: h.schemeName, amc_name: h.amcName, units: h.units,
        avg_nav: h.avgNav, current_nav: currentNav ?? h.avgNav,
        invested_amount: h.investedAmount, current_value: cv,
        xirr: 0, last_updated: new Date().toISOString(),
      }, { onConflict: "user_id,folio_number,scheme_name", ignoreDuplicates: false });
    }

    return jsonResponse({ imported: holdings.length });
  }

  return errorResponse("Not found", 404);
});

export { fetchLatestNav, searchSchemes };
