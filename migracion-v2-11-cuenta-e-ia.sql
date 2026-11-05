-- Colmena v2.11 · «Eliminar mi cuenta» solo desde el servidor y límites de IA sin huecos
-- Córrela en Supabase → SQL Editor después de la v2.8. Se puede repetir sin problema.
-- 1) Eliminar mi cuenta: la parte de la base (pasar talleres, borradores y lo capturado a una persona admin y
--    salir del equipo) ya no se puede llamar desde el navegador. Solo la usa la función «account», después de
--    confirmar la contraseña, el segundo paso y la palabra ELIMINAR.
-- 2) IA · resumen y definiciones del entregable: el «una vez por taller» se aparta en un solo paso (dos pedidos
--    al mismo tiempo ya no generan dos llamadas) y respetan la pausa y el tope mensual que pone el admin.
-- 3) IA · propuestas: el límite de 30 al día se cuenta en orden (dos pedidos al mismo tiempo no lo rebasan).
-- 4) Uso de IA: cada llamada marca cuándo terminó (done_at); así se sabe si una sigue en curso.
-- Después de correrla, actualiza las funciones «account» y «suggest-workshop» (vienen en esta misma versión).
-- Al final sale una fila: funciones = 3, version = 2.11.0
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.8.0') then
    raise exception 'Primero corre migracion-v280-entregable.sql (v2.8) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,11,0] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Eliminar mi cuenta: solo el servidor
-- ------------------------------------------------------------
-- La versión anterior (sin datos) se podía llamar con la sesión de la persona y se saltaba la contraseña.
drop function if exists ws_self_remove();

-- La llama la función «account» con la llave del servidor, ya confirmada la identidad. Recibe la cuenta.
-- Sus talleres, borradores, lo capturado e invitaciones pendientes pasan a la persona admin que los recibe,
-- se cancelan las invitaciones para su correo y sale del equipo. Todo o nada.
-- Después, «account» borra su cuenta (ws_sessions y ws_drafts se borrarían en cascada con ella).
create or replace function ws_self_remove(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v ws_admins; h ws_admins; v_heir uuid; v_who text; v_body text;
        n_ses int := 0; n_dra int := 0; n_par int := 0;
begin
  if p_user is null then raise exception 'Falta indicar la cuenta'; end if;
  -- Candado en orden fijo sobre las admins activas y la propia fila: dos bajas al mismo tiempo no dejan a Colmena sin admin
  perform 1 from ws_admins a where (a.active and a.role = 'admin') or a.user_id = p_user order by a.user_id for update;
  select * into v from ws_admins a where a.user_id = p_user and a.active;
  if not found then raise exception 'Inicia sesión para eliminar tu cuenta'; end if;
  v_heir := ws_self_heir(p_user);
  if v_heir is null then
    if v.role = 'admin' then
      raise exception 'Eres la única persona admin de Colmena. Antes de eliminar tu cuenta, haz admin a alguien más en Equipo.';
    end if;
    raise exception 'No hay una persona admin activa que reciba tus talleres. Pide ayuda a quien administra Colmena.';
  end if;
  select * into h from ws_admins a where a.user_id = v_heir;
  v_who := coalesce(nullif(trim(v.name), ''), v.email, 'Alguien');

  update ws_sessions set owner_id = v_heir where owner_id = p_user;
  get diagnostics n_ses = row_count;
  update ws_drafts set owner_id = v_heir where owner_id = p_user;
  get diagnostics n_dra = row_count;
  -- Lo que capturó como participante con su cuenta del panel también pasa (si quien recibe ya participó
  -- en ese mismo taller, se conserva su registro y el de la persona se va con su cuenta)
  update ws_participants p set user_id = v_heir where p.user_id = p_user
     and not exists (select 1 from ws_participants q where q.session_id = p.session_id and q.user_id = v_heir);
  get diagnostics n_par = row_count;
  -- Invitaciones pendientes que mandó: ahora son de quien recibe; las que eran para su correo se cancelan
  update ws_invites set created_by = v_heir where created_by = p_user and used_at is null and revoked_at is null;
  update ws_invites set revoked_at = now()
   where lower(email) = lower(v.email) and used_at is null and revoked_at is null;
  delete from ws_admins where user_id = p_user;

  v_body := case when n_ses = 0 and n_dra = 0 then 'No tenía talleres ni borradores a su nombre.'
    else 'Ahora están a tu nombre ' || concat_ws(' y ',
           case when n_ses = 1 then 'su taller' when n_ses > 1 then 'sus ' || n_ses || ' talleres' end,
           case when n_dra = 1 then 'su borrador' when n_dra > 1 then 'sus ' || n_dra || ' borradores' end) || ', con todo lo capturado.' end;
  perform ws_notify(v_heir, 'member_left', v_who || ' eliminó su cuenta', v_body,
    case when n_ses + n_dra > 0 then jsonb_build_object('label', 'Ver mis talleres', 'view', 'mine') else jsonb_build_object('label', 'Ver equipo', 'view', 'team') end,
    jsonb_build_object('email', v.email), true, null);

  return jsonb_build_object('talleres', n_ses, 'borradores', n_dra, 'participaciones', n_par,
    'email', v.email, 'nombre', v.name,
    'para', jsonb_build_object('nombre', coalesce(nullif(trim(h.name), ''), h.email), 'correo', h.email));
end $$;
revoke execute on function ws_self_remove(uuid) from public, anon, authenticated;
grant execute on function ws_self_remove(uuid) to service_role;

-- ------------------------------------------------------------
-- 2) Uso de IA: cuándo terminó cada llamada
-- ------------------------------------------------------------
alter table ws_ai_log add column if not exists done_at timestamptz;
-- Lo de antes de esta versión ya terminó
update ws_ai_log set done_at = at where done_at is null and at < now() - interval '10 minutes';

