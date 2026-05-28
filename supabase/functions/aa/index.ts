import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

const FINVU_BASE_URL = Deno.env.get("FINVU_BASE_URL") ?? "https://aa.sandbox.finvu.in/consentapi";
const FINVU_API_KEY = Deno.env.get("FINVU_CLIENT_API_KEY") ?? "";
const FINVU_FIU_ENTITY = Deno.env.get("FINVU_FIU_ENTITY_ID") ?? "";

const FI_TYPES = ["DEPOSIT", "TERM_DEPOSIT", "RECURRING_DEPOSIT", "MUTUAL_FUNDS", "INSURANCE_POLICIES", "LOAN"];

function classifyCategory(merchant: string): string {
  const m = merchant.toLowerCase();
  const CATEGORY_MAP: [RegExp, string][] = [
    [/zomato|swiggy|blinkit|zepto|dunzo|uber.?eat|food.*panda/i, "food_delivery"],
    [/restaurant|cafe|dhaba|eatery|biryani|pizza|burger/i, "dining"],
    [/amazon|flipkart|myntra|ajio|nykaa|meesho|snapdeal/i, "shopping"],
    [/netflix|prime|hotstar|zee5|sony.*liv|jio.*cinema|spotify|youtube.*premium/i, "subscriptions"],
    [/uber|ola|rapido|bounce|yulu/i, "transport"],
    [/irctc|makemytrip|goibibo|cleartrip|easemytrip/i, "travel"],
    [/apollo|pharmeasy|1mg|medplus|netmeds|fortis|aiims|hospital|clinic/i, "health"],
    [/airtel|vodafone|jio|bsnl|tata.*sky|recharge/i, "utilities"],
    [/sip|mf|mutual|groww|zerodha|kite|coin|paytm.*money|smallcase/i, "investments"],
    [/emi|loan.*repay|home.*loan|car.*loan|personal.*loan/i, "emi"],
    [/salary|credit.*salary|payroll/i, "income"],
    [/petrol|diesel|fuel|hp.*petrol|bpcl|iocl/i, "fuel"],
  ];
  for (const [pattern, category] of CATEGORY_MAP) { if (pattern.test(m)) return category; }
  return "others";
}

function extractMerchant(narration: string): string {
  return narration.replace(/^(UPI[-/]|IMPS[-/]|NEFT[-/]|RTGS[-/]|ATW[-/]|POS[-/]|EMI[-/])/i, "")
    .split("/")[0].split("-")[0].trim().slice(0, 50);
}

function mapFIType(fiType: string): string {
  const map: Record<string, string> = {
    DEPOSIT: "savings", TERM_DEPOSIT: "fd", RECURRING_DEPOSIT: "fd",
    MUTUAL_FUNDS: "mf", INSURANCE_POLICIES: "insurance", LOAN: "loan",
  };
  return map[fiType] ?? "savings";
}

