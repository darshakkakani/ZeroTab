/**
 * ZeroTab — Mutual Fund Service
 * Handles AMFI NAV fetches, CAS PDF parsing, XIRR calculation,
 * and daily NAV update job.
 */
import axios from 'axios';
import pdf from 'pdf-parse';
import xirr from 'xirr';
import { supabaseAdmin } from '../lib/supabase.js';
import { MFHolding } from '../types/index.js';

const MFAPI_BASE = 'https://api.mfapi.in/mf';

// ── NAV fetch ─────────────────────────────────────────────

/** Fetch current NAV for a single scheme */
export async function fetchCurrentNav(schemeCode: string): Promise<number | null> {
  try {
    const { data } = await axios.get(`${MFAPI_BASE}/${schemeCode}`, { timeout: 8000 });
    const latest = data?.data?.[0]?.nav;
    return latest ? parseFloat(latest) : null;
  } catch {
    return null;
  }
}

/** Search schemes by name */
export async function searchSchemes(query: string) {
  const { data } = await axios.get(`${MFAPI_BASE}/search`, {
    params: { q: query },
    timeout: 8000,
  });
  return data ?? [];
}

/** Get full scheme list (~16 000 schemes) */
export async function getAllSchemes() {
  const { data } = await axios.get(MFAPI_BASE, { timeout: 20000 });
  return data ?? [];
}

// ── CAS PDF parser ────────────────────────────────────────

interface CASHolding {
  folioNumber: string;
  schemeName: string;
  amcName: string;
  units: number;
  avgNav: number;
  currentValue: number;
  investedAmount: number;
}

interface CASCashflow {
  date: Date;
  amount: number; // negative = purchase, positive = redemption
}

/** Parse a CAMS/KFintech CAS PDF buffer and return holdings */
export async function parseCasPdf(buffer: Buffer): Promise<CASHolding[]> {
  const { text } = await pdf(buffer);
  const holdings: CASHolding[] = [];

  // Split into folio blocks
  const folioBlocks = text.split(/Folio\s+No[.:]/i).slice(1);

  for (const block of folioBlocks) {
    const folioMatch = block.match(/^\s*([A-Z0-9\/\-]+)/);
    if (!folioMatch) continue;
    const folioNumber = folioMatch[1].trim();

    // AMC name is usually the first line before folio
    const amcMatch   = block.match(/([A-Z][a-zA-Z\s]+(?:Mutual Fund|MF))/);
    const amcName    = amcMatch ? amcMatch[1].trim() : 'Unknown AMC';

    // Each scheme within a folio
    const schemeMatches = block.matchAll(
      /Scheme[:\s]+([^\n]+)\n[\s\S]*?Units\s*:\s*([\d,.]+)[\s\S]*?Avg[.\s]*Cost\s*:\s*([\d,.]+)[\s\S]*?Market\s*Value\s*:\s*([\d,.]+)/gi
    );

    for (const m of schemeMatches) {
      const units         = parseFloat(m[2].replace(/,/g, ''));
      const avgNav        = parseFloat(m[3].replace(/,/g, ''));
      const currentValue  = parseFloat(m[4].replace(/,/g, ''));
      const investedAmount = units * avgNav;

      holdings.push({
        folioNumber,
        schemeName:    m[1].trim(),
        amcName,
        units,
        avgNav,
        currentValue,
        investedAmount,
      });
    }
  }

  // Fallback: simpler regex for different CAS formats
  if (holdings.length === 0) {
    const simpleMatches = text.matchAll(
      /([A-Z][^\n]{10,80}(?:Fund|Growth|Dividend)[^\n]*)\n[^\n]*?(\d[\d,]+\.\d{3})\s+(\d[\d,]+\.\d{4})\s+(\d[\d,]+\.\d{2})/gim
    );
    let folio = 'UNKNOWN';
    const folioLine = text.match(/Folio[^:]*:\s*([A-Z0-9\/]+)/i);
    if (folioLine) folio = folioLine[1];

    for (const m of simpleMatches) {
      const units        = parseFloat(m[2].replace(/,/g, ''));
      const avgNav       = parseFloat(m[3].replace(/,/g, ''));
      const currentValue = parseFloat(m[4].replace(/,/g, ''));
      holdings.push({
        folioNumber:     folio,
        schemeName:      m[1].trim(),
        amcName:         'Unknown AMC',
        units,
        avgNav,
        currentValue,
        investedAmount:  units * avgNav,
      });
    }
  }

  return holdings;
}

