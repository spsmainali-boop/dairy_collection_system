// Supabase Edge Function: change-pin
// Updates a user's PIN (bcrypt-hashed) and clears must_change_pin.
// Deploy: supabase functions deploy change-pin

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { mobile, new_pin } = await req.json();
    if (!mobile || !new_pin || new_pin.length < 4) {
      return new Response(JSON.stringify({ error: 'mobile and a 4+ digit new_pin required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { error } = await supabase.rpc('set_user_pin', { p_mobile: mobile, p_new_pin: new_pin });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

/* Companion Postgres function (already applied to your database):

create or replace function set_user_pin(p_mobile text, p_new_pin text)
returns void language plpgsql security definer as $$
begin
  update users
  set pin_hash = crypt(p_new_pin, gen_salt('bf')), must_change_pin = false, updated_at = now()
  where mobile = p_mobile;
end;
$$;

*/