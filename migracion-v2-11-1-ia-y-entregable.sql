-- Colmena v2.11.1 · Límites de IA más firmes y entregable sin ediciones perdidas
-- Córrela en Supabase → SQL Editor después de la v2.11 (migracion-v2-11-cuenta-e-ia.sql). Se puede repetir sin problema.
-- Sale de una segunda revisión de la v2.11:
-- 1) Tope mensual: cuenta también las llamadas a la IA que siguen en curso (cada una aparta 3,000 tokens hasta que
--    termina) y todas las de una persona se revisan de una en una. Antes, con tope de 1 token pasaban 4 pedidos
--    seguidos porque sus tokens aún no se registraban.
-- 2) «Una vez por taller» del resumen y de las definiciones ya no depende solo de Uso de IA (que borra lo de más de
--    400 días): si el taller ya tiene su resumen o ya usó sus definiciones con IA, no se vuelven a generar.
-- 3) Entregable: la IA (ws_deliverable_ai_merge) y quien facilita (ws_deliverable_patch) guardan con candado y sobre
--    lo último guardado. Antes, la IA guardaba lo que había leído antes de llamar a la IA y se perdía lo editado
--    mientras tanto (por ejemplo, en otra pestaña).
-- Después de correrla, actualiza la función «suggest-workshop» y la app (vienen en esta misma versión).
-- Al final sale una fila: funciones = 4, version = 2.11.1
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.11.0') then
    raise exception 'Primero corre migracion-v2-11-cuenta-e-ia.sql (v2.11) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,11,1] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Propuestas con IA: pausa, tope mensual (con lo que sigue en curso) y 30 al día
