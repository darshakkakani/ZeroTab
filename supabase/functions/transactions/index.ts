import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { autoCategory } from "../_shared/categories.ts";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/transactions\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // GET /transactions/summary
  if (method === "GET" && pathParts[0] === "summary") {
    const params = url.searchParams;
    const now = new Date();
    const m = params.get("month") ? parseInt(params.get("month")!) : now.getMonth() + 1;
    const y = params.get("year") ? parseInt(params.get("year")!) : now.getFullYear();
    const from = `${y}-${String(m).padStart(2, "0")}-01`;
    const to = new Date(y, m, 0).toISOString().split("T")[0];

    const { data } = await supabaseAdmin
      .from("transactions").select("category, amount, type")
      .eq("user_id", user.id).gte("txn_date", from).lte("txn_date", to);

    const byCategory: Record<string, number> = {};
    let totalSpend = 0, totalIncome = 0;
    for (const t of data ?? []) {
      if (t.type === "debit") {
        byCategory[t.category ?? "others"] = (byCategory[t.category ?? "others"] ?? 0) + t.amount;
        totalSpend += t.amount;
      } else {
        totalIncome += t.amount;
      }
    }
    return jsonResponse({ byCategory, totalSpend, totalIncome, month: m, year: y });
  }

  // GET /transactions/cashflow
  if (method === "GET" && pathParts[0] === "cashflow") {
    const months = parseInt(url.searchParams.get("months") ?? "6");
    const result: { month: string; income: number; spend: number }[] = [];

    for (let i = months - 1; i >= 0; i--) {
      const d = new Date();
      d.setMonth(d.getMonth() - i);
      const y = d.getFullYear();
      const m = d.getMonth() + 1;
      const from = `${y}-${String(m).padStart(2, "0")}-01`;
      const to = new Date(y, m, 0).toISOString().split("T")[0];

      const { data } = await supabaseAdmin
        .from("transactions").select("amount, type")
        .eq("user_id", user.id).gte("txn_date", from).lte("txn_date", to);

      const income = (data ?? []).filter((t: any) => t.type === "credit").reduce((s: number, t: any) => s + t.amount, 0);
      const spend = (data ?? []).filter((t: any) => t.type === "debit").reduce((s: number, t: any) => s + t.amount, 0);
      result.push({ month: `${y}-${String(m).padStart(2, "0")}`, income, spend });
    }
    return jsonResponse(result);
  }

  // POST /transactions/recategorize
  if (method === "POST" && pathParts[0] === "recategorize") {
    const { data: transactions } = await supabaseAdmin
      .from("transactions").select("id, merchant, category").eq("user_id", user.id);

    let fixed = 0;
    for (const txn of transactions ?? []) {
      if (!txn.merchant) continue;
      const suggested = autoCategory(txn.merchant);
      if (suggested !== txn.category) {
        const { error } = await supabaseAdmin
          .from("transactions").update({ category: suggested })
          .eq("id", txn.id).eq("user_id", user.id);
        if (!error) fixed++;
      }
    }
    return jsonResponse({ fixed });
  }

  // GET /transactions
  if (method === "GET" && pathParts.length === 0) {
    const params = url.searchParams;
    const limit = Math.min(parseInt(params.get("limit") ?? "50"), 200);
    const offset = parseInt(params.get("offset") ?? "0");

    let query = supabaseAdmin
      .from("transactions").select("*", { count: "exact" })
      .eq("user_id", user.id)
      .order("txn_date", { ascending: false })
      .range(offset, offset + limit - 1);

    if (params.get("from")) query = query.gte("txn_date", params.get("from")!);
    if (params.get("to")) query = query.lte("txn_date", params.get("to")!);
    if (params.get("category")) query = query.eq("category", params.get("category")!);
    if (params.get("account_id")) query = query.eq("account_id", params.get("account_id")!);
    if (params.get("search")) query = query.ilike("merchant", `%${params.get("search")}%`);

    const { data, error, count } = await query;
    if (error) return errorResponse(error.message);
    return jsonResponse({ data, total: count, limit, offset });
  }

  // POST /transactions
  if (method === "POST" && pathParts.length === 0) {
    const body = await req.json();
    const userId = user.id;

    let accountId: string = body.account_id;
    if (!accountId) {
      await supabaseAdmin.from("users").upsert({
        id: userId, phone: user.phone || "", last_active: new Date().toISOString(),
      }, { onConflict: "id" });

      const { data: existing } = await supabaseAdmin
        .from("accounts").select("id")
        .eq("user_id", userId).eq("source_type", "manual").maybeSingle();

      if (existing) {
        accountId = existing.id;
      } else {
        const { data: wallet, error: walletErr } = await supabaseAdmin
          .from("accounts").insert({
            user_id: userId, source_type: "manual",
            institution_name: "Manual Wallet", account_type: "savings",
            masked_number: "MANUAL", current_balance: 0, currency: "INR", is_active: true,
          }).select("id").single();
        if (walletErr) return errorResponse(`Could not create wallet: ${walletErr.message}`);
        accountId = wallet.id;
      }
    }

    const payload: any = {
      ...body,
      account_id: accountId,
      user_id: userId,
      source: "manual",
      is_recurring: body.is_recurring ?? false,
      description: body.description ?? body.merchant ?? "",
      merchant: body.merchant ?? body.description ?? "Manual entry",
    };
    if (!payload.category && payload.merchant) {
      payload.category = autoCategory(payload.merchant);
    }

    const { data, error } = await supabaseAdmin
      .from("transactions").insert(payload).select().single();
    if (error) return errorResponse(error.message);

    try {
      const { data: acc } = await supabaseAdmin
        .from("accounts").select("current_balance").eq("id", accountId).single();
      if (acc) {
        const delta = payload.type === "credit" ? payload.amount : -payload.amount;
        await supabaseAdmin.from("accounts")
          .update({ current_balance: (acc.current_balance ?? 0) + delta })
          .eq("id", accountId);
      }
    } catch { /* non-fatal */ }

    return jsonResponse(data, 201);
  }

  // PATCH /transactions/:id
  if (method === "PATCH" && pathParts.length === 1) {
    const id = pathParts[0];
    const body = await req.json();

    const { data: existing } = await supabaseAdmin
      .from("transactions").select("*").eq("id", id).eq("user_id", user.id).single();
    if (!existing) return errorResponse("Transaction not found", 404);

    const { data, error } = await supabaseAdmin
      .from("transactions").update(body).eq("id", id).eq("user_id", user.id).select().single();
    if (error) return errorResponse(error.message);
    return jsonResponse(data);
  }

  // DELETE /transactions/:id
  if (method === "DELETE" && pathParts.length === 1) {
    const id = pathParts[0];

    const { data: existing } = await supabaseAdmin
      .from("transactions").select("*").eq("id", id).eq("user_id", user.id).single();
    if (!existing) return errorResponse("Transaction not found", 404);

    const { error } = await supabaseAdmin
      .from("transactions").delete().eq("id", id).eq("user_id", user.id);
    if (error) return errorResponse(error.message);

    try {
      const { data: acc } = await supabaseAdmin
        .from("accounts").select("current_balance").eq("id", existing.account_id).single();
      if (acc) {
        const delta = existing.type === "credit" ? -existing.amount : existing.amount;
        await supabaseAdmin.from("accounts")
          .update({ current_balance: (acc.current_balance ?? 0) + delta })
          .eq("id", existing.account_id);
      }
    } catch { /* non-fatal */ }

    return new Response(null, { status: 204, headers: { "Access-Control-Allow-Origin": "*" } });
  }

  return errorResponse("Not found", 404);
});
