class ApiConstants {
  // Supabase Edge Functions base URL
  // Format: https://<project-ref>.supabase.co/functions/v1
  // Passed via --dart-define=SUPABASE_FUNCTIONS_URL=...
  static const String baseUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_URL',
    defaultValue: 'http://localhost:54321/functions/v1', // local Supabase dev
  );

  // Supabase (required — pass via --dart-define)
  static const String supabaseUrl     = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Analytics (optional)
  static const String posthogKey = String.fromEnvironment('POSTHOG_KEY', defaultValue: '');

  // Finvu AA
  static const String finvuBaseUrl =
      String.fromEnvironment('FINVU_BASE_URL', defaultValue: 'https://aa.sandbox.finvu.in/consentapi');

  // ── REST endpoints (now pointing to Edge Functions) ────
  // Each edge function handles its own sub-routing internally
  static const String aaConsentCreate  = '/aa/consent/create';
  static const String aaConsentRevoke  = '/aa/consent/revoke';
  static const String aaSync           = '/aa/sync';
  static const String accounts         = '/accounts';
  static const String accountsSummary  = '/accounts/summary';
  static const String transactions     = '/transactions';
  static const String txnSummary       = '/transactions/summary';
  static const String cashflow         = '/transactions/cashflow';
  static const String insightsLatest   = '/insights/latest';
  static const String insights         = '/insights';
  static const String mfHoldings       = '/mf/holdings';
  static const String mfSearch         = '/mf/search';
  static const String casUpload        = '/mf/cas-upload';
  static const String userMe           = '/users/me';
  static const String userRegister     = '/users/me/register';
  static const String userSnapshot     = '/users/me/snapshot';
  static const String fcmToken         = '/users/me/fcm-token';
  static const String demoSeed         = '/demo/seed';

  // Stocks
  static const String stockHoldings = '/stocks/holdings';
  static const String stockRefresh  = '/stocks/refresh';
  static const String stockQuote    = '/stocks/quote';

  // ETFs
  static const String etfHoldings   = '/stocks/etf/holdings';
  static const String etfRefresh    = '/stocks/etf/refresh';
  static const String etfQuote      = '/stocks/quote';

  // Commodities
  static const String commodityHoldings = '/stocks/commodity/holdings';
  static const String commodityRefresh  = '/stocks/commodity/refresh';
  static const String commodityQuote    = '/stocks/commodity/quote';

  // MF manual
  static const String mfRefreshNav  = '/mf/refresh-nav';

  // Accounts
  static const String accountAdjustBalance = '/accounts';
}
