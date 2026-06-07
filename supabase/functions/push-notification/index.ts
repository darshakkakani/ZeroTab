// ZeroTab Push Notification Edge Function
// Deploy: supabase functions deploy push-notification --no-verify-jwt
// Secrets needed (set via dashboard or CLI):
//   supabase secrets set FCM_PROJECT_ID=zerotab-ff69e
//   supabase secrets set FCM_SERVICE_ACCOUNT='{"type":"service_account","project_id":...}'

import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

interface NotificationRecord {
  id: string
  user_id: string
  title: string
  body: string
  data: Record<string, string>
}

interface WebhookPayload {
  type: 'INSERT'
  table: string
  record: NotificationRecord
  schema: 'public'
  old_record: null | Record<string, unknown>
}

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

Deno.serve(async (req) => {
  try {
    // Load Firebase service account from environment variable (set as Supabase secret)
    const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT')
    const projectId          = Deno.env.get('FCM_PROJECT_ID') ?? 'zerotab-ff69e'

    if (!serviceAccountJson) {
      console.error('FCM_SERVICE_ACCOUNT secret not set')
      return new Response('no_fcm_config', { status: 200 })
    }

    const serviceAccount = JSON.parse(serviceAccountJson)
    const payload: WebhookPayload = await req.json()
    const { user_id, title, body, data } = payload.record

    // 1. Fetch recipient FCM token
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('fcm_token')
      .eq('id', user_id)
      .single()

    if (error || !profile?.fcm_token) {
      console.log('No FCM token for user:', user_id)
      return new Response('no_token', { status: 200 })
    }

    // 2. Get Google OAuth2 access token
    const accessToken = await getAccessToken(serviceAccount)

    // 3. Send FCM push notification
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: { title, body },
            data: data ?? {},
            android: { priority: 'high' },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
          },
        }),
      },
    )

    const result = await fcmRes.json()

    // Clean stale tokens
    if (!fcmRes.ok) {
      const code = result?.error?.details?.[0]?.errorCode
      if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT') {
        await supabase.from('profiles').update({ fcm_token: null }).eq('id', user_id)
      }
      console.error('FCM error:', JSON.stringify(result))
    }

    return new Response(JSON.stringify(result), {
      status: fcmRes.ok ? 200 : 500,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Edge Function error:', err)
    return new Response(String(err), { status: 500 })
  }
})

function getAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  return new Promise((resolve, reject) => {
    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key:   serviceAccount.private_key,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })
    jwtClient.authorize((err, tokens) => {
      if (err || !tokens?.access_token) {
        reject(err ?? new Error('No access_token'))
        return
      }
      resolve(tokens.access_token)
    })
  })
}