-- ------------------------------------------------------------
-- 3) Resumen y definiciones con IA: una vez por taller, una a la vez, con pausa y tope
-- ------------------------------------------------------------
-- La llama «suggest-workshop» con la sesión de quien facilita, ANTES de llamar a la IA. Si responde ok, deja el
-- renglón «en curso» en Uso de IA y devuelve su id; la función lo completa con los tokens y done_at al terminar.
-- Motivos para no seguir: denied (no es su taller), paused (su admin pausó la IA), once (ya se generó y se guardó),
-- busy (hay otra llamada en curso para ese taller, de menos de 2 minutos) y cap (llegó a su tope del mes).
create or replace function ws_ai_once(p_session uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a ws_admins; v_used bigint; v_id bigint; v_name text;
begin
  if p_kind is null or p_kind not in ('insights', 'entregable') then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  if p_session is null or not ws_is_owner(p_session) then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  select * into a from ws_admins where user_id = auth.uid();
  if not coalesce(a.ai_enabled, true) then return jsonb_build_object('ok', false, 'reason', 'paused'); end if;
  -- Una a la vez por taller y tipo: quien llega segundo espera aquí y después ve el renglón del primero
  perform pg_advisory_xact_lock(hashtextextended('ws_ai_once:' || p_session::text || ':' || p_kind, 0));
  if exists (select 1 from ws_ai_log where session_id = p_session and kind = p_kind and ok) then
    return jsonb_build_object('ok', false, 'reason', 'once');
  end if;
  if exists (select 1 from ws_ai_log where session_id = p_session and kind = p_kind and done_at is null
               and at > now() - interval '2 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;
  select coalesce(sum(input_tokens + output_tokens), 0) into v_used from ws_ai_log
   where user_id = auth.uid() and at >= date_trunc('month', now());
  if a.ai_monthly_cap is not null and v_used >= a.ai_monthly_cap then
    return jsonb_build_object('ok', false, 'reason', 'cap', 'used', v_used, 'cap', a.ai_monthly_cap);
  end if;
  select s.name into v_name from ws_sessions s where s.id = p_session;
  insert into ws_ai_log(user_id, kind, session_id, label)
  values (auth.uid(), p_kind, p_session, left(v_name, 160))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'used', v_used, 'cap', a.ai_monthly_cap);
end $$;
revoke execute on function ws_ai_once(uuid, text) from public, anon;
grant execute on function ws_ai_once(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- 4) Propuestas con IA: el límite del día se cuenta en orden
-- ------------------------------------------------------------
-- Igual que en la v1.21 (pausa, tope mensual y 30 al día), pero los pedidos de una misma persona pasan de uno
-- en uno por esta revisión: dos al mismo tiempo ya no ven el mismo conteo.
create or replace function ws_ai_begin(p_kind text default 'propuesta', p_draft uuid default null, p_label text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a ws_admins; v_used bigint; v_n int; v_id bigint;
begin
  if not ws_is_admin() then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  perform pg_advisory_xact_lock(hashtextextended('ws_ai_begin:' || auth.uid()::text, 0));
  select * into a from ws_admins where user_id = auth.uid();
  if not coalesce(a.ai_enabled, true) then return jsonb_build_object('ok', false, 'reason', 'paused'); end if;
  select coalesce(sum(input_tokens + output_tokens), 0) into v_used from ws_ai_log
   where user_id = auth.uid() and at >= date_trunc('month', now());
  if a.ai_monthly_cap is not null and v_used >= a.ai_monthly_cap then
    return jsonb_build_object('ok', false, 'reason', 'cap', 'used', v_used, 'cap', a.ai_monthly_cap);
  end if;
  select count(*) into v_n from ws_ai_log where user_id = auth.uid() and at > now() - interval '1 day';
  if v_n >= 30 then return jsonb_build_object('ok', false, 'reason', 'daily'); end if;
  insert into ws_ai_log(user_id, kind, draft_id, label)
  values (auth.uid(), case when p_kind in ('propuesta','otra','ajuste','insights') then p_kind else 'propuesta' end, p_draft, left(p_label, 160))
  returning id into v_id;
  delete from ws_ai_log where at < now() - interval '400 days';
  return jsonb_build_object('ok', true, 'id', v_id, 'used', v_used, 'cap', a.ai_monthly_cap);
end $$;
revoke execute on function ws_ai_begin(text, uuid, text) from public, anon;
grant execute on function ws_ai_begin(text, uuid, text) to authenticated;

insert into ws_schema_version(version) values ('2.11.0') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('ws_self_remove','ws_ai_once','ws_ai_begin')) as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
