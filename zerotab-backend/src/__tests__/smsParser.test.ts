/**
 * ZeroTab — SMS Parser Test Suite
 * 20 real Indian bank SMS templates
 */
import { SmsParserService } from '../services/smsParser.js';

const parser = new SmsParserService();

// ── Test fixtures: 20 real bank SMS templates ─────────────
const SMS_FIXTURES = [
  // 1. HDFC Debit Card
  {
    id: 1,
    bank: 'HDFC',
    sms: 'Your HDFC Bank Debit Card XX4521 has been used for INR 480.00 at ZOMATO on 18-05-2025. Your available balance is INR 41,520.00.',
    expected: { amount: 480, type: 'debit', last4: '4521', category: 'food_delivery' },
  },
  // 2. SBI UPI Credit
  {
    id: 2,
    bank: 'SBI',
    sms: 'Rs.1,00,000.00 credited to your A/c XX7711 on 01-05-25 by UPI ref no 412345678901. Avl Bal: Rs.4,20,000.00.',
    expected: { amount: 100000, type: 'credit' },
  },
  // 3. ICICI Credit Card Spend
  {
    id: 3,
    bank: 'ICICI',
    sms: 'ICICI Bank Credit Card XX8832 has been used for Rs 1,299.00 at AMAZON on 17-05-2025 18:34:22. Available Credit Limit: Rs 1,54,278.00.',
    expected: { amount: 1299, type: 'debit', last4: '8832', category: 'shopping' },
  },
  // 4. Axis Bank NEFT Debit
  {
    id: 4,
    bank: 'Axis',
    sms: 'Dear Customer, Rs. 22,800.00 debited from your Axis Bank A/c XX3891 towards EMI on 05-05-2025. Available Balance: Rs. 58,200.00.',
    expected: { amount: 22800, type: 'debit', category: 'emi' },
  },
  // 5. Kotak Bank ATM Withdrawal
  {
    id: 5,
    bank: 'Kotak',
    sms: 'Rs 5,000.00 withdrawn from Kotak Bank ATM using Debit Card ending 2291 on 15-May-2025. Available balance Rs 36,000.00.',
    expected: { amount: 5000, type: 'debit', last4: '2291' },
  },
  // 6. HDFC UPI Debit
  {
    id: 6,
    bank: 'HDFC',
    sms: 'UPI: Rs 340.00 debited from A/c XX4521 on 17-05-25 to UBER@axisbank for UPI Ref 512345678. Avl Bal: INR 41,180.00.',
    expected: { amount: 340, type: 'debit', last4: '4521', category: 'transport' },
  },
  // 7. SBI NEFT Credit
  {
    id: 7,
    bank: 'SBI',
    sms: 'Rs.50,000.00 credited to SBI A/c XX7711 on 10-05-2025 by NEFT from CRESTDATA. Avl Bal Rs.3,70,000.00. -SBIINB',
    expected: { amount: 50000, type: 'credit' },
  },
  // 8. ICICI Bank UPI Debit
  {
    id: 8,
    bank: 'ICICI',
    sms: 'Dear Customer, INR 649.00 debited from A/c XX7234 on 17-05-25 via UPI to NETFLIX@icici. Avl Bal INR 22,145.00.',
    expected: { amount: 649, type: 'debit', category: 'subscriptions' },
  },
  // 9. Axis Credit Card Payment
  {
    id: 9,
    bank: 'Axis',
    sms: 'Payment of Rs.1,800.00 received for Axis Bank Credit Card XX3312 on 14-05-2025. Total outstanding: Rs.26,200.00.',
    expected: { amount: 1800, type: 'credit', last4: '3312' },
  },
  // 10. HDFC Salary Credit
  {
    id: 10,
    bank: 'HDFC',
    sms: 'Salary of Rs.85,000.00 has been credited to your HDFC Bank A/c XX1123 on 01-May-2025. Available Balance: Rs.1,05,000.00.',
    expected: { amount: 85000, type: 'credit', category: 'income' },
  },
  // 11. IndusInd Bank Debit
  {
    id: 11,
    bank: 'IndusInd',
    sms: 'Your IndusInd Bank A/c XX9921 is debited by INR 2,499.00 on 12/05/2025 towards IRCTC. Balance is INR 14,501.00.',
    expected: { amount: 2499, type: 'debit', category: 'travel' },
  },
  // 12. PNB Net Banking Transfer
  {
    id: 12,
    bank: 'PNB',
    sms: 'Your A/c XX3401 Debited Rs.10,000.00 on 08-05-2025. Info: IMPS TXN to HDFC XXXX5678. Avl Bal Rs.45,000.00. PNB',
    expected: { amount: 10000, type: 'debit' },
  },
  // 13. SBI Credit Card Bill Payment
  {
    id: 13,
    bank: 'SBI',
    sms: 'Payment of Rs 4,500 received against SBI Credit Card XX3219 on 16-05-2025. Available Credit Limit Rs 96,500. -SBIINB',
    expected: { amount: 4500, type: 'credit', last4: '3219' },
  },
  // 14. HDFC FASTag Debit
  {
    id: 14,
    bank: 'HDFC',
    sms: 'Rs.75.00 deducted from FASTag linked to Vehicle MH01AB1234 on 16-05-2025 at Mumbai-Pune Expressway. Balance: Rs.924.00.',
    expected: { amount: 75, type: 'debit' },
  },
  // 15. Kotak Credit Card
  {
    id: 15,
    bank: 'Kotak',
    sms: 'Alert: Kotak Credit Card XX6789 used for Rs 3,499 at MAKEMYTRIP on 17-May-2025 19:22. Avl limit Rs 46,501.',
    expected: { amount: 3499, type: 'debit', last4: '6789', category: 'travel' },
  },
  // 16. ICICI Cashback Credit
  {
    id: 16,
    bank: 'ICICI',
    sms: 'Cashback of Rs.150.00 credited to your ICICI Bank account XX7234 on 15-05-2025. Avl Bal INR 22,295.00.',
    expected: { amount: 150, type: 'credit', category: 'income' },
  },
  // 17. Yes Bank UPI Debit
  {
    id: 17,
    bank: 'Yes Bank',
    sms: 'YBL: A/c XX5502 debited INR 199.00 on 13-05-25. UPI Ref: 312987456123 to SPOTIFY@yesbank. Bal INR 8,301.00.',
    expected: { amount: 199, type: 'debit', category: 'subscriptions' },
  },
  // 18. Standard Chartered Credit Card
  {
    id: 18,
    bank: 'SCB',
    sms: 'Your Standard Chartered Credit Card ending 4411 has been charged INR 12,500 at APPLE INDIA on 14-05-2025. Avl credit: Rs 87,500.',
    expected: { amount: 12500, type: 'debit', last4: '4411', category: 'shopping' },
  },
  // 19. BOI UPI Credit
  {
    id: 19,
    bank: 'BOI',
    sms: 'Rs.2,000 has been credited to your Bank of India account XX8123 via UPI on 11-05-2025. Current balance: Rs.18,000.',
    expected: { amount: 2000, type: 'credit' },
  },
  // 20. HDFC Loan EMI
  {
    id: 20,
    bank: 'HDFC',
    sms: 'HDFC Home Loan EMI of Rs.14,500.00 has been auto-debited from your A/c XX4521 on 05-May-2025. Outstanding: Rs.47,20,000.',
    expected: { amount: 14500, type: 'debit', category: 'emi' },
  },
];

