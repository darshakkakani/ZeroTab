import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { getUser, unauthorized } from "../_shared/auth.ts";
import { handleCors, jsonResponse, errorResponse } from "../_shared/cors.ts";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const user = await getUser(req);
  if (!user) return unauthorized();

  const method = req.method;
  const userId = user.id;

  // DELETE /demo/seed
  if (method === "DELETE") {
    try {
      await supabaseAdmin.from("transactions").delete().eq("user_id", userId).eq("raw_sms_text", "ZEROTAB_DEMO");
      await supabaseAdmin.from("mf_holdings").delete().eq("user_id", userId).in("folio_number", ["ZT-DEMO-001", "ZT-DEMO-002", "ZT-DEMO-003"]);
      await supabaseAdmin.from("accounts").delete().eq("user_id", userId).contains("metadata", { demo: true });
      return jsonResponse({ ok: true });
    } catch (err: any) {
      return errorResponse(err?.message ?? String(err));
    }
  }

  // POST /demo/seed
  if (method === "POST") {
    try {
      await supabaseAdmin.from("users").upsert({
        id: userId, phone: user.phone || "",
        financial_archetype: "BALANCED_WEALTH_BUILDER", last_active: new Date().toISOString(),
      }, { onConflict: "id" });

      // Clear existing demo data
      await supabaseAdmin.from("transactions").delete().eq("user_id", userId).eq("raw_sms_text", "ZEROTAB_DEMO");
      await supabaseAdmin.from("mf_holdings").delete().eq("user_id", userId).in("folio_number", ["ZT-DEMO-001", "ZT-DEMO-002", "ZT-DEMO-003"]);
      await supabaseAdmin.from("accounts").delete().eq("user_id", userId).contains("metadata", { demo: true });

      // Accounts
      const { data: accounts, error: accErr } = await supabaseAdmin.from("accounts").insert([
        { user_id: userId, source_type: "aa_bank", institution_name: "State Bank of India", account_type: "savings", masked_number: "****4821", current_balance: 125480.50, currency: "INR", is_active: true, metadata: { demo: true } },
        { user_id: userId, source_type: "aa_bank", institution_name: "HDFC Bank", account_type: "savings", masked_number: "****3302", current_balance: 42300.00, currency: "INR", is_active: true, metadata: { demo: true } },
        { user_id: userId, source_type: "aa_bank", institution_name: "HDFC Bank", account_type: "credit_card", masked_number: "****9944", current_balance: -38500.00, credit_limit: 300000, currency: "INR", is_active: true, metadata: { demo: true } },
        { user_id: userId, source_type: "aa_bank", institution_name: "ICICI Bank", account_type: "credit_card", masked_number: "****1122", current_balance: -12200.00, credit_limit: 200000, currency: "INR", is_active: true, metadata: { demo: true } },
        { user_id: userId, source_type: "aa_bank", institution_name: "HDFC Bank", account_type: "loan", masked_number: "HL-190042", current_balance: -1850000.00, currency: "INR", is_active: true, metadata: { demo: true } },
        { user_id: userId, source_type: "aa_bank", institution_name: "SBI Mutual Fund", account_type: "fd", masked_number: "FD-9214", current_balance: 100000.00, currency: "INR", is_active: true, metadata: { demo: true } },
      ]).select();
      if (accErr) throw new Error(`accounts insert failed: ${accErr.message}`);

      const aid = accounts![0].id;
      const DEMO_TAG = "ZEROTAB_DEMO";
      const d = (date: string, merchant: string, amount: number, category: string, desc?: string) =>
        ({ user_id: userId, account_id: aid, txn_date: date, amount, type: "debit", category, merchant, description: desc ?? merchant, source: "manual", raw_sms_text: DEMO_TAG, is_recurring: false });
      const c = (date: string, merchant: string, amount: number, category: string) =>
        ({ user_id: userId, account_id: aid, txn_date: date, amount, type: "credit", category, merchant, description: merchant, source: "manual", raw_sms_text: DEMO_TAG, is_recurring: false });

      const txns = [
        c("2026-05-01", "Salary — Tata Consultancy Services", 95000, "income"),
        d("2026-05-02", "HDFC Home Loan EMI", 22500, "emi", "Monthly home loan EMI"),
        d("2026-05-02", "SBI Life Insurance", 2800, "insurance", "Monthly premium"),
        d("2026-05-03", "Big Bazaar", 4320, "grocery", "Monthly grocery run"),
        d("2026-05-04", "Zomato", 680, "food_delivery", "Dinner - Biryani House"),
        d("2026-05-05", "Swiggy", 420, "food_delivery", "Lunch order"),
        d("2026-05-06", "BPCL Fuel Station", 2800, "fuel"),
        d("2026-05-07", "Netflix", 649, "subscriptions", "Monthly plan"),
        d("2026-05-08", "Spotify", 119, "subscriptions"),
        d("2026-05-09", "Meesho", 1299, "shopping", "Kurta set"),
        d("2026-05-10", "Myntra", 2349, "shopping", "Nike shoes sale"),
        d("2026-05-11", "BESCOM Electricity", 1840, "utilities", "May electricity bill"),
        d("2026-05-12", "Airtel Postpaid", 699, "utilities", "Mobile + broadband"),
        d("2026-05-13", "Apollo Pharmacy", 870, "health", "Monthly medicines"),
        d("2026-05-17", "SIP — Parag Parikh Flexi Cap", 5000, "investment", "Monthly SIP auto-debit"),
        d("2026-05-18", "SIP — Axis Bluechip", 3000, "investment", "Monthly SIP auto-debit"),
        c("2026-04-01", "Salary — Tata Consultancy Services", 95000, "income"),
        c("2026-04-15", "Freelance Payment — Toptal", 18000, "income"),
        d("2026-04-02", "HDFC Home Loan EMI", 22500, "emi"),
        d("2026-04-03", "Big Bazaar", 5100, "grocery"),
        d("2026-04-04", "Swiggy", 540, "food_delivery"),
        d("2026-04-05", "Zomato", 890, "food_delivery"),
        d("2026-04-06", "BPCL Fuel Station", 3100, "fuel"),
        d("2026-04-07", "Amazon", 3499, "shopping", "Philips trimmer"),
        d("2026-04-08", "BESCOM Electricity", 2100, "utilities"),
        d("2026-04-10", "Netflix", 649, "subscriptions"),
        d("2026-04-17", "SIP — Parag Parikh Flexi Cap", 5000, "investment"),
        d("2026-04-18", "SIP — Axis Bluechip", 3000, "investment"),
        c("2026-03-01", "Salary — Tata Consultancy Services", 95000, "income"),
        c("2026-03-31", "Annual Bonus", 50000, "income"),
        d("2026-03-02", "HDFC Home Loan EMI", 22500, "emi"),
        d("2026-03-03", "Big Bazaar", 4800, "grocery"),
        d("2026-03-06", "Netflix", 649, "subscriptions"),
        d("2026-03-08", "Flipkart", 5299, "shopping", "Holi sale - clothing"),
        d("2026-03-15", "SIP — Parag Parikh Flexi Cap", 5000, "investment"),
        d("2026-03-16", "SIP — Axis Bluechip", 3000, "investment"),
      ];

      const { error: txnErr } = await supabaseAdmin.from("transactions").insert(txns);
      if (txnErr) throw new Error(`transactions insert failed: ${txnErr.message}`);

      const { error: mfErr } = await supabaseAdmin.from("mf_holdings").insert([
        { user_id: userId, folio_number: "ZT-DEMO-001", scheme_code: "122639", scheme_name: "Parag Parikh Flexi Cap Fund - Direct Plan", amc_name: "PPFAS Mutual Fund", units: 142.456, avg_nav: 63.52, current_nav: 78.34, invested_amount: 90000, current_value: 111584.15, xirr: 18.4, last_updated: new Date().toISOString() },
        { user_id: userId, folio_number: "ZT-DEMO-002", scheme_code: "120503", scheme_name: "Axis Bluechip Fund - Direct Plan", amc_name: "Axis Mutual Fund", units: 218.33, avg_nav: 45.80, current_nav: 52.20, invested_amount: 60000, current_value: 71552.82, xirr: 11.2, last_updated: new Date().toISOString() },
        { user_id: userId, folio_number: "ZT-DEMO-003", scheme_code: "119551", scheme_name: "Mirae Asset Large Cap Fund - Direct Plan", amc_name: "Mirae Asset", units: 309.87, avg_nav: 80.25, current_nav: 93.40, invested_amount: 42000, current_value: 48942.00, xirr: 16.8, last_updated: new Date().toISOString() },
      ]);
      if (mfErr) throw new Error(`mf_holdings insert failed: ${mfErr.message}`);

      return jsonResponse({ ok: true, seeded: { accounts: 6, transactions: txns.length, mf_holdings: 3 } });
    } catch (err: any) {
      return errorResponse(err?.message ?? String(err));
    }
  }

  return errorResponse("Method not allowed", 405);
});
