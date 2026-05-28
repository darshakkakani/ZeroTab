$ErrorActionPreference = "Stop"

if (-not (Test-Path ".env")) {
  Copy-Item ".env.example" ".env"
  Write-Host "Created .env from .env.example. Fill in your credentials before starting the backend."
}

npm install

Write-Host ""
Write-Host "Backend setup complete."
Write-Host "Start it with: npm run dev"
