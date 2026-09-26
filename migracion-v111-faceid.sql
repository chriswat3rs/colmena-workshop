-- Colmena v1.11 · Entrar con Face ID / huella (passkeys)
-- Córrelo UNA vez en Supabase → SQL Editor (se puede repetir sin problema).
-- Hace que entrar con Face ID cuente como acceso completo, pero SOLO con llaves que tú aprobaste
-- estando con tu código de verificación. Si aparece una llave que no aprobaste, Face ID deja de contar.

-- v1.11 · ¿Entraste con acceso fuerte? Sí si usaste el segundo factor (aal2) o si entraste con
-- Face ID / huella (passkey) usando una llave que TÚ aprobaste estando con segundo factor.
-- Si aparece una llave que no aprobaste, Face ID deja de contar hasta que la revises.
alter table ws_admins add column if not exists passkeys_trusted uuid[] not null default '{}';
create or replace function ws_strong() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    or ( exists (select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end) e
                 where e ->> 'method' = 'passkey')
         and exists (select 1 from ws_admins a where a.user_id = auth.uid() and cardinality(a.passkeys_trusted) > 0
                     and not exists (select 1 from auth.webauthn_credentials c where c.user_id = a.user_id and not (c.id = any(a.passkeys_trusted)))) );
$$;

create or replace function ws_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active)
     and ws_strong();
$$;

create or replace function ws_is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active and a.role = 'admin')
     and ws_strong();
$$;

drop function if exists ws_me();
create function ws_me() returns table (role text, name text, email text, active boolean, avatar text, title text)
language sql stable security definer set search_path = public as $$
  select a.role, a.name, a.email, a.active, a.avatar, a.title from ws_admins a
  where a.user_id = auth.uid() and ws_strong();
$$;

grant execute on function ws_me() to authenticated;
revoke execute on function ws_me() from public, anon;

create or replace function ws_mark_read(p_ids uuid[]) returns void
language sql security definer set search_path = public as $$
  update ws_notifications set read_at = now()
  where user_id = auth.uid() and read_at is null and id = any(p_ids)
    and ws_strong();
$$;

create or replace function ws_mark_all_read() returns void
language sql security definer set search_path = public as $$
  update ws_notifications set read_at = now()
  where user_id = auth.uid() and read_at is null and ws_strong();
$$;

create or replace function ws_my_email_prefs() returns jsonb
language sql stable security definer set search_path = public as $$
  select a.email_prefs from ws_admins a where a.user_id = auth.uid() and ws_strong();
$$;

drop policy if exists ws_notifications_own on ws_notifications;
create policy ws_notifications_own on ws_notifications for select to authenticated
  using (user_id = auth.uid() and ws_strong());

-- ------------------------------------------------------------
-- 4d) v1.11 · Entrar con Face ID / huella (passkeys)
-- ------------------------------------------------------------
-- Aprobar tus llaves nuevas: solo con segundo factor real (código), y solo las creadas en los últimos 10 minutos.
create or replace function ws_trust_passkeys() returns int
language plpgsql security definer set search_path = public, auth as $$
declare n int;
begin
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' or not exists (select 1 from ws_admins where user_id = auth.uid() and active) then
    raise exception 'Para activar Face ID entra con tu código de verificación';
  end if;
  update ws_admins a set passkeys_trusted = array(
      select c.id from auth.webauthn_credentials c where c.user_id = a.user_id
        and (c.id = any(a.passkeys_trusted) or c.created_at > now() - interval '10 minutes'))
    where a.user_id = auth.uid();
  select cardinality(passkeys_trusted) into n from ws_admins where user_id = auth.uid();
  return n;
end $$;
-- Estado de tus llaves: aprobadas, sin aprobar (alerta) y última vez usada
create or replace function ws_passkey_status() returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select jsonb_build_object(
    'trusted', (select count(*) from auth.webauthn_credentials c where c.user_id = a.user_id and c.id = any(a.passkeys_trusted)),
    'untrusted', (select count(*) from auth.webauthn_credentials c where c.user_id = a.user_id and not (c.id = any(a.passkeys_trusted))),
    'last_used', (select max(c.last_used_at) from auth.webauthn_credentials c where c.user_id = a.user_id and c.id = any(a.passkeys_trusted)))
  from ws_admins a where a.user_id = auth.uid() and ws_strong();
$$;
-- Apagar Face ID en todos tus dispositivos (vuelves a entrar con contraseña y código)
create or replace function ws_untrust_passkeys() returns void
language sql security definer set search_path = public as $$
  update ws_admins set passkeys_trusted = '{}' where user_id = auth.uid() and ws_strong();
$$;
revoke all on function ws_strong(), ws_trust_passkeys(), ws_passkey_status(), ws_untrust_passkeys() from public, anon;
grant execute on function ws_strong(), ws_trust_passkeys(), ws_passkey_status(), ws_untrust_passkeys() to authenticated;


-- Verificación: debe mostrar 4 funciones nuevas
select proname from pg_proc where proname in ('ws_strong','ws_trust_passkeys','ws_passkey_status','ws_untrust_passkeys') order by 1;
