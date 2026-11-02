-- Colmena v2.8 · Entregable del taller (modelo de competencias y plan de acción)
-- Córrela en Supabase → SQL Editor después de la v2.5. Se puede repetir sin problema.
-- En Resultados, el entregable se arma con lo que decidió la sala. Aquí se guarda solo lo que completa
-- quien facilita: la definición de cada competencia (las que sugiere la IA quedan marcadas «por validar»)
-- y, en Mejora de procesos, el primer paso, responsable, fecha y estado de cada acción.
-- Vive en su propia tabla: no viaja por tiempo real y los celulares de la sala no la pueden leer.
-- La ve quien facilita el taller (y una persona admin, en solo lectura); solo quien facilita la edita.
-- Al final sale una fila: tabla = 1, reglas = 3, version = 2.8.0
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.5.0') then
    raise exception 'Primero corre migracion-v250-eliminar-cuenta.sql (v2.5) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,8,0] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- Una fila por taller. «data» lleva lo que completa quien facilita, por elemento del entregable:
--   {"v":1, "kind":"comp"|"dt", "ai_at":"…", "items":{"<id>":{"def":"…","src":"ai"|"ok", "paso":"…","resp":"…","fecha":"AAAA-MM-DD","estado":"pend"|"curso"|"hecho"}}}
create table if not exists ws_deliverables (
  session_id uuid primary key references ws_sessions(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table ws_deliverables drop constraint if exists ws_deliverables_data_check;
alter table ws_deliverables add constraint ws_deliverables_data_check
  check (jsonb_typeof(data) = 'object' and pg_column_size(data) < 100000);
alter table ws_deliverables enable row level security;

drop policy if exists ws_deliverables_select on ws_deliverables;
create policy ws_deliverables_select on ws_deliverables for select to authenticated
  using (ws_can_view(session_id));
drop policy if exists ws_deliverables_insert on ws_deliverables;
create policy ws_deliverables_insert on ws_deliverables for insert to authenticated
  with check (ws_is_owner(session_id));
drop policy if exists ws_deliverables_update on ws_deliverables;
create policy ws_deliverables_update on ws_deliverables for update to authenticated
  using (ws_is_owner(session_id))
  with check (ws_is_owner(session_id));
revoke all on ws_deliverables from anon, authenticated;
grant select, insert, update on ws_deliverables to authenticated;

-- Fecha y autor de cada cambio los pone la base (la página no los puede alterar).
-- La IA guarda con la llave del servidor (sin sesión): ahí se respeta el autor que manda la función.
create or replace function ws_deliverables_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;
revoke execute on function ws_deliverables_stamp() from public, anon, authenticated;
drop trigger if exists ws_deliverables_stamp on ws_deliverables;
create trigger ws_deliverables_stamp before insert or update on ws_deliverables
  for each row execute function ws_deliverables_stamp();

insert into ws_schema_version(version) values ('2.8.0') on conflict (version) do nothing;

select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'ws_deliverables' and c.relrowsecurity) as tabla,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ws_deliverables') as reglas,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
