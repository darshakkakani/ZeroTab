$ErrorActionPreference = "Stop"

Write-Host "=== ZeroTab Pre-Start Verification ===" -ForegroundColor Cyan
Write-Host ""

# Check Flutter installation
Write-Host "[1/6] Checking Flutter installation..." -ForegroundColor Yellow
try {
    $flutterVersion = flutter --version 2>&1 | Select-String "Flutter" | Select-Object -First 1
    Write-Host "  OK Flutter found: $flutterVersion" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR Flutter not found. Please install Flutter." -ForegroundColor Red
    exit 1
}

# Check if Supabase is running
Write-Host "[2/6] Checking Supabase local instance..." -ForegroundColor Yellow
$supabaseRunning = Get-NetTCPConnection -LocalPort 54321 -State Listen -ErrorAction SilentlyContinue
if ($supabaseRunning) {
    Write-Host "  OK Supabase is running on port 54321" -ForegroundColor Green
}
else {
    Write-Host "  WARNING Supabase not detected on port 54321" -ForegroundColor Yellow
    Write-Host "    Run 'supabase start' if using local instance" -ForegroundColor Gray
}

# Check environment variables
Write-Host "[3/6] Checking environment configuration..." -ForegroundColor Yellow
$SUPABASE_URL = if ($env:SUPABASE_URL) { $env:SUPABASE_URL } else { "https://jegpotribejwrclaiygy.supabase.co" }
$SUPABASE_ANON_KEY = if ($env:SUPABASE_ANON_KEY) { $env:SUPABASE_ANON_KEY } else { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplZ3BvdHJpYmVqd3JjbGFpeWd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDY1NDIsImV4cCI6MjA5NTI4MjU0Mn0.hwg_U3XCjOObW2pt4mHW_4cHn4jB3IZKU873ReMPb6E" }
$API_BASE_URL = if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "http://127.0.0.1:3000" }

$urlPreview = $SUPABASE_URL.Substring(0, [Math]::Min(40, $SUPABASE_URL.Length))
Write-Host "  OK SUPABASE_URL: $urlPreview..." -ForegroundColor Green
Write-Host "  OK API_BASE_URL: $API_BASE_URL" -ForegroundColor Green

# Check if backend is running
Write-Host "[4/6] Checking backend API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$API_BASE_URL/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
    Write-Host "  OK Backend API is responding" -ForegroundColor Green
}
catch {
    Write-Host "  WARNING Backend API not responding at $API_BASE_URL" -ForegroundColor Yellow
    Write-Host "    Start backend if needed" -ForegroundColor Gray
}

# Check port availability
Write-Host "[5/6] Checking port availability..." -ForegroundColor Yellow
$WEB_PORT = if ($env:ZEROTAB_WEB_PORT) { [int]$env:ZEROTAB_WEB_PORT } else { 8080 }
$listeners = Get-NetTCPConnection -LocalPort $WEB_PORT -State Listen -ErrorAction SilentlyContinue
if ($listeners) {
    $pids = $listeners.OwningProcess | Sort-Object -Unique
    $pidList = $pids -join ', '
    Write-Host "  WARNING Port $WEB_PORT is already in use (PID: $pidList)" -ForegroundColor Yellow
    Write-Host "    Stop existing server or set different port" -ForegroundColor Gray
}
else {
    Write-Host "  OK Port $WEB_PORT is available" -ForegroundColor Green
}

# Run Flutter doctor
Write-Host "[6/6] Running Flutter doctor..." -ForegroundColor Yellow
$doctorOutput = flutter doctor --no-version-check 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  OK Flutter environment is healthy" -ForegroundColor Green
}
else {
    Write-Host "  WARNING Flutter doctor found some issues (non-critical)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Verification Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ready to start ZeroTab!" -ForegroundColor Green
Write-Host "Run: .\run_dev.ps1" -ForegroundColor Cyan
Write-Host ""
