import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Background handler — MUST be a top-level function ────────
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage msg) async {
  debugPrint('[FCM] Background: ${msg.messageId}');
}

// ── Notification channel (Android) ───────────────────────────
const _kChannel = AndroidNotificationChannel(
  'settle_channel',
  'SettleUp Notifications',
  description: 'Expense splits and group activity',
  importance: Importance.max,
);

class FcmService {
  FcmService._();

  static final _messaging   = FirebaseMessaging.instance;
  static final _localNotif  = FlutterLocalNotificationsPlugin();

  // Call once from main() AFTER Firebase.initializeApp()
  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);

    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Android notification channel
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kChannel);

    // Local notification plugin init
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:     DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Foreground messages → show as local notification
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Token refresh → sync to Supabase
    _messaging.onTokenRefresh.listen(_saveToken);

    // Initial token save
    await _saveInitialToken();
  }

  static Future<void> _saveInitialToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS requires APNs token before FCM token is available
        final apns = await _messaging.getAPNSToken();
        if (apns == null) return;
      }
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('[FCM] saveInitialToken: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .upsert({'id': uid, 'fcm_token': token});
    } catch (e) {
      debugPrint('[FCM] saveToken: $e');
    }
  }

  static void _showLocal(RemoteMessage msg) {
    final n = msg.notification;
    if (n == null) return;
    _localNotif.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannel.id, _kChannel.name,
          importance: Importance.max, priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: msg.data['expense_id'] ?? msg.data['split_id'],
    );
  }

  static void _onTap(NotificationResponse res) {
    // Navigate based on payload if needed
    debugPrint('[FCM] Notification tapped: ${res.payload}');
  }

  // Call when user logs in/out to refresh token state
  static Future<void> refreshToken() => _saveInitialToken();
}
