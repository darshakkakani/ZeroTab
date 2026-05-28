import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/accounts\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // GET /accounts/summary
  if (method === "GET" && pathParts[0] === "summary") {
    const { data: accounts } = await supabaseAdmin
      .from("accounts").select("*").eq("user_id", user.id).eq("is_active", true);
    const { data: mf } = await supabaseAdmin
      .from("mf_holdings").select("current_value").eq("user_id", user.id);

    const bankBalance = (accounts ?? [])
      .filter((a: any) => ["savings", "current", "fd"].includes(a.account_type))
      .reduce((s: number, a: any) => s + (a.current_balance ?? 0), 0);
    const creditCardDebt = (accounts ?? [])
      .filter((a: any) => a.account_type === "credit_card")
      .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
    const loanOutstanding = (accounts ?? [])
      .filter((a: any) => a.account_type === "loan")
      .reduce((s: number, a: any) => s + Math.abs(a.current_balance ?? 0), 0);
    const mfValue = (mf ?? []).reduce((s: number, h: any) => s + (h.current_value ?? 0), 0);
    const netWorth = bankBalance + mfValue - creditCardDebt - loanOutstanding;

    return jsonResponse({ netWorth, bankBalance, creditCardDebt, loanOutstanding, mfValue, accounts });
  }

  // GET /accounts
  if (method === "GET" && pathParts.length === 0) {
    const { data, error } = await supabaseAdmin
      .from("accounts").select("*")
      .eq("user_id", user.id).eq("is_active", true)
      .order("account_type");
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // POST /accounts
  if (method === "POST" && pathParts.length === 0) {
    const body = await req.json();
    const { data, error } = await supabaseAdmin
      .from("accounts")
      .insert({ ...body, user_id: user.id, currency: "INR" })
      .select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data, 201);
  }

  // POST /accounts/:id/adjust-balance
  if (method === "POST" && pathParts.length === 2 && pathParts[1] === "adjust-balance") {
    const id = pathParts[0];
    const { balance } = await req.json();
    const { data, error } = await supabaseAdmin
      .from("accounts")
      .update({ current_balance: balance, last_synced_at: new Date().toISOString() })
      .eq("id", id).eq("user_id", user.id)
      .select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // PATCH /accounts/:id
  if (method === "PATCH" && pathParts.length === 1) {
    const id = pathParts[0];
    const updates = await req.json();
    const { data, error } = await supabaseAdmin
      .from("accounts").update(updates)
      .eq("id", id).eq("user_id", user.id)
      .select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // DELETE /accounts/:id — soft delete
  if (method === "DELETE" && pathParts.length === 1) {
    const id = pathParts[0];
    await supabaseAdmin
      .from("accounts").update({ is_active: false })
      .eq("id", id).eq("user_id", user.id);
    return jsonResponse({ ok: true });
  }

  return errorResponse("Not found", 404);
});
