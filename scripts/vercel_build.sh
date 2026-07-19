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

# This repo was hand-authored rather than scaffolded with `flutter create`,
# so the platform-specific web/ folder (index.html, manifest.json, icons)
# doesn't exist yet. Generate it if missing — safe to run repeatedly, and
# does NOT touch existing lib/ code, only adds the platform folder.
if [ ! -f "web/index.html" ]; then
  echo "web/ folder missing — scaffolding it now..."
  flutter create . --platforms web
fi

# sqflite on web (sqflite_common_ffi_web) needs sqlite3.wasm + a worker script
# copied into web/ — these aren't created by `flutter create`, only by this
# package-specific setup command. Without them the app loads a blank page and
# throws "Failed to fetch a worker script" at runtime.
if [ ! -f "web/sqflite_sw.js" ]; then
  echo "Setting up sqflite web worker files..."
  dart run sqflite_common_ffi_web:setup
fi

echo "Building release web bundle..."
flutter build web --release --source-maps \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

echo "Build complete: flutter_app/build/web"
