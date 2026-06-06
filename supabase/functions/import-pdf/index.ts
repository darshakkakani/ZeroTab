// ════════════════════════════════════════════════════════════════
//  ZeroTab — Bank Statement PDF Import Edge Function  (v2)
//
//  ZERO npm dependencies — pure Deno TypeScript text extraction.
//  Eliminates the BOOT_ERROR from npm:pdf-parse which uses Node fs.
//
//  Supports: HDFC, SBI, ICICI, Axis, Standard Chartered + generic
// ════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Pure Deno PDF text extractor ──────────────────────────────
// Reads PDF content streams (BT...ET blocks) without any library.

function decodeOctal(s: string): string {
  return s
    .replace(/\\(\d{3})/g, (_, oct) => String.fromCharCode(parseInt(oct, 8)))
    .replace(/\\n/g, ' ')
    .replace(/\\r/g, '')
    .replace(/\\\\/g, '\\')
    .replace(/\\t/g, ' ')
}

function extractPdfText(bytes: Uint8Array): string {
  // Decode as latin1 (preserves byte values for PDF parsing)
  const raw = new TextDecoder('latin1').decode(bytes)
  const texts: string[] = []

  // Strategy 1: Extract BT...ET text blocks
  const btRe = /BT([\s\S]*?)ET/g
  let block: RegExpExecArray | null
  while ((block = btRe.exec(raw)) !== null) {
    const b = block[1]

    // (text) Tj  and  (text) ' and  (text) "
    const tjRe = /\(([^)]*(?:\\.[^)]*)*)\)\s*(?:Tj|'|")/g
    let m: RegExpExecArray | null
    while ((m = tjRe.exec(b)) !== null) {
      const t = decodeOctal(m[1]).trim()
      if (t.length > 0) texts.push(t)
    }

    // [(text1) n (text2) n ...] TJ
    const tjArrRe = /\[([\s\S]*?)\]\s*TJ/g
    while ((m = tjArrRe.exec(b)) !== null) {
      const inner = m[1]
      const innerRe = /\(([^)]*(?:\\.[^)]*)*)\)/g
      let m2: RegExpExecArray | null
      while ((m2 = innerRe.exec(inner)) !== null) {
        const t = decodeOctal(m2[1]).trim()
        if (t.length > 0) texts.push(t)
      }
    }
  }

  // Strategy 2: Extract from compressed streams (if text blocks empty)
  // Look for readable ASCII text sequences (bank statement data is often uncompressed)
  if (texts.length < 5) {
    const asciiRe = /[ -~]{6,}/g
    let m: RegExpExecArray | null
    while ((m = asciiRe.exec(raw)) !== null) {
      const t = m[0].trim()
      if (t.length >= 8 && !t.startsWith('<<') && !t.startsWith('>>')) {
        texts.push(t)
      }
    }
  }

  return texts.join('\n')
}

// ── Date parser ───────────────────────────────────────────────

function parseDate(raw: string): string | null {
  raw = raw.trim()
  const months: Record<string, string> = {
    jan:'01',feb:'02',mar:'03',apr:'04',may:'05',jun:'06',
    jul:'07',aug:'08',sep:'09',oct:'10',nov:'11',dec:'12',
  }

  // DD/MM/YYYY or DD-MM-YYYY
  const dmy = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/)
  if (dmy) return `${dmy[3]}-${dmy[2].padStart(2,'0')}-${dmy[1].padStart(2,'0')}`

  // DD/MM/YY or DD-MM-YY
  const dmyS = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2})$/)
  if (dmyS) {
    const yr = parseInt(dmyS[3]) > 50 ? `19${dmyS[3]}` : `20${dmyS[3]}`
    return `${yr}-${dmyS[2].padStart(2,'0')}-${dmyS[1].padStart(2,'0')}`
  }

  // DD MMM YYYY or DD MMM YY (Standard Chartered uses YY)
  const dmy3 = raw.match(/^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})$/)
  if (dmy3) {
    const m = months[dmy3[2].toLowerCase()]
    let yr = dmy3[3]
    if (yr.length === 2) yr = parseInt(yr) > 50 ? `19${yr}` : `20${yr}`
    if (m) return `${yr}-${m}-${dmy3[1].padStart(2,'0')}`
  }

  // DD-MMM-YYYY
  const icici = raw.match(/^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/)
  if (icici) {
    const m = months[icici[2].toLowerCase()]
    if (m) return `${icici[3]}-${m}-${icici[1].padStart(2,'0')}`
  }

  return null
}

