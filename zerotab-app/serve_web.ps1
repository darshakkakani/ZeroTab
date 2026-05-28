$ErrorActionPreference = "Stop"

$PORT = if ($env:ZEROTAB_WEB_PORT) { [int]$env:ZEROTAB_WEB_PORT } else { 8080 }
$root = Join-Path $PSScriptRoot "build\web"

if (-not (Test-Path $root)) {
  throw "Web build not found at $root. Run: C:\flutter-sdk\bin\flutter.bat build web"
}

Set-Location $root
python -m http.server $PORT
