-- Colmena v1.12 · Alta sin contraseñas, invitaciones que se reenvían, reinicio de acceso y creador con IA
-- Córrelo UNA vez en Supabase → SQL Editor → New query → pegar todo → Run. Se puede repetir sin problema.
-- Qué agrega:
--   · Invitación con Face ID / huella (sin contraseña ni app) y estado de la invitación (vigente, vencida, usada).
--   · Reenviar invitaciones vencidas y que el invitado pida una nueva.
--   · «Reiniciar acceso» para quien perdió su teléfono.
--   · Protección: si alguien entra solo con Face ID, un correo + una app agregada a escondidas no bastan.
--   · Campo «caso» del taller (textos de la sala) y límite de 30 propuestas de IA al día por persona.

-- ------------------------------------------------------------
-- 4e) v1.12 · Alta sin contraseña, invitaciones con estado y reenvío, reinicio de acceso
-- ------------------------------------------------------------
alter table ws_admins add column if not exists reenroll_until timestamptz;
-- passkey_only: la persona entró solo con Face ID (sin app autenticadora). Así, un enlace de correo + una app
-- agregada a escondidas NO basta para entrar a su cuenta: el código de app solo cuenta si ella lo aprobó con Face ID.
alter table ws_admins add column if not exists passkey_only boolean not null default false;

create or replace function ws_strong() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select ( coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
           and not exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.passkey_only) )
    or ( exists (select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end) e
                 where e ->> 'method' = 'passkey')
         and exists (select 1 from ws_admins a where a.user_id = auth.uid() and cardinality(a.passkeys_trusted) > 0
                     and not exists (select 1 from auth.webauthn_credentials c where c.user_id = a.user_id and not (c.id = any(a.passkeys_trusted)))) );
$$;

-- Primera cuenta = admin. Además, al entrar con acceso completo se cierra un reinicio de acceso pendiente.
create or replace function ws_claim_admin() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
     or coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    return false;
  end if;
  if exists (select 1 from ws_admins where user_id = auth.uid()) then
    if ws_strong() then update ws_admins set reenroll_until = null where user_id = auth.uid() and reenroll_until is not null; end if;
    return exists (select 1 from ws_admins where user_id = auth.uid() and active);
  end if;
  lock table ws_admins in exclusive mode;
  if not exists (select 1 from ws_admins) then
    insert into ws_admins (user_id, email, role) values (auth.uid(), auth.jwt() ->> 'email', 'admin');
    return true;
  end if;
  return false;
end $$;

