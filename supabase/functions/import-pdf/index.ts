// ════════════════════════════════════════════════════════════════
//  ZeroTab — Bank Statement PDF Import  (v3 — with decompression)
//
//  Pure Deno — zero npm dependencies.
//  Uses native DecompressionStream to handle FlateDecode streams.
//  Includes position-aware text grouping for accurate row assembly.
//
//  Banks: HDFC, SBI, ICICI, Axis, Standard Chartered + generic
// ════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// ── Deno-native zlib decompression ────────────────────────────
async function inflateRaw(compressed: Uint8Array): Promise<string> {
  try {
    const ds  = new DecompressionStream('deflate-raw')
    const wr  = ds.writable.getWriter()
    const rd  = ds.readable.getReader()
    wr.write(compressed).catch(() => {})
    wr.close().catch(() => {})
    const chunks: Uint8Array[] = []
    try {
      while (true) {
        const { done, value } = await rd.read()
        if (done) break
        if (value) chunks.push(value)
      }
    } catch { /* partial decompression — use what we got */ }
    const total = chunks.reduce((s, c) => s + c.length, 0)
    const result = new Uint8Array(total)
    let pos = 0
    for (const c of chunks) { result.set(c, pos); pos += c.length }
    return new TextDecoder('latin1').decode(result)
  } catch { return '' }
}

// ── Octal / escape decoder ────────────────────────────────────
function decodeOctal(s: string): string {
  return s
    .replace(/\\(\d{3})/g, (_, o) => String.fromCharCode(parseInt(o, 8)))
    .replace(/\\n/g, ' ').replace(/\\r/g, '').replace(/\\\\/g, '\\')
    .replace(/\\t/g, ' ').replace(/\\'/g, "'").replace(/\\"/g, '"')
}

// ── Position-aware text element ───────────────────────────────
interface Glyph { x: number; y: number; text: string }

// Extracts glyphs from a decoded PDF content stream with X/Y positions
function extractGlyphs(content: string): Glyph[] {
  const glyphs: Glyph[] = []
  let cx = 0, cy = 0, fs = 10

  const lines = content.split(/\r?\n/)
  for (const ln of lines) {
    const l = ln.trim()
    if (!l) continue

    // Tm: a b c d e f Tm  (e=x, f=y — absolute position)
    const tmM = l.match(/^([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+Tm$/)
    if (tmM) { cx = parseFloat(tmM[5]); cy = parseFloat(tmM[6]); continue }

    // Td / TD: dx dy Td
    const tdM = l.match(/^([-\d.]+)\s+([-\d.]+)\s+T[dD]$/)
    if (tdM) { cx += parseFloat(tdM[1]); cy += parseFloat(tdM[2]); continue }

    // (text) Tj
    const tjM = l.match(/^\(([^)]*(?:\\.[^)]*)*)\)\s*Tj$/)
    if (tjM) {
      const t = decodeOctal(tjM[1]).trim()
      if (t) glyphs.push({ x: cx, y: cy, text: t })
      continue
    }

    // [(text) n (text)] TJ
    const tjArrM = l.match(/^\[([\s\S]*)\]\s*TJ$/)
    if (tjArrM) {
      const re = /\(([^)]*(?:\\.[^)]*)*)\)/g
      let m: RegExpExecArray | null
      while ((m = re.exec(tjArrM[1])) !== null) {
        const t = decodeOctal(m[1]).trim()
        if (t) glyphs.push({ x: cx, y: cy, text: t })
      }
      continue
    }
  }
  return glyphs
}

// Group glyphs into rows by Y position (tolerance = 3 pts)
function groupRows(glyphs: Glyph[]): string[] {
  if (!glyphs.length) return []
  const TOL = 3
  const rowMap = new Map<number, Glyph[]>()
  for (const g of glyphs) {
    const bucket = Math.round(g.y / TOL) * TOL
    if (!rowMap.has(bucket)) rowMap.set(bucket, [])
    rowMap.get(bucket)!.push(g)
  }
  // Sort Y descending (PDF coords: 0 = bottom)
  const ys = [...rowMap.keys()].sort((a, b) => b - a)
  return ys.map(y =>
    rowMap.get(y)!.sort((a, b) => a.x - b.x).map(g => g.text).join(' ')
  ).filter(r => r.trim().length > 2)
}

