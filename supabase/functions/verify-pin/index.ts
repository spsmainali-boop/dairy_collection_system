// Supabase Edge Function: verify-pin
// Verifies mobile + PIN against the bcrypt hash stored in `users.pin_hash`
// using Postgres's pgcrypto `crypt()`, never exposing the hash to the client.
// Deploy: supabase functions deploy verify-pin

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req) => {
  try {
    const { mobile, pin } = await req.json();
    if (!mobile || !pin) {
      return new Response(JSON.stringify({ error: 'mobile and pin required' }), { status: 400 });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // crypt(pin, pin_hash) = pin_hash  <=>  PIN matches (bcrypt semantics)
    const { data, error } = await supabase.rpc('verify_user_pin', { p_mobile: mobile, p_pin: pin });

    if (error || !data || data.length === 0) {
      return new Response(JSON.stringify({ error: 'invalid credentials' }), { status: 401 });
    }

    const user = data[0];
    return new Response(
      JSON.stringify({
        user_id: user.id,
        role: user.role,
        center_id: user.center_id,
        must_change_pin: user.must_change_pin,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});

/* Companion Postgres function (add to schema.sql):

create or replace function verify_user_pin(p_mobile text, p_pin text)
returns table(id uuid, role user_role, center_id uuid, must_change_pin boolean)
language sql security definer as $$
  select id, role, center_id, must_change_pin
  from users
  where mobile = p_mobile and pin_hash = crypt(p_pin, pin_hash) and is_active = true;
$$;

*/
