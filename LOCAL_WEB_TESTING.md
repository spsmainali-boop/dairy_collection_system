# Local Web Testing Guide

This app targets both Android and Web, but this guide covers **web-only local
testing** — no Android SDK/emulator needed.

There are two ways to get a backend for this, pick one:

- **Path A — your cloud Supabase project** (what you already set up). Fastest
  if it's already running.
- **Path B — fully local Supabase via Docker** (`scripts/local_supabase_start.sh`).
  Zero cloud account, zero internet dependency — everything, including auth,
  runs on your machine. Best if you want a disposable, resettable test env.

Both paths use the same Flutter run scripts afterward.

---

## Path A: test against your cloud Supabase project

```bash
cd dairy_collection_system
cp .env.web.example .env.web
# edit .env.web: set SUPABASE_URL and SUPABASE_ANON_KEY from your project's
# Settings -> API page, and make sure you've already run supabase/schema.sql
# there and inserted test data (see README.md step 2.4), or run the seed
# block manually from supabase/seed.sql.

./scripts/run_web.sh
```
This opens Chrome automatically at `http://localhost:8080` with hot reload —
edit any `.dart` file and press `r` in the terminal to hot-reload.

If you don't have Chrome / are on a headless machine, use:
```bash
./scripts/run_web_headless.sh
```
and open the printed `http://localhost:8080` URL in whatever browser you have.

---

## Path B: fully local Supabase (recommended for repeatable testing)

Prerequisites: Docker Desktop running, Supabase CLI (`npm install -g supabase`).

**Terminal 1** — start the local backend (leave running):
```bash
cd dairy_collection_system
./scripts/local_supabase_start.sh
```
This will:
1. Boot local Postgres + Auth + Studio in Docker.
2. Apply `supabase/schema.sql`.
3. Apply `supabase/seed.sql` (a ready-to-use test center, operator login
   `9800000000` / PIN `0000`, rate chart, and farmer `F001`).
4. Serve the `verify-pin` / `change-pin` Edge Functions locally.
5. Print a local API URL + anon key — copy these.

You can browse/edit the local database visually at **http://127.0.0.1:54323**
(Supabase Studio) — handy for inspecting synced rows during testing.

**Terminal 2** — run the web app against it:
```bash
cp .env.web.example .env.web
# paste the local URL + anon key printed by Terminal 1 into .env.web
# (Option B block, already commented in the template)

./scripts/run_web.sh
```

To reset to a clean state at any point: `supabase db reset` (re-applies
schema + seed, wipes all test data you created in the UI).

---

## Production-like smoke test (release build, static server)

Once dev testing looks good, do one pass against an actual release build
(catches issues hot-reload can hide):
```bash
./scripts/build_and_serve_web.sh
```
Builds an optimized `flutter build web` bundle and serves it with Python's
built-in HTTP server at `http://localhost:8080`.

---

## What to click through (same as the general testing guide, web-specific notes)

1. **Login** — mobile `9800000000`, PIN `0000` → forced PIN-change dialog →
   set a new PIN (e.g. `1234`).
2. **Milk collection** — search farmer "राम" or code `F001` → pick shift →
   enter FAT `4.0`, quantity `10` → amount should live-calculate to
   **रु. 650.00** (from the seeded rate chart) → Save.
3. **Offline test on web** — open Chrome DevTools → Network tab → set
   throttling to **Offline** → add another entry → it should still save
   instantly (local IndexedDB via `sqflite_common_ffi_web`). Switch back to
   **Online** and within a few seconds check Supabase Studio /
   `milk_collections` table — the row should appear.
4. **Browser storage note**: on web, the local SQLite mirror lives in
   IndexedDB, scoped to `http://localhost:8080` — clearing browser site data
   for that origin wipes local test data (Supabase data is untouched).

## Known web-specific caveats
- `mobile_scanner` (QR) has more limited/needs-HTTPS-context behavior on web
  than on Android; fine to skip during this phase of testing.
- Web push notifications (Firebase) need additional web-specific FCM setup
  not yet wired — out of scope for this phase.
- Always use the **same** `.env.web` values across test runs within one
  session, or the local IndexedDB data (tied to Path B's local project ref)
  and cloud data (Path A) will look like two different, unrelated datasets.