async function fetchAAData(userId: string, consentHandle: string) {
  const { data: consent } = await supabaseAdmin.from("consents").select("*")
    .eq("user_id", userId).eq("consent_handle", consentHandle).single();
  if (!consent || consent.consent_status !== "active") throw new Error("No active consent");

  const sessionRes = await fetch(`${FINVU_BASE_URL}/FI/request`, {
    method: "POST",
    headers: { "client_api_key": FINVU_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      ver: "1.1.2", timestamp: new Date().toISOString(), txnid: `ZT-DS-${Date.now()}`,
      FIDataRange: { from: new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString(), to: new Date().toISOString() },
      Consent: { id: consentHandle, digitalSignature: "sandbox_sig" },
    }),
  });
  const sessionData = await sessionRes.json();
  const sessionId = sessionData?.sessionId ?? sessionData?.SessionID;
  if (!sessionId) throw new Error("Failed to create FI data session");

  let fiData: any = null;
  for (let i = 0; i < 10; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    const fetchRes = await fetch(`${FINVU_BASE_URL}/FI/fetch/${sessionId}`, { headers: { "client_api_key": FINVU_API_KEY } });
    const fetchData = await fetchRes.json();
    if (fetchData?.FI?.length > 0) { fiData = fetchData.FI; break; }
  }
  if (!fiData) throw new Error("FI data fetch timed out");

  for (const fi of fiData) {
    const fipId = fi.fipID ?? "";
    for (const acc of fi.account ?? []) {
      const txnData = acc.Transactions?.Transaction ?? [];
      const accountPayload = {
        user_id: userId, source_type: "aa_bank", institution_name: fipId,
        account_type: mapFIType(fi.fiType), masked_number: acc.maskedAccNumber?.slice(-4) ?? null,
        current_balance: parseFloat(acc.Summary?.currentBalance ?? "0"),
        currency: "INR", last_synced_at: new Date().toISOString(), is_active: true,
        metadata: { fipId, consentId: fi.consentId, linkRefNumber: acc.linkRefNumber },
      };
      const { data: upsertedAcc } = await supabaseAdmin.from("accounts")
        .upsert(accountPayload, { onConflict: "user_id,institution_name,masked_number", ignoreDuplicates: false })
        .select("id").single();
      if (!upsertedAcc?.id) continue;

      const txns = txnData.map((t: any) => ({
        account_id: upsertedAcc.id, user_id: userId,
        txn_date: t.valueDate?.split("T")[0] ?? t.transactionTimestamp?.split("T")[0],
        amount: Math.abs(parseFloat(t.amount ?? "0")),
        type: t.type?.toLowerCase() === "credit" ? "credit" : "debit",
        description: t.narration ?? t.description,
        merchant: extractMerchant(t.narration ?? ""),
        category: classifyCategory(extractMerchant(t.narration ?? "")),
        source: "aa",
      }));
      for (let i = 0; i < txns.length; i += 100) {
        await supabaseAdmin.from("transactions").upsert(txns.slice(i, i + 100), { ignoreDuplicates: true });
      }
    }
  }
  await supabaseAdmin.from("accounts").update({ last_synced_at: new Date().toISOString() }).eq("user_id", userId);
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/aa\/?/, "").split("/").filter(Boolean);
  const method = req.method;

  // POST /aa/consent/callback — UNAUTHENTICATED (called by Finvu servers)
  if (method === "POST" && pathParts[0] === "consent" && pathParts[1] === "callback") {
    const body = await req.json();
    const { consentHandle, status } = body;
    const mappedStatus = { ACTIVE: "active", REJECTED: "revoked", REVOKED: "revoked" }[status as string] ?? "expired";
    await supabaseAdmin.from("consents").update({ consent_status: mappedStatus }).eq("consent_handle", consentHandle);

    if (status === "ACTIVE") {
      const { data: consent } = await supabaseAdmin.from("consents").select("user_id").eq("consent_handle", consentHandle).single();
      if (consent?.user_id) {
        try { await fetchAAData(consent.user_id, consentHandle); } catch (e) { console.error("AA fetch failed:", e); }
      }
    }
    return jsonResponse({ ok: true });
  }

  // All other routes require auth
  const user = await getUser(req);
  if (!user) return unauthorized();

  // POST /aa/consent/create
  if (method === "POST" && pathParts[0] === "consent" && pathParts[1] === "create") {
    const body = await req.json();
    const { phoneNumber, fiTypes = FI_TYPES } = body;
    const payload = {
      ver: "1.1.2", timestamp: new Date().toISOString(),
      txnid: `ZT-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      ConsentDetail: {
        consentStart: new Date().toISOString(),
        consentExpiry: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
        consentMode: "VIEW", fetchType: "PERIODIC",
        consentTypes: ["TRANSACTIONS", "SUMMARY", "PROFILE"], fiTypes,
        DataConsumer: { id: FINVU_FIU_ENTITY },
        Customer: { id: `${phoneNumber}@finvu` },
        Purpose: { code: "101", refUri: "https://api.rebit.org.in/aa/purpose/101.xml", text: "Wealth management service", Category: { type: "Financial Reporting" } },
        FIDataRange: { from: new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString(), to: new Date().toISOString() },
        DataLife: { unit: "MONTH", value: 1 }, Frequency: { unit: "DAY", value: 1 },
        DataFilter: [{ type: "TRANSACTIONAMOUNT", operator: ">=", value: "1" }],
      },
    };
    const response = await fetch(`${FINVU_BASE_URL}/Consent`, {
      method: "POST", headers: { "client_api_key": FINVU_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const resData = await response.json();
    const consentHandle = resData?.ConsentHandle ?? resData?.consentHandle;
    const redirectUrl = `https://webview.finvu.in/?consent_handle=${consentHandle}`;
    await supabaseAdmin.from("consents").insert({
      user_id: user.id, aa_provider: "finvu", consent_handle: consentHandle,
      consent_status: "pending", fip_ids: [],
      valid_from: new Date().toISOString(), valid_to: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
    });
    return jsonResponse({ consentHandle, redirectUrl });
  }

  // POST /aa/sync
  if (method === "POST" && pathParts[0] === "sync") {
    const { consentHandle } = await req.json();
    try { await fetchAAData(user.id, consentHandle); } catch (e: any) { return errorResponse(e.message); }
    return jsonResponse({ queued: false });
  }

  // POST /aa/consent/revoke
  if (method === "POST" && pathParts[0] === "consent" && pathParts[1] === "revoke") {
    const { data: consents } = await supabaseAdmin.from("consents").select("*").eq("user_id", user.id).eq("consent_status", "active");
    for (const c of consents ?? []) {
      await supabaseAdmin.from("consents").update({ consent_status: "revoked" }).eq("consent_handle", c.consent_handle);
    }
    await supabaseAdmin.from("accounts").update({ is_active: false }).eq("user_id", user.id).eq("source_type", "aa_bank");
    return jsonResponse({ revoked: consents?.length ?? 0 });
  }

  return errorResponse("Not found", 404);
});
