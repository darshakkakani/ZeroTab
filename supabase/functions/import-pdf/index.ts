// ════════════════════════════════════════════════════════════════
//  ZeroTab — Bank Statement PDF Import Edge Function
//
//  Supports: HDFC, SBI, ICICI, Axis, Kotak, IndusInd, Yes Bank
//
//  Flow:
//   1. Receive base64-encoded PDF bytes
//   2. Extract text using pdf-parse (npm)
//   3. Parse transactions using bank-specific regex patterns
//   4. Deduplicate against existing transactions
//   5. Insert new transactions into DB
//   6. Return { imported, skipped, errors }
// ════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Use pdf-parse via npm specifier (Deno 1.30+)
// @ts-ignore
import pdfParse from 'npm:pdf-parse/lib/pdf-parse.js'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface ParsedTransaction {
  date:        string   // YYYY-MM-DD
  description: string
  amount:      number
  type:        'debit' | 'credit'
  balance?:    number
  reference?:  string
}

// ── Master date parser ────────────────────────────────────────
function parseDate(raw: string): string | null {
  raw = raw.trim()

  // DD/MM/YYYY or DD-MM-YYYY
  const dmy = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/)
  if (dmy) return `${dmy[3]}-${dmy[2].padStart(2,'0')}-${dmy[1].padStart(2,'0')}`

  // DD/MM/YY or DD-MM-YY
  const dmyShort = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2})$/)
  if (dmyShort) {
    const yr = parseInt(dmyShort[3]) > 50 ? `19${dmyShort[3]}` : `20${dmyShort[3]}`
    return `${yr}-${dmyShort[2].padStart(2,'0')}-${dmyShort[1].padStart(2,'0')}`
  }

  // DD MMM YYYY
  const months: Record<string,string> = {
    jan:'01',feb:'02',mar:'03',apr:'04',may:'05',jun:'06',
    jul:'07',aug:'08',sep:'09',oct:'10',nov:'11',dec:'12',
  }
  const dmy3 = raw.match(/^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$/)
  if (dmy3) {
    const m = months[dmy3[2].toLowerCase()]
    if (m) return `${dmy3[3]}-${m}-${dmy3[1].padStart(2,'0')}`
  }

  // DD-MMM-YYYY (ICICI format)
  const icici = raw.match(/^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/)
  if (icici) {
    const m = months[icici[2].toLowerCase()]
    if (m) return `${icici[3]}-${m}-${icici[1].padStart(2,'0')}`
  }

  // MMM DD, YYYY
  const mdy = raw.match(/^([A-Za-z]{3})\s+(\d{1,2}),\s*(\d{4})$/)
  if (mdy) {
    const m = months[mdy[1].toLowerCase()]
    if (m) return `${mdy[3]}-${m}-${mdy[2].padStart(2,'0')}`
  }

  return null
}

// ── Amount parser (handles Indian comma notation) ─────────────
function parseAmount(raw: string): number {
  return parseFloat(raw.replace(/,/g, '').replace(/[^\d.]/g, '')) || 0
}

// ── Category auto-suggester ───────────────────────────────────
function suggestCategory(description: string): string {
  const d = description.toLowerCase()
  if (d.match(/swiggy|zomato|dunzo|blinkit|zepto|food|restaurant|cafe|pizza|burger|kfc|mcd/)) return 'food_delivery'
  if (d.match(/grocery|bigbasket|dmart|jiomart|supermarket|kirana|sabzi|vegetables/)) return 'grocery'
  if (d.match(/amazon|flipkart|myntra|meesho|snapdeal|ajio|shopping|mall/)) return 'shopping'
  if (d.match(/emi|loan|hl|cl|pl|hdfc loan|sbi loan|icici loan|bajaj|capital first/)) return 'emi'
  if (d.match(/petrol|diesel|fuel|bpcl|iocl|hpcl|shell/)) return 'fuel'
  if (d.match(/electricity|water|gas|internet|broadband|airtel|jio|bsnl|tata sky|recharge/)) return 'utilities'
  if (d.match(/uber|ola|rapido|metro|irctc|bus|flight|makemytrip|goibibo|cab|auto/)) return 'transport'
  if (d.match(/netflix|spotify|prime|hotstar|zee5|youtube premium|subscription/)) return 'subscriptions'
  if (d.match(/hospital|pharmacy|medicine|doctor|apollo|medplus|health|medical/)) return 'health'
  if (d.match(/mutual fund|sip|mf|zerodha|groww|kite|upstox|nsdl|invest|shares|nse|bse/)) return 'investment'
  if (d.match(/insurance|lic|term|sbi life|hdfc life|max life/)) return 'insurance'
  if (d.match(/salary|sal|payroll|neft|rtgs|credit|bonus/)) return 'income'
  return 'others'
}

