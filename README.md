# Dairy Collection Management System — Nepal

Offline-first Flutter (Android + Web) app + Supabase backend for managing a
multi-level dairy collection hierarchy (L2 → L1 → L0 → Farmers).

Read **`ARCHITECTURE.md`** first — it explains the full system design, data
model, sync strategy, security model, and the phased build plan. This repo
contains a working **Phase 0** foundation: schema, auth, offline DB, sync
engine, and the core milk-collection entry flow. Everything else (farmer/
center registration UI, payments UI, dashboards, reports, QR, notifications,
exports) is scoped in the architecture doc and builds on these same patterns.

## 1. Backend setup (Supabase)

1. Create a project at supabase.com.
2. In the SQL editor, run `supabase/schema.sql` (creates tables, enums, RLS
   policies, recursive hierarchy helpers, reporting views, and auth RPCs).
3. Deploy the two Edge Functions:
   ```
   supabase functions deploy verify-pin
   supabase functions deploy change-pin
   ```
4. Create your first `super_admin` user manually via SQL, e.g.:
   ```sql
   insert into centers (name, level) values ('राष्ट्रिय प्रशासन', 'L2');
   insert into users (mobile, pin_hash, name, role, must_change_pin)
   values ('9800000000', set_default_pin('9800000000'), 'Admin', 'super_admin', true);
   ```
   Default PIN will be `0000` (last 4 digits of the mobile number) — the app
   will force a PIN change on first login.

## 2. Flutter app setup

```bash
cd flutter_app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

For web: add `sqflite_common_ffi_web` initialization (stubbed with a TODO in
`main.dart`) and run `flutter run -d chrome` with the same `--dart-define`s.

Add a Devanagari font (e.g. Noto Sans Devanagari) under
`flutter_app/assets/fonts/` — already wired up in `pubspec.yaml`.

## 3. What's implemented vs. scoped

| Area | Status |
|---|---|
| Hierarchy schema, RLS, recursive reporting views | ✅ implemented (`schema.sql`) |
| Mobile+PIN auth, default PIN, forced change, offline login | ✅ implemented |
| Offline SQLite mirror + sync queue + bidirectional sync engine | ✅ implemented |
| Milk collection entry with live FAT→rate→amount calculation | ✅ implemented |
| Farmer/center registration screens | 🔲 scoped in ARCHITECTURE.md §13 Phase 1 — same CRUD + `upsertAndQueue` pattern as milk collection |
| Rate chart management UI | 🔲 Phase 1 |
| Payments, partial payments, 15-day/monthly settlement, farmer ledger | 🔲 Phase 2 — `farmer_ledger_view` already in schema |
| Admin/Center/Farmer dashboards | 🔲 Phase 3 |
| Reports + PDF/Excel export | 🔲 Phase 3 — `center_summary_view` / `district_summary_view` already in schema |
| QR generation/scanning | 🔲 Phase 4 — packages already in `pubspec.yaml`, hook point marked in `milk_collection_screen.dart` |
| Push notifications (FCM) + SMS fallback | 🔲 Phase 4 |
| Automated cloud backup | 🔲 Phase 4 |
| Bluetooth scale / analyzer / AI analytics / vet records / inventory / GPS / digital payments | 🔲 Phase 5 — hook points documented in ARCHITECTURE.md §12 |

## 4. Key design decisions worth knowing before extending

- **Every syncable table has a `client_uuid` unique constraint** — this is
  what makes offline-created rows safely upsert-able without duplication
  when they eventually reach Supabase, regardless of how many times a push
  is retried.
- **The local SQLite DB is the source of truth for the UI** — screens read
  and write locally first, always feel instant, and never block on network.
  `SyncService` is purely a background reconciliation process.
- **RLS enforces the hierarchy**, not the Flutter app — `is_descendant_of()`
  means an operator can never see another branch's data even if the client
  is compromised or offline logic has a bug.
- **Amount is always derived, never hand-entered** — `MilkCollectionEntry.
  calculateAmount()` is the single place this happens, called both at entry
  time and whenever an entry is edited, so numbers can never drift.