-- Canje clásico (con app autenticadora): la invitación nueva también deja la app como método válido
create or replace function ws_redeem_invite(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare v ws_invites; v_mail text := lower(coalesce(auth.jwt() ->> 'email',''));
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Inicia sesión con tu correo para usar la invitación';
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Activa la verificación en dos pasos para usar la invitación';
  end if;
  select * into v from ws_invites i where i.code_hash = ws_invite_hash(p_code) for update;
  if v.id is null or v.revoked_at is not null or v.expires_at <= now()
     or (v.used_at is not null and v.used_by is distinct from auth.uid()) then
    raise exception 'La invitación no es válida, ya se usó o venció. Pide una nueva al admin.';
  end if;
  if v.email <> v_mail then
    raise exception 'Esta invitación es para %. Entra con ese correo.', v.email;
  end if;
  insert into ws_admins (user_id, email, role, name, active)
  values (auth.uid(), v_mail, v.role, v.name, true)
  on conflict (user_id) do update
    set role = excluded.role, active = true, email = excluded.email,
        name = coalesce(ws_admins.name, excluded.name), passkey_only = false, reenroll_until = null;
  update ws_invites set used_by = auth.uid(), used_at = coalesce(used_at, now()) where id = v.id;
  return v.role;
end $$;

-- Quien entra solo con Face ID agrega una app autenticadora como respaldo (debe estar dentro con Face ID)
create or replace function ws_allow_totp() returns boolean
language plpgsql security definer set search_path = public, auth as $$
begin
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' or not ws_strong() then
    raise exception 'Confirma con Face ID o tu huella para agregar la app';
  end if;
  update ws_admins set passkey_only = false where user_id = auth.uid();
  return true;
end $$;
create table if not exists ws_auth_mail_log (id bigint generated always as identity primary key, email text not null, kind text not null, at timestamptz not null default now());
create index if not exists ws_auth_mail_log_email on ws_auth_mail_log(email, at);
alter table ws_auth_mail_log enable row level security;          -- sin políticas: solo el servidor (service role) la usa
revoke all on ws_auth_mail_log from anon, authenticated;

-- Creador con IA: «caso» = una unidad del proceso («un siniestro», «una solicitud») para los textos de la sala
alter table ws_sessions add column if not exists caso text check (char_length(caso) <= 40);
drop function if exists ws_join_lookup(text);
create function ws_join_lookup(p_code text)
returns table (id uuid, code text, name text, facilitator text, phase text,
               votes_per_user int, areas jsonb, stages jsonb,
               q_checkin text, q_expect text, q_pain text, brand text,
               roles jsonb, tools jsonb, quickwins jsonb, q_idea text,
               idea_votes int, idea_top int, tasks jsonb, caso text)
language sql stable security definer set search_path = public as $$
  select s.id, s.code, s.name, s.facilitator, s.phase, s.votes_per_user, s.areas, s.stages,
         s.q_checkin, s.q_expect, s.q_pain, s.brand,
         s.roles, s.tools, s.quickwins, s.q_idea, s.idea_votes, s.idea_top, s.tasks, s.caso
  from ws_sessions s
  where auth.uid() is not null and s.code = upper(trim(p_code));
$$;
revoke execute on function ws_join_lookup(text) from public, anon;
grant execute on function ws_join_lookup(text) to authenticated;

-- Límite de propuestas con IA: 30 al día por persona (cuida el gasto de la cuenta de Anthropic)
create table if not exists ws_ai_log (id bigint generated always as identity primary key, user_id uuid not null, at timestamptz not null default now());
create index if not exists ws_ai_log_user on ws_ai_log(user_id, at);
alter table ws_ai_log enable row level security;
revoke all on ws_ai_log from anon, authenticated;
create or replace function ws_ai_take() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_admin() then return false; end if;
  if (select count(*) from ws_ai_log where user_id = auth.uid() and at > now() - interval '1 day') >= 30 then return false; end if;
  insert into ws_ai_log(user_id) values (auth.uid());
  delete from ws_ai_log where at < now() - interval '30 days';
  return true;
end $$;
revoke execute on function ws_ai_take() from public, anon;
grant execute on function ws_ai_take() to authenticated;

-- Invitación: datos + estado (vigente, vencida, usada, cancelada) y quién invitó. Solo con el código exacto.
drop function if exists ws_invite_peek(text);
create function ws_invite_peek(p_code text)
returns table (email text, name text, role text, expires_at timestamptz, status text, inviter text)
language sql stable security definer set search_path = public as $$
  select i.email, i.name, i.role, i.expires_at,
         case when i.used_at is not null then 'used' when i.revoked_at is not null then 'revoked'
              when i.expires_at <= now() then 'expired' else 'valid' end,
         (select coalesce(a.name, a.email) from ws_admins a where a.user_id = i.created_by)
  from ws_invites i where i.code_hash = ws_invite_hash(p_code)
  order by i.created_at desc limit 1;
$$;

-- Reenviar: nueva invitación (código nuevo, 7 días) con los mismos datos; la anterior deja de funcionar
drop function if exists ws_resend_invite(uuid);
create function ws_resend_invite(p_id uuid)
returns table (id uuid, code text, email text, name text, role text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare v ws_invites; r record;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede reenviar invitaciones'; end if;
  select * into v from ws_invites i where i.id = p_id;
  if v.id is null or v.used_at is not null then raise exception 'Esa invitación ya no existe o ya se usó'; end if;
  select * into r from ws_create_invite(v.email, v.name, v.role);
  return query select r.id, r.code, r.email, v.name, v.role, r.expires_at;
end $$;

-- El invitado con enlace vencido pide uno nuevo: avisa a quien lo invitó (una vez al día)
create or replace function ws_request_invite_renewal(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v ws_invites;
begin
  select * into v from ws_invites i where i.code_hash = ws_invite_hash(p_code);
  if v.id is null or v.used_at is not null then return false; end if;
  perform ws_notify(v.created_by, 'invite_expiring', coalesce(v.name, v.email) || ' pide una nueva invitación',
    'Su enlace venció o se canceló. Reenvíale la invitación desde Equipo.',
    jsonb_build_object('label','Reenviar','view','team'), jsonb_build_object('invite', v.id), true,
    'renew:' || v.id || ':' || to_char(now(),'YYYYMMDD'));
  return true;
end $$;

-- Estado de tu cuenta aunque aún no confirmes con Face ID o código (solo sobre ti)
create or replace function ws_account_state() returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select jsonb_build_object(
    'staff', a.user_id is not null, 'active', coalesce(a.active,false),
    'trusted', coalesce((select count(*) from auth.webauthn_credentials c where c.user_id = auth.uid() and c.id = any(a.passkeys_trusted)),0),
    'reenroll', coalesce(a.reenroll_until > now(), false), 'passkey_only', coalesce(a.passkey_only, false))
  from (select 1) x left join ws_admins a on a.user_id = auth.uid()
  where auth.uid() is not null and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
$$;

-- Canjear la invitación activando Face ID / huella (sin contraseña ni app). El ancla de confianza es
-- el enlace de invitación (llegó a tu correo); se aprueba solo la llave que acabas de crear.
create or replace function ws_redeem_invite_passkey(p_code text, p_cred uuid default null) returns text
language plpgsql security definer set search_path = public, auth as $$
declare v ws_invites; v_mail text := lower(coalesce(auth.jwt() ->> 'email','')); v_ids uuid[];
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'Abre de nuevo tu invitación'; end if;
  select * into v from ws_invites i where i.code_hash = ws_invite_hash(p_code) for update;
  if v.id is null or v.revoked_at is not null or v.expires_at <= now()
     or (v.used_at is not null and v.used_by is distinct from auth.uid()) then
    raise exception 'La invitación no es válida, ya se usó o venció. Pide una nueva.';
  end if;
  if v.email <> v_mail then raise exception 'Esta invitación es para %.', v.email; end if;
  select array_agg(c.id) into v_ids from auth.webauthn_credentials c
   where c.user_id = auth.uid() and c.created_at > now() - interval '5 minutes' and (p_cred is null or c.id = p_cred);
  if coalesce(cardinality(v_ids),0) = 0 then raise exception 'Primero activa Face ID o tu huella en este dispositivo'; end if;
  insert into ws_admins (user_id, email, role, name, active, passkeys_trusted, passkey_only)
  values (auth.uid(), v_mail, v.role, v.name, true, v_ids, true)
  on conflict (user_id) do update set role = excluded.role, active = true, email = excluded.email,
      name = coalesce(ws_admins.name, excluded.name), passkeys_trusted = excluded.passkeys_trusted, reenroll_until = null, passkey_only = true;
  update ws_invites set used_by = auth.uid(), used_at = coalesce(used_at, now()) where id = v.id;
  return v.role;
end $$;

-- Tras un reinicio de acceso hecho por el admin: activar Face ID de nuevo (una vez, en 7 días)
create or replace function ws_reenroll_passkey(p_cred uuid default null) returns int
language plpgsql security definer set search_path = public, auth as $$
declare v_ids uuid[];
begin
  if not exists (select 1 from ws_admins where user_id = auth.uid() and active and reenroll_until > now()) then
    raise exception 'Tu acceso no está en reinicio. Entra con tu Face ID o tu código.';
  end if;
  select array_agg(c.id) into v_ids from auth.webauthn_credentials c
   where c.user_id = auth.uid() and c.created_at > now() - interval '5 minutes' and (p_cred is null or c.id = p_cred);
  if coalesce(cardinality(v_ids),0) = 0 then raise exception 'Primero activa Face ID o tu huella en este dispositivo'; end if;
  update ws_admins set passkeys_trusted = v_ids, reenroll_until = null, passkey_only = true where user_id = auth.uid();
  return cardinality(v_ids);
end $$;

-- Aprobar una llave nueva (solo la que acabas de crear). Vale si estás dentro con tu código de app
-- (y tu app está aprobada) o con Face ID de una llave ya aprobada (para agregar otro dispositivo).
drop function if exists ws_trust_passkeys();
create or replace function ws_trust_passkeys(p_cred uuid default null) returns int
language plpgsql security definer set search_path = public, auth as $$
declare n int; v_ok boolean;
begin
  select a.active and (
           (coalesce(auth.jwt() ->> 'aal', '') = 'aal2' and not a.passkey_only)
        or (exists (select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end) e
                    where e ->> 'method' = 'passkey')
            and cardinality(a.passkeys_trusted) > 0
            and not exists (select 1 from auth.webauthn_credentials c where c.user_id = a.user_id
                            and not (c.id = any(a.passkeys_trusted)) and c.created_at <= now() - interval '10 minutes')))
    into v_ok from ws_admins a where a.user_id = auth.uid();
  if not coalesce(v_ok, false) then
    raise exception 'Para activar Face ID entra con tu código de verificación';
  end if;
  update ws_admins a set passkeys_trusted = array(
      select c.id from auth.webauthn_credentials c where c.user_id = a.user_id
        and (c.id = any(a.passkeys_trusted) or (c.created_at > now() - interval '10 minutes' and (p_cred is null or c.id = p_cred))))
    where a.user_id = auth.uid();
  select cardinality(passkeys_trusted) into n from ws_admins where user_id = auth.uid();
  return n;
end $$;

-- Estado de tus llaves + si entras solo con Face ID (sin app de respaldo)
create or replace function ws_passkey_status() returns jsonb
language sql stable security definer set search_path = public, auth as $$
  select jsonb_build_object(
    'trusted', (select count(*) from auth.webauthn_credentials c where c.user_id = a.user_id and c.id = any(a.passkeys_trusted)),
    'untrusted', (select count(*) from auth.webauthn_credentials c where c.user_id = a.user_id and not (c.id = any(a.passkeys_trusted))),
    'last_used', (select max(c.last_used_at) from auth.webauthn_credentials c where c.user_id = a.user_id and c.id = any(a.passkeys_trusted)),
    'passkey_only', a.passkey_only)
  from ws_admins a where a.user_id = auth.uid() and ws_strong();
$$;
-- Apagar Face ID: no se permite si es tu único método (te quedarías fuera)
create or replace function ws_untrust_passkeys() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from ws_admins where user_id = auth.uid() and passkey_only) then
    raise exception 'Face ID es tu único método para entrar. Agrega primero la app autenticadora como respaldo.';
  end if;
  update ws_admins set passkeys_trusted = '{}' where user_id = auth.uid() and ws_strong();
end $$;

-- El admin reinicia el acceso de alguien (perdió su teléfono): la función admin-account borra sus
-- métodos y luego llama a esta, que deja la cuenta lista para volver a activar Face ID o app.
create or replace function ws_admin_reset_access(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_mail text;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede reiniciar accesos'; end if;
  if p_user = auth.uid() then raise exception 'No puedes reiniciar tu propio acceso'; end if;
  update ws_admins set passkeys_trusted = '{}', reenroll_until = now() + interval '7 days', passkey_only = false where user_id = p_user returning email into v_mail;
  if v_mail is null then raise exception 'Esa cuenta no es del equipo'; end if;
  return v_mail;
end $$;

-- Inicio: invitaciones vigentes y vencidas (hasta 30 días) con su estado
create or replace function ws_dashboard() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'code', s.code, 'name', s.name, 'phase', s.phase, 'owner_id', s.owner_id,
        'created_at', s.created_at, 'closed_at', s.closed_at,
        'participants', (select count(*) from ws_participants p where p.session_id = s.id),
        'listos', (select count(*) from ws_participants p where p.session_id = s.id and p.done_phases ? s.phase),
        'cards', (select count(*) from ws_cards c where c.session_id = s.id),
        'ideas', (select count(*) from ws_ideas i where i.session_id = s.id and i.kind = 'idea')
      ) order by s.created_at desc)
      from ws_sessions s
      where ws_is_admin() and (s.owner_id = auth.uid() or ws_is_superadmin())), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'name', i.name, 'role', i.role, 'expires_at', i.expires_at) order by i.expires_at)
      from ws_invites i
      where ws_is_superadmin() and i.used_at is null and i.revoked_at is null and i.expires_at > now() - interval '30 days'), '[]'::jsonb)
  );
