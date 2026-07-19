-- =====================================================================
-- Dairy Collection Management System — Supabase (Postgres) Schema
-- =====================================================================
-- Run in Supabase SQL editor. Requires pgcrypto for bcrypt PIN hashing.

create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
create type center_level as enum ('L2', 'L1', 'L0');
create type user_role as enum ('super_admin', 'l2_admin', 'l1_operator', 'l0_operator', 'farmer');
create type collection_shift as enum ('morning', 'evening');
create type settlement_cycle as enum ('15day', 'monthly');
create type payment_type as enum ('partial', 'full');
create type payment_method as enum ('cash', 'bank_transfer', 'esewa', 'khalti', 'other');
create type notification_channel as enum ('push', 'sms', 'in_app');
create type quantity_source as enum ('manual', 'bluetooth_scale');
create type fat_source as enum ('manual', 'analyzer');

-- ---------------------------------------------------------------------
-- CENTERS (self-referential hierarchy: L2 -> L1 -> L0)
-- ---------------------------------------------------------------------
create table centers (
  id uuid primary key default uuid_generate_v4(),
  client_uuid uuid unique,                     -- set by offline client on creation
  name text not null,
  level center_level not null,
  parent_center_id uuid references centers(id),
  district text,
  gps_lat double precision,
  gps_lng double precision,
  settlement_cycle settlement_cycle not null default '15day',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_centers_parent on centers(parent_center_id);

-- Recursive helper: is `descendant_id` under (or equal to) `ancestor_id`?
create or replace function is_descendant_of(descendant_id uuid, ancestor_id uuid)
returns boolean language sql stable as $$
  with recursive up as (
    select id, parent_center_id from centers where id = descendant_id
    union all
    select c.id, c.parent_center_id from centers c
    join up on c.id = up.parent_center_id
  )
  select ancestor_id in (select id from up) or descendant_id = ancestor_id;
$$;

-- ---------------------------------------------------------------------
-- USERS (mobile + PIN auth, mapped 1:many to a center)
-- ---------------------------------------------------------------------
create table users (
  id uuid primary key default uuid_generate_v4(),
  mobile text unique not null,
  pin_hash text not null,               -- bcrypt(pgcrypto)
  name text not null,
  role user_role not null,
  center_id uuid references centers(id),
  must_change_pin boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function set_default_pin(mobile_number text)
returns text language plpgsql as $$
begin
  return crypt(right(mobile_number, 4), gen_salt('bf'));
end;
$$;

-- ---------------------------------------------------------------------
-- FARMERS
-- ---------------------------------------------------------------------
create table farmers (
  id uuid primary key default uuid_generate_v4(),
  client_uuid uuid unique,
  farmer_code text unique not null,      -- printed on QR
  name text not null,
  mobile text,
  center_id uuid not null references centers(id),
  join_date date not null default current_date,
  bank_account text,
  gps_lat double precision,
  gps_lng double precision,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_farmers_center on farmers(center_id);

-- ---------------------------------------------------------------------
-- RATE CHARTS (monthly, per-center, FAT-slab based)
-- ---------------------------------------------------------------------
create table rate_charts (
  id uuid primary key default uuid_generate_v4(),
  center_id uuid not null references centers(id),
  month date not null,                   -- first-of-month marker
  fat_min numeric(4,2) not null,
  fat_max numeric(4,2) not null,
  rate_per_liter numeric(10,2) not null,
  snf_min numeric(4,2),                  -- reserved for future SNF-based pricing
  snf_max numeric(4,2),
  created_by uuid references users(id),
  created_at timestamptz not null default now()
);

create index idx_rate_charts_center_month on rate_charts(center_id, month);

create or replace function get_rate(p_center_id uuid, p_month date, p_fat numeric)
returns numeric language sql stable as $$
  select rate_per_liter from rate_charts
  where center_id = p_center_id and month = date_trunc('month', p_month)::date
    and p_fat >= fat_min and p_fat < fat_max
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- MILK COLLECTIONS
-- ---------------------------------------------------------------------
create table milk_collections (
  id uuid primary key default uuid_generate_v4(),
  client_uuid uuid unique not null,       -- generated on-device, used for idempotent sync
  farmer_id uuid not null references farmers(id),
  center_id uuid not null references centers(id),
  collection_date date not null,
  shift collection_shift not null,
  fat numeric(4,2) not null,
  snf numeric(4,2),
  quantity_liters numeric(8,2) not null,
  quantity_source quantity_source not null default 'manual',
  fat_source fat_source not null default 'manual',
  rate_applied numeric(10,2) not null,
  amount numeric(12,2) not null,
  entered_by uuid references users(id),
  edited_by uuid references users(id),
  edit_history jsonb not null default '[]'::jsonb,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_milk_farmer_date on milk_collections(farmer_id, collection_date);
create index idx_milk_center_date on milk_collections(center_id, collection_date);

-- ---------------------------------------------------------------------
-- PAYMENTS (partial payments, 15-day / monthly settlement)
-- ---------------------------------------------------------------------
create table payments (
  id uuid primary key default uuid_generate_v4(),
  client_uuid uuid unique,
  farmer_id uuid not null references farmers(id),
  center_id uuid not null references centers(id),
  period_start date not null,
  period_end date not null,
  amount_due numeric(12,2) not null,
  amount_paid numeric(12,2) not null,
  payment_type payment_type not null,
  method payment_method not null default 'cash',
  paid_by uuid references users(id),
  paid_at timestamptz not null default now(),
  notes text
);

create index idx_payments_farmer on payments(farmer_id, period_start);

-- Farmer running balance (recursive over period is unnecessary; simple aggregate)
create or replace view farmer_ledger_view as
select
  f.id as farmer_id,
  f.name,
  f.center_id,
  coalesce(sum(mc.amount) filter (where mc.is_deleted = false), 0) as total_earned,
  coalesce((select sum(p.amount_paid) from payments p where p.farmer_id = f.id), 0) as total_paid,
  coalesce(sum(mc.amount) filter (where mc.is_deleted = false), 0)
    - coalesce((select sum(p.amount_paid) from payments p where p.farmer_id = f.id), 0) as balance
from farmers f
left join milk_collections mc on mc.farmer_id = f.id
group by f.id, f.name, f.center_id;

-- ---------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  farmer_id uuid references farmers(id),
  user_id uuid references users(id),
  channel notification_channel not null default 'push',
  title text not null,
  body text not null,
  payload jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- AUDIT LOG (append-only)
-- ---------------------------------------------------------------------
create table audit_log (
  id uuid primary key default uuid_generate_v4(),
  table_name text not null,
  row_id uuid not null,
  action text not null,          -- insert/update/delete
  actor_id uuid references users(id),
  diff jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- RECURSIVE REPORTING VIEWS
-- ---------------------------------------------------------------------
create or replace function centers_under(p_center_id uuid)
returns table(id uuid) language sql stable as $$
  with recursive down as (
    select id from centers where id = p_center_id
    union all
    select c.id from centers c join down d on c.parent_center_id = d.id
  )
  select id from down;
$$;

create or replace view center_summary_view as
select
  c.id as center_id, c.name, c.level, c.district,
  count(distinct f.id) as farmer_count,
  coalesce(sum(mc.quantity_liters) filter (where mc.is_deleted = false), 0) as total_liters,
  coalesce(sum(mc.amount) filter (where mc.is_deleted = false), 0) as total_amount
from centers c
left join farmers f on f.center_id = c.id
left join milk_collections mc on mc.center_id = c.id
group by c.id, c.name, c.level, c.district;

create or replace view district_summary_view as
select
  district,
  count(distinct c.id) as center_count,
  coalesce(sum(mc.quantity_liters) filter (where mc.is_deleted = false), 0) as total_liters,
  coalesce(sum(mc.amount) filter (where mc.is_deleted = false), 0) as total_amount
from centers c
left join milk_collections mc on mc.center_id = c.id
where c.district is not null
group by district;

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
alter table centers enable row level security;
alter table users enable row level security;
alter table farmers enable row level security;
alter table rate_charts enable row level security;
alter table milk_collections enable row level security;
alter table payments enable row level security;
alter table notifications enable row level security;

-- Helper: current user's row
create or replace function current_app_user()
returns users language sql stable as $$
  select * from users where id = auth.uid();
$$;

-- Super admins see everything; others see their own subtree only.
create policy centers_select on centers for select using (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(id, (select center_id from users where id = auth.uid()))
  or id = (select center_id from users where id = auth.uid())
);

create policy farmers_select on farmers for select using (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(center_id, (select center_id from users where id = auth.uid()))
);

create policy milk_collections_rw on milk_collections for all using (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(center_id, (select center_id from users where id = auth.uid()))
) with check (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(center_id, (select center_id from users where id = auth.uid()))
);

create policy payments_rw on payments for all using (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(center_id, (select center_id from users where id = auth.uid()))
) with check (
  (select role from users where id = auth.uid()) = 'super_admin'
  or is_descendant_of(center_id, (select center_id from users where id = auth.uid()))
);

-- (Similar policies to be added for rate_charts, notifications, users —
--  pattern is identical: super_admin OR is_descendant_of(center_id, my_center_id))

-- =====================================================================
-- AUTH RPCs (called by Edge Functions verify-pin / change-pin — service
-- role only, `security definer` so they can read pin_hash despite RLS)
-- =====================================================================
create or replace function verify_user_pin(p_mobile text, p_pin text)
returns table(id uuid, role user_role, center_id uuid, must_change_pin boolean)
language sql security definer as $$
  select id, role, center_id, must_change_pin
  from users
  where mobile = p_mobile and pin_hash = crypt(p_pin, pin_hash) and is_active = true;
$$;

create or replace function set_user_pin(p_mobile text, p_new_pin text)
returns void language plpgsql security definer as $$
begin
  update users
  set pin_hash = crypt(p_new_pin, gen_salt('bf')), must_change_pin = false, updated_at = now()
  where mobile = p_mobile;
end;
$$;

-- Example: creating a new user with the default PIN convention
-- (last 4 digits of mobile), forcing a PIN change on first login:
--
-- insert into users (mobile, pin_hash, name, role, center_id, must_change_pin)
-- values ('9800000000', set_default_pin('9800000000'), 'Ram Bahadur', 'l0_operator',
--         '<center-uuid>', true);
