/**
 * ZeroTab — Finvu Account Aggregator Service
 * Handles consent creation, data fetch, and normalisation.
 * Uses Finvu TSP sandbox APIs.
 */
import axios from 'axios';
import { supabaseAdmin } from '../lib/supabase.js';
import { Transaction, Account } from '../types/index.js';

const FINVU_BASE_URL    = process.env.FINVU_BASE_URL    ?? 'https://aa.sandbox.finvu.in/consentapi';
const FINVU_API_KEY     = process.env.FINVU_CLIENT_API_KEY ?? '';
const FINVU_FIU_ENTITY  = process.env.FINVU_FIU_ENTITY_ID  ?? '';

// Supported FI types for consent
const FI_TYPES = [
  'DEPOSIT',
  'TERM_DEPOSIT',
  'RECURRING_DEPOSIT',
  'MUTUAL_FUNDS',
  'INSURANCE_POLICIES',
  'LOAN',
];

interface ConsentRequest {
  userId: string;
  phoneNumber: string;
  fiTypes?: string[];
}

interface ConsentResponse {
  consentHandle: string;
  redirectUrl: string;
}

// ── Create consent ────────────────────────────────────────
export async function createConsent(req: ConsentRequest): Promise<ConsentResponse> {
  const { userId, phoneNumber, fiTypes = FI_TYPES } = req;

  // Build Finvu consent request body
  const payload = {
    ver: '1.1.2',
    timestamp: new Date().toISOString(),
    txnid: `ZT-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    ConsentDetail: {
      consentStart: new Date().toISOString(),
      consentExpiry: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
      consentMode: 'VIEW',
      fetchType: 'PERIODIC',
      consentTypes: ['TRANSACTIONS', 'SUMMARY', 'PROFILE'],
      fiTypes,
      DataConsumer: { id: FINVU_FIU_ENTITY },
      Customer: { id: `${phoneNumber}@finvu` },
      Purpose: {
        code: '101',
        refUri: 'https://api.rebit.org.in/aa/purpose/101.xml',
        text: 'Wealth management service',
        Category: { type: 'Financial Reporting' },
      },
      FIDataRange: {
        from: new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString(),
        to: new Date().toISOString(),
      },
      DataLife: { unit: 'MONTH', value: 1 },
      Frequency: { unit: 'DAY', value: 1 },
      DataFilter: [{ type: 'TRANSACTIONAMOUNT', operator: '>=', value: '1' }],
    },
  };

  const response = await axios.post(`${FINVU_BASE_URL}/Consent`, payload, {
    headers: {
      'client_api_key': FINVU_API_KEY,
      'Content-Type': 'application/json',
    },
    timeout: 15_000,
  });

  const consentHandle = response.data?.ConsentHandle ?? response.data?.consentHandle;
  const redirectUrl   = `https://webview.finvu.in/?consent_handle=${consentHandle}`;

  // Persist consent record
  await supabaseAdmin.from('consents').insert({
    user_id:        userId,
    aa_provider:    'finvu',
    consent_handle: consentHandle,
    consent_status: 'pending',
    fip_ids:        [],
    valid_from:     new Date().toISOString(),
    valid_to:       new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
  });

  return { consentHandle, redirectUrl };
}

// ── Handle consent callback ───────────────────────────────
export async function handleConsentCallback(
  consentHandle: string,
  status: 'ACTIVE' | 'REJECTED' | 'REVOKED'
): Promise<void> {
  const mappedStatus = {
    ACTIVE:   'active',
    REJECTED: 'revoked',
    REVOKED:  'revoked',
  }[status] ?? 'expired';

  await supabaseAdmin
    .from('consents')
    .update({ consent_status: mappedStatus })
    .eq('consent_handle', consentHandle);
}

// ── Fetch AA data for a user (called by BullMQ job) ───────
export async function fetchAAData(userId: string, consentHandle: string): Promise<void> {
  // 1. Get active consent
  const { data: consent } = await supabaseAdmin
    .from('consents')
    .select('*')
    .eq('user_id', userId)
    .eq('consent_handle', consentHandle)
    .single();

  if (!consent || consent.consent_status !== 'active') {
    throw new Error(`No active consent found for user ${userId}`);
  }

  // 2. Create data session
  const sessionRes = await axios.post(
    `${FINVU_BASE_URL}/FI/request`,
    {
      ver: '1.1.2',
      timestamp: new Date().toISOString(),
      txnid: `ZT-DS-${Date.now()}`,
      FIDataRange: {
        from: new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString(),
        to: new Date().toISOString(),
      },
      Consent: { id: consentHandle, digitalSignature: 'sandbox_sig' },
    },
    { headers: { 'client_api_key': FINVU_API_KEY } }
  );

  const sessionId = sessionRes.data?.sessionId ?? sessionRes.data?.SessionID;
  if (!sessionId) throw new Error('Failed to create FI data session');

  // 3. Poll for data (max 30s)
  let fiData: any = null;
  for (let i = 0; i < 10; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    const fetchRes = await axios.get(
      `${FINVU_BASE_URL}/FI/fetch/${sessionId}`,
      { headers: { 'client_api_key': FINVU_API_KEY } }
    );
    if (fetchRes.data?.FI?.length > 0) {
      fiData = fetchRes.data.FI;
      break;
    }
  }

  if (!fiData) throw new Error('FI data fetch timed out');

  // 4. Normalise and upsert accounts + transactions
  for (const fi of fiData) {
    await processFIData(userId, fi);
  }

  // 5. Update last_synced for all user accounts
  await supabaseAdmin
    .from('accounts')
    .update({ last_synced_at: new Date().toISOString() })
    .eq('user_id', userId);
}

// ── Parse & upsert a single FIP's data ───────────────────
async function processFIData(userId: string, fi: any): Promise<void> {
  const fipId    = fi.fipID ?? '';
  const accounts = fi.account ?? [];

  for (const acc of accounts) {
    const summary = acc.Profile?.Holders?.Holder?.[0] ?? {};
    const txnData = acc.Transactions?.Transaction ?? [];

    // Upsert account
    const accountPayload: Partial<Account> = {
      user_id:          userId,
      source_type:      'aa_bank',
      institution_name: fipId,
      account_type:     mapFIType(fi.fiType),
      masked_number:    acc.maskedAccNumber?.slice(-4) ?? null,
      current_balance:  parseFloat(acc.Summary?.currentBalance ?? '0'),
      currency:         'INR',
      last_synced_at:   new Date().toISOString(),
      is_active:        true,
      metadata:         { fipId, consentId: fi.consentId, linkRefNumber: acc.linkRefNumber },
    };

    const { data: upsertedAcc } = await supabaseAdmin
      .from('accounts')
      .upsert(accountPayload, {
        onConflict: 'user_id,institution_name,masked_number',
        ignoreDuplicates: false,
      })
      .select('id')
      .single();

    if (!upsertedAcc?.id) continue;

    // Normalise transactions
    const txns: Partial<Transaction>[] = txnData.map((t: any) => ({
      account_id:  upsertedAcc.id,
      user_id:     userId,
      txn_date:    t.valueDate?.split('T')[0] ?? t.transactionTimestamp?.split('T')[0],
      amount:      Math.abs(parseFloat(t.amount ?? '0')),
      type:        t.type?.toLowerCase() === 'credit' ? 'credit' : 'debit',
      description: t.narration ?? t.description,
      merchant:    extractMerchant(t.narration ?? ''),
      category:    classifyCategory(extractMerchant(t.narration ?? '')),
      source:      'aa',
    }));

    if (txns.length > 0) {
      // Batch upsert (100 at a time)
      for (let i = 0; i < txns.length; i += 100) {
        await supabaseAdmin
          .from('transactions')
          .upsert(txns.slice(i, i + 100), { ignoreDuplicates: true });
      }
    }
  }
}

// ── Helpers ───────────────────────────────────────────────
function mapFIType(fiType: string): Account['account_type'] {
  const map: Record<string, Account['account_type']> = {
    DEPOSIT:           'savings',
    TERM_DEPOSIT:      'fd',
    RECURRING_DEPOSIT: 'fd',
    MUTUAL_FUNDS:      'mf',
    INSURANCE_POLICIES:'insurance',
    LOAN:              'loan',
  };
  return map[fiType] ?? 'savings';
}

function extractMerchant(narration: string): string {
  // Strip common prefixes like "UPI-", "IMPS-", "NEFT-"
  return narration
    .replace(/^(UPI[-/]|IMPS[-/]|NEFT[-/]|RTGS[-/]|ATW[-/]|POS[-/]|EMI[-/])/i, '')
    .split('/')[0]
    .split('-')[0]
    .trim()
    .slice(0, 50);
}

export function classifyCategory(merchant: string): string {
  const m = merchant.toLowerCase();
  const CATEGORY_MAP: [RegExp, string][] = [
    [/zomato|swiggy|blinkit|zepto|dunzo|uber.?eat|food.*panda/i, 'food_delivery'],
    [/restaurant|cafe|dhaba|eatery|biryani|pizza|burger/i, 'dining'],
    [/amazon|flipkart|myntra|ajio|nykaa|meesho|snapdeal/i, 'shopping'],
    [/netflix|prime|hotstar|zee5|sony.*liv|jio.*cinema|spotify|youtube.*premium/i, 'subscriptions'],
    [/uber|ola|rapido|bounce|yulu/i, 'transport'],
    [/irctc|makemytrip|goibibo|cleartrip|easemytrip/i, 'travel'],
    [/apollo|pharmeasy|1mg|medplus|netmeds|fortis|aiims|hospital|clinic/i, 'health'],
    [/airtel|vodafone|jio|bsnl|tata.*sky|recharge/i, 'utilities'],
    [/sip|mf|mutual|groww|zerodha|kite|coin|paytm.*money|smallcase/i, 'investments'],
    [/emi|loan.*repay|home.*loan|car.*loan|personal.*loan/i, 'emi'],
    [/salary|credit.*salary|payroll/i, 'income'],
    [/school|college|fees|tuition|byju|unacademy|coursera/i, 'education'],
    [/rent|maintenance|society|electricity|gas|water/i, 'housing'],
    [/petrol|diesel|fuel|hp.*petrol|bpcl|iocl/i, 'fuel'],
  ];

  for (const [pattern, category] of CATEGORY_MAP) {
    if (pattern.test(m)) return category;
  }
  return 'others';
}
