# check_theme.ps1 — guardrail against design-system drift.
#
# Fails (exit 1) if any of the banned "drift" colours reappear as raw hex in
# feature/shared UI code. Every colour must come from AppColors in
# lib/core/theme/app_theme.dart. Run from anywhere:
#     pwsh tool/check_theme.ps1
#
# The canonical tokens these map to:
#   7B2FFE -> AppColors.accent (#7B5FFF)   22C55E -> AppColors.green (#1EBF7A)
#   EF4444 -> AppColors.red (#E04A3F)       F59E0B/FF8C42/FFAA00 -> AppColors.gold
#   00CFDE/00C896/00C9B1 -> AppColors.teal  3B82F6 -> AppColors.dataETF (#4F9DF7)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$drift = '22C55E|EF4444|7B2FFE|F59E0B|FF8C42|00CFDE|00C896|00C9B1|3B82F6|FFAA00'

$paths = @((Join-Path $root 'lib\features'), (Join-Path $root 'lib\shared'))
$files = Get-ChildItem -Recurse -Path $paths -Filter *.dart -ErrorAction SilentlyContinue
$hits  = @()
foreach ($f in $files) {
  $m = Select-String -Path $f.FullName -Pattern $drift
  if ($m) { $hits += $m }
}

if ($hits.Count -gt 0) {
  Write-Host "THEME DRIFT DETECTED — replace raw drift hex with an AppColors token:" -ForegroundColor Red
  $hits | ForEach-Object {
    Write-Host ("  {0}:{1}  {2}" -f (Split-Path $_.Path -Leaf), $_.LineNumber, $_.Line.Trim())
  }
  exit 1
}

Write-Host "Theme check passed — no drift colours in lib/features or lib/shared." -ForegroundColor Green
exit 0
