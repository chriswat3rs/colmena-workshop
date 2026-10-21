-- Colmena v2.3.1 · Último acceso del equipo
-- Córrela en Supabase → SQL Editor después de la v2.3. Se puede repetir sin problema.
-- Solo un admin con acceso fuerte puede consultar estas fechas.
-- Al final sale una fila: funciones = 1, version = 2.3.1
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.3') then
    raise exception 'Primero corre migracion-v230-analitica.sql (v2.3) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,3,1] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- Combina el último inicio de sesión de Supabase con la última actividad técnica
-- de Colmena. No devuelve eventos, IP, respuestas ni información de participantes.
create or replace function ws_team_activity()
returns table(user_id uuid, last_sign_in_at timestamptz, last_access_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede ver el último acceso del equipo'; end if;
  return query
    select a.user_id,
           u.last_sign_in_at,
           greatest(u.last_sign_in_at, t.last_event_at) as last_access_at
    from ws_admins a
    left join auth.users u on u.id = a.user_id
    left join lateral (
      select max(e.received_at) as last_event_at
      from ws_telemetry_events e
      where e.actor_key = md5(a.user_id::text || ':colmena-telemetry-v1:a')
                        || md5(a.user_id::text || ':colmena-telemetry-v1:b')
    ) t on true
    order by a.created_at, a.user_id;
end;
$$;

revoke execute on function ws_team_activity() from public, anon;
grant execute on function ws_team_activity() to authenticated;

insert into ws_schema_version(version) values ('2.3.1') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='ws_team_activity') as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
