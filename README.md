# ZeroTab — AI-powered personal finance tracker for India

> **Know where every rupee goes.** Banks, credit cards, loans, mutual funds — one app, one AI-generated weekly insight written like your personal CFO.

---

## Quick start (3 steps)

### Step 1 — Supabase (free)

1. Create a project at [supabase.com](https://supabase.com) (free tier works)
2. Go to **SQL Editor** → paste and run `supabase/migrations/001_initial_schema.sql`
3. Copy your **Project URL**, **anon key**, **service_role key** from Settings → API

### Step 2 — Backend

```bash
cd zerotab-backend
bash setup.sh           # creates .env, installs deps, guides you
# Edit .env with your keys, then:
npm run dev             # starts on :3000
```

Minimum required `.env` values to run:

| Key | Where to get it | Cost |
|-----|-----------------|------|
| `SUPABASE_URL` | Supabase → Settings → API | Free |
| `SUPABASE_ANON_KEY` | Supabase → Settings → API | Free |
| `SUPABASE_SERVICE_KEY` | Supabase → Settings → API | Free |
| `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) | Pay per use |
| `UPSTASH_REDIS_URL` | [upstash.com](https://upstash.com) → New Redis | Free tier |
| `UPSTASH_REDIS_TOKEN` | Upstash → Redis → REST | Free tier |

Optional (for push notifications):

| Key | Where to get it | Cost |
|-----|-----------------|------|
| `FCM_PROJECT_ID` | [Firebase Console](https://console.firebase.google.com) → Project Settings | Free |
| `FCM_SERVICE_ACCOUNT_JSON` | Firebase → Project Settings → Service Accounts → Generate key | Free |

Optional (for analytics):

| Key | Where to get it | Cost |
|-----|-----------------|------|
| `POSTHOG_API_KEY` | [posthog.com](https://posthog.com) | Free tier |

> **No Upstash?** Leave `UPSTASH_REDIS_URL` empty and run a local Redis: `redis-server` (BullMQ will use `localhost:6379` automatically).

### Step 3 — Flutter app

```bash
cd zerotab-app

# Edit run_dev.sh — fill in SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL
bash run_dev.sh         # downloads fonts + runs the app
```

---

## Project structure

```
ZeroTab/
├── supabase/migrations/001_initial_schema.sql   ← Run this in Supabase SQL editor
│
├── zerotab-backend/                ← Node.js + Fastify + TypeScript
│   ├── src/
│   │   ├── index.ts                ← Server entry point
│   │   ├── routes/                 ← aa, accounts, transactions, mf, insights, users
│   │   ├── services/
│   │   │   ├── aaService.ts        ← Finvu AA consent + data fetch + category classifier
│   │   │   ├── smsParser.ts        ← On-device SMS parser (20 bank templates)
│   │   │   ├── mfService.ts        ← AMFI NAV fetch + CAS PDF parser + XIRR
│   │   │   ├── archetypeEngine.ts  ← 20 financial archetypes + snapshot builder
│   │   │   ├── insightService.ts   ← Claude claude-sonnet-4-5 weekly AI insights
│   │   │   └── notificationService.ts ← FCM HTTP v1 push notifications
│   │   ├── jobs/
│   │   │   ├── queues.ts           ← BullMQ queue definitions
│   │   │   ├── workers.ts          ← Worker handlers (AA fetch, insights, NAV, archetype)
│   │   │   └── index.ts            ← Cron job registrations
│   │   ├── middleware/auth.ts      ← Supabase JWT validation
│   │   └── lib/                    ← supabase.ts, redis.ts
│   ├── .env.example
│   ├── setup.sh                    ← One-command setup
│   └── package.json
│
└── zerotab-app/                    ← Flutter app (Dart)
    ├── lib/
    │   ├── main.dart               ← Entry point + Firebase + Supabase init
    │   ├── core/
    │   │   ├── theme/app_theme.dart ← Design tokens from ZeroTab design system
    │   │   ├── constants/routes.dart ← GoRouter config
    │   │   ├── constants/api_constants.dart
    │   │   └── utils/formatters.dart ← INR formatting, date helpers
    │   ├── features/
    │   │   ├── auth/               ← SplashScreen, PhoneOtpScreen (6-digit)
    │   │   ├── onboarding/         ← 2-slide onboarding
    │   │   ├── connect/            ← ConnectAccountsScreen + Finvu WebView
    │   │   ├── home/               ← HomeScreen (real data), InsightDetail, HealthScore
    │   │   ├── transactions/       ← TransactionsScreen (grouped, additive filters)
    │   │   ├── investments/        ← InvestmentsScreen + CAS PDF upload
    │   │   ├── cashflow/           ← CashFlowScreen (real 6-month chart)
    │   │   ├── debt/               ← DebtTrackerScreen (real balances)
    │   │   └── settings/           ← SettingsScreen (persisted prefs, real revoke)
    │   └── shared/
    │       ├── models/models.dart  ← All domain models + FinancialSnapshotModel
    │       ├── services/providers.dart ← Riverpod providers incl. snapshotProvider
    │       └── widgets/            ← ZTCard, ZTPill, MainScaffold
    ├── run_dev.sh                  ← One-command run with env vars
    └── pubspec.yaml
```

---

## Architecture

```
Flutter App (Dart + Riverpod)
         │
         │ REST + Supabase JWT
         ▼
Fastify Backend (Node.js + TypeScript)
         │
         ├── /aa/*           → Finvu AA SDK (sandbox/prod)
         ├── /accounts/*     → Net worth, account CRUD
         ├── /transactions/* → Paginated list, cashflow, category summary
         ├── /mf/*           → AMFI NAV, CAS PDF import
         ├── /insights/*     → Claude AI insight (weekly)
         └── /users/*        → Profile, snapshot, FCM token
         │
         ├── BullMQ + Redis (Upstash free / local)
         │   ├── aa-fetch        → Runs after AA consent approved
         │   ├── insight-gen     → Monday 9 AM IST (all users)
         │   ├── nav-update      → 10:30 PM IST daily
         │   └── archetype-compute → Sunday midnight IST
         │
         └── Supabase Postgres (RLS on every table)
             users · accounts · transactions
             mf_holdings · ai_insights · consents
```

---

## All API routes

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET  | `/health` | — | Health check |
| POST | `/aa/consent/create` | ✓ | Create Finvu AA consent → returns redirectUrl |
| POST | `/aa/consent/callback` | — | Finvu webhook after user approves |
| POST | `/aa/consent/revoke` | ✓ | Revoke active AA consent |
| POST | `/aa/sync` | ✓ | Manually trigger AA data fetch |
| GET  | `/accounts` | ✓ | List all accounts |
| POST | `/accounts` | ✓ | Add manual account |
| GET  | `/accounts/summary` | ✓ | Net worth breakdown |
| GET  | `/transactions` | ✓ | Paginated list (filter by category, date, search) |
| GET  | `/transactions/summary` | ✓ | Category totals for a month |
| GET  | `/transactions/cashflow` | ✓ | 6-month income vs spend |
| POST | `/transactions` | ✓ | Manual transaction entry |
| GET  | `/mf/holdings` | ✓ | MF holdings with current NAV |
| POST | `/mf/cas-upload` | ✓ | Upload CAMS/KFintech CAS PDF |
| GET  | `/mf/search?q=` | — | Search AMFI scheme list |
| GET  | `/insights/latest` | ✓ | Latest weekly AI insight |
| GET  | `/insights` | ✓ | All insights (last 10) |
| POST | `/insights/generate` | ✓ | Trigger insight generation now |
| GET  | `/users/me` | ✓ | User profile |
| PUT  | `/users/me` | ✓ | Update name |
| GET  | `/users/me/snapshot` | ✓ | Full financial snapshot (savings rate, EMI ratio, etc.) |
| POST | `/users/me/register` | ✓ | Upsert user after OTP login |
| DELETE | `/users/me` | ✓ | Delete account (GDPR) |
| POST | `/users/me/fcm-token` | ✓ | Register push token |

---

## Flutter app screens

| Route | Screen | Data source |
|-------|--------|-------------|
| `/splash` | Animated splash | — |
| `/onboard` | 2-slide onboarding | — |
| `/login` | Phone + 6-digit OTP | Supabase Auth |
| `/connect` | AA / SMS / CAS connect | Backend + Finvu WebView |
| `/home` | Net worth + insight card + real stats | `/accounts/summary` + `/users/me/snapshot` |
| `/transactions` | Grouped list + additive filters | `/transactions` |
| `/investments` | MF holdings + donut chart | `/mf/holdings` |
| `/cashflow` | Income vs spend bar chart | `/transactions/cashflow` |
| `/debt` | Loans + credit cards + utilization | `/accounts` + snapshot |
| `/insight/:id` | Full AI insight + action items | `/insights/:id` |
| `/health` | Real health score gauge (computed) | `/users/me/snapshot` |
| `/settings` | Accounts, persisted notif prefs, revoke, delete | `/accounts` + SharedPreferences |

---

## Running tests

```bash
cd zerotab-backend
npm test
# Runs SMS parser test suite (20 bank templates)
```

---

## Finvu AA sandbox — how to test end-to-end

1. Register at [finvu.in/developers](https://finvu.in/developers) → get sandbox credentials
2. Set `FINVU_CLIENT_API_KEY` and `FINVU_FIU_ENTITY_ID` in backend `.env`
3. In the app → Connect accounts → Bank accounts via AA
4. `POST /aa/consent/create` is called → Finvu WebView opens
5. On the Finvu sandbox page, approve with test OTP `123456`
6. Finvu fires callback → `POST /aa/consent/callback` (update backend URL in Finvu dashboard)
7. BullMQ job runs `fetchAAData` → accounts + transactions populate

---

## Design tokens

All sourced from the ZeroTab Design System HTML:

```dart
AppColors.bg       = Color(0xFF0A0A0F)   // page background
AppColors.accent   = Color(0xFF7B6FFF)   // primary CTA
AppColors.teal     = Color(0xFF00BFA6)   // AI / insights
AppColors.green    = Color(0xFF2ECC71)   // income / positive
AppColors.red      = Color(0xFFE74C3C)   // expense / danger
AppColors.amber    = Color(0xFFF0A500)   // warning / caution
// Font: DM Sans (400/500/600/700) + DM Mono (400)
```

---

## Free tier summary

| Service | Free tier |
|---------|-----------|
| Supabase | 500 MB DB, 2 GB bandwidth, 50 MB file storage |
| Upstash Redis | 10,000 req/day, 256 MB |
| Firebase FCM | Unlimited push notifications |
| AMFI NAV API | Completely free, no auth |
| PostHog | 1M events/month |
| Anthropic Claude | Pay per token (~₹0.15 per insight) |
| Railway | $5 credit/month (covers ~1 backend instance) |

> **Total free running cost: ~₹0** for development. ~₹5–15/month at 1,000 users (Anthropic API only).