function parseAmount(raw: string): number {
  return parseFloat(raw.replace(/,/g, '').replace(/[^\d.]/g, '')) || 0
}

// ── Category auto-suggester ───────────────────────────────────
function suggestCategory(d: string): string {
  const dl = d.toLowerCase()
  if (dl.match(/swiggy|zomato|blinkit|zepto|food|restaurant|cafe|pizza|kfc|mcd|burger|dominos/)) return 'food_delivery'
  if (dl.match(/grocery|bigbasket|dmart|jiomart|kirana|supermarket|vegetables|milk|bread/)) return 'grocery'
  if (dl.match(/amazon|flipkart|myntra|meesho|snapdeal|ajio|mall|shop/)) return 'shopping'
  if (dl.match(/emi|loan|hdfc loan|icici loan|sbi loan|bajaj|capital/)) return 'emi'
  if (dl.match(/petrol|diesel|fuel|bpcl|iocl|hpcl|shell/)) return 'fuel'
  if (dl.match(/electricity|water|gas|internet|airtel|jio|bsnl|broadband|recharge/)) return 'utilities'
  if (dl.match(/uber|ola|rapido|metro|irctc|makemytrip|redbus|cab|auto|flight/)) return 'transport'
  if (dl.match(/netflix|spotify|prime|hotstar|zee5|youtube premium|subscription/)) return 'subscriptions'
  if (dl.match(/hospital|pharmacy|medicine|doctor|apollo|medplus|health/)) return 'health'
  if (dl.match(/mutual fund|sip|zerodha|groww|kite|upstox|invest|nifty|bse|nse/)) return 'investment'
  if (dl.match(/insurance|lic|term|sbi life|hdfc life|max life/)) return 'insurance'
  if (dl.match(/salary|payroll|credit|bonus|neft.*cr|imps.*cr/)) return 'income'
  return 'others'
}

// ── Bank-specific parsers ─────────────────────────────────────

interface ParsedTxn {
  date: string; description: string; amount: number;
  type: 'debit' | 'credit'; balance?: number;
}

// HDFC: Date | Narration | Ref | Value Date | Withdrawal | Deposit | Balance
function parseHDFC(lines: string[]): ParsedTxn[] {
  const txns: ParsedTxn[] = []
  const re = /^(\d{2}\/\d{2}\/\d{4})\s+(.+?)\s+\S+\s+\d{2}\/\d{2}\/\d{4}\s+([\d,]+\.\d{2})?\s*([\d,]+\.\d{2})?\s*([\d,]+\.\d{2})/
  for (const line of lines) {
    const m = line.match(re)
    if (!m) continue
    const date = parseDate(m[1])
    if (!date) continue
    const debit  = m[3] ? parseAmount(m[3]) : 0
    const credit = m[4] ? parseAmount(m[4]) : 0
    if (debit === 0 && credit === 0) continue
    txns.push({ date, description: m[2].trim(), amount: debit || credit,
      type: debit > 0 ? 'debit' : 'credit', balance: m[5] ? parseAmount(m[5]) : undefined })
  }
  return txns
}