$$;

revoke execute on function ws_allow_totp() from public, anon;
grant execute on function ws_allow_totp() to authenticated;
revoke execute on function ws_invite_peek(text), ws_resend_invite(uuid), ws_request_invite_renewal(text), ws_account_state(),
  ws_redeem_invite_passkey(text,uuid), ws_reenroll_passkey(uuid), ws_trust_passkeys(uuid), ws_admin_reset_access(uuid), ws_dashboard() from public, anon;
grant execute on function ws_resend_invite(uuid), ws_account_state(), ws_redeem_invite_passkey(text,uuid), ws_reenroll_passkey(uuid),
  ws_trust_passkeys(uuid), ws_admin_reset_access(uuid), ws_dashboard(), ws_invite_peek(text), ws_request_invite_renewal(text) to authenticated;
grant execute on function ws_invite_peek(text), ws_request_invite_renewal(text) to anon;


-- Verificación: deben salir 12 funciones
select proname from pg_proc where proname in ('ws_invite_peek','ws_resend_invite','ws_request_invite_renewal','ws_account_state',
  'ws_redeem_invite_passkey','ws_reenroll_passkey','ws_trust_passkeys','ws_admin_reset_access','ws_allow_totp','ws_ai_take','ws_join_lookup','ws_strong')
order by 1;
