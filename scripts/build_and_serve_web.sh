#!/usr/bin/env bash
# Builds a release web bundle (optimized, no hot reload) and serves it with
# Python's built-in HTTP server — closest to how it'll behave once actually
# deployed. Good for a final pre-deploy smoke test on a local server.
#
# Usage:
#   cp .env.web.example .env.web   # once, then fill in real values
#   ./scripts/build_and_serve_web.sh

set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=".env.web"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy .env.web.example to .env.web and fill in your Supabase URL/key first."
  exit 1
fi
set -a
source "$ENV_FILE"
set +a

: "${SUPABASE_URL:?Set SUPABASE_URL in .env.web}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY in .env.web}"
WEB_PORT="${WEB_PORT:-8080}"

flutter config --enable-web >/dev/null
cd flutter_app
flutter pub get

if [ ! -f "web/index.html" ]; then
  echo "web/ folder missing — scaffolding it now..."
  flutter create . --platforms web
fi

if [ ! -f "web/sqflite_sw.js" ]; then
  echo "Setting up sqflite web worker files..."
  dart run sqflite_common_ffi_web:setup
fi

echo "Building release web bundle..."
flutter build web \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

echo "Serving flutter_app/build/web on http://localhost:${WEB_PORT} (Ctrl+C to stop)..."
cd build/web
python3 -m http.server "${WEB_PORT}"
