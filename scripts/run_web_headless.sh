#!/usr/bin/env bash
# Alternative to run_web.sh for environments without Chrome (e.g. a remote VM,
# WSL without GUI passthrough, or a headless container). Uses Flutter's
# built-in `web-server` device — open the printed URL in ANY browser yourself.
#
# Usage:
#   cp .env.web.example .env.web   # once, then fill in real values
#   ./scripts/run_web_headless.sh

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

echo "Serving at http://localhost:${WEB_PORT} — open this URL in your browser."
flutter run -d web-server \
  --web-port="${WEB_PORT}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"
