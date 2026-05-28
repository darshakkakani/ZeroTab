#!/bin/bash
# ZeroTab Backend — one-command setup
set -e

echo "🚀 ZeroTab Backend Setup"
echo "========================"

# 1. Check .env exists
if [ ! -f .env ]; then
  echo "📋 Creating .env from template..."
  cp .env.example .env
  echo ""
  echo "⚠️  IMPORTANT: Edit .env and fill in your credentials before proceeding."
  echo "   Required: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY, ANTHROPIC_API_KEY"
  echo "   Optional: UPSTASH_REDIS_URL (or uses local Redis on localhost:6379)"
  echo ""
  read -p "Press Enter after filling in .env to continue..."
fi

# 2. Install dependencies
echo ""
echo "📦 Installing dependencies..."
npm install

# 3. Check if local Redis is needed (no Upstash configured)
if ! grep -q "upstash.io" .env 2>/dev/null; then
  echo ""
  echo "ℹ️  No Upstash Redis configured — using local Redis on localhost:6379"
  echo "   Make sure Redis is running: redis-server"
  echo "   (Install: brew install redis / sudo apt install redis-server)"
fi

echo ""
echo "✅ Setup complete! Run the backend with:"
echo "   npm run dev"
echo ""
echo "📝 Then run Supabase migration:"
echo "   1. Open supabase.com → Your project → SQL Editor"
echo "   2. Paste + run: ../supabase/migrations/001_initial_schema.sql"
