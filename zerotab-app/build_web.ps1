$ErrorActionPreference = "Stop"

$SUPABASE_URL = if ($env:SUPABASE_URL) { $env:SUPABASE_URL } else { "https://xxxxxxxxxxxxxxxxxxxx.supabase.co" }
$SUPABASE_ANON_KEY = if ($env:SUPABASE_ANON_KEY) { $env:SUPABASE_ANON_KEY } else { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." }
$API_BASE_URL = if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "http://127.0.0.1:3000" }
$POSTHOG_KEY = if ($env:POSTHOG_KEY) { $env:POSTHOG_KEY } else { "" }
$PUB_CACHE = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "C:\pub-cache" }
$TEMP_DIR = if ($env:ZEROTAB_TEMP) { $env:ZEROTAB_TEMP } else { "D:\flutter-temp" }

New-Item -ItemType Directory -Force $TEMP_DIR | Out-Null
$env:TEMP = $TEMP_DIR
$env:TMP = $TEMP_DIR
$env:PUB_CACHE = $PUB_CACHE

flutter build web --no-wasm-dry-run `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=API_BASE_URL=$API_BASE_URL `
  --dart-define=POSTHOG_KEY=$POSTHOG_KEY
