/**
 * ZeroTab — On-device SMS Parser Service
 * Parses Indian bank SMS messages into structured transactions.
 * All parsing happens locally — no raw SMS ever leaves the device via this module.
 */
import { ParsedTransaction } from '../types/index.js';
import { classifyCategory } from './aaService.js';

// ── Transaction patterns ──────────────────────────────────
const TRANSACTION_PATTERNS = {
  debit_card: /(?:debited|spent|used|withdrawn|debit|deducted).*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  credit_card_spent: /(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?).*?(?:spent|used|charged|debited)/i,
  bank_debit: /(?:deducted|debited|payment.*?of|transferred).*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  bank_credit: /(?:credited|received|deposited|credit).*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  upi_debit: /UPI.*?(?:debited|paid|sent).*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  upi_credit: /UPI.*?(?:credited|received).*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  amount_first: /(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?).*?(?:debited|credited|deducted|received|spent)/i,
};

// Patterns that reliably indicate a transaction SMS
const TRANSACTION_INDICATORS = [
  /(?:debited|credited|deducted|deposited|withdrawn)/i,
  /(?:Rs\.?|INR|₹)\s*[\d,]+/i,
  /(?:UPI|NEFT|IMPS|RTGS|ATM|POS)\s+(?:ref|txn|id)?/i,
  /(?:available\s+balance|avl\s+bal|bal\s+is)/i,
];

// Balance extraction
const BALANCE_PATTERNS = [
  /(?:available\s+balance|avl\s+bal|bal(?:ance)?)\s*(?:is|:)?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)/i,
  /(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)\s*(?:available|avl|bal)/i,
];

// Last 4 digits of card/account
const LAST4_PATTERNS = [
  /(?:card|a\/c|acct?|account).*?(?:XX+|ending|x{2,}|no\.?)[\s-]?(\d{4})/i,
  /(?:XX|xx|\*{2,})(\d{4})/,
  /(\d{4})(?:\s+is\s+debited|\s+credited)/i,
];

// Merchant extraction
const MERCHANT_PATTERNS = [
  /(?:at|to|@|toward[s]?)\s+([A-Za-z][A-Za-z0-9\s&_\-\.]{1,40}?)(?:\s+on|\s+via|\s+ref|\s+txn|\s+dated|\s*\.|\s*,|\s*$)/i,
  /UPI[:\s]+([A-Za-z][A-Za-z0-9\s&_\-\.]{1,40})@/i,
];

// Trusted bank sender IDs
export const TRUSTED_SENDERS = [
  'HDFCBK', 'SBIINB', 'ICICIB', 'AXISBK', 'KOTAKB',
  'SCBINB', 'YESBK', 'INDUSB', 'PNBSMS', 'BOIIND',
  'AMEXIN', 'CITIBN', 'HSBC', 'IDFCBK', 'RBLBK',
  'FEDERL', 'KARURC', 'SOUTHB', 'CANARAB', 'UNIONBK',
];

// ── Main parser class ─────────────────────────────────────
export class SmsParserService {
  /**
   * Check if an SMS is likely a bank transaction message
   */
  isTransactionSms(smsText: string): boolean {
    const matches = TRANSACTION_INDICATORS.filter((p) => p.test(smsText));
    return matches.length >= 2;
  }

  /**
   * Parse a bank SMS into a structured transaction
   */
  parseSms(smsText: string): ParsedTransaction | null {
    if (!this.isTransactionSms(smsText)) return null;

    const amount = this.extractAmount(smsText);
    if (!amount || amount <= 0) return null;

    const type    = this.extractType(smsText);
    const date    = this.extractDate(smsText);
    const last4   = this.extractLast4(smsText);
    const balance = this.extractBalance(smsText);
    const merchant = this.extractMerchant(smsText);
    const category = merchant ? this.classifyCategory(merchant) : 'others';

    return {
      amount,
      type,
      date,
      merchant,
      category,
      last4,
      balance,
      rawText: smsText,
    };
  }

  /**
   * Classify merchant name to category
   */
  classifyCategory(merchant: string): string {
    return classifyCategory(merchant);
  }

  /**
   * Deduplicate transactions by (date + amount + last4 + type)
   */
  deduplicateTransactions(txns: ParsedTransaction[]): ParsedTransaction[] {
    const seen = new Set<string>();
    return txns.filter((t) => {
      const key = `${t.date.toDateString()}|${t.amount}|${t.last4 ?? ''}|${t.type}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  // ── Private helpers ────────────────────────────────────
  private extractAmount(text: string): number | null {
    for (const pattern of Object.values(TRANSACTION_PATTERNS)) {
      const match = text.match(pattern);
      if (match?.[1]) {
        return parseFloat(match[1].replace(/,/g, ''));
      }
    }
    return null;
  }

  private extractType(text: string): 'debit' | 'credit' {
    const lower = text.toLowerCase();
    if (/\b(credited|received|deposited|credit|cashback|refund)\b/.test(lower)) {
      return 'credit';
    }
    return 'debit';
  }

  private extractDate(text: string): Date {
    // Try various date formats common in Indian bank SMSes
    const patterns = [
      /(\d{2})[\/\-](\d{2})[\/\-](\d{2,4})/,   // DD/MM/YY or DD-MM-YYYY
      /(\d{2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{4})/i,
    ];

    for (const p of patterns) {
      const m = text.match(p);
      if (m) {
        if (p === patterns[0]) {
          const [, d, mo, y] = m;
          const year = y.length === 2 ? `20${y}` : y;
          return new Date(`${year}-${mo}-${d}`);
        } else {
          return new Date(m[0]);
        }
      }
    }
    return new Date(); // Default to today
  }

  private extractLast4(text: string): string | undefined {
    for (const p of LAST4_PATTERNS) {
      const m = text.match(p);
      if (m?.[1]) return m[1];
    }
    return undefined;
  }

  private extractBalance(text: string): number | undefined {
    for (const p of BALANCE_PATTERNS) {
      const m = text.match(p);
      if (m?.[1]) return parseFloat(m[1].replace(/,/g, ''));
    }
    return undefined;
  }

  private extractMerchant(text: string): string | undefined {
    for (const p of MERCHANT_PATTERNS) {
      const m = text.match(p);
      if (m?.[1]) return m[1].trim().slice(0, 50);
    }
    return undefined;
  }
}

export const smsParser = new SmsParserService();