// ── Non-transaction SMS (should return null) ──────────────
const NON_TXN_SMS = [
  'Your HDFC Bank account statement for April 2025 is ready. Login to netbanking to view.',
  'OTP for your ICICI Bank transaction is 482910. Valid for 10 minutes. Do not share this OTP.',
  'Dear Customer, your Kotak 811 account has been opened. Welcome to Kotak Mahindra Bank!',
];

// ── Test suite ────────────────────────────────────────────
describe('SmsParserService', () => {
  describe('isTransactionSms', () => {
    test.each(SMS_FIXTURES)('fixture $id ($bank) is identified as transaction', ({ sms }) => {
      expect(parser.isTransactionSms(sms)).toBe(true);
    });

    test.each(NON_TXN_SMS)('non-transaction SMS returns false: %s', (sms) => {
      expect(parser.isTransactionSms(sms)).toBe(false);
    });
  });

  describe('parseSms — amount extraction', () => {
    test.each(SMS_FIXTURES)('fixture $id ($bank) extracts correct amount', ({ sms, expected }) => {
      const result = parser.parseSms(sms);
      expect(result).not.toBeNull();
      expect(result!.amount).toBe(expected.amount);
    });
  });

  describe('parseSms — type classification', () => {
    test.each(SMS_FIXTURES)('fixture $id ($bank) classifies as $expected.type', ({ sms, expected }) => {
      const result = parser.parseSms(sms);
      expect(result).not.toBeNull();
      expect(result!.type).toBe(expected.type);
    });
  });

  describe('parseSms — last 4 digits', () => {
    const withLast4 = SMS_FIXTURES.filter((f) => f.expected.last4);
    test.each(withLast4)('fixture $id ($bank) extracts last4=$expected.last4', ({ sms, expected }) => {
      const result = parser.parseSms(sms);
      expect(result).not.toBeNull();
      expect(result!.last4).toBe(expected.last4);
    });
  });

  describe('parseSms — category classification', () => {
    const withCategory = SMS_FIXTURES.filter((f) => f.expected.category);
    test.each(withCategory)('fixture $id ($bank) classifies as category=$expected.category', ({ sms, expected }) => {
      const result = parser.parseSms(sms);
      expect(result).not.toBeNull();
      expect(result!.category).toBe(expected.category);
    });
  });

  describe('deduplicateTransactions', () => {
    test('removes exact duplicates', () => {
      const txns = SMS_FIXTURES.slice(0, 5)
        .map((f) => parser.parseSms(f.sms)!)
        .filter(Boolean);

      const doubled = [...txns, ...txns];
      const deduped = parser.deduplicateTransactions(doubled);
      expect(deduped.length).toBe(txns.length);
    });

    test('keeps transactions with different amounts', () => {
      const t1 = parser.parseSms(SMS_FIXTURES[0].sms)!;
      const t2 = parser.parseSms(SMS_FIXTURES[1].sms)!;
      const result = parser.deduplicateTransactions([t1, t2]);
      expect(result.length).toBe(2);
    });
  });

  describe('classifyCategory', () => {
    const categoryTests: [string, string][] = [
      ['Zomato', 'food_delivery'],
      ['Swiggy', 'food_delivery'],
      ['Amazon', 'shopping'],
      ['Flipkart', 'shopping'],
      ['Netflix', 'subscriptions'],
      ['Spotify', 'subscriptions'],
      ['Uber', 'transport'],
      ['IRCTC', 'travel'],
      ['MakeMyTrip', 'travel'],
      ['Apollo Pharmacy', 'health'],
    ];

    test.each(categoryTests)('"%s" classifies as "%s"', (merchant, expected) => {
      expect(parser.classifyCategory(merchant)).toBe(expected);
    });
  });
});
