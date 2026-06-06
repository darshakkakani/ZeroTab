import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/auth/screens/phone_otp_screen.dart';
import '../../features/connect/screens/connect_accounts_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/investments/screens/investments_screen.dart';
import '../../features/cashflow/screens/cashflow_screen.dart';
import '../../features/debt/screens/debt_tracker_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/home/screens/insight_detail_screen.dart';
import '../../features/home/screens/health_score_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/chat_hub_screen.dart';
import '../../shared/widgets/main_scaffold.dart';
import '../../shared/services/providers.dart';

// ── 120ms fade — feels instant, avoids jarring hard-cut ──────
Page<void> _fade(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 120),
      reverseTransitionDuration: const Duration(milliseconds: 80),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

// ── Tab switch — no animation (instantaneous) ─────────────────
Page<void> _instant(GoRouterState s, Widget child) =>
    NoTransitionPage<void>(key: s.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    // ── Redirect — synchronous Supabase check ──────────────────
    // IMPORTANT: Do NOT use ref.watch/ref.read here — that caused
    // GoRouter recreation on every auth change (the root cause of
    // "need to refresh page after login" bug).
    redirect: (context, state) {
      final isLoggedIn =
          Supabase.instance.client.auth.currentUser != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/onboard') ||
          loc.startsWith('/login') ||
          loc == '/splash';

      if (!isLoggedIn && !isAuthRoute) return '/splash';
      // After login OTP succeeds → immediately jump to home
      if (isLoggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, s) => _fade(s, const SplashScreen()),
      ),
      GoRoute(
        path: '/onboard',
        pageBuilder: (_, s) => _fade(s, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => _fade(s, const PhoneOtpScreen()),
      ),
      GoRoute(
        path: '/connect',
        pageBuilder: (_, s) => _fade(s, const ConnectAccountsScreen()),
      ),

      // ── Main app shell with bottom nav ──────────────────────
      ShellRoute(
        pageBuilder: (context, state, child) => NoTransitionPage(
          key: state.pageKey,
          child: MainScaffold(child: child),
        ),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, s) => _instant(s, const HomeScreen()),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (_, s) => _instant(s, const TransactionsScreen()),
          ),
          GoRoute(
            path: '/investments',
            pageBuilder: (_, s) => _instant(s, const InvestmentsScreen()),
          ),
          GoRoute(
            path: '/cashflow',
            pageBuilder: (_, s) => _instant(s, const CashFlowScreen()),
          ),
          GoRoute(
            path: '/debt',
            pageBuilder: (_, s) => _instant(s, const DebtTrackerScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, s) => _instant(s, const SettingsScreen()),
          ),
          GoRoute(
            path: '/insight/:id',
            pageBuilder: (_, s) => _fade(
              s,
              InsightDetailScreen(insightId: s.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/health',
            pageBuilder: (_, s) => _fade(s, const HealthScoreScreen()),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (_, s) => _fade(s, const ChatHubScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (_, s) {
                  final query = s.uri.queryParameters['q'];
                  return _fade(s, ChatScreen(initialQuery: query));
                },
              ),
              GoRoute(
                path: 'session/:sessionId',
                pageBuilder: (_, s) => _fade(
                  s,
                  ChatScreen(sessionId: s.pathParameters['sessionId']),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // ── Trigger redirect re-eval on every auth state change ──────
  // When OTP verification succeeds → Supabase fires auth event
  // → ref.listen callback fires → router.refresh() re-runs redirect
  // → isLoggedIn is now true → navigates to /home instantly.
  // No page refresh needed.
  ref.listen(authStateProvider, (_, __) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});