// ── Main PDF extractor ────────────────────────────────────────
async function extractPdfText(bytes: Uint8Array): Promise<string> {
  const raw   = new TextDecoder('latin1').decode(bytes)
  const allRows: string[] = []

  // Find all PDF stream ... endstream blocks
  const streamRe = /stream\r?\n([\s\S]*?)\r?\nendstream/g
  let sm: RegExpExecArray | null

  while ((sm = streamRe.exec(raw)) !== null) {
    // Look for /Filter in the 400 chars before 'stream'
    const before = raw.substring(Math.max(0, sm.index - 400), sm.index)
    const isFlate = /\/FlateDecode|\/Fl\b/.test(before)
    const isText  = !/\/Subtype\s*\/Image/.test(before) // skip image streams

    if (!isText) continue

    let content: string
    if (isFlate) {
      // Convert the raw latin1 stream bytes back to a Uint8Array
      const sc = sm[1]
      const sb = new Uint8Array(sc.length)
      for (let i = 0; i < sc.length; i++) sb[i] = sc.charCodeAt(i) & 0xFF
      content = await inflateRaw(sb)
    } else {
      content = sm[1]
    }

    if (!content || content.length < 10) continue

    // Extract glyphs and group into rows
    const glyphs = extractGlyphs(content)
    if (glyphs.length > 0) {
      allRows.push(...groupRows(glyphs))
    } else {
      // Fallback: plain BT/ET extraction (some PDFs skip Tm operators)
      const btRe = /BT([\s\S]*?)ET/g
      let bm: RegExpExecArray | null
      while ((bm = btRe.exec(content)) !== null) {
        const block = bm[1]
        const tjRe = /\(([^)]*(?:\\.[^)]*)*)\)\s*(?:Tj|'|")/g
        let tm: RegExpExecArray | null
        const parts: string[] = []
        while ((tm = tjRe.exec(block)) !== null) {
          const t = decodeOctal(tm[1]).trim()
          if (t) parts.push(t)
        }
        if (parts.length > 0) allRows.push(parts.join(' '))
      }
    }
  }

  // ASCII fallback for uncompressed PDFs
  if (allRows.length < 3) {
    const asciiRe = /[ -~]{8,}/g
    let am: RegExpExecArray | null
    while ((am = asciiRe.exec(raw)) !== null) {
      const t = am[0].trim()
      if (t.length >= 10 && !/^%PDF|^%%EOF|^\/[A-Z]/.test(t)) allRows.push(t)
    }
  }

  console.log(`Extracted ${allRows.length} rows from PDF`)
  return allRows.join('\n')
}

// ════════════════════════════════════════════════════════════════
//  Parsers
// ════════════════════════════════════════════════════════════════

interface ParsedTxn {
  date: string; description: string; amount: number;
  type: 'debit' | 'credit'; balance?: number
}

function parseDate(raw: string): string | null {
  raw = raw.trim()
  const M: Record<string, string> = {
    jan:'01',feb:'02',mar:'03',apr:'04',may:'05',jun:'06',
    jul:'07',aug:'08',sep:'09',oct:'10',nov:'11',dec:'12',
  }
  const dmy  = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/)
  if (dmy) return `${dmy[3]}-${dmy[2].padStart(2,'0')}-${dmy[1].padStart(2,'0')}`
  const dmyS = raw.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2})$/)
  if (dmyS) {
    const yr = parseInt(dmyS[3]) > 50 ? `19${dmyS[3]}` : `20${dmyS[3]}`
    return `${yr}-${dmyS[2].padStart(2,'0')}-${dmyS[1].padStart(2,'0')}`
  }
  // DD MMM YY or DD MMM YYYY (Standard Chartered)
  const dmy3 = raw.match(/^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})$/)
  if (dmy3) {
    const m = M[dmy3[2].toLowerCase()]
    let yr = dmy3[3]
    if (yr.length === 2) yr = parseInt(yr) > 50 ? `19${yr}` : `20${yr}`
    if (m) return `${yr}-${m}-${dmy3[1].padStart(2,'0')}`
  }
  // DD-MMM-YYYY
  const dmy4 = raw.match(/^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/)
  if (dmy4) {
    const m = M[dmy4[2].toLowerCase()]
    if (m) return `${dmy4[3]}-${m}-${dmy4[1].padStart(2,'0')}`
  }
  return null
}

