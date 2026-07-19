# Dairy Collection Management System (Nepal) — Architecture & Build Plan

Stack: **Flutter (Android + Web)** frontend, **Supabase (Postgres + Auth + Storage + Realtime + Edge Functions)** backend,
**SQLite (sqflite / sqflite_common_ffi for web via drift)** as the offline-first local store, with a **queue-based bidirectional sync engine**.

This document is the master plan. The `supabase/schema.sql` and `flutter_app/` folders contain a working starter
implementation of the core (auth, hierarchy, offline DB, sync engine, milk collection entry). Every other module
listed below is scoped, schemed, and ready to build on top of this foundation using the same patterns.

---

## 1. Hierarchy Model

```
Admin (Anthropic-style super-admin, national level)
  └── Level 2 Collection Center (District / Chilling Center)
        └── Level 1 Collection Center (Route / Sub-center)
              └── Level 0 Collection Center (Village Collection Point — where actual milk intake happens)
                    └── Farmers
```

- Every center has a `parent_center_id` (nullable at L2), a `level` (0/1/2), and a `district`/`gps` field.
- Users (login accounts) are 1:1 or 1:many with a center via `center_users`, with a `role` enum.
- Farmers belong to exactly one L0 center (`farmers.center_id`).
- This self-referential tree means **all reporting (district summary, center summary) is just a recursive
  aggregation up the tree** — one SQL pattern (`WITH RECURSIVE`) reused everywhere.

## 2. Roles & Permissions

| Role | Scope | Key permissions |
|---|---|---|
| `super_admin` | National | everything, manage all centers, override rates |
| `l2_admin` | District | manage L1/L0 centers under them, view district reports, set FAT rate charts |
| `l1_operator` | Route | manage L0 centers under them, view route reports |
| `l0_operator` | Village center | register farmers, record collection, manage payments — the primary daily-use role |
| `farmer` | Self only | view own ledger, collection history, payments, via app or SMS/QR lookup |

Permissions are enforced **twice**: Postgres Row Level Security (RLS) policies (source of truth) and mirrored
client-side checks (for UX / offline reasoning, never trusted alone).

## 3. Authentication

- Login = **mobile number + PIN** (4–6 digit), not email/password — matches rural literacy/UX needs.
- Default PIN = **last 4 digits of the registered mobile number**, forced change on first login
  (`must_change_pin = true` flag on the user row).
- Supabase Auth doesn't natively do phone+PIN, so we use **Supabase Auth's phone provider in "custom" mode**:
  a Postgres function issues a signed JWT after verifying PIN hash server-side (Edge Function), avoiding
  storing PINs in plaintext (bcrypt via `pgcrypto`).
  - Offline login: last successful auth is cached locally (hashed PIN + session token with long expiry);
    device can authenticate against the **local SQLite copy** when offline, then re-validate silently once
    back online.

## 4. Offline-First Architecture

**Principle: the local SQLite DB is the primary source of truth for the UI. Supabase is the sync target.**

- Every mutable table has a **local mirror table** in SQLite with the same columns plus:
  `_sync_status` (`synced` / `pending` / `conflict`), `_local_updated_at`, `_device_id`.
- A **write-ahead outbox** (`sync_queue` table) records every insert/update as a JSON diff with a monotonic
  local sequence number.
- **Sync Engine** (`SyncService`):
  1. Listens to connectivity (`connectivity_plus`).
  2. On reconnect: pushes `sync_queue` entries in order (batched), then pulls server changes since
     `last_synced_at` (per table, using `updated_at` watermark + `deleted_at` soft-deletes).
  3. Conflict resolution: **last-write-wins by default**, except milk-collection edits, which use
     **field-level merge + farmer notification** (see §7) because two operators rarely edit the same
     entry — conflicts here almost always mean a genuine correction that must be visible to the farmer.
  4. Idempotent: every row carries a `client_uuid` generated on-device, so retried pushes never duplicate.
- Background sync also runs periodically (`workmanager` on Android) so a center with intermittent signal
  stays nearly real-time without a person opening the app.

## 5. Core Data Model (see `supabase/schema.sql` for full DDL)

- `centers` (hierarchy, level, parent_center_id, district, gps)
- `users` (mobile, pin_hash, role, center_id, must_change_pin)
- `farmers` (code, name, mobile, center_id, join_date, bank/payment info, qr_code)
- `rate_charts` (center_id, month, fat_min, fat_max, rate_per_liter, snf-based option for future)
- `milk_collections` (farmer_id, center_id, date, shift[morning/evening], fat, snf, quantity_liters,
  rate_applied, amount, entered_by, edited_by, edit_history jsonb, is_deleted)
- `payments` (farmer_id, center_id, period_start, period_end, amount_due, amount_paid, payment_type
  [partial/full], settlement_cycle [15day/monthly], paid_at, paid_by)
- `notifications` (farmer_id/user_id, type, payload, read_at, channel [push/sms])
- `audit_log` (table_name, row_id, action, actor_id, diff jsonb, created_at) — append-only, for every
  sensitive mutation (edits, payments, rate changes)

## 6. Milk Collection & Rate Calculation

