#!/bin/bash
# ZeroTab Flutter App — run with environment variables
# Usage: bash run_dev.sh
# Edit the values below, then run this script.

# ── Fill these in ─────────────────────────────────────────
SUPABASE_URL="https://xxxxxxxxxxxxxxxxxxxx.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
API_BASE_URL="http://10.0.2.2:3000"   # Android emulator → localhost backend
# API_BASE_URL="http://localhost:3000" # iOS simulator
POSTHOG_KEY=""                          # Optional: phc_xxx from posthog.com

# ─────────────────────────────────────────────────────────

set -e

# Download fonts if not present
if [ ! -f "assets/fonts/DMSans-Regular.ttf" ]; then
  echo "📦 Fonts not found — downloading..."
  bash scripts/download_fonts.sh
fi

echo "📱 Running ZeroTab Flutter app..."
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=POSTHOG_KEY="$POSTHOG_KEY"
