#!/usr/bin/env bash
# Runs the Flutter web app in DEV mode (hot reload) via `flutter run -d chrome`,
# pulling SUPABASE_URL / SUPABASE_ANON_KEY / WEB_PORT from .env.web.
#
# Usage:
#   cp .env.web.example .env.web   # once, then fill in real values
#   ./scripts/run_web.sh
#
# Requires: Flutter SDK on PATH, Chrome installed.

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

echo "Enabling Flutter web support (no-op if already enabled)..."
flutter config --enable-web >/dev/null

cd flutter_app
echo "Fetching packages..."
flutter pub get

# Scaffold the web/ platform folder if this is the first time it's been built
# (the repo was hand-authored, not created via `flutter create`).
if [ ! -f "web/index.html" ]; then
  echo "web/ folder missing — scaffolding it now..."
  flutter create . --platforms web
fi

echo "Launching web app on http://localhost:${WEB_PORT} ..."
flutter run -d chrome \
  --web-port="${WEB_PORT}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"
