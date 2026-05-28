$ErrorActionPreference = "SilentlyContinue"

# ── Flutter SDK ───────────────────────────────────────────────
$flutterSdk = "C:\flutter_sdk\bin"
if (Test-Path $flutterSdk) { $env:PATH = "$flutterSdk;" + $env:PATH }

# ── Environment ───────────────────────────────────────────────
$SUPABASE_URL      = if ($env:SUPABASE_URL)      { $env:SUPABASE_URL }      else { "https://jegpotribejwrclaiygy.supabase.co" }
$SUPABASE_ANON_KEY = if ($env:SUPABASE_ANON_KEY) { $env:SUPABASE_ANON_KEY } else { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplZ3BvdHJpYmVqd3JjbGFpeWd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDY1NDIsImV4cCI6MjA5NTI4MjU0Mn0.hwg_U3XCjOObW2pt4mHW_4cHn4jB3IZKU873ReMPb6E" }
$SUPABASE_FUNCTIONS_URL = if ($env:SUPABASE_FUNCTIONS_URL) { $env:SUPABASE_FUNCTIONS_URL } else { "$SUPABASE_URL/functions/v1" }
$POSTHOG_KEY       = if ($env:POSTHOG_KEY)       { $env:POSTHOG_KEY }       else { "" }

# ── Use the existing pub cache (already cached — don't move it) ──
$env:PUB_CACHE = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "$env:LOCALAPPDATA\Pub\Cache" }

# ── Clean up locked build artifacts from previous run ────────
Write-Host ""
Write-Host "  Cleaning previous build artifacts..." -ForegroundColor DarkGray

# Kill any dart/flutter processes holding the build folder
Get-Process | Where-Object { $_.Name -match "^(dart|flutter|flutter_tester)$" } | Stop-Process -Force -ErrorAction SilentlyContinue

# Use cmd rd which bypasses PowerShell file-lock issues
if (Test-Path "build") {
    cmd /c "rd /s /q build" 2>$null
    # If rd failed (antivirus/deep lock), try icacls + rd
    if (Test-Path "build") {
        cmd /c "icacls build /grant Everyone:F /T /Q" 2>$null
        cmd /c "rd /s /q build" 2>$null
    }
}

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ZeroTab Dev Server" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  URL    : http://localhost:8080" -ForegroundColor White
Write-Host "  Backend: $SUPABASE_FUNCTIONS_URL (Edge Functions)" -ForegroundColor White
Write-Host ""
Write-Host "  HOT RELOAD (after first launch):" -ForegroundColor Yellow
Write-Host "    r  = hot reload       < 1 second  (UI/logic changes)" -ForegroundColor Green
Write-Host "    R  = hot restart      ~ 3 seconds (state reset)" -ForegroundColor Green
Write-Host "    q  = quit" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  FIRST LAUNCH takes 3-5 min (compiles 180 packages once)." -ForegroundColor DarkGray
Write-Host "  Every change after that is instant — do NOT quit and rerun." -ForegroundColor DarkGray
Write-Host ""

# ── Run ──────────────────────────────────────────────────────
# HTML renderer set via flutter_bootstrap.js (--web-renderer removed in Flutter 3.22+)
# --hot    : incremental compilation
# --no-pub : skip pub resolve (packages already resolved)
flutter run `
  -d chrome `
  --web-port=8080 `
  --hot `
  --no-pub `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=SUPABASE_FUNCTIONS_URL=$SUPABASE_FUNCTIONS_URL `
  --dart-define=POSTHOG_KEY=$POSTHOG_KEY