// SBI: Date | Description | Ref | Debit | Credit | Balance
function parseSBI(lines: string[]): ParsedTxn[] {
  const txns: ParsedTxn[] = []
  const re = /^(\d{2}\/\d{2}\/\d{4}|\d{2}-\d{2}-\d{4})\s+(.+?)\s+\S+\s+([\d,]+\.\d{2})?\s*([\d,]+\.\d{2})?\s*([\d,]+\.\d{2})/
  for (const line of lines) {
    const m = line.match(re)
    if (!m) continue
    const date = parseDate(m[1])
    if (!date) continue
    const debit  = m[3] ? parseAmount(m[3]) : 0
    const credit = m[4] ? parseAmount(m[4]) : 0
    if (debit === 0 && credit === 0) continue
    txns.push({ date, description: m[2].trim(), amount: debit || credit,
      type: debit > 0 ? 'debit' : 'credit', balance: m[5] ? parseAmount(m[5]) : undefined })
  }
  return txns
}

// Standard Chartered: DD MMM YY format, Deposit | Withdrawal | Balance
function parseStanChart(text: string): ParsedTxn[] {
  const txns: ParsedTxn[] = []
  const lines = text.split('\n').map(l => l.trim())
  const dateRe = /(\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4})/
  const amtRe  = /([\d,]+\.\d{2})/g

  for (const line of lines) {
    if (line.length < 15) continue
    const dm = line.match(dateRe)
    if (!dm) continue
    const date = parseDate(dm[1])
    if (!date) continue
    const upper = line.toUpperCase()
    if (upper.includes('BALANCE FORWARD') || upper.includes('OPENING BALANCE')) continue
    const allAmts = [...line.matchAll(amtRe)].map(m => parseAmount(m[1]))
    if (allAmts.length < 1) continue
    const balance = allAmts.length >= 2 ? allAmts[allAmts.length - 1] : undefined
    const amount  = allAmts.length >= 2 ? allAmts[allAmts.length - 2] : allAmts[0]
    if (amount <= 0) continue
    const isCredit = upper.includes('CREDIT') || upper.includes('DEPOSIT') ||
                     upper.includes('NEFT') || upper.includes('SALARY') ||
                     upper.includes('IMPS') || upper.includes('INTEREST')
    const desc = line.replace(dateRe, '').replace(amtRe, '').replace(/\s+/g, ' ').trim()
    txns.push({ date, description: desc.substring(0, 100) || 'Transaction',
      amount, type: isCredit ? 'credit' : 'debit', balance })
  }
  return txns
}

// Generic fallback
function parseGeneric(lines: string[]): ParsedTxn[] {
  const txns: ParsedTxn[] = []
  const dateRe   = /(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4})/
  const amountRe = /([\d,]+\.\d{2})/g
  for (const line of lines) {
    if (line.length < 20) continue
    const dm = line.match(dateRe)
    if (!dm) continue
    const date = parseDate(dm[1])
    if (!date) continue
    const amounts = [...line.matchAll(amountRe)].map(m => parseAmount(m[1]))
    if (amounts.length < 1) continue
    const amount  = amounts.length >= 2 ? amounts[amounts.length - 2] : amounts[0]
    if (amount <= 0 || amount > 10000000) continue
    const upper   = line.toUpperCase()
    const isCredit = upper.includes('CR') || upper.includes('CREDIT') ||
                     upper.includes('DEPOSIT') || upper.includes('SALARY')
    const desc = line.replace(dateRe, '').replace(amountRe, '').replace(/\s+/g, ' ').trim()
    txns.push({ date, description: desc.substring(0, 100) || 'Transaction',
      amount, type: isCredit ? 'credit' : 'debit',
      balance: amounts.length >= 2 ? amounts[amounts.length - 1] : undefined })
  }
  return txns
}

