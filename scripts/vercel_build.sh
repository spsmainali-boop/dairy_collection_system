#!/usr/bin/env bash
# Vercel's build environment has no Flutter pre-installed, so this script
# fetches the stable SDK (shallow clone, fast) and builds the web release,
# reading Supabase credentials from Vercel Environment Variables.
#
# Required Vercel env vars (set in Project Settings -> Environment Variables):
#   SUPABASE_URL       - your cloud Supabase project URL
#   SUPABASE_ANON_KEY  - your cloud Supabase anon/public key
#
# Referenced by vercel.json as the buildCommand.

set -euo pipefail

: "${SUPABASE_URL:?Set SUPABASE_URL in Vercel project env vars}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY in Vercel project env vars}"

echo "Fetching Flutter SDK (stable channel, shallow clone)..."
git clone https://github.com/flutter/flutter.git --depth 1 -b stable /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"

flutter config --enable-web --no-analytics
flutter precache --web

cd flutter_app
flutter pub get

echo "Building release web bundle..."
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

echo "Build complete: flutter_app/build/web"