-- ------------------------------------------------------------
create or replace function ws_ai_begin(p_kind text default 'propuesta', p_draft uuid default null, p_label text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a ws_admins; v_used bigint; v_run int; v_n int; v_id bigint;
begin
  if not ws_is_admin() then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  -- Candado de la persona: sus pedidos de IA (propuestas, resumen y definiciones) se revisan de uno en uno
  perform pg_advisory_xact_lock(hashtextextended('ws_ai_begin:' || auth.uid()::text, 0));
  select * into a from ws_admins where user_id = auth.uid();
  if not coalesce(a.ai_enabled, true) then return jsonb_build_object('ok', false, 'reason', 'paused'); end if;
  select coalesce(sum(input_tokens + output_tokens), 0) into v_used from ws_ai_log
   where user_id = auth.uid() and at >= date_trunc('month', now());
  -- Llamadas suyas que siguen en curso (sin terminar y de menos de 2 minutos): cada una aparta 3,000 tokens
  select count(*) into v_run from ws_ai_log
   where user_id = auth.uid() and done_at is null and at > now() - interval '2 minutes';
  if a.ai_monthly_cap is not null and v_used + v_run * 3000 >= a.ai_monthly_cap then
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

-- ------------------------------------------------------------
-- 2) Resumen y definiciones con IA: una vez por taller (también después de 400 días), una a la vez, pausa y tope
-- ------------------------------------------------------------
create or replace function ws_ai_once(p_session uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a ws_admins; v_used bigint; v_run int; v_id bigint; v_name text;
begin
  if p_kind is null or p_kind not in ('insights', 'entregable') then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  if p_session is null or not ws_is_owner(p_session) then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
  -- Primero el candado de la persona (el mismo de ws_ai_begin: el tope se revisa con todos sus pedidos en orden)
  -- y después el del taller y tipo: quien llega segundo espera aquí y después ve el renglón del primero
  perform pg_advisory_xact_lock(hashtextextended('ws_ai_begin:' || auth.uid()::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('ws_ai_once:' || p_session::text || ':' || p_kind, 0));
  select * into a from ws_admins where user_id = auth.uid();
  if not coalesce(a.ai_enabled, true) then return jsonb_build_object('ok', false, 'reason', 'paused'); end if;
  -- Ya se usó: lo dice Uso de IA o, aunque ese registro ya se haya borrado, el propio taller
  if exists (select 1 from ws_ai_log where session_id = p_session and kind = p_kind and ok)
     or (p_kind = 'insights' and exists (select 1 from ws_sessions s where s.id = p_session and nullif(trim(s.summary), '') is not null))
     or (p_kind = 'entregable' and exists (select 1 from ws_deliverables d where d.session_id = p_session and d.data ? 'ai_at')) then
    return jsonb_build_object('ok', false, 'reason', 'once');
  end if;
  if exists (select 1 from ws_ai_log where session_id = p_session and kind = p_kind and done_at is null
               and at > now() - interval '2 minutes') then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;
  select coalesce(sum(input_tokens + output_tokens), 0) into v_used from ws_ai_log
   where user_id = auth.uid() and at >= date_trunc('month', now());
  select count(*) into v_run from ws_ai_log
   where user_id = auth.uid() and done_at is null and at > now() - interval '2 minutes';
  if a.ai_monthly_cap is not null and v_used + v_run * 3000 >= a.ai_monthly_cap then
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
-- 3) Entregable: la IA y quien facilita guardan con el mismo candado y sobre lo último guardado
-- ------------------------------------------------------------
-- Definiciones con IA. La llama «suggest-workshop» con la llave del servidor, ya revisado que el taller es de quien
-- facilita. p_defs = {"<id de la competencia>": "definición", …}. Llena solo las competencias sin una definición
-- revisada (src «ok») y marca ai_at. Si ya tenía ai_at, no cambia nada (once). Si ninguna aplica, no escribe (n = 0).
create or replace function ws_deliverable_ai_merge(p_session uuid, p_defs jsonb, p_at timestamptz, p_by uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; it jsonb; k text; v text; n int := 0; existe boolean;
begin
  if p_session is null or p_defs is null or jsonb_typeof(p_defs) <> 'object' then
    raise exception 'Solicitud inválida' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ws_deliverable:' || p_session::text, 0));
  select data into d from ws_deliverables where session_id = p_session for update;
  existe := found;
  if d is null or jsonb_typeof(d) <> 'object' then d := '{}'::jsonb; end if;
  if d ? 'ai_at' then return jsonb_build_object('ok', false, 'reason', 'once', 'n', 0, 'data', d); end if;
  d := d || jsonb_build_object('v', 1, 'kind', 'comp');
  if jsonb_typeof(d -> 'items') is distinct from 'object' then d := jsonb_set(d, '{items}', '{}'::jsonb); end if;
  for k, v in select e.key, e.value #>> '{}' from jsonb_each(p_defs) e loop
    continue when nullif(trim(coalesce(v, '')), '') is null;
    it := d -> 'items' -> k;
    if it is null or jsonb_typeof(it) <> 'object' then it := '{}'::jsonb; end if;
    continue when nullif(it ->> 'def', '') is not null and it ->> 'src' = 'ok';   -- nunca reemplaza una definición revisada
    d := jsonb_set(d, array['items', k], it || jsonb_build_object('def', left(v, 400), 'src', 'ai', 'at', p_at));
    n := n + 1;
  end loop;
  if n = 0 then return jsonb_build_object('ok', true, 'n', 0, 'data', d); end if;
  d := d || jsonb_build_object('ai_at', p_at);
  if existe then
    update ws_deliverables set data = d, updated_by = p_by where session_id = p_session;
  else
    insert into ws_deliverables(session_id, data, updated_by) values (p_session, d, p_by);
  end if;
  return jsonb_build_object('ok', true, 'n', n, 'data', d);
end $$;
revoke execute on function ws_deliverable_ai_merge(uuid, jsonb, timestamptz, uuid) from public, anon, authenticated;
grant execute on function ws_deliverable_ai_merge(uuid, jsonb, timestamptz, uuid) to service_role;

-- Lo que completa quien facilita (definición, primer paso, responsable, fecha, estado): un elemento a la vez.
-- p_patch se mezcla con lo guardado de ese elemento; un valor null o vacío lo quita, y si el elemento queda vacío se
-- borra. Mismos permisos que la tabla (solo quien facilita el taller). Regresa {data, updated_at}.
create or replace function ws_deliverable_patch(p_session uuid, p_key text, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; it jsonb; v_kind text; v_at timestamptz;
begin
  if p_session is null or nullif(p_key, '') is null or length(p_key) > 120
     or p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Solicitud inválida' using errcode = '22023';
  end if;
  if not ws_is_owner(p_session) then
    raise exception 'permission denied for table ws_deliverables' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ws_deliverable:' || p_session::text, 0));
  select data into d from ws_deliverables where session_id = p_session for update;
  if d is null or jsonb_typeof(d) <> 'object' then d := '{}'::jsonb; end if;
  select coalesce(nullif(s.kind, ''), 'dt') into v_kind from ws_sessions s where s.id = p_session;
  d := d || jsonb_build_object('v', 1, 'kind', v_kind);
  if jsonb_typeof(d -> 'items') is distinct from 'object' then d := jsonb_set(d, '{items}', '{}'::jsonb); end if;
  it := case when jsonb_typeof(d -> 'items' -> p_key) = 'object' then d -> 'items' -> p_key else '{}'::jsonb end || p_patch;
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into it
    from jsonb_each(it) e where e.value not in ('null'::jsonb, '""'::jsonb);
  if it = '{}'::jsonb then d := d #- array['items', p_key];
  else d := jsonb_set(d, array['items', p_key], it); end if;
  insert into ws_deliverables(session_id, data) values (p_session, d)
  on conflict (session_id) do update set data = excluded.data
  returning updated_at into v_at;
  return jsonb_build_object('data', d, 'updated_at', v_at);
end $$;
revoke execute on function ws_deliverable_patch(uuid, text, jsonb) from public, anon;
grant execute on function ws_deliverable_patch(uuid, text, jsonb) to authenticated;

insert into ws_schema_version(version) values ('2.11.1') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('ws_ai_begin','ws_ai_once','ws_deliverable_ai_merge','ws_deliverable_patch')) as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
