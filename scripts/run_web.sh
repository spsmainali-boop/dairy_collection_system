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

echo "Fetching packages..."
(cd flutter_app && flutter pub get)

echo "Launching web app on http://localhost:${WEB_PORT} ..."
(cd flutter_app && flutter run -d chrome \
  --web-port="${WEB_PORT}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}")