function parseAmt(s: string): number {
  return parseFloat(s.replace(/,/g,'').replace(/[^\d.]/g,'')) || 0
}

function suggestCategory(d: string): string {
  const dl = d.toLowerCase()
  if (dl.match(/swiggy|zomato|blinkit|zepto|food|restaurant|cafe|pizza|kfc|mcd|burger|dominos/)) return 'food_delivery'
  if (dl.match(/grocery|bigbasket|dmart|jiomart|kirana|supermarket|vegetables|milk|bread/)) return 'grocery'
  if (dl.match(/amazon|flipkart|myntra|meesho|mall|shop/)) return 'shopping'
  if (dl.match(/emi|loan|hdfc loan|icici loan|sbi loan|bajaj/)) return 'emi'
  if (dl.match(/petrol|diesel|fuel|bpcl|iocl|hpcl|shell/)) return 'fuel'
  if (dl.match(/electricity|water|gas|internet|airtel|jio|bsnl|broadband|recharge/)) return 'utilities'
  if (dl.match(/uber|ola|rapido|metro|irctc|makemytrip|redbus|cab|auto|flight/)) return 'transport'
  if (dl.match(/netflix|spotify|prime|hotstar|zee5|youtube premium|subscription/)) return 'subscriptions'
  if (dl.match(/hospital|pharmacy|medicine|doctor|apollo|medplus|health/)) return 'health'
  if (dl.match(/sip|mutual fund|zerodha|groww|kite|upstox|invest|nifty|nse|bse/)) return 'investment'
  if (dl.match(/insurance|lic|term|sbi life|hdfc life/)) return 'insurance'
  if (dl.match(/salary|payroll|credit.*cr|neft.*cr|imps.*cr|interest credit/)) return 'income'
  return 'others'
}

// Generic row-based parser — works on any bank after row assembly
function parseRows(rows: string[]): ParsedTxn[] {
  const txns: ParsedTxn[] = []
  const dateRe = /(\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4}|\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{1,2}-[A-Za-z]{3}-\d{4})/
  const amtRe  = /([\d,]+\.\d{2})/g

  for (const row of rows) {
    if (row.length < 12) continue
    const dm = row.match(dateRe)
    if (!dm) continue
    const date = parseDate(dm[1])
    if (!date) continue

    const upper = row.toUpperCase()
    // Skip totals / headers / balance-forward rows
    if (/BALANCE FORWARD|OPENING BAL|CLOSING BAL|TOTAL|BROUGHT FORWARD/.test(upper)) continue

    const amounts = [...row.matchAll(amtRe)].map(m => parseAmt(m[1]))
    if (!amounts.length) continue

    // With 3+ amounts: last = balance, second-to-last = txn amount
    // With 2 amounts: last = balance (if > 0), first = txn
    // With 1 amount: it's the txn amount
    const balance  = amounts.length >= 2 ? amounts[amounts.length - 1] : undefined
    const amount   = amounts.length >= 2 ? amounts[amounts.length - 2] : amounts[0]
    if (!amount || amount <= 0 || amount > 50_000_000) continue

    // Credit detection: keywords or deposit column position
    const isCredit =
      /\b(CR|CREDIT|DEPOSIT|NEFT CR|IMPS CR|SALARY|INTEREST CR|UPI CR|RTGS CR|RECEIVED)\b/.test(upper) ||
      // Standard Chartered: Deposit comes before Withdrawal in column order
      // If description doesn't mention withdrawal keywords → treat as credit for SC
      (/STANDARD CHAR|SCBL/.test(upper) === false &&
       /ATM|WITHDRAWAL|DEBIT|PURCHASE|PAYMENT|DR\b|CHARGED/.test(upper) === false &&
       amounts.length >= 3)

    const desc = row
      .replace(dateRe, '')
      .replace(amtRe, '')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 120)

    txns.push({
      date, amount,
      type:        isCredit ? 'credit' : 'debit',
      description: desc || 'Transaction',
      balance,
    })
  }

  // Deduplicate
  const seen = new Set<string>()
  return txns.filter(t => {
    const k = `${t.date}:${t.amount}:${t.type}`
    return seen.has(k) ? false : (seen.add(k), true)
  })
}

