import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

async function fetchStockPrice(symbol: string, exchange: "NSE" | "BSE" = "NSE"): Promise<number | null> {
  const suffix = exchange === "BSE" ? ".BO" : ".NS";
  const ticker = encodeURIComponent(`${symbol.toUpperCase()}${suffix}`);
  try {
    const res = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}?interval=1d&range=1d`,
      { headers: { "User-Agent": "Mozilla/5.0 (compatible; ZeroTab/1.0)", Accept: "application/json" }, signal: AbortSignal.timeout(8000) }
    );
    const json = await res.json();
    return json?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null;
  } catch { return null; }
}

const COMMODITY_TICKER_MAP: Record<string, string> = {
  GOLD: "GC=F", SILVER: "SI=F", CRUDEOIL: "CL=F", NATURALGAS: "NG=F",
  COPPER: "HG=F", ALUMINIUM: "ALI=F", GOLDPETAL: "GC=F",
};

async function fetchUSDINR(): Promise<number> {
  try {
    const res = await fetch("https://query1.finance.yahoo.com/v8/finance/chart/USDINR=X?interval=1d&range=1d",
      { headers: { "User-Agent": "Mozilla/5.0 (compatible; ZeroTab/1.0)" }, signal: AbortSignal.timeout(8000) });
    const json = await res.json();
    return json?.chart?.result?.[0]?.meta?.regularMarketPrice ?? 83.5;
  } catch { return 83.5; }
}

async function fetchCommodityPrice(symbol: string): Promise<number | null> {
  const ticker = COMMODITY_TICKER_MAP[symbol.toUpperCase()];
  if (!ticker) return null;
  try {
    const res = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?interval=1d&range=1d`,
      { headers: { "User-Agent": "Mozilla/5.0 (compatible; ZeroTab/1.0)" }, signal: AbortSignal.timeout(10000) });
    const json = await res.json();
    const usdPrice = json?.chart?.result?.[0]?.meta?.regularMarketPrice;
    if (usdPrice == null) return null;
    const usdInr = await fetchUSDINR();
    return usdPrice * usdInr;
  } catch { return null; }
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/stocks\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // === STOCK ROUTES ===

  if (method === "GET" && pathParts[0] === "holdings" && pathParts.length === 1) {
    const { data, error } = await supabaseAdmin.from("mf_holdings").select("*")
      .eq("user_id", user.id).like("folio_number", "STOCK-%").order("current_value", { ascending: false });
    if (error) return errorResponse(error.message);
    return jsonResponse(data ?? []);
  }

  if (method === "POST" && pathParts[0] === "holdings" && pathParts.length === 1) {
    const body = await req.json();
    const symbol = (body.symbol as string)?.toUpperCase();
    const exchange = (body.exchange as string)?.toUpperCase() === "BSE" ? "BSE" : "NSE";
    const qty = Number(body.qty);
    const avgPrice = Number(body.avg_price);
    if (!symbol || !qty || !avgPrice) return errorResponse("symbol, qty, avg_price are required", 400);

    const currentPrice = (await fetchStockPrice(symbol, exchange as "NSE" | "BSE")) ?? avgPrice;
    const invested = qty * avgPrice;
    const folioNumber = `STOCK-${symbol}-${exchange}`;

    const { data: existing } = await supabaseAdmin.from("mf_holdings").select("id, units, avg_nav, invested_amount")
      .eq("user_id", user.id).eq("folio_number", folioNumber).maybeSingle();

    if (existing) {
      const totalQty = (existing.units ?? 0) + qty;
      const totalCost = (existing.invested_amount ?? 0) + invested;
      const { data, error } = await supabaseAdmin.from("mf_holdings").update({
        units: totalQty, avg_nav: totalCost / totalQty, current_nav: currentPrice,
        invested_amount: totalCost, current_value: totalQty * currentPrice, last_updated: new Date().toISOString(),
      }).eq("id", existing.id).select().single();
      if (error) return errorResponse(error.message);
      return jsonResponse(data);
    }

    const { data, error } = await supabaseAdmin.from("mf_holdings").insert({
      user_id: user.id, folio_number: folioNumber, scheme_code: symbol,
      scheme_name: body.company_name ?? symbol, amc_name: exchange,
      units: qty, avg_nav: avgPrice, current_nav: currentPrice,
      invested_amount: invested, current_value: qty * currentPrice, xirr: 0, last_updated: new Date().toISOString(),
    }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  if (method === "PATCH" && pathParts[0] === "holdings" && pathParts.length === 2) {
    const id = pathParts[1];
    const body = await req.json();
    const { data: existing } = await supabaseAdmin.from("mf_holdings").select("*")
      .eq("id", id).eq("user_id", user.id).like("folio_number", "STOCK-%").single();
    if (!existing) return errorResponse("Holding not found", 404);
    const qty = body.qty != null ? Number(body.qty) : existing.units;
    const avgPrice = body.avg_price != null ? Number(body.avg_price) : existing.avg_nav;
    const currentPrice = existing.current_nav ?? avgPrice;
    const { data, error } = await supabaseAdmin.from("mf_holdings").update({
      units: qty, avg_nav: avgPrice, invested_amount: qty * avgPrice,
      current_value: qty * currentPrice, last_updated: new Date().toISOString(),
      ...(body.company_name ? { scheme_name: body.company_name } : {}),
    }).eq("id", id).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  if (method === "DELETE" && pathParts[0] === "holdings" && pathParts.length === 2) {
    await supabaseAdmin.from("mf_holdings").delete().eq("id", pathParts[1]).eq("user_id", user.id).like("folio_number", "STOCK-%");
    return jsonResponse({ ok: true });
  }

  if (method === "POST" && pathParts[0] === "refresh") {
    const { data: holdings } = await supabaseAdmin.from("mf_holdings").select("id, scheme_code, amc_name, units")
      .eq("user_id", user.id).like("folio_number", "STOCK-%");
    let updated = 0;
    for (const h of holdings ?? []) {
      const exchange = (h.amc_name === "BSE" ? "BSE" : "NSE") as "NSE" | "BSE";
      const price = await fetchStockPrice(h.scheme_code, exchange);
      if (price !== null) {
        await supabaseAdmin.from("mf_holdings").update({ current_nav: price, current_value: (h.units ?? 0) * price, last_updated: new Date().toISOString() }).eq("id", h.id);
        updated++;
      }
    }
    return jsonResponse({ ok: true, updated });
  }

  if (method === "GET" && pathParts[0] === "quote") {
    const symbol = url.searchParams.get("symbol");
    if (!symbol) return errorResponse("symbol param required", 400);
    const exch = (url.searchParams.get("exchange")?.toUpperCase() === "BSE" ? "BSE" : "NSE") as "NSE" | "BSE";
    const price = await fetchStockPrice(symbol, exch);
    if (price === null) return errorResponse(`Could not fetch price for ${symbol.toUpperCase()} on ${exch}`, 404);
    return jsonResponse({ symbol: symbol.toUpperCase(), exchange: exch, price, ts: new Date().toISOString() });
  }

  // === ETF ROUTES ===

  if (method === "GET" && pathParts[0] === "etf" && pathParts[1] === "holdings") {
    const { data, error } = await supabaseAdmin.from("mf_holdings").select("*")
      .eq("user_id", user.id).like("folio_number", "ETF-%").order("current_value", { ascending: false });
    if (error) return errorResponse(error.message);
    return jsonResponse(data ?? []);
  }

  if (method === "POST" && pathParts[0] === "etf" && pathParts[1] === "holdings" && pathParts.length === 2) {
    const body = await req.json();
    const symbol = (body.symbol as string)?.toUpperCase();
    const units = Number(body.units);
    const avgPrice = Number(body.avg_price);
    if (!symbol || !units || !avgPrice) return errorResponse("symbol, units, avg_price are required", 400);
    const currentPrice = (await fetchStockPrice(symbol, "NSE")) ?? avgPrice;
    const folioNumber = `ETF-${symbol}-NSE`;
    const { data: existing } = await supabaseAdmin.from("mf_holdings").select("id, units, avg_nav, invested_amount")
      .eq("user_id", user.id).eq("folio_number", folioNumber).maybeSingle();
    if (existing) {
      const totalUnits = (existing.units ?? 0) + units;
      const totalCost = (existing.invested_amount ?? 0) + units * avgPrice;
      const { data, error } = await supabaseAdmin.from("mf_holdings").update({
        units: totalUnits, avg_nav: totalCost / totalUnits, current_nav: currentPrice,
        invested_amount: totalCost, current_value: totalUnits * currentPrice, last_updated: new Date().toISOString(),
      }).eq("id", existing.id).select().single();
      if (error) return errorResponse(error.message);
      return jsonResponse(data);
    }
    const { data, error } = await supabaseAdmin.from("mf_holdings").insert({
      user_id: user.id, folio_number: folioNumber, scheme_code: symbol,
      scheme_name: body.company_name ?? symbol, amc_name: "NSE",
      units, avg_nav: avgPrice, current_nav: currentPrice,
      invested_amount: units * avgPrice, current_value: units * currentPrice, xirr: 0, last_updated: new Date().toISOString(),
    }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  if (method === "DELETE" && pathParts[0] === "etf" && pathParts[1] === "holdings" && pathParts.length === 3) {
    await supabaseAdmin.from("mf_holdings").delete().eq("id", pathParts[2]).eq("user_id", user.id).like("folio_number", "ETF-%");
    return jsonResponse({ ok: true });
  }

  if (method === "POST" && pathParts[0] === "etf" && pathParts[1] === "refresh") {
    const { data: holdings } = await supabaseAdmin.from("mf_holdings").select("id, scheme_code, units")
      .eq("user_id", user.id).like("folio_number", "ETF-%");
    let updated = 0;
    for (const h of holdings ?? []) {
      const price = await fetchStockPrice(h.scheme_code, "NSE");
      if (price !== null) {
        await supabaseAdmin.from("mf_holdings").update({ current_nav: price, current_value: (h.units ?? 0) * price, last_updated: new Date().toISOString() }).eq("id", h.id);
        updated++;
      }
    }
    return jsonResponse({ ok: true, updated });
  }

  // === COMMODITY ROUTES ===

  if (method === "GET" && pathParts[0] === "commodity" && pathParts[1] === "holdings") {
    const { data, error } = await supabaseAdmin.from("mf_holdings").select("*")
      .eq("user_id", user.id).like("folio_number", "COMM-%").order("current_value", { ascending: false });
    if (error) return errorResponse(error.message);
    return jsonResponse(data ?? []);
  }

  if (method === "POST" && pathParts[0] === "commodity" && pathParts[1] === "holdings" && pathParts.length === 2) {
    const body = await req.json();
    const symbol = (body.symbol as string)?.toUpperCase();
    const qty = Number(body.qty);
    const avgPrice = Number(body.avg_price);
    if (!symbol || !qty || !avgPrice) return errorResponse("symbol, qty, avg_price are required", 400);
    if (!COMMODITY_TICKER_MAP[symbol]) return errorResponse(`Unknown commodity. Supported: ${Object.keys(COMMODITY_TICKER_MAP).join(", ")}`, 400);
    const currentPrice = (await fetchCommodityPrice(symbol)) ?? avgPrice;
    const folioNumber = `COMM-${symbol}`;
    const { data: existing } = await supabaseAdmin.from("mf_holdings").select("id, units, avg_nav, invested_amount")
      .eq("user_id", user.id).eq("folio_number", folioNumber).maybeSingle();
    if (existing) {
      const totalQty = (existing.units ?? 0) + qty;
      const totalCost = (existing.invested_amount ?? 0) + qty * avgPrice;
      const { data, error } = await supabaseAdmin.from("mf_holdings").update({
        units: totalQty, avg_nav: totalCost / totalQty, current_nav: currentPrice,
        invested_amount: totalCost, current_value: totalQty * currentPrice, last_updated: new Date().toISOString(),
      }).eq("id", existing.id).select().single();
      if (error) return errorResponse(error.message);
      return jsonResponse(data);
    }
    const { data, error } = await supabaseAdmin.from("mf_holdings").insert({
      user_id: user.id, folio_number: folioNumber, scheme_code: symbol,
      scheme_name: body.display_name ?? symbol, amc_name: "MCX",
      units: qty, avg_nav: avgPrice, current_nav: currentPrice,
      invested_amount: qty * avgPrice, current_value: qty * currentPrice, xirr: 0, last_updated: new Date().toISOString(),
    }).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  if (method === "DELETE" && pathParts[0] === "commodity" && pathParts[1] === "holdings" && pathParts.length === 3) {
    await supabaseAdmin.from("mf_holdings").delete().eq("id", pathParts[2]).eq("user_id", user.id).like("folio_number", "COMM-%");
    return jsonResponse({ ok: true });
  }

  if (method === "POST" && pathParts[0] === "commodity" && pathParts[1] === "refresh") {
    const { data: holdings } = await supabaseAdmin.from("mf_holdings").select("id, scheme_code, units")
      .eq("user_id", user.id).like("folio_number", "COMM-%");
    let updated = 0;
    for (const h of holdings ?? []) {
      const price = await fetchCommodityPrice(h.scheme_code);
      if (price !== null) {
        await supabaseAdmin.from("mf_holdings").update({ current_nav: price, current_value: (h.units ?? 0) * price, last_updated: new Date().toISOString() }).eq("id", h.id);
        updated++;
      }
    }
    return jsonResponse({ ok: true, updated });
  }

  if (method === "GET" && pathParts[0] === "commodity" && pathParts[1] === "quote") {
    const symbol = url.searchParams.get("symbol")?.toUpperCase();
    if (!symbol) return errorResponse("symbol param required", 400);
    if (!COMMODITY_TICKER_MAP[symbol]) return errorResponse(`Unknown commodity. Supported: ${Object.keys(COMMODITY_TICKER_MAP).join(", ")}`, 400);
    const price = await fetchCommodityPrice(symbol);
    if (price === null) return errorResponse(`Could not fetch price for ${symbol}`, 404);
    return jsonResponse({ symbol, ticker: COMMODITY_TICKER_MAP[symbol], price_inr: price, ts: new Date().toISOString() });
  }

  return errorResponse("Not found", 404);
});
