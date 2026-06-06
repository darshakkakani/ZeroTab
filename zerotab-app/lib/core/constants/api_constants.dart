class ApiConstants {
  // Supabase Edge Functions base URL
  // Format: https://<project-ref>.supabase.co/functions/v1
  // Passed via --dart-define=SUPABASE_FUNCTIONS_URL=...
  static const String baseUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_URL',
    defaultValue: 'https://jegpotribejwrclaiygy.supabase.co/functions/v1',
  );

  // Supabase — falls back to production values if dart-define not passed.
  // The anon key is a public client credential (security is enforced by RLS).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jegpotribejwrclaiygy.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplZ3BvdHJpYmVqd3JjbGFpeWd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDY1NDIsImV4cCI6MjA5NTI4MjU0Mn0.hwg_U3XCjOObW2pt4mHW_4cHn4jB3IZKU873ReMPb6E',
  );

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

  // AI Chat
  static const String aiChatMessage   = '/ai-chat/message';
  static const String aiChatQuick     = '/ai-chat/quick';
  static const String aiChatSessions  = '/ai-chat/sessions';
  static const String aiChatHistory   = '/ai-chat/history';
}
