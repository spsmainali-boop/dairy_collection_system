-- Auto-applied by the Supabase CLI on `supabase db reset` (local dev only).
-- Gives you a ready-to-log-in test center, operator, rate chart, and farmer
-- so you can test the collection flow immediately without hand-writing SQL.

insert into centers (id, name, level) values
  ('11111111-1111-1111-1111-111111111111', 'परीक्षण केन्द्र', 'L0')
on conflict (id) do nothing;

-- Default PIN = last 4 digits of mobile = "0000" (must_change_pin forces reset on first login)
insert into users (mobile, pin_hash, name, role, center_id, must_change_pin)
values ('9800000000', set_default_pin('9800000000'), 'Test Operator',
        'l0_operator', '11111111-1111-1111-1111-111111111111', true)
on conflict (mobile) do nothing;

insert into rate_charts (center_id, month, fat_min, fat_max, rate_per_liter)
values ('11111111-1111-1111-1111-111111111111', date_trunc('month', now())::date, 0, 10, 65.00)
on conflict do nothing;

insert into farmers (farmer_code, name, center_id)
values ('F001', 'राम बहादुर', '11111111-1111-1111-1111-111111111111')
on conflict (farmer_code) do nothing;