// ── Master parser ─────────────────────────────────────────────
function parseStatement(text: string): ParsedTxn[] {
  const upper = text.toUpperCase()
  const lines = text.split('\n').map(l => l.replace(/\s+/g, ' ').trim()).filter(l => l.length > 10)

  let txns: ParsedTxn[]
  if (upper.includes('STANDARD CHARTERED') || upper.includes('SCBL'))
    txns = parseStanChart(text)
  else if (upper.includes('HDFC BANK'))
    txns = parseHDFC(lines)
  else if (upper.includes('STATE BANK') || upper.includes('SBI'))
    txns = parseSBI(lines)
  else {
    // Try all parsers, pick the winner
    const candidates = [parseStanChart(text), parseHDFC(lines), parseSBI(lines), parseGeneric(lines)]
    txns = candidates.reduce((best, cur) => cur.length > best.length ? cur : best, [])
  }

  // Deduplicate within parsed set
  const seen = new Set<string>()
  return txns.filter(t => {
    const key = `${t.date}:${t.amount}:${t.type}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

// ════════════════════════════════════════════════════════════════
//  Handler
// ════════════════════════════════════════════════════════════════

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return new Response(
      JSON.stringify({ error: 'Missing auth' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !user) return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    const body = await req.json()
    const fileB64: string = body.file_bytes_b64 || ''
    if (!fileB64) return new Response(
      JSON.stringify({ error: 'No file provided' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    // Decode base64 → Uint8Array
    const binaryStr = atob(fileB64)
    const bytes = new Uint8Array(binaryStr.length)
    for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i)

    // Extract text from PDF (pure Deno — no npm packages)
    const text = extractPdfText(bytes)
    console.log(`Extracted ${text.length} chars from PDF`)

    if (text.trim().length < 50) {
      return new Response(JSON.stringify({
        error: 'No readable text found. This may be a scanned/image PDF. Please use a digital bank statement.',
      }), { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Parse transactions
    const parsed = parseStatement(text)
    console.log(`Parsed ${parsed.length} transactions`)

    if (parsed.length === 0) {
      return new Response(JSON.stringify({
        imported: 0, skipped: 0,
        message: 'No transactions detected. Please ensure this is a standard bank statement PDF.',
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Get or create account
    const { data: accounts } = await supabase
      .from('accounts')
      .select('id, account_type')
      .eq('user_id', user.id)
      .eq('is_active', true)

    let accountId: string
    const bankAcc = accounts?.find((a: { account_type: string }) =>
      a.account_type === 'savings_account' || a.account_type === 'current_account')

    if (bankAcc) {
      accountId = bankAcc.id
    } else {
      const { data: newAcc, error: accErr } = await supabase
        .from('accounts')
        .insert({
          user_id: user.id, source_type: 'manual',
          account_type: 'savings_account',
          institution_name: `${body.file_name || 'Statement'} Import`,
          currency: 'INR', is_active: true,
        })
        .select('id').single()
      if (accErr || !newAcc) return new Response(
        JSON.stringify({ error: 'Could not create account' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      accountId = newAcc.id
    }

    // Dedup against existing
    const ago400 = new Date()
    ago400.setDate(ago400.getDate() - 400)
    const { data: existing } = await supabase
      .from('transactions')
      .select('txn_date, amount, type')
      .eq('user_id', user.id)
      .gte('txn_date', ago400.toISOString().split('T')[0])

    const existingKeys = new Set(
      (existing || []).map((t: { txn_date: string; amount: number; type: string }) =>
        `${t.txn_date?.split('T')[0]}:${t.amount}:${t.type}`)
    )

    const toInsert = parsed
      .filter(t => !existingKeys.has(`${t.date}:${t.amount}:${t.type}`))
      .map(t => ({
        user_id: user.id, account_id: accountId,
        txn_date: t.date, amount: t.amount, type: t.type,
        description: t.description,
        merchant: t.description.split(' ').slice(0, 3).join(' '),
        category: suggestCategory(t.description),
        source: 'pdf_import',
      }))

    let imported = 0, errors = 0
    for (let i = 0; i < toInsert.length; i += 50) {
      const { error } = await supabase.from('transactions').insert(toInsert.slice(i, i + 50))
      if (error) { console.error('Insert error:', error); errors += 50 }
      else imported += Math.min(50, toInsert.length - i)
    }

    return new Response(JSON.stringify({
      imported, skipped: parsed.length - toInsert.length, errors,
      total_parsed: parsed.length,
      message: imported > 0 ? `Imported ${imported} transactions` : 'No new transactions',
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err) {
    console.error('import-pdf error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
