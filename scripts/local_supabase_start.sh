#!/usr/bin/env bash
# Spins up a FULLY LOCAL Supabase stack (Postgres, Auth, Studio, Edge
# Functions runtime) via Docker, using the Supabase CLI. This means you can
# test the whole app — including auth and sync — with zero cloud account,
# zero internet dependency, entirely on your own machine.
#
# Prerequisites: Docker Desktop running, Supabase CLI installed
#   npm install -g supabase
#
# Usage:
#   ./scripts/local_supabase_start.sh
#
# On first run this also applies supabase/schema.sql and serves the two
# Edge Functions locally. Leave this running in its own terminal tab.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "supabase/.temp" ] && [ ! -f "supabase/config.toml" ]; then
  echo "Initializing local Supabase project config..."
  supabase init
fi

echo "Starting local Supabase stack (Postgres + Auth + Studio)..."
supabase start

echo
echo "Applying schema.sql to the local database..."
supabase db execute --file supabase/schema.sql --local || \
  psql "$(supabase status -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["DB_URL"])')" \
       -f supabase/schema.sql

echo
echo "Serving Edge Functions locally (verify-pin, change-pin)..."
supabase functions serve verify-pin --no-verify-jwt &
supabase functions serve change-pin --no-verify-jwt &

echo
echo "======================================================================"
echo "Local Supabase is up. Copy the API URL + anon key it printed above into"
echo "your .env.web as SUPABASE_URL / SUPABASE_ANON_KEY (see the commented"
echo "Option B block in .env.web.example), then run ./scripts/run_web.sh"
echo "in another terminal tab."
echo "Studio UI (browse your local tables): http://127.0.0.1:54323"
echo "======================================================================"
wait