- Rate chart is **monthly, per-center, FAT-slab based**: e.g. FAT 3.0–3.5 → Rs 62/L, 3.5–4.0 → Rs 66/L …
  L2 admin uploads/edits the chart; L1/L0 inherit unless overridden.
- Entry screen (see `milk_collection_screen.dart`): pick farmer (search or QR scan) → shift → FAT (numeric
  keypad, large buttons) → quantity (liters) → **amount auto-computed** from the active rate chart, shown
  live, editable only by admin roles with a reason logged.
- Every edit after the fact re-triggers the amount calc, writes to `edit_history`, and queues a
  **farmer notification** ("तपाईंको मिति X को दूध विवरण संशोधन गरिएको छ").

## 7. Payments & Settlement

- Settlement cycle configurable per center: `15day` or `monthly`.
- `payments` supports partial payments against a running farmer balance (ledger = sum(collections.amount)
  − sum(payments.amount_paid), recursive over the period).
- Farmer ledger screen shows running balance, printable/exportable statement.

## 8. Dashboards

- **Admin**: national totals, district drill-down map, top/bottom performing centers, pending syncs count.
- **Center (L0/L1/L2)**: today's collection (morning+evening), pending payments, farmer count, rate chart
  status, sync status indicator (green/yellow/red).
- **Farmer**: this month's total liters, average FAT, amount earned, payment status, QR code for ID.

## 9. Reporting & Exports

All reports are recursive-CTE Postgres views (`district_summary_view`, `center_summary_view`) with
Flutter-side PDF (`pdf` + `printing` packages) and Excel (`syncfusion_flutter_xlsio` or `excel` package)
export, generated from the same query results used on-screen so numbers can never drift between UI and export.

Reports: Daily collection sheet · Monthly summary · Farmer ledger · Payment ledger · Center summary ·
District summary.

## 10. QR, Notifications, Backup

- Each farmer gets a QR code (`qr_flutter` to generate, `mobile_scanner` to read) encoding `farmer_code` —
  used at the collection counter to pull up their record in under a second.
- Push notifications via **Supabase Edge Function → Firebase Cloud Messaging** (Android) and web push for
  the web app; SMS fallback (e.g. Sparrow SMS / local Nepali SMS gateway) for feature-phone-adjacent farmers
  with no smartphone.
- Cloud backup = Supabase is already the durable store; additionally nightly `pg_dump` to Supabase Storage
  (or S3-compatible bucket) with 30-day retention, restorable per district.

## 11. Security

- RLS on every table keyed off `auth.uid()` → `users.center_id` → hierarchy check (`is_descendant_of()` SQL
  function) so an L1 operator can never see another route's data.
- PIN hashed with bcrypt (`pgcrypto`), never stored/transmitted in plaintext.
- All sensitive mutations audit-logged.
- API keys/service role key only ever used server-side (Edge Functions), never shipped in the Flutter app.

## 12. Future-Ready Modules (scoped, not built yet — architecture already accommodates them)

| Module | Hook point |
|---|---|
| Bluetooth weighing scale | `milk_collections.quantity_liters` gets a `source` enum (`manual`/`bluetooth_scale`); a `DeviceIntegrationService` interface to implement per hardware SDK |
| Milk analyzer (FAT/SNF meter) | Same pattern: `source` on `fat`/`snf` fields, serial/BLE reader service |
| AI analytics | Read-only service against Postgres views — fraud detection (adulteration patterns via FAT/SNF anomalies), yield prediction |
| Veterinary records | New `farmer_livestock` + `vet_visits` tables, farmer-scoped, same RLS pattern |
| Inventory | New `inventory_items`/`inventory_transactions` tables per center |
| GPS mapping | `centers.gps` and `farmers.gps` already present; map view via `google_maps_flutter` |
| Digital payments | `payments.method` enum extended to `esewa`/`khalti`/`bank_transfer`; webhook Edge Function to mark paid |

---

## 13. Build Phases (recommended order)

1. **Phase 0 (this delivery)**: schema, auth, offline DB, sync engine, hierarchy, milk collection entry.
2. **Phase 1**: farmer & center registration screens, rate chart management.
3. **Phase 2**: payments & settlement, farmer ledger.
4. **Phase 3**: dashboards (admin/center/farmer) + reports + PDF/Excel export.
5. **Phase 4**: QR, push notifications, cloud backup automation.
6. **Phase 5**: future modules per table above, added incrementally without touching core.

## 14. Folder Structure

```
dairy_collection_system/
├── ARCHITECTURE.md
├── supabase/
│   └── schema.sql
└── flutter_app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── core/
        │   ├── database/local_db.dart       (SQLite schema + DAO helpers)
        │   ├── sync/sync_service.dart        (bidirectional sync engine)
        │   ├── auth/auth_service.dart        (PIN auth, offline session)
        │   ├── models/                       (Center, Farmer, MilkCollection, ...)
        │   └── theme/app_theme.dart           (large-button, Nepali-first UI theme)
        └── features/
            ├── auth/login_screen.dart
            ├── collection/milk_collection_screen.dart
            ├── farmers/ (to build)
            ├── centers/ (to build)
            ├── payments/ (to build)
            ├── reports/ (to build)
            └── dashboard/ (to build)
```
