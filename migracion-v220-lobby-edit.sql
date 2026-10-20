-- Colmena v2.2 · Edición segura en Sala de espera
-- Córrela en Supabase → SQL Editor después de la v2.1. Se puede repetir sin problema.
-- Qué cambia:
--   · La configuración se puede editar únicamente en Sala de espera y antes de que entre la primera persona.
--   · La comprobación vive en PostgreSQL y es atómica: una entrada y una edición simultáneas no se cruzan.
--   · Cambiar de fase, usar el reloj y editar el resumen siguen funcionando normalmente.
-- Al final sale una fila: candados = 2, version = 2.2
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.1') then
    raise exception 'Primero corre migracion-v210-seguridad.sql (v2.1) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,2] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

alter table ws_sessions add column if not exists config_locked boolean not null default false;
update ws_sessions s set config_locked = true
where not s.config_locked and exists (select 1 from ws_participants p where p.session_id = s.id);

-- La entrada toma el mismo candado que una edición y marca la propia fila de la sesión.
-- Ese cambio de fila hace que PostgreSQL reevalúe una edición concurrente con el valor ya bloqueado.
create or replace function ws_lobby_join_lock() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(2201, hashtext(new.session_id::text));
  update ws_sessions set config_locked = true where id = new.session_id and not config_locked;
  return new;
end $$;

drop trigger if exists ws_00_lobby_join_lock on ws_participants;
create trigger ws_00_lobby_join_lock before insert on ws_participants
  for each row execute function ws_lobby_join_lock();
revoke execute on function ws_lobby_join_lock() from public, anon, authenticated;

-- Solo estas columnas forman la configuración del recorrido. Fase, reloj, cierre y resumen
-- no entran en este candado porque se actualizan durante o después del taller.
create or replace function ws_sessions_config_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if old.config_locked and not new.config_locked then
    raise exception 'La configuración bloqueada no puede volver a abrirse.';
  end if;
  if row(new.name, new.facilitator, new.votes_per_user, new.areas, new.stages,
         new.roles, new.tools, new.tasks, new.quickwins, new.q_checkin, new.q_expect,
         new.q_pain, new.q_idea, new.idea_votes, new.idea_top, new.brand, new.caso,
         new.kind, new.mins)
     is distinct from
     row(old.name, old.facilitator, old.votes_per_user, old.areas, old.stages,
         old.roles, old.tools, old.tasks, old.quickwins, old.q_checkin, old.q_expect,
         old.q_pain, old.q_idea, old.idea_votes, old.idea_top, old.brand, old.caso,
         old.kind, old.mins) then
    perform pg_advisory_xact_lock(2201, hashtext(old.id::text));
    if old.phase <> 'lobby' then
      raise exception 'La sala ya comenzó. La configuración quedó bloqueada para no cambiar el recorrido del grupo.';
    end if;
    if old.config_locked or exists (select 1 from ws_participants p where p.session_id = old.id) then
      raise exception 'Ya entraron personas a la sala. La configuración quedó bloqueada para no cambiarles el recorrido.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists ws_sessions_config_guard on ws_sessions;
create trigger ws_sessions_config_guard before update on ws_sessions
  for each row execute function ws_sessions_config_guard();
revoke execute on function ws_sessions_config_guard() from public, anon, authenticated;

insert into ws_schema_version(version, note)
values ('2.2', 'Creador sin fricción: edición atómica en Sala de espera hasta la primera entrada')
on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('ws_lobby_join_lock','ws_sessions_config_guard')
       and p.prosrc like '%pg_advisory_xact_lock%') as candados,
  (select version from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1) as version;