// ════════════════════════════════════════════════════════════════
//  Bank-specific parsers
// ════════════════════════════════════════════════════════════════

// HDFC Bank: Date | Narration | Chq/Ref No | Value Date | Withdrawal | Deposit | Closing Balance
function parseHDFC(lines: string[]): ParsedTransaction[] {
  const txns: ParsedTransaction[] = []
  const re = /^(\d{2}\/\d{2}\/\d{4})\s+(.+?)\s+(\S+)\s+\d{2}\/\d{2}\/\d{4}\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})/

  for (const line of lines) {
    const m = line.match(re)
    if (!m) continue
    const date  = parseDate(m[1])
    if (!date) continue
    const debit  = m[4] ? parseAmount(m[4]) : 0
    const credit = m[5] ? parseAmount(m[5]) : 0
    if (debit === 0 && credit === 0) continue

    txns.push({
      date,
      description: m[2].trim(),
      amount:      debit > 0 ? debit : credit,
      type:        debit > 0 ? 'debit' : 'credit',
      balance:     m[6] ? parseAmount(m[6]) : undefined,
      reference:   m[3],
    })
  }
  return txns
}

// SBI: Date | Description | Ref | Debit | Credit | Balance
function parseSBI(lines: string[]): ParsedTransaction[] {
  const txns: ParsedTransaction[] = []
  const re = /^(\d{2}\s+[A-Za-z]{3}\s+\d{4}|\d{2}\/\d{2}\/\d{4}|\d{2}-\d{2}-\d{4})\s+(.+?)\s+(\S+)\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})/

  for (const line of lines) {
    const m = line.match(re)
    if (!m) continue
    const date = parseDate(m[1])
    if (!date) continue
    const debit  = m[4] ? parseAmount(m[4]) : 0
    const credit = m[5] ? parseAmount(m[5]) : 0
    if (debit === 0 && credit === 0) continue
    txns.push({
      date,
      description: m[2].trim(),
      amount:      debit > 0 ? debit : credit,
      type:        debit > 0 ? 'debit' : 'credit',
      balance:     m[6] ? parseAmount(m[6]) : undefined,
    })
  }
  return txns
}

// ICICI Bank: Date | Mode | Particulars | Deposits | Withdrawals | Balance
function parseICICI(lines: string[]): ParsedTransaction[] {
  const txns: ParsedTransaction[] = []
  const re = /^(\d{2}-[A-Za-z]{3}-\d{4}|\d{2}\/\d{2}\/\d{4})\s+(\S+)\s+(.+?)\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})?\s+([\d,]+\.\d{2})/

  for (const line of lines) {
    const m = line.match(re)
    if (!m) continue
    const date = parseDate(m[1])
    if (!date) continue
    const credit = m[4] ? parseAmount(m[4]) : 0
    const debit  = m[5] ? parseAmount(m[5]) : 0
    if (debit === 0 && credit === 0) continue
    txns.push({
      date,
      description: m[3].trim(),
      amount:      debit > 0 ? debit : credit,
      type:        debit > 0 ? 'debit' : 'credit',
      balance:     m[6] ? parseAmount(m[6]) : undefined,
    })
  }
  return txns
}

// Generic: try to extract any line with a date and amount
function parseGeneric(lines: string[]): ParsedTransaction[] {
  const txns: ParsedTransaction[] = []
  const dateRe    = /(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{1,2}\s+[A-Za-z]{3}\s+\d{4})/
  const amountRe  = /([\d,]+\.\d{2})/g

  for (const line of lines) {
    if (line.length < 20) continue
    const dateMatch = line.match(dateRe)
    if (!dateMatch) continue
    const date = parseDate(dateMatch[1])
    if (!date) continue

    const amounts = [...line.matchAll(amountRe)].map(m => parseAmount(m[1]))
    if (amounts.length < 1) continue

    // Heuristic: last amount = balance, previous = credit or debit
    const amount  = amounts.length >= 2 ? amounts[amounts.length - 2] : amounts[0]
    if (amount === 0) continue

    // Try to determine type from keywords
    const upper   = line.toUpperCase()
    const isCredit = upper.includes('CR') || upper.includes('CREDIT') || upper.includes('DEPOSIT') || upper.includes('SALARY')
    const desc     = line.replace(dateMatch[1], '').replace(/[\d,]+\.\d{2}/g, '').trim()

    txns.push({
      date,
      description: desc.substring(0, 120).trim(),
      amount,
      type:     isCredit ? 'credit' : 'debit',
      balance:  amounts.length >= 2 ? amounts[amounts.length - 1] : undefined,
    })
  }
  return txns
}

