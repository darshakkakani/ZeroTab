// ── Core domain types for ZeroTab ─────────────────────────

export interface User {
  id: string;
  phone: string;
  name?: string;
  financial_archetype?: string;
  created_at: string;
  last_active?: string;
}

export interface Account {
  id: string;
  user_id: string;
  source_type: 'aa_bank' | 'aa_fd' | 'sms_card' | 'manual' | 'mf_cas';
  institution_name?: string;
  account_type?: 'savings' | 'current' | 'credit_card' | 'loan' | 'mf' | 'demat' | 'fd' | 'epf' | 'insurance';
  masked_number?: string;
  current_balance?: number;
  credit_limit?: number;
  currency: string;
  last_synced_at?: string;
  is_active: boolean;
  metadata?: Record<string, unknown>;
}

export interface Transaction {
  id: string;
  account_id: string;
  user_id: string;
  txn_date: string;
  amount: number;
  type: 'debit' | 'credit';
  category?: string;
  merchant?: string;
  description?: string;
  source?: 'aa' | 'sms' | 'email' | 'manual';
  raw_sms_text?: string;
  is_recurring: boolean;
  created_at: string;
}

export interface MFHolding {
  id: string;
  user_id: string;
  folio_number?: string;
  scheme_code?: string;
  scheme_name?: string;
  amc_name?: string;
  units?: number;
  avg_nav?: number;
  current_nav?: number;
  invested_amount?: number;
  current_value?: number;
  xirr?: number;
  last_updated?: string;
}

export interface AIInsight {
  id: string;
  user_id: string;
  week_number: number;
  year: number;
  archetype?: string;
  insight_text: string;
  insight_type?: string;
  action_items?: ActionItem[];
  data_snapshot?: FinancialSnapshot;
  generated_at: string;
}

export interface ActionItem {
  step: number;
  text: string;
}

export interface Consent {
  id: string;
  user_id: string;
  aa_provider: string;
  consent_handle?: string;
  consent_status: 'pending' | 'active' | 'revoked' | 'expired';
  fip_ids?: string[];
  valid_from?: string;
  valid_to?: string;
  created_at: string;
}

export interface FinancialSnapshot {
  netWorth: number;
  monthlyIncome: number;
  monthlySpend: number;
  savingsRate: number;
  emiRatio: number;
  mfValue: number;
  mfXIRR: number;
  creditUtil: number;
  topCategories: string[];
  biggestChange: string;
  archetype: string;
  bankBalance: number;
  creditCardDebt: number;
  loanOutstanding: number;
}

export interface ParsedTransaction {
  amount: number;
  type: 'debit' | 'credit';
  date: Date;
  merchant?: string;
  category?: string;
  last4?: string;
  balance?: number;
  rawText: string;
}

// Archetype definitions
export type ArchetypeCode =
  | 'HIGH_INCOME_HIGH_EMI'
  | 'YOUNG_SAVER'
  | 'LIFESTYLE_INFLATED'
  | 'UNDERINVESTED'
  | 'CREDIT_STRESSED'
  | 'GOOD_INVESTOR'
  | 'DEBT_FREE_SPENDER'
  | 'CONSERVATIVE_SAVER'
  | 'SIP_STARTER'
  | 'REAL_ESTATE_HEAVY'
  | 'CASH_HOARDER'
  | 'EMI_JUGGLER'
  | 'SUBSCRIPTIONS_HEAVY'
  | 'FOOD_DELIVERY_ADDICT'
  | 'TRAVEL_SPENDER'
  | 'INSURANCE_UNDERSERVED'
  | 'HIGH_NET_WORTH'
  | 'EMERGING_PROFESSIONAL'
  | 'BUDGET_CONSCIOUS'
  | 'BALANCED_WEALTH_BUILDER';
