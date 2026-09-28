-- Colmena v1.13 · Borradores de talleres en la base de datos
-- Córrelo UNA vez en Supabase → SQL Editor → New query → pegar todo → Run. Se puede repetir sin problema.
-- Qué agrega: los borradores del creador se guardan en tu cuenta (los ves en Inicio desde cualquier dispositivo).
-- Solo tú ves y editas tus borradores; nadie más (ni participantes, ni otros facilitadores, ni el admin).

-- ------------------------------------------------------------
-- 4f) v1.13 · Borradores de talleres en la base (se ven en cualquier dispositivo)
-- ------------------------------------------------------------
create table if not exists ws_drafts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text check (char_length(name) <= 160),
  step int not null default 0 check (step between 0 and 20),
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) < 200000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ws_drafts_owner on ws_drafts(owner_id, updated_at desc);
alter table ws_drafts enable row level security;
drop policy if exists ws_drafts_own on ws_drafts;
create policy ws_drafts_own on ws_drafts for all to authenticated
  using (owner_id = auth.uid() and ws_is_admin())
  with check (owner_id = auth.uid() and ws_is_admin());
revoke all on ws_drafts from anon;
grant select, insert, update, delete on ws_drafts to authenticated;
-- Máximo 50 borradores por persona (evita que se llene la base por error)
create or replace function ws_drafts_cap() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from ws_drafts where owner_id = new.owner_id) >= 50 then
    raise exception 'Tienes demasiados borradores. Elimina alguno para guardar uno nuevo.';
  end if;
  return new;
end $$;
drop trigger if exists ws_drafts_cap on ws_drafts;
create trigger ws_drafts_cap before insert on ws_drafts for each row execute function ws_drafts_cap();

-- Verificación: debe salir ws_drafts con rls = true
select relname, relrowsecurity from pg_class where relname = 'ws_drafts';
