# ZeroTab — Build Release APK (Supabase-only architecture)
# Usage: .\build_apk.ps1
#
# Set these environment variables before running:
#   $env:SUPABASE_URL = "https://YOUR_PROJECT_REF.supabase.co"
#   $env:SUPABASE_ANON_KEY = "YOUR_ANON_KEY"

$SUPABASE_URL     = $env:SUPABASE_URL
$SUPABASE_ANON_KEY = $env:SUPABASE_ANON_KEY

if (-not $SUPABASE_URL -or -not $SUPABASE_ANON_KEY) {
    Write-Error "Please set SUPABASE_URL and SUPABASE_ANON_KEY environment variables"
    exit 1
}

$SUPABASE_FUNCTIONS_URL = "$SUPABASE_URL/functions/v1"

Write-Host "Building APK with:" -ForegroundColor Cyan
Write-Host "  SUPABASE_URL:           $SUPABASE_URL"
Write-Host "  SUPABASE_FUNCTIONS_URL: $SUPABASE_FUNCTIONS_URL"

flutter build apk --release `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=SUPABASE_FUNCTIONS_URL=$SUPABASE_FUNCTIONS_URL

Write-Host ""
Write-Host "APK built at: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
