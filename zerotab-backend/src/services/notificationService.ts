/**
 * ZeroTab — Push Notification Service
 * Uses Firebase Cloud Messaging HTTP v1 API (OAuth2-based, not deprecated legacy API).
 * Free: FCM is completely free with no send limits for standard notifications.
 */
import axios from 'axios';
import { GoogleAuth } from 'google-auth-library';
import { supabaseAdmin } from '../lib/supabase.js';

interface PushPayload {
  title: string;
  body:  string;
  data?: Record<string, string>;
}

// Get OAuth2 access token for FCM v1 API
let _cachedToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string | null> {
  const serviceAccountJson = process.env.FCM_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) return null;

  // Return cached token if still valid (with 5 min buffer)
  if (_cachedToken && Date.now() < _cachedToken.expiresAt - 300_000) {
    return _cachedToken.token;
  }

  try {
    const credentials = JSON.parse(serviceAccountJson);
    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
    const client = await auth.getClient();
    const tokenResponse = await client.getAccessToken();
    const token = tokenResponse.token;
    if (!token) return null;

    _cachedToken = { token, expiresAt: Date.now() + 3600_000 }; // 1h cache
    return token;
  } catch (err) {
    console.error('[FCM] Failed to get access token:', err);
    return null;
  }
}

export async function sendPushToUser(userId: string, payload: PushPayload): Promise<void> {
  const { data: user } = await supabaseAdmin
    .from('users')
    .select('metadata')
    .eq('id', userId)
    .single();

  const fcmToken = (user?.metadata as Record<string, string> | null)?.fcm_token;
  if (!fcmToken) return; // user hasn't registered a push token

  await sendFcmPush(fcmToken, payload);
}

export async function sendFcmPush(token: string, payload: PushPayload): Promise<void> {
  const projectId = process.env.FCM_PROJECT_ID;
  if (!projectId) {
    console.warn('[FCM] FCM_PROJECT_ID not set — skipping push notification');
    return;
  }

  const accessToken = await getFcmAccessToken();
  if (!accessToken) {
    console.warn('[FCM] Could not obtain access token — skipping push notification');
    return;
  }

  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  try {
    await axios.post(url, {
      message: {
        token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data ?? {},
        android: {
          notification: {
            color: '#7B6FFF',
            channel_id: 'zerotab_main',
          },
        },
        apns: {
          payload: {
            aps: { badge: 1, sound: 'default' },
          },
        },
      },
    }, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });
  } catch (err: any) {
    // Non-fatal — log and continue
    console.error('[FCM] Push send failed:', err?.response?.data ?? err.message);
  }
}
