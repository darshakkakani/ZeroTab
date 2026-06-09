import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/api_constants.dart';
import 'core/constants/routes.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/api_service.dart';

final FlutterLocalNotificationsPlugin _localNotifs =
    FlutterLocalNotificationsPlugin();

final Future<void> _bootstrapFuture = _bootstrap();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error');
    debugPrintStack(stackTrace: stack);
    return false;
  };

  runApp(const ProviderScope(child: ZeroTabBootstrap()));
}

Future<void> _bootstrap() async {
  try {
    // Set system UI overlay style synchronously (no await needed)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

    if (ApiConstants.supabaseUrl.isEmpty ||
        ApiConstants.supabaseAnonKey.isEmpty) {
      throw Exception(
        'Supabase URL or Anon Key is empty. '
        'Run via .\\run_dev.ps1 (or pass --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY).',
      );
    }

    // Initialize Supabase (critical - must complete)
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      publishableKey: ApiConstants.supabaseAnonKey,
    );

    // Initialize API service (synchronous)
    api.init();

    // Run non-critical initializations in parallel to speed up startup
    await Future.wait([
      // Firebase & FCM (non-critical)
      _initFirebase(),
      // Local notifications (non-critical)
      _initNotifications(),
      // PostHog analytics (non-critical)
      _initPostHog(),
    ], eagerError: false); // Continue even if some fail
  } catch (error, stackTrace) {
    debugPrint('[StartupError] $error');
    debugPrintStack(stackTrace: stackTrace);
    rethrow;
  }
}

Future<void> _initFirebase() async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );
    await _setupFCM();
  } catch (e) {
    debugPrint('[Firebase] Init skipped: $e');
  }
}

Future<void> _initNotifications() async {
  if (kIsWeb) return; // local notifications not supported on web
  try {
    await _localNotifs.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  } catch (e) {
    debugPrint('[Notifications] Init skipped: $e');
  }
}

Future<void> _initPostHog() async {
  const posthogKey = String.fromEnvironment('POSTHOG_KEY', defaultValue: '');
  if (posthogKey.isEmpty) return;
  debugPrint('[PostHog] Key provided but package not installed — skipping');
}

Future<void> _setupFCM() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  if (token != null) {
    _registerFcmToken(token);
  }

  messaging.onTokenRefresh.listen((token) {
    _registerFcmToken(token);
  });

  FirebaseMessaging.onMessage.listen((msg) {
    final notif = msg.notification;
    if (notif == null) return;
    _localNotifs.show(
      notif.hashCode,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'zerotab_main',
          'ZeroTab',
          importance: Importance.high,
          priority: Priority.high,
          color: AppColors.accent,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  });
}

Future<void> _registerFcmToken(String token) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return;
  try {
    // Register via backend Edge Function (existing flow)
    await api.post(ApiConstants.fcmToken, data: {'token': token});
  } catch (_) {}
  try {
    // ALSO upsert directly into profiles.fcm_token so SettleUp push
    // notifications can find the token without going through Edge Functions.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      await Supabase.instance.client
          .from('profiles')
          .upsert({'id': uid, 'fcm_token': token});
    }
  } catch (_) {
    // Non-fatal — SettleUp push degrades gracefully without token.
  }
}

class ZeroTabBootstrap extends StatelessWidget {
  const ZeroTabBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: AppColors.bgVoid,
              body: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return StartupErrorApp(
            error: snapshot.error.toString(),
            stackTrace: snapshot.stackTrace?.toString() ?? '',
          );
        }

        return const ZeroTabApp();
      },
    );
  }
}

class ZeroTabApp extends ConsumerWidget {
  const ZeroTabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ZeroTab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  final String error;
  final String stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.bgVoid,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ZeroTab startup failed',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(error),
                    const SizedBox(height: 16),
                    Text(stackTrace),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