// ── Main parser: detect bank and apply correct parser ─────────
function parseStatement(text: string): ParsedTransaction[] {
  const lines  = text.split('\n').map(l => l.replace(/\s+/g, ' ').trim()).filter(l => l.length > 10)
  const upper  = text.toUpperCase()

  let txns: ParsedTransaction[] = []

  if (upper.includes('HDFC BANK'))      txns = parseHDFC(lines)
  else if (upper.includes('STATE BANK') || upper.includes('SBI')) txns = parseSBI(lines)
  else if (upper.includes('ICICI BANK')) txns = parseICICI(lines)
  else {
    // Try HDFC, then SBI, then generic
    txns = parseHDFC(lines)
    if (txns.length < 2) txns = parseSBI(lines)
    if (txns.length < 2) txns = parseGeneric(lines)
  }

  // Deduplicate within the parsed set
  const seen = new Set<string>()
  return txns.filter(t => {
    const key = `${t.date}:${t.amount}:${t.type}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

// ════════════════════════════════════════════════════════════════
//  Edge Function handler
// ════════════════════════════════════════════════════════════════

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing auth' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Get user from JWT
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json()
    const fileB64: string = body.file_bytes_b64 || ''
    if (!fileB64) {
      return new Response(JSON.stringify({ error: 'No file provided' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Decode base64 → Uint8Array
    const binaryStr = atob(fileB64)
    const bytes     = new Uint8Array(binaryStr.length)
    for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i)

    // Extract text from PDF
    let text = ''
    try {
      const pdfData = await pdfParse(bytes)
      text = pdfData.text || ''
    } catch (e) {
      return new Response(JSON.stringify({ error: `PDF parse failed: ${e}` }), {
        status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!text.trim()) {
      return new Response(JSON.stringify({
        error: 'No text extracted — may be a scanned PDF image. Use a digital statement.',
      }), { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Parse transactions
    const parsed = parseStatement(text)
    if (parsed.length === 0) {
      return new Response(JSON.stringify({
        imported: 0, skipped: 0,
        message: 'No transactions detected. Try a different bank statement format.',
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Get user's accounts — look for a bank account
    const { data: accounts } = await supabase
      .from('accounts')
      .select('id, account_type')
      .eq('user_id', user.id)
      .eq('is_active', true)

    // Use first bank account, or create a "Statement Import" account
    let accountId: string
    const bankAcc = accounts?.find((a: any) => a.account_type === 'savings_account' || a.account_type === 'current_account')
    if (bankAcc) {
      accountId = bankAcc.id
    } else {
      // Create a placeholder account for the import
      const { data: newAcc, error: accErr } = await supabase
        .from('accounts')
        .insert({
          user_id:       user.id,
          source_type:   'manual',
          account_type:  'savings_account',
          institution_name: `${body.file_name || 'Statement'} Import`,
          currency:      'INR',
          is_active:     true,
        })
        .select('id')
        .single()
      if (accErr || !newAcc) {
        return new Response(JSON.stringify({ error: 'Could not create account' }), {
          status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      accountId = newAcc.id
    }

    // Fetch existing transactions to deduplicate
    const thirtyDaysAgo = new Date()
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 400)
    const { data: existingTxns } = await supabase
      .from('transactions')
      .select('txn_date, amount, type')
      .eq('user_id', user.id)
      .gte('txn_date', thirtyDaysAgo.toISOString().split('T')[0])

    const existingKeys = new Set(
      (existingTxns || []).map((t: any) => `${t.txn_date?.split('T')[0]}:${t.amount}:${t.type}`)
    )

    // Filter out duplicates and prepare for insert
    const toInsert = parsed
      .filter(t => {
        const key = `${t.date}:${t.amount}:${t.type}`
        return !existingKeys.has(key)
      })
      .map(t => ({
        user_id:     user.id,
        account_id:  accountId,
        txn_date:    t.date,
        amount:      t.amount,
        type:        t.type,
        description: t.description,
        merchant:    t.description.split(' ').slice(0, 3).join(' '),
        category:    suggestCategory(t.description),
        source:      'pdf_import',
      }))

    let imported = 0
    let errors   = 0

    // Insert in batches of 50
    for (let i = 0; i < toInsert.length; i += 50) {
      const batch = toInsert.slice(i, i + 50)
      const { error } = await supabase.from('transactions').insert(batch)
      if (error) {
        console.error('Batch insert error:', error)
        errors += batch.length
      } else {
        imported += batch.length
      }
    }

    return new Response(JSON.stringify({
      imported,
      skipped: parsed.length - toInsert.length,
      errors,
      total_parsed: parsed.length,
      message: imported > 0
        ? `Successfully imported ${imported} transactions`
        : 'All transactions already exist — no duplicates imported',
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err) {
    console.error('import-pdf error:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