/** Fuzzy-match a scheme name to an AMFI scheme code */
export async function matchSchemeCode(schemeName: string): Promise<string | null> {
  try {
    const results = await searchSchemes(schemeName.split(' ').slice(0, 4).join(' '));
    if (results.length === 0) return null;
    // Return the best match (first result from AMFI search)
    return String(results[0].schemeCode ?? results[0].id ?? null);
  } catch {
    return null;
  }
}

// ── XIRR calculation ──────────────────────────────────────

interface Cashflow {
  date: Date;
  amount: number;
}

/**
 * Calculate XIRR for a set of cashflows.
 * Purchases are negative, redemptions/current value is positive.
 */
export function calculateXirr(cashflows: Cashflow[]): number | null {
  if (cashflows.length < 2) return null;
  try {
    const result = xirr(
      cashflows.map((cf) => ({ amount: cf.amount, when: cf.date }))
    );
    return Math.round(result * 10000) / 10000; // 4 decimal places
  } catch {
    return null;
  }
}

// ── Store CAS holdings to DB ──────────────────────────────

export async function storeCasHoldings(userId: string, holdings: CASHolding[]): Promise<void> {
  for (const h of holdings) {
    const schemeCode = await matchSchemeCode(h.schemeName);
    const currentNav = schemeCode ? await fetchCurrentNav(schemeCode) : null;
    const currentValue = currentNav ? h.units * currentNav : h.currentValue;

    // Simple XIRR: one purchase cashflow + current value
    const cashflows: Cashflow[] = [
      { date: new Date(Date.now() - 365 * 24 * 3600 * 1000), amount: -h.investedAmount },
      { date: new Date(), amount: currentValue },
    ];
    const xirrVal = calculateXirr(cashflows);

    await supabaseAdmin.from('mf_holdings').upsert(
      {
        user_id:         userId,
        folio_number:    h.folioNumber,
        scheme_code:     schemeCode ?? null,
        scheme_name:     h.schemeName,
        amc_name:        h.amcName,
        units:           h.units,
        avg_nav:         h.avgNav,
        current_nav:     currentNav ?? h.avgNav,
        invested_amount: h.investedAmount,
        current_value:   currentValue,
        xirr:            xirrVal,
        last_updated:    new Date().toISOString(),
      },
      { onConflict: 'user_id,folio_number,scheme_name', ignoreDuplicates: false }
    );
  }
}

// ── Daily NAV update job (called by BullMQ worker) ────────

export async function updateAllNavs(): Promise<void> {
  // Get all distinct scheme codes across all users
  const { data: holdings, error } = await supabaseAdmin
    .from('mf_holdings')
    .select('id, user_id, scheme_code, units, invested_amount')
    .not('scheme_code', 'is', null);

  if (error || !holdings?.length) return;

  // Deduplicate scheme codes to avoid redundant API calls
  const schemeMap = new Map<string, number>(); // schemeCode → latestNav
  const uniqueCodes = [...new Set(holdings.map((h) => h.scheme_code).filter(Boolean))];

  // Fetch NAVs in parallel (batches of 20)
  for (let i = 0; i < uniqueCodes.length; i += 20) {
    const batch = uniqueCodes.slice(i, i + 20);
    await Promise.all(
      batch.map(async (code) => {
        const nav = await fetchCurrentNav(code);
        if (nav) schemeMap.set(code, nav);
      })
    );
    await new Promise((r) => setTimeout(r, 500)); // rate-limit courtesy pause
  }

  // Update each holding
  for (const holding of holdings) {
    const nav = schemeMap.get(holding.scheme_code);
    if (!nav) continue;

    const currentValue = holding.units * nav;
    const cashflows: Cashflow[] = [
      { date: new Date(Date.now() - 365 * 24 * 3600 * 1000), amount: -holding.invested_amount },
      { date: new Date(), amount: currentValue },
    ];
    const xirrVal = calculateXirr(cashflows);

    await supabaseAdmin
      .from('mf_holdings')
      .update({
        current_nav:   nav,
        current_value: currentValue,
        xirr:          xirrVal,
        last_updated:  new Date().toISOString(),
      })
      .eq('id', holding.id);
  }
}