// ════════════════════════════════════════════════════════════════
//  Handler
// ════════════════════════════════════════════════════════════════

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const auth = req.headers.get('Authorization')
    if (!auth) return new Response(JSON.stringify({ error: 'No auth' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )
    const { data: { user }, error: ue } = await supabase.auth.getUser(auth.replace('Bearer ', ''))
    if (ue || !user) return new Response(JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    const body = await req.json()

    // Accept pre-extracted text (from Flutter Syncfusion client) OR legacy base64
    let text: string = body.extracted_text || ''

    if (!text) {
      // Legacy fallback: raw PDF bytes
      const b64: string = body.file_bytes_b64 || ''
      if (!b64) return new Response(JSON.stringify({ error: 'No text or file provided' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      const binStr = atob(b64)
      const bytes = new Uint8Array(binStr.length)
      for (let i = 0; i < binStr.length; i++) bytes[i] = binStr.charCodeAt(i)
      text = await extractPdfText(bytes)
    }

    console.log(`Text length: ${text.length}, first 300 chars:\n${text.substring(0, 300)}`)

    if (text.trim().length < 30) {
      return new Response(JSON.stringify({
        error: 'Could not read text from this PDF. It may be a scanned image. Please use a digital bank statement.',
      }), { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const rows = text.split('\n').map(r => r.trim()).filter(r => r.length > 5)
    const parsed = parseRows(rows)
    console.log(`Parsed ${parsed.length} transactions from ${rows.length} rows`)

    // Log first 5 transactions for debugging
    for (const t of parsed.slice(0, 5)) {
      console.log(`  ${t.date} | ${t.type} | ${t.amount} | ${t.description.substring(0, 40)}`)
    }

    if (!parsed.length) {
      // Return the extracted text for debugging
      return new Response(JSON.stringify({
        imported: 0, skipped: 0,
        debug_rows: rows.slice(0, 20),
        message: 'No transactions detected. See debug_rows for extracted content.',
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Get or create account
    const { data: accs } = await supabase.from('accounts')
      .select('id, account_type').eq('user_id', user.id).eq('is_active', true)
    let accountId: string
    const bankAcc = accs?.find((a: { account_type: string }) =>
      ['savings_account','current_account'].includes(a.account_type))
    if (bankAcc) {
      accountId = bankAcc.id
    } else {
      const { data: na } = await supabase.from('accounts').insert({
        user_id: user.id, source_type: 'manual',
        account_type: 'savings_account',
        institution_name: body.file_name || 'Imported Statement',
        currency: 'INR', is_active: true,
      }).select('id').single()
      if (!na) return new Response(JSON.stringify({ error: 'Account creation failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      accountId = na.id
    }

    // Deduplicate
    const ago = new Date(); ago.setDate(ago.getDate() - 400)
    const { data: ex } = await supabase.from('transactions')
      .select('txn_date, amount, type').eq('user_id', user.id)
      .gte('txn_date', ago.toISOString().split('T')[0])
    const exSet = new Set((ex || []).map((t: { txn_date: string; amount: number; type: string }) =>
      `${t.txn_date?.split('T')[0]}:${t.amount}:${t.type}`))

    const toInsert = parsed
      .filter(t => !exSet.has(`${t.date}:${t.amount}:${t.type}`))
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
      if (error) errors++; else imported += Math.min(50, toInsert.length - i)
    }

    return new Response(JSON.stringify({
      imported, skipped: parsed.length - toInsert.length, errors,
      total_parsed: parsed.length,
      message: imported > 0 ? `Imported ${imported} transactions from your statement` : 'All transactions already exist',
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (err) {
    console.error('import-pdf error:', err)
    return new Response(JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
