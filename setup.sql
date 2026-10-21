-- ============================================================
-- COLMENA · setup.sql · ESTADO ACTUAL v2.3.1
-- Lo arma tools/arma_setup.py: no lo edites a mano (edita la migración y vuelve a armarlo).
--
-- Base nueva: pega TODO este archivo en Supabase → SQL Editor → New query → Run.
-- Base que ya existe: también sirve y no borra datos (todo es «if not exists» / «create or replace»),
-- aunque basta con correr la migración nueva que indique el README.
-- Incluye, en orden: Base v1.26 · v2.0 · Tipos de taller, «Juntar parecidas» y tiempo por fase · v2.1 · Seguridad y datos · v2.2 · Edición segura en Sala de espera · v2.3 · Analítica privada de producto · v2.3.1 · Último acceso del equipo.
-- Si la base ya está en una versión más nueva que la 2.3.1, se detiene con un aviso y no cambia nada.
-- ============================================================
do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is not null then
    select version into v from public.ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
    if v is not null and string_to_array(v, '.')::int[] > array[2,3,1] then
      raise exception 'Tu base ya está en la versión % y este setup.sql es de la 2.3.1. No lo corras: regresaría funciones a una versión anterior. Usa el setup.sql más nuevo.', v;
    end if;
  end if;
end $$;

-- ============================================================
-- PARTE · Base v1.26 (el setup.sql anterior: tablas, reglas de acceso, funciones y tiempo real)
-- (de migraciones-anteriores/setup-base-v126.sql)
-- ============================================================
-- ============================================================
-- COLMENA v1.7 · esquema seguro para Supabase
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- Es re-ejecutable: puedes correrlo las veces que quieras.
-- Si ya tenías la v1.1, la actualiza SIN borrar tu cuenta, tus
-- talleres ni lo capturado (solo agrega columnas, tablas y reglas).
--
-- Novedades v1.2: perfil del participante (rol y etapas en las que
-- participa), herramienta en cada dolor, fase «Quick wins» (calificar
-- mejoras propuestas y sugerir nuevas) y fase «Ideas» («¿Cómo
-- podríamos…?» sobre los dolores más votados, con apoyos limitados).
-- Novedades v1.3: actividades por etapa (cada dolor puede señalar la
-- actividad exacta del proceso) y listas a validar con distintas escalas
-- (quick wins, reglas del nuevo flujo y tiempos por etapa) dentro de la
-- misma fase; se guardan en la columna quickwins con un campo «kind».
-- Novedades v1.4: cada participante marca cuándo terminó cada actividad
-- (done_phases) y todos ven «X de N ya terminaron» sin ver a los demás.
-- Novedades v1.5: dos roles de cuenta.
--   · Admin: crea sus talleres, VE (solo lectura) y exporta los talleres de
--     todos los facilitadores, invita facilitadores y los activa/desactiva.
--   · Facilitador: crea y opera solo sus propios talleres; no ve los de otros.
--   Las cuentas nuevas entran con una invitación de un solo uso (vence en
--   7 días) que genera el admin. La primera cuenta que activó su segundo
--   factor (tú) queda como admin automáticamente.
--   Cada cuenta puede subir su foto de perfil (se guarda chica, ~10 KB).
-- Novedades v1.6: centro de notificaciones (campana en el panel + correo en lo importante).
-- Novedades v1.7: Inicio con saludo y widgets, nombre y puesto editables, creador paso a paso.
--
-- Cómo protege los datos (todo se valida aquí, en la base de datos,
-- no en la página, porque el código de una página se puede alterar):
--   · Facilitador: correo + contraseña + segundo factor (app
--     autenticadora). Sin el segundo factor la base no le entrega nada.
--   · Participantes: identidad anónima automática por celular.
--     Solo ven su sesión, sus propios datos y las tarjetas para votar.
--   · Sin iniciar sesión (solo con la llave pública) no se lee nada.
--
-- Requisitos en el panel de Supabase (ver README):
--   · Authentication → Sign In / Providers → Allow anonymous sign-ins: ON
--   · Tu usuario facilitador creado en Authentication → Users
--   · v1.5: Authentication → Sign In / Providers → Email: «Allow new users
--     to sign up» ON y «Confirm email» OFF (los invitados crean su cuenta
--     desde la app; sin invitación válida no obtienen ningún permiso)
-- ============================================================

-- ------------------------------------------------------------
-- 0) Migración desde la v1 (sin autenticación).
--    Si detecta las tablas de la v1 (columna "pin"), las borra.
--    La v1 nunca se usó en un taller real: solo contiene pruebas.
-- ------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'ws_sessions' and column_name = 'pin') then
    drop table if exists ws_votes, ws_cards, ws_participants, ws_sessions cascade;
  end if;
end $$;

-- ------------------------------------------------------------
-- 1) Tablas
-- ------------------------------------------------------------
create table if not exists ws_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

create table if not exists ws_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  code text unique not null check (code ~ '^[A-Z0-9]{6}$'),
  name text not null check (char_length(name) between 1 and 160),
  facilitator text check (char_length(facilitator) <= 120),
  phase text not null default 'lobby'
    check (phase in ('lobby','checkin','pains','votes','quickwins','ideas','results','closed')),
  votes_per_user int not null default 5 check (votes_per_user between 1 and 20),
  areas jsonb not null default '[]',
  stages jsonb not null default '[]',
  q_checkin text, q_expect text, q_pain text,
  brand text,
  created_at timestamptz not null default now()
);

create table if not exists ws_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nombre text not null check (char_length(nombre) between 1 and 80),
  apellido text check (char_length(apellido) <= 80),
  area text check (char_length(area) <= 80),
  rol text check (char_length(rol) <= 120),
  emoji text check (char_length(emoji) <= 16),
  mood text check (char_length(mood) <= 20),
  expectativa text check (char_length(expectativa) <= 280),
  joined_at timestamptz not null default now(),
  unique (session_id, user_id)
);

create table if not exists ws_cards (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  participant_id uuid not null references ws_participants(id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 500),
  etapa text check (char_length(etapa) <= 120),
  severidad int not null default 3 check (severidad between 1 and 5),
  created_at timestamptz not null default now()
);

create table if not exists ws_votes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  participant_id uuid not null references ws_participants(id) on delete cascade,
  card_id uuid not null references ws_cards(id) on delete cascade,
  points int not null default 0 check (points >= 0),
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, card_id)
);

create index if not exists ws_sessions_owner       on ws_sessions(owner_id);
create index if not exists ws_participants_session on ws_participants(session_id);
create index if not exists ws_participants_user    on ws_participants(user_id);
create index if not exists ws_cards_session        on ws_cards(session_id);
create index if not exists ws_votes_session        on ws_votes(session_id);

-- ------------------------------------------------------------
-- 1b) Novedades v1.2 (solo agrega lo que falte; no borra nada)
-- ------------------------------------------------------------
alter table ws_sessions add column if not exists roles jsonb not null default '[]'
  check (jsonb_typeof(roles) = 'array');
alter table ws_sessions add column if not exists tools jsonb not null default '{}'
  check (jsonb_typeof(tools) = 'object');
alter table ws_sessions add column if not exists quickwins jsonb not null default '[]'
  check (jsonb_typeof(quickwins) = 'array');
alter table ws_sessions add column if not exists q_idea text
  check (char_length(q_idea) <= 280);
-- v1.3 · actividades por etapa: {"3 Revisar información": ["3.7 Validación de bajas", …]}
alter table ws_sessions add column if not exists tasks jsonb not null default '{}'
  check (jsonb_typeof(tasks) = 'object');
-- v1.3 · cada dolor puede señalar la actividad del proceso donde ocurre
alter table ws_cards add column if not exists actividad text
  check (char_length(actividad) <= 160);
-- v1.4 · actividades que el participante dio por terminadas (p. ej. ["checkin","pains"])
alter table ws_participants add column if not exists done_phases jsonb not null default '[]'
  check (jsonb_typeof(done_phases) = 'array');
alter table ws_sessions add column if not exists idea_votes int not null default 3
  check (idea_votes between 1 and 10);
alter table ws_sessions add column if not exists idea_top int not null default 3
  check (idea_top between 1 and 6);

alter table ws_sessions drop constraint if exists ws_sessions_phase_check;
alter table ws_sessions add constraint ws_sessions_phase_check
  check (phase in ('lobby','checkin','pains','votes','quickwins','ideas','results','closed'));

alter table ws_participants add column if not exists etapas jsonb not null default '[]'
  check (jsonb_typeof(etapas) = 'array' and jsonb_array_length(etapas) <= 30
         and octet_length(etapas::text) <= 4000);

alter table ws_cards add column if not exists herramienta text
  check (char_length(herramienta) <= 120);

-- Calificación de quick wins: 3 = ayuda mucho, 2 = algo, 1 = poco, 0 = no aplica
create table if not exists ws_qw_ratings (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  participant_id uuid not null references ws_participants(id) on delete cascade,
  qw_id text not null check (char_length(qw_id) between 1 and 20),
  score int not null check (score between 0 and 3),
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, qw_id)
);

-- Ideas («¿Cómo podríamos…?», kind = 'idea') y quick wins propuestos por el equipo (kind = 'qw')
create table if not exists ws_ideas (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  participant_id uuid not null references ws_participants(id) on delete cascade,
  kind text not null check (kind in ('idea','qw')),
  card_id uuid references ws_cards(id) on delete cascade,
  etapa text check (char_length(etapa) <= 120),
  texto text not null check (char_length(texto) between 1 and 500),
  created_at timestamptz not null default now()
);

-- Apoyos a ideas (tope por persona, validado en el servidor)
create table if not exists ws_idea_votes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ws_sessions(id) on delete cascade,
  participant_id uuid not null references ws_participants(id) on delete cascade,
  idea_id uuid not null references ws_ideas(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (session_id, participant_id, idea_id)
);

-- v1.5 · Roles de cuenta: 'admin' ve todo (solo lectura en talleres ajenos) · 'facilitator' solo lo suyo
alter table ws_admins add column if not exists role text not null default 'facilitator';
alter table ws_admins add column if not exists active boolean not null default true;
alter table ws_admins add column if not exists name text;
alter table ws_admins drop constraint if exists ws_admins_role_check;
alter table ws_admins add constraint ws_admins_role_check check (role in ('admin','facilitator'));
alter table ws_admins add column if not exists avatar text;
alter table ws_admins drop constraint if exists ws_admins_avatar_check;
alter table ws_admins add constraint ws_admins_avatar_check
  check (avatar is null or (avatar ~ '^data:image/(webp|jpeg|png);base64,[A-Za-z0-9+/=]+$' and octet_length(avatar) <= 150000));
alter table ws_admins drop constraint if exists ws_admins_name_check;
alter table ws_admins add constraint ws_admins_name_check check (char_length(name) <= 120);
-- Quien ya era facilitador en la v1.4 (la primera cuenta) pasa a admin
update ws_admins set role = 'admin'
where not exists (select 1 from ws_admins where role = 'admin')
  and user_id = (select user_id from ws_admins order by created_at, user_id limit 1);

-- v1.5 · Invitaciones de un solo uso. Se guarda solo la huella (sha256) del código.
create table if not exists ws_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash text unique not null,
  email text not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  name text check (char_length(name) <= 120),
  role text not null default 'facilitator' check (role in ('admin','facilitator')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz,
  revoked_at timestamptz
);
create index if not exists ws_invites_email on ws_invites(email);

create index if not exists ws_qw_ratings_session  on ws_qw_ratings(session_id);
create index if not exists ws_ideas_session       on ws_ideas(session_id);
create index if not exists ws_idea_votes_session  on ws_idea_votes(session_id);

-- ------------------------------------------------------------
-- 2) Funciones de apoyo (se ejecutan con privilegios del dueño,
--    pero solo responden sobre el usuario que hace la petición)
-- ------------------------------------------------------------

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

-- ¿Eres facilitador (o admin) activo Y entraste con segundo factor?
-- (el nombre se conserva por compatibilidad: significa «cuenta con acceso al panel»)
create or replace function ws_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active)
     and ws_strong();
$$;

-- v1.5 · ¿Eres admin (rol que ve todos los talleres) activo con segundo factor?
create or replace function ws_is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active and a.role = 'admin')
     and ws_strong();
$$;

-- ¿Eres el facilitador dueño de esta sesión (con segundo factor)?
create or replace function ws_is_owner(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select ws_is_admin()
     and exists (select 1 from ws_sessions s where s.id = p_session and s.owner_id = auth.uid());
$$;

-- v1.5 · ¿Puedes VER el panel de esta sesión? Su dueño, o un admin (solo lectura)
create or replace function ws_can_view(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select ws_is_owner(p_session)
      or (ws_is_superadmin() and exists (select 1 from ws_sessions s where s.id = p_session));
$$;

-- Tu registro de participante en esta sesión (o null)
create or replace function ws_my_participant(p_session uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select p.id from ws_participants p
  where p.session_id = p_session and p.user_id = auth.uid();
$$;

create or replace function ws_is_member(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select ws_my_participant(p_session) is not null;
$$;

create or replace function ws_session_phase(p_session uuid) returns text
language sql stable security definer set search_path = public as $$
  select s.phase from ws_sessions s where s.id = p_session;
$$;

-- El participante busca la sesión por su código (solo datos públicos del taller)
drop function if exists ws_join_lookup(text);
create function ws_join_lookup(p_code text)
returns table (id uuid, code text, name text, facilitator text, phase text,
               votes_per_user int, areas jsonb, stages jsonb,
               q_checkin text, q_expect text, q_pain text, brand text,
               roles jsonb, tools jsonb, quickwins jsonb, q_idea text,
               idea_votes int, idea_top int, tasks jsonb)
language sql stable security definer set search_path = public as $$
  select s.id, s.code, s.name, s.facilitator, s.phase, s.votes_per_user, s.areas, s.stages,
         s.q_checkin, s.q_expect, s.q_pain, s.brand,
         s.roles, s.tools, s.quickwins, s.q_idea, s.idea_votes, s.idea_top, s.tasks
  from ws_sessions s
  where auth.uid() is not null and s.code = upper(trim(p_code));
$$;

-- v1.4 · Avance de la fase en curso: cuántos van y cuántos ya terminaron.
-- Solo números (nunca nombres): lo ven los miembros del taller y el facilitador.
create or replace function ws_phase_progress(p_session uuid)
returns table (phase text, total int, listos int)
language sql stable security definer set search_path = public as $$
  select s.phase,
         (select count(*)::int from ws_participants p where p.session_id = s.id),
         (select count(*)::int from ws_participants p where p.session_id = s.id and p.done_phases ? s.phase)
  from ws_sessions s
  where s.id = p_session and (ws_can_view(p_session) or ws_is_member(p_session));
$$;

-- Totales de votos por tarjeta: el facilitador siempre; participantes cuando
-- la votación ya terminó (Quick wins, Ideas, Resultados, Cierre)
create or replace function ws_card_totals(p_session uuid)
returns table (card_id uuid, points bigint)
language sql stable security definer set search_path = public as $$
  select v.card_id, sum(v.points)::bigint
  from ws_votes v
  where v.session_id = p_session
    and ( ws_can_view(p_session)
          or (ws_is_member(p_session) and ws_session_phase(p_session) in ('quickwins','ideas','results','closed')) )
  group by v.card_id;
$$;

-- Primer facilitador: si aún no hay ninguno, la primera cuenta con
-- correo (no anónima) que entra con segundo factor queda como facilitador.
-- Después, nadie más puede auto-asignarse.
create or replace function ws_claim_admin() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
     or coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    return false;
  end if;
  if exists (select 1 from ws_admins where user_id = auth.uid()) then
    return exists (select 1 from ws_admins where user_id = auth.uid() and active);
  end if;
  lock table ws_admins in exclusive mode;
  if not exists (select 1 from ws_admins) then
    insert into ws_admins (user_id, email, role) values (auth.uid(), auth.jwt() ->> 'email', 'admin');
    return true;
  end if;
  return false;
end $$;

-- v1.5 · Tu cuenta: rol, nombre y si está activa (vacío si no tienes acceso o te falta el segundo factor)
drop function if exists ws_me();
create function ws_me() returns table (role text, name text, email text, active boolean, avatar text)
language sql stable security definer set search_path = public as $$
  select a.role, a.name, a.email, a.active, a.avatar from ws_admins a
  where a.user_id = auth.uid() and ws_strong();
$$;

-- v1.5 · Huella del código de invitación (no se guarda el código en claro)
create or replace function ws_invite_hash(p_code text) returns text
language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(regexp_replace(upper(coalesce(p_code,'')), '[^A-Z0-9]', '', 'g'), 'UTF8')), 'hex');
$$;

-- v1.5 · El admin crea una invitación. Devuelve el código UNA sola vez.
drop function if exists ws_create_invite(text, text, text);
create function ws_create_invite(p_email text, p_name text default null, p_role text default 'facilitator')
returns table (id uuid, code text, email text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(coalesce(p_email,''))); v_code text; v_id uuid; v_exp timestamptz;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede invitar facilitadores'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Escribe un correo válido'; end if;
  if coalesce(p_role,'') not in ('admin','facilitator') then raise exception 'Rol no válido'; end if;
  if exists (select 1 from ws_admins a where lower(a.email) = v_email and a.active) then
    raise exception 'Ese correo ya tiene acceso al panel';
  end if;
  -- una invitación vigente por correo: la nueva reemplaza a las anteriores
  update ws_invites i set revoked_at = now()
  where i.email = v_email and i.used_at is null and i.revoked_at is null;
  v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12) || substr(replace(gen_random_uuid()::text,'-',''),1,4));
  insert into ws_invites (code_hash, email, name, role, created_by)
  values (ws_invite_hash(v_code), v_email, nullif(trim(coalesce(p_name,'')),''), p_role, auth.uid())
  returning ws_invites.id, ws_invites.expires_at into v_id, v_exp;
  return query select v_id, substr(v_code,1,4)||'-'||substr(v_code,5,4)||'-'||substr(v_code,9,4)||'-'||substr(v_code,13,4), v_email, v_exp;
end $$;

-- v1.5 · Datos públicos de una invitación vigente (para la pantalla «Crea tu cuenta»).
-- Solo responde con el código exacto (16 caracteres al azar): no permite adivinar.
drop function if exists ws_invite_peek(text);
create function ws_invite_peek(p_code text)
returns table (email text, name text, role text, expires_at timestamptz)
language sql stable security definer set search_path = public as $$
  select i.email, i.name, i.role, i.expires_at from ws_invites i
  where i.code_hash = ws_invite_hash(p_code)
    and i.used_at is null and i.revoked_at is null and i.expires_at > now();
$$;

-- v1.5 · El invitado canjea su invitación (ya con contraseña y segundo factor)
drop function if exists ws_redeem_invite(text);
create function ws_redeem_invite(p_code text) returns text
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
  if v.id is null or v.revoked_at is not null or v.expires_at <= now() then
    raise exception 'La invitación no es válida o venció. Pide una nueva al admin.';
  end if;
  -- v1.16 · Una invitación ya canjeada nunca vuelve a tocar la cuenta (antes reactivaba cuentas desactivadas
  -- y restauraba el rol). Si quien la canjeó la repite y sigue activo, se responde igual, sin cambios.
  if v.used_at is not null then
    if v.used_by = auth.uid() and exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active) then
      return (select a.role from ws_admins a where a.user_id = auth.uid());
    end if;
    raise exception 'Esta invitación ya se usó. Pide una nueva al admin.';
  end if;
  if v.email <> v_mail then
    raise exception 'Esta invitación es para %. Entra con ese correo.', v.email;
  end if;
  insert into ws_admins (user_id, email, role, name, active)
  values (auth.uid(), v_mail, v.role, v.name, true)
  on conflict (user_id) do update
    set role = excluded.role, active = true, email = excluded.email,
        name = coalesce(ws_admins.name, excluded.name);
  update ws_invites set used_by = auth.uid(), used_at = coalesce(used_at, now()) where id = v.id;
  return v.role;
end $$;

-- v1.5 · El admin cancela una invitación pendiente
create or replace function ws_revoke_invite(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede cancelar invitaciones'; end if;
  update ws_invites set revoked_at = now() where id = p_id and used_at is null and revoked_at is null;
end $$;

-- v1.5 · Foto de perfil: cada quien cambia o quita SOLO la suya (imagen chica, ya recortada en el navegador)
create or replace function ws_set_my_avatar(p_avatar text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_admin() then raise exception 'Inicia sesión con tu segundo factor para cambiar tu foto'; end if;
  update ws_admins set avatar = nullif(p_avatar, '') where user_id = auth.uid();
end $$;

-- v1.5 · El admin activa/desactiva una cuenta o cambia su rol (nunca la suya)
create or replace function ws_set_staff(p_user uuid, p_active boolean default null, p_role text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede cambiar cuentas'; end if;
  if p_user = auth.uid() then raise exception 'No puedes cambiar tu propia cuenta'; end if;
  if p_role is not null and p_role not in ('admin','facilitator') then raise exception 'Rol no válido'; end if;
  update ws_admins set active = coalesce(p_active, active), role = coalesce(p_role, role) where user_id = p_user;
  if not found then raise exception 'Esa cuenta no existe'; end if;
  -- v1.16 · Al desactivar a alguien se cancelan sus invitaciones pendientes
  if p_active is false then
    update ws_invites set revoked_at = now()
     where lower(email) = (select lower(email) from ws_admins where user_id = p_user)
       and used_at is null and revoked_at is null;
  end if;
end $$;

-- Tope de votos por persona, validado en el servidor
create or replace function ws_votes_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_cap int; v_used int;
begin
  if not exists (select 1 from ws_cards c where c.id = new.card_id and c.session_id = new.session_id) then
    raise exception 'La tarjeta no pertenece a esta sesión';
  end if;
  select s.votes_per_user into v_cap from ws_sessions s where s.id = new.session_id;
  select coalesce(sum(v.points), 0) into v_used
  from ws_votes v
  where v.session_id = new.session_id
    and v.participant_id = new.participant_id
    and v.card_id <> new.card_id;
  if v_used + new.points > v_cap then
    raise exception 'Ya usaste todos tus votos (% de %)', v_used, v_cap;
  end if;
  return new;
end $$;

drop trigger if exists ws_votes_guard on ws_votes;
create trigger ws_votes_guard before insert or update on ws_votes
  for each row execute function ws_votes_guard();

-- v1.2 · Totales de quick wins: el facilitador siempre; participantes en Resultados
create or replace function ws_qw_totals(p_session uuid)
returns table (qw_id text, mucho bigint, algo bigint, poco bigint, no_aplica bigint)
language sql stable security definer set search_path = public as $$
  select r.qw_id,
         count(*) filter (where r.score = 3),
         count(*) filter (where r.score = 2),
         count(*) filter (where r.score = 1),
         count(*) filter (where r.score = 0)
  from ws_qw_ratings r
  where r.session_id = p_session
    and ( ws_can_view(p_session)
          or (ws_is_member(p_session) and ws_session_phase(p_session) in ('results','closed')) )
  group by r.qw_id;
$$;

-- v1.2 · Apoyos por idea: el facilitador siempre; participantes en Resultados
create or replace function ws_idea_totals(p_session uuid)
returns table (idea_id uuid, votes bigint)
language sql stable security definer set search_path = public as $$
  select v.idea_id, count(*)::bigint
  from ws_idea_votes v
  where v.session_id = p_session
    and ( ws_can_view(p_session)
          or (ws_is_member(p_session) and ws_session_phase(p_session) in ('results','closed')) )
  group by v.idea_id;
$$;

-- v1.2 · Solo se califican quick wins que existen en la sesión
create or replace function ws_qw_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from ws_sessions s, jsonb_array_elements(s.quickwins) e
                 where s.id = new.session_id and e->>'id' = new.qw_id) then
    raise exception 'Ese quick win no existe en esta sesión';
  end if;
  return new;
end $$;

drop trigger if exists ws_qw_guard on ws_qw_ratings;
create trigger ws_qw_guard before insert or update on ws_qw_ratings
  for each row execute function ws_qw_guard();

-- v1.2 · Una idea responde a un dolor de la misma sesión
create or replace function ws_ideas_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'idea' then
    if new.card_id is null or not exists
       (select 1 from ws_cards c where c.id = new.card_id and c.session_id = new.session_id) then
      raise exception 'La idea debe responder a un dolor de esta sesión';
    end if;
  else
    new.card_id := null;
  end if;
  return new;
end $$;

drop trigger if exists ws_ideas_guard on ws_ideas;
create trigger ws_ideas_guard before insert or update on ws_ideas
  for each row execute function ws_ideas_guard();

-- v1.2 · Apoyos: tope por persona y no a tu propia idea
create or replace function ws_idea_votes_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_cap int; v_used int; v_author uuid; v_kind text;
begin
  select i.participant_id, i.kind into v_author, v_kind
  from ws_ideas i where i.id = new.idea_id and i.session_id = new.session_id;
  if v_author is null or v_kind <> 'idea' then
    raise exception 'La idea no pertenece a esta sesión';
  end if;
  if v_author = new.participant_id then
    raise exception 'No puedes apoyar tu propia idea';
  end if;
  select s.idea_votes into v_cap from ws_sessions s where s.id = new.session_id;
  select count(*) into v_used from ws_idea_votes v
  where v.session_id = new.session_id and v.participant_id = new.participant_id and v.idea_id <> new.idea_id;
  if v_used + 1 > v_cap then
    raise exception 'Ya usaste todos tus apoyos (% de %)', v_used, v_cap;
  end if;
  return new;
end $$;

drop trigger if exists ws_idea_votes_guard on ws_idea_votes;
create trigger ws_idea_votes_guard before insert or update on ws_idea_votes
  for each row execute function ws_idea_votes_guard();

-- ------------------------------------------------------------
-- 3) Reglas de acceso (RLS)
-- ------------------------------------------------------------
alter table ws_admins       enable row level security;
alter table ws_sessions     enable row level security;
alter table ws_participants enable row level security;
alter table ws_cards        enable row level security;
alter table ws_votes        enable row level security;
alter table ws_qw_ratings   enable row level security;
alter table ws_ideas        enable row level security;
alter table ws_idea_votes   enable row level security;
alter table ws_invites      enable row level security;

-- Borra cualquier regla previa de Colmena (incluidas las abiertas de la v1)
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename like 'ws\_%' loop
    execute format('drop policy %I on %I', r.policyname, r.tablename);
  end loop;
end $$;

-- Cuentas del panel: cada quien se ve a sí mismo; el admin ve a todo el equipo
create policy ws_admins_self on ws_admins for select to authenticated
  using (user_id = auth.uid() or ws_is_superadmin());

-- v1.5 · Invitaciones: solo el admin las ve (se crean y cancelan con funciones)
create policy ws_invites_select on ws_invites for select to authenticated
  using (ws_is_superadmin());

-- Sesiones
create policy ws_sessions_select on ws_sessions for select to authenticated
  using ((owner_id = auth.uid() and ws_is_admin()) or ws_is_superadmin() or ws_is_member(id));
create policy ws_sessions_insert on ws_sessions for insert to authenticated
  with check (owner_id = auth.uid() and ws_is_admin());
create policy ws_sessions_update on ws_sessions for update to authenticated
  using (owner_id = auth.uid() and ws_is_admin())
  with check (owner_id = auth.uid() and ws_is_admin());
create policy ws_sessions_delete on ws_sessions for delete to authenticated
  using (owner_id = auth.uid() and ws_is_admin());

-- Participantes: cada quien ve y edita solo su registro; el facilitador ve a todos
create policy ws_participants_select on ws_participants for select to authenticated
  using (user_id = auth.uid() or ws_can_view(session_id));
create policy ws_participants_insert on ws_participants for insert to authenticated
  with check (user_id = auth.uid() and coalesce(ws_session_phase(session_id), 'closed') <> 'closed');
create policy ws_participants_update on ws_participants for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and coalesce(ws_session_phase(session_id), 'closed') <> 'closed');
create policy ws_participants_delete on ws_participants for delete to authenticated
  using (ws_is_owner(session_id));

-- Tarjetas: se ven dentro de la sesión (sin autor); se publican solo en fase Dolores
create policy ws_cards_select on ws_cards for select to authenticated
  using (ws_is_member(session_id) or ws_can_view(session_id));
create policy ws_cards_insert on ws_cards for insert to authenticated
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'pains');
create policy ws_cards_delete on ws_cards for delete to authenticated
  using ( (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'pains')
          or ws_is_owner(session_id) );

-- Votos: cada quien ve y cambia solo los suyos, solo en fase Votación
create policy ws_votes_select on ws_votes for select to authenticated
  using (participant_id = ws_my_participant(session_id) or ws_can_view(session_id));
create policy ws_votes_insert on ws_votes for insert to authenticated
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'votes');
create policy ws_votes_update on ws_votes for update to authenticated
  using (participant_id = ws_my_participant(session_id))
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'votes');
create policy ws_votes_delete on ws_votes for delete to authenticated
  using (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'votes');

-- v1.2 · Quick wins: cada quien califica y ve solo lo suyo, solo en fase Quick wins
create policy ws_qw_ratings_select on ws_qw_ratings for select to authenticated
  using (participant_id = ws_my_participant(session_id) or ws_can_view(session_id));
create policy ws_qw_ratings_insert on ws_qw_ratings for insert to authenticated
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'quickwins');
create policy ws_qw_ratings_update on ws_qw_ratings for update to authenticated
  using (participant_id = ws_my_participant(session_id))
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'quickwins');
create policy ws_qw_ratings_delete on ws_qw_ratings for delete to authenticated
  using (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'quickwins');

-- v1.2 · Ideas: las propuestas de quick win solo las ven su autor y el facilitador;
--        las ideas se ven dentro de la sesión (sin autor) desde la fase Ideas
create policy ws_ideas_select on ws_ideas for select to authenticated
  using ( participant_id = ws_my_participant(session_id)
          or ws_can_view(session_id)
          or (kind = 'idea' and ws_is_member(session_id)
              and ws_session_phase(session_id) in ('ideas','results','closed')) );
create policy ws_ideas_insert on ws_ideas for insert to authenticated
  with check ( participant_id = ws_my_participant(session_id)
               and ( (kind = 'qw'   and ws_session_phase(session_id) = 'quickwins')
                  or (kind = 'idea' and ws_session_phase(session_id) = 'ideas') ) );
create policy ws_ideas_delete on ws_ideas for delete to authenticated
  using ( ( participant_id = ws_my_participant(session_id)
            and ( (kind = 'qw'   and ws_session_phase(session_id) = 'quickwins')
               or (kind = 'idea' and ws_session_phase(session_id) = 'ideas') ) )
          or ws_is_owner(session_id) );

-- v1.2 · Apoyos: cada quien ve y cambia solo los suyos, solo en fase Ideas
create policy ws_idea_votes_select on ws_idea_votes for select to authenticated
  using (participant_id = ws_my_participant(session_id) or ws_can_view(session_id));
create policy ws_idea_votes_insert on ws_idea_votes for insert to authenticated
  with check (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'ideas');
create policy ws_idea_votes_delete on ws_idea_votes for delete to authenticated
  using (participant_id = ws_my_participant(session_id) and ws_session_phase(session_id) = 'ideas');

-- ------------------------------------------------------------
-- 4) Permisos: la llave pública sola (rol anon) no accede a nada
-- ------------------------------------------------------------
revoke all on ws_admins, ws_sessions, ws_participants, ws_cards, ws_votes,
  ws_qw_ratings, ws_ideas, ws_idea_votes, ws_invites from anon;
revoke insert, update, delete on ws_admins, ws_invites from authenticated;
grant usage on schema public to authenticated;
grant select on ws_admins, ws_invites to authenticated;
grant select, insert, update, delete on ws_sessions, ws_participants, ws_cards, ws_votes,
  ws_qw_ratings, ws_ideas, ws_idea_votes to authenticated;

revoke execute on function ws_is_admin(), ws_is_owner(uuid), ws_my_participant(uuid), ws_is_member(uuid),
  ws_session_phase(uuid), ws_join_lookup(text), ws_card_totals(uuid), ws_claim_admin(),
  ws_qw_totals(uuid), ws_idea_totals(uuid), ws_phase_progress(uuid),
  ws_is_superadmin(), ws_can_view(uuid), ws_me(), ws_invite_hash(text), ws_create_invite(text,text,text),
  ws_invite_peek(text), ws_redeem_invite(text), ws_revoke_invite(uuid), ws_set_staff(uuid,boolean,text),
  ws_set_my_avatar(text)
  from public, anon;
grant execute on function ws_is_admin(), ws_is_owner(uuid), ws_my_participant(uuid), ws_is_member(uuid),
  ws_session_phase(uuid), ws_join_lookup(text), ws_card_totals(uuid), ws_claim_admin(),
  ws_qw_totals(uuid), ws_idea_totals(uuid), ws_phase_progress(uuid),
  ws_is_superadmin(), ws_can_view(uuid), ws_me(), ws_create_invite(text,text,text),
  ws_invite_peek(text), ws_redeem_invite(text), ws_revoke_invite(uuid), ws_set_staff(uuid,boolean,text),
  ws_set_my_avatar(text)
  to authenticated;
-- La pantalla «Crea tu cuenta» consulta la invitación antes de iniciar sesión
grant execute on function ws_invite_peek(text) to anon;

-- ------------------------------------------------------------
-- 4b) v1.6 · Centro de notificaciones
--   · Los avisos los crea la BASE (disparadores y una revisión diaria):
--     nadie puede inventarlos desde la página y llegan aunque la app esté cerrada.
--   · Cada quien solo lee y marca como leídos los suyos.
--   · Los importantes también van por correo: quedan en una «bandeja de salida»
--     (email_status = 'pending') que la función send-notifications envía cada 5 min.
-- ------------------------------------------------------------
create table if not exists ws_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (char_length(type) <= 40),
  title text not null check (char_length(title) <= 200),
  body text check (char_length(body) <= 600),
  action jsonb not null default '{}' check (jsonb_typeof(action) = 'object'),
  data jsonb not null default '{}' check (jsonb_typeof(data) = 'object'),
  read_at timestamptz,
  email_status text not null default 'none'
    check (email_status in ('none','pending','sending','sent','failed')),
  email_attempts int not null default 0,
  email_error text,
  email_claimed_at timestamptz,
  dedupe_key text unique,
  created_at timestamptz not null default now()
);
create index if not exists ws_notifications_user on ws_notifications(user_id, created_at desc);
create index if not exists ws_notifications_outbox on ws_notifications(email_status) where email_status in ('pending','sending');

-- Preferencias de correo por tipo de aviso: {"invite_accepted": false, …} (vacío = todo encendido)
alter table ws_admins add column if not exists email_prefs jsonb not null default '{}'
  check (jsonb_typeof(email_prefs) = 'object');
-- Fecha de cierre del taller (para el recordatorio de los 30 días)
alter table ws_sessions add column if not exists closed_at timestamptz;
update ws_sessions set closed_at = now() where phase = 'closed' and closed_at is null;

-- Configuración del proyecto (URL de las funciones, para la tarea programada de correos)
create table if not exists ws_config (key text primary key, value text);
alter table ws_config enable row level security;
revoke all on ws_config from anon, authenticated;

-- Crea un aviso (uso interno: solo lo llaman los disparadores y la revisión diaria)
create or replace function ws_notify(p_user uuid, p_type text, p_title text, p_body text,
                                     p_action jsonb default '{}', p_data jsonb default '{}',
                                     p_email boolean default false, p_dedupe text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_prefs jsonb;
begin
  if p_user is null then return; end if;
  select a.email_prefs into v_prefs from ws_admins a where a.user_id = p_user and a.active;
  if not found then return; end if;                        -- solo cuentas activas del panel
  insert into ws_notifications (user_id, type, title, body, action, data, email_status, dedupe_key)
  values (p_user, p_type, left(p_title, 200), left(p_body, 600), coalesce(p_action,'{}'), coalesce(p_data,'{}'),
          case when p_email and coalesce((v_prefs ->> p_type)::boolean, true) then 'pending' else 'none' end,
          p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

-- Nombre visible de una cuenta
create or replace function ws_staff_label(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(a.name), ''), a.email, 'Alguien') from ws_admins a where a.user_id = p_user;
$$;

-- Evento: invitación aceptada → avisa a quien invitó (app + correo)
create or replace function ws_ev_invite_used() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_who text; v_role text;
begin
  if old.used_at is null and new.used_at is not null and new.created_by is not null
     and new.created_by is distinct from new.used_by then
    v_who  := coalesce(ws_staff_label(new.used_by), new.name, new.email);
    v_role := case new.role when 'admin' then 'admin' else 'facilitador' end;
    perform ws_notify(new.created_by, 'invite_accepted',
      v_who || ' aceptó tu invitación',
      'Ya creó su cuenta y entra a Colmena como ' || v_role || '.',
      jsonb_build_object('label','Ver equipo','view','team'),
      jsonb_build_object('email', new.email), true, 'invite_accepted:' || new.id);
  end if;
  return new;
end $$;
drop trigger if exists ws_ev_invite_used on ws_invites;
create trigger ws_ev_invite_used after update of used_at on ws_invites
  for each row execute function ws_ev_invite_used();

-- Evento: cuenta nueva → bienvenida (solo app)
create or replace function ws_ev_staff_new() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform ws_notify(new.user_id, 'welcome', 'Bienvenido a Colmena',
    'Cuéntale a la IA tu proceso, revisa la propuesta y proyecta el QR: la sala entra desde su celular.',
    jsonb_build_object('label','Crear mi primer taller','view','create'), '{}', false, 'welcome:' || new.user_id);
  return new;
end $$;
drop trigger if exists ws_ev_staff_new on ws_admins;
create trigger ws_ev_staff_new after insert on ws_admins
  for each row execute function ws_ev_staff_new();

-- Evento: cambio de rol o reactivación → avisa a la persona (app + correo)
create or replace function ws_ev_staff_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.active and old.role is distinct from new.role then
    perform ws_notify(new.user_id, 'role_changed',
      case new.role when 'admin' then 'Ahora eres admin en Colmena' else 'Ahora eres facilitador en Colmena' end,
      case new.role when 'admin'
        then 'Además de tus talleres, ves y exportas los de todo el equipo, e invitas o desactivas cuentas.'
        else 'Creas y operas tus propios talleres.' end,
      jsonb_build_object('label','Abrir Colmena','view','mine'), '{}', true, null);
  end if;
  if new.active and not old.active then
    perform ws_notify(new.user_id, 'reactivated', 'Tu acceso a Colmena está activo de nuevo',
      'Ya puedes entrar al panel y ver tus talleres.',
      jsonb_build_object('label','Abrir Colmena','view','mine'), '{}', true, null);
  end if;
  return new;
end $$;
drop trigger if exists ws_ev_staff_change on ws_admins;
create trigger ws_ev_staff_change after update of role, active on ws_admins
  for each row execute function ws_ev_staff_change();

-- Evento: un facilitador crea o cierra un taller → avisa a los admins (solo app)
create or replace function ws_ev_session() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_who text; v_n int; r record;
begin
  v_who := coalesce(ws_staff_label(new.owner_id), 'Alguien');
  if tg_op = 'INSERT' then
    for r in select a.user_id from ws_admins a where a.role = 'admin' and a.active and a.user_id <> new.owner_id loop
      perform ws_notify(r.user_id, 'session_created', v_who || ' creó el taller «' || new.name || '»',
        'Código ' || new.code || '. Puedes verlo en solo lectura.',
        jsonb_build_object('label','Ver taller','code',new.code), jsonb_build_object('session',new.id), false,
        'session_created:' || new.id || ':' || r.user_id);
    end loop;
  elsif new.phase = 'closed' and old.phase is distinct from 'closed' then
    select count(*) into v_n from ws_participants p where p.session_id = new.id;
    for r in select a.user_id from ws_admins a where a.role = 'admin' and a.active and a.user_id <> new.owner_id loop
      perform ws_notify(r.user_id, 'session_closed', v_who || ' cerró el taller «' || new.name || '»',
        v_n || case v_n when 1 then ' participante' else ' participantes' end || '. Los resultados ya están listos para ver y exportar.',
        jsonb_build_object('label','Ver resultados','code',new.code), jsonb_build_object('session',new.id), false,
        'session_closed:' || new.id || ':' || r.user_id);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists ws_ev_session on ws_sessions;
create trigger ws_ev_session after insert or update of phase on ws_sessions
  for each row execute function ws_ev_session();

-- Marca la fecha de cierre (y la limpia si se reabre)
create or replace function ws_session_closed_at() returns trigger
language plpgsql as $$
begin
  if new.phase <> 'closed' then
    new.closed_at := null;
  elsif tg_op = 'INSERT' then
    new.closed_at := now();
  elsif old.phase is distinct from 'closed' then
    new.closed_at := now();
  end if;
  return new;
end $$;
drop trigger if exists ws_session_closed_at on ws_sessions;
create trigger ws_session_closed_at before insert or update of phase on ws_sessions
  for each row execute function ws_session_closed_at();

-- Evento: todos terminaron la actividad en curso → avisa al facilitador (solo app, una vez por fase)
create or replace function ws_ev_phase_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare s ws_sessions; v_n int; v_t text;
begin
  select * into s from ws_sessions where id = new.session_id;
  if s.id is null or s.phase not in ('checkin','pains','votes','quickwins','ideas') then return new; end if;
  if not (new.done_phases ? s.phase) or coalesce(old.done_phases ? s.phase, false) then return new; end if;
  select count(*) into v_n from ws_participants p where p.session_id = s.id;
  if v_n = 0 or exists (select 1 from ws_participants p where p.session_id = s.id and not (p.done_phases ? s.phase)) then
    return new;
  end if;
  v_t := case s.phase when 'checkin' then 'Check-in' when 'pains' then 'Dolores' when 'votes' then 'Votación'
                      when 'quickwins' then 'Validación' else 'Ideas' end;
  perform ws_notify(s.owner_id, 'phase_done', 'Todos terminaron ' || v_t || ' en «' || s.name || '»',
    v_n || case v_n when 1 then ' participante listo' else ' participantes listos' end || '. Puedes abrir la siguiente actividad.',
    jsonb_build_object('label','Abrir taller','code',s.code), jsonb_build_object('session',s.id,'phase',s.phase), false,
    'phase_done:' || s.id || ':' || s.phase);
  return new;
end $$;
drop trigger if exists ws_ev_phase_done on ws_participants;
create trigger ws_ev_phase_done after update of done_phases on ws_participants
  for each row execute function ws_ev_phase_done();

-- Revisión diaria: invitaciones por vencer / vencidas, talleres con 30 días cerrados y limpieza (90 días)
create or replace function ws_notifications_daily() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select * from ws_invites i where i.used_at is null and i.revoked_at is null and i.created_by is not null
           and i.expires_at > now() and i.expires_at <= now() + interval '24 hours' loop
    perform ws_notify(r.created_by, 'invite_expiring', 'La invitación de ' || coalesce(nullif(r.name,''), r.email) || ' vence mañana',
      'Aún no crea su cuenta. Si hace falta, reenvíale una invitación nueva.',
      jsonb_build_object('label','Reenviar','view','team','email',r.email), jsonb_build_object('email',r.email), false,
      'invite_expiring:' || r.id);
  end loop;
  for r in select * from ws_invites i where i.used_at is null and i.revoked_at is null and i.created_by is not null
           and i.expires_at <= now() and i.expires_at > now() - interval '3 days' loop
    perform ws_notify(r.created_by, 'invite_expired', 'La invitación de ' || coalesce(nullif(r.name,''), r.email) || ' venció sin usarse',
      'Si todavía necesita acceso, invítala de nuevo.',
      jsonb_build_object('label','Invitar de nuevo','view','team','email',r.email), jsonb_build_object('email',r.email), false,
      'invite_expired:' || r.id);
  end loop;
  for r in select * from ws_sessions s where s.phase = 'closed' and s.closed_at <= now() - interval '30 days' loop
    perform ws_notify(r.owner_id, 'retention', '«' || r.name || '» lleva 30 días cerrado',
      'Si ya no lo necesitas, exporta los resultados y bórralo para no guardar datos del cliente más tiempo del necesario.',
      jsonb_build_object('label','Exportar o borrar','code',r.code), jsonb_build_object('session',r.id), true,
      'retention:' || r.id);
  end loop;
  delete from ws_notifications where created_at < now() - interval '90 days';
end $$;

-- La campana: marcar como leído (solo los tuyos)
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

-- Tus preferencias de correo (solo tipos conocidos, true/false)
create or replace function ws_set_my_email_prefs(p_prefs jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; clean jsonb := '{}';
begin
  if not ws_is_admin() then raise exception 'Inicia sesión con tu segundo factor'; end if;
  for k, v in select * from jsonb_each(coalesce(p_prefs,'{}')) loop
    if k in ('invite_accepted','role_changed','reactivated','retention') and jsonb_typeof(v) = 'boolean' then
      clean := clean || jsonb_build_object(k, v);
    end if;
  end loop;
  update ws_admins set email_prefs = clean where user_id = auth.uid();
end $$;
create or replace function ws_my_email_prefs() returns jsonb
language sql stable security definer set search_path = public as $$
  select a.email_prefs from ws_admins a where a.user_id = auth.uid() and ws_strong();
$$;

-- Bandeja de salida (solo la función send-notifications, con la llave de servidor)
drop function if exists ws_claim_email_batch(int);
create function ws_claim_email_batch(p_limit int default 20)
returns table (id uuid, email text, name text, type text, title text, body text, action jsonb)
language plpgsql security definer set search_path = public as $$
begin
  -- rescata envíos que se quedaron a medias (más de 15 min en «sending»)
  update ws_notifications n set email_status = 'pending'
  where n.email_status = 'sending' and n.email_claimed_at < now() - interval '15 minutes';
  return query
  with c as (
    select n.id from ws_notifications n
    where n.email_status = 'pending' order by n.created_at limit greatest(1, least(p_limit, 50))
    for update skip locked
  ), u as (
    update ws_notifications n set email_status = 'sending', email_attempts = n.email_attempts + 1, email_claimed_at = now()
    from c where n.id = c.id returning n.*
  )
  select u.id, a.email, a.name, u.type, u.title, u.body, u.action
  from u join ws_admins a on a.user_id = u.user_id;
end $$;
create or replace function ws_finish_email(p_id uuid, p_ok boolean, p_error text default null) returns void
language sql security definer set search_path = public as $$
  update ws_notifications set
    email_status = case when p_ok then 'sent' when email_attempts >= 3 then 'failed' else 'pending' end,
    email_error = case when p_ok then null else left(p_error, 300) end
  where id = p_id;
$$;

-- Reglas de acceso
alter table ws_notifications enable row level security;
drop policy if exists ws_notifications_own on ws_notifications;
create policy ws_notifications_own on ws_notifications for select to authenticated
  using (user_id = auth.uid() and ws_strong());
revoke all on ws_notifications from anon, authenticated;
grant select on ws_notifications to authenticated;

revoke execute on function ws_notify(uuid,text,text,text,jsonb,jsonb,boolean,text), ws_staff_label(uuid),
  ws_notifications_daily(), ws_claim_email_batch(int), ws_finish_email(uuid,boolean,text),
  ws_mark_read(uuid[]), ws_mark_all_read(), ws_set_my_email_prefs(jsonb), ws_my_email_prefs()
  from public, anon, authenticated;
grant execute on function ws_mark_read(uuid[]), ws_mark_all_read(), ws_set_my_email_prefs(jsonb), ws_my_email_prefs()
  to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function ws_claim_email_batch(int), ws_finish_email(uuid,boolean,text), ws_notifications_daily() to service_role;
  end if;
end $$;

-- Tareas programadas (solo en Supabase, donde existen pg_cron y pg_net):
--   · todos los días a las 9:00 (hora de CDMX) → ws_notifications_daily()
--   · cada 5 minutos, si hay correos pendientes → llama a la función send-notifications
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    execute 'create extension if not exists pg_cron';
    execute 'create extension if not exists pg_net';
    perform cron.unschedule(jobid) from cron.job where jobname in ('colmena-daily','colmena-mail');
    perform cron.schedule('colmena-daily', '0 15 * * *', 'select public.ws_notifications_daily()');
    perform cron.schedule('colmena-mail', '*/5 * * * *', $cron$
      select net.http_post(
        url := (select value from public.ws_config where key = 'functions_url') || '/send-notifications',
        headers := '{"Content-Type":"application/json"}'::jsonb, body := '{}'::jsonb)
      where exists (select 1 from public.ws_notifications where email_status = 'pending')
        and exists (select 1 from public.ws_config where key = 'functions_url' and value is not null)
    $cron$);
  end if;
end $$;

-- ------------------------------------------------------------
-- 4c) v1.7 · Inicio, perfil editable
-- ------------------------------------------------------------
-- Puesto en el perfil
alter table ws_admins add column if not exists title text;
alter table ws_admins drop constraint if exists ws_admins_title_check;
alter table ws_admins add constraint ws_admins_title_check check (char_length(title) <= 120);

drop function if exists ws_me();
create function ws_me() returns table (role text, name text, email text, active boolean, avatar text, title text)
language sql stable security definer set search_path = public as $$
  select a.role, a.name, a.email, a.active, a.avatar, a.title from ws_admins a
  where a.user_id = auth.uid() and ws_strong();
$$;

-- Cada quien edita su nombre y puesto
create or replace function ws_set_my_profile(p_name text, p_title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_admin() then raise exception 'Inicia sesión con tu segundo factor'; end if;
  if char_length(trim(coalesce(p_name,''))) < 2 then raise exception 'Escribe tu nombre'; end if;
  update ws_admins set name = left(trim(p_name), 120), title = nullif(left(trim(coalesce(p_title,'')), 120), '')
  where user_id = auth.uid();
end $$;

-- Datos del Inicio: mis talleres (o todos, si soy admin) con conteos, e invitaciones pendientes (admin)
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
      select jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'name', i.name, 'expires_at', i.expires_at) order by i.expires_at)
      from ws_invites i
      where ws_is_superadmin() and i.used_at is null and i.revoked_at is null), '[]'::jsonb)
  );
$$;

revoke execute on function ws_me(), ws_set_my_profile(text,text), ws_dashboard() from public, anon;
grant execute on function ws_me(), ws_set_my_profile(text,text), ws_dashboard() to authenticated;


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
revoke all on function ws_strong(), ws_passkey_status(), ws_untrust_passkeys() from public, anon;
grant execute on function ws_strong(), ws_passkey_status(), ws_untrust_passkeys() to authenticated;

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
  if v.id is null or v.revoked_at is not null or v.expires_at <= now() then
    raise exception 'La invitación no es válida o venció. Pide una nueva al admin.';
  end if;
  -- v1.16 · Una invitación ya canjeada nunca vuelve a tocar la cuenta (antes reactivaba cuentas desactivadas
  -- y restauraba el rol). Si quien la canjeó la repite y sigue activo, se responde igual, sin cambios.
  if v.used_at is not null then
    if v.used_by = auth.uid() and exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active) then
      return (select a.role from ws_admins a where a.user_id = auth.uid());
    end if;
    raise exception 'Esta invitación ya se usó. Pide una nueva al admin.';
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
  if v.id is null or v.revoked_at is not null or v.expires_at <= now() then
    raise exception 'La invitación no es válida o venció. Pide una nueva.';
  end if;
  -- v1.16 · Una invitación ya canjeada nunca vuelve a tocar la cuenta
  if v.used_at is not null then
    if v.used_by = auth.uid() and exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active) then
      return (select a.role from ws_admins a where a.user_id = auth.uid());
    end if;
    raise exception 'Esta invitación ya se usó. Pide una nueva al admin.';
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

-- ------------------------------------------------------------
-- 4g) v1.15 · Pulso del participante (talleres grandes, hasta ~200 personas en el plan gratis)
--     El celular ya no abre conexión en tiempo real: cada 6–8 s pregunta aquí, en una sola
--     consulta mínima, en qué actividad va el taller, si cambió su configuración (ver) y cuántos
--     compañeros ya terminaron. Solo cuando «ver» cambia vuelve a pedir el taller completo.
-- ------------------------------------------------------------
create or replace function ws_pulse(p_code text)
returns table (phase text, ver text, total int, listos int)
language sql stable security definer set search_path = public as $$
  select s.phase,
         md5(concat_ws('|', s.phase, s.name, s.facilitator, s.votes_per_user, s.areas, s.stages,
                       s.q_checkin, s.q_expect, s.q_pain, s.brand, s.roles, s.tools, s.quickwins,
                       s.q_idea, s.idea_votes, s.idea_top, s.tasks, s.caso)),
         (select count(*)::int from ws_participants p where p.session_id = s.id),
         (select count(*)::int from ws_participants p where p.session_id = s.id and p.done_phases ? s.phase)
  from ws_sessions s
  where auth.uid() is not null and s.code = upper(trim(p_code));
$$;
revoke execute on function ws_pulse(text) from public, anon;
grant execute on function ws_pulse(text) to authenticated;
-- Ideas y tarjetas: índices para las consultas por persona y por fecha (listas incrementales)
create index if not exists ws_ideas_session_created on ws_ideas(session_id, created_at);
create index if not exists ws_cards_session_part on ws_cards(session_id, participant_id);

-- ------------------------------------------------------------
-- 4h) v1.17 · Eliminar a alguien del equipo (solo cuentas desactivadas)
--     Sus talleres, borradores y todo lo capturado pasan a nombre del admin que lo elimina y sale del
--     equipo; DESPUÉS la función «account» (acción admin-remove) borra su cuenta. Se hace en ese orden
--     porque ws_sessions y ws_drafts se borran en cascada con la cuenta.
-- ------------------------------------------------------------
create or replace function ws_admin_remove_member(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v ws_admins; v_me uuid := auth.uid(); n_ses int := 0; n_dra int := 0; n_par int := 0;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede eliminar cuentas'; end if;
  if p_user is null then raise exception 'Falta indicar a quién eliminar'; end if;
  if p_user = v_me then raise exception 'No puedes eliminar tu propia cuenta'; end if;
  select * into v from ws_admins a where a.user_id = p_user for update;
  if v.user_id is null then raise exception 'Esa cuenta no es del equipo'; end if;
  if v.active then raise exception 'Primero desactiva esa cuenta. Después podrás eliminarla.'; end if;
  -- Talleres y borradores: pasan a tu nombre (con ellos, todo lo capturado en sus talleres)
  update ws_sessions set owner_id = v_me where owner_id = p_user;
  get diagnostics n_ses = row_count;
  update ws_drafts set owner_id = v_me where owner_id = p_user;
  get diagnostics n_dra = row_count;
  -- Lo que capturó como participante con su cuenta del panel también pasa a ti
  -- (si tú también participaste en ese mismo taller, se conserva tu registro y el suyo se va con su cuenta)
  update ws_participants p set user_id = v_me where p.user_id = p_user
     and not exists (select 1 from ws_participants q where q.session_id = p.session_id and q.user_id = v_me);
  get diagnostics n_par = row_count;
  -- Invitaciones pendientes que mandó: ahora son tuyas (a ti te llegan sus avisos)
  update ws_invites set created_by = v_me where created_by = p_user and used_at is null and revoked_at is null;
  -- Invitaciones pendientes para su correo: se cancelan
  update ws_invites set revoked_at = now()
   where lower(email) = lower(v.email) and used_at is null and revoked_at is null;
  delete from ws_admins where user_id = p_user;
  return jsonb_build_object('talleres', n_ses, 'borradores', n_dra, 'participaciones', n_par, 'email', v.email);
end $$;
revoke execute on function ws_admin_remove_member(uuid) from public, anon;
grant execute on function ws_admin_remove_member(uuid) to authenticated;

-- ------------------------------------------------------------
-- 4i) v1.21 · Uso de IA: tokens por propuesta, pausa y tope mensual por persona
-- ------------------------------------------------------------
alter table ws_ai_log add column if not exists kind text not null default 'propuesta';
alter table ws_ai_log add column if not exists draft_id uuid;
alter table ws_ai_log add column if not exists session_id uuid;
alter table ws_ai_log add column if not exists label text;
alter table ws_ai_log add column if not exists model text;
alter table ws_ai_log add column if not exists input_tokens int not null default 0;
alter table ws_ai_log add column if not exists output_tokens int not null default 0;
alter table ws_ai_log add column if not exists ok boolean not null default false;
create index if not exists ws_ai_log_at on ws_ai_log(at);
create index if not exists ws_ai_log_draft on ws_ai_log(draft_id);

alter table ws_admins add column if not exists ai_enabled boolean not null default true;
alter table ws_admins add column if not exists ai_monthly_cap int;   -- tokens al mes; vacío = sin tope

-- Antes de llamar a la IA: ¿puede? (equipo activo, IA no pausada, bajo su tope del mes y del día). Deja el renglón.
create or replace function ws_ai_begin(p_kind text default 'propuesta', p_draft uuid default null, p_label text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a ws_admins; v_used bigint; v_n int; v_id bigint;
begin
  if not ws_is_admin() then return jsonb_build_object('ok', false, 'reason', 'denied'); end if;
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

-- Compatibilidad con la función suggest-workshop anterior: respeta la pausa y el tope, y ya no borra el historial
create or replace function ws_ai_take() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return coalesce((ws_ai_begin('propuesta', null, null) ->> 'ok')::boolean, false);
end $$;
revoke execute on function ws_ai_take() from public, anon;
grant execute on function ws_ai_take() to authenticated;

-- Al crear el taller: los tokens de su borrador pasan a contar para el taller
create or replace function ws_ai_link(p_draft uuid, p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_admin() or p_draft is null or p_session is null then return; end if;
  if not exists (select 1 from ws_sessions s where s.id = p_session and s.owner_id = auth.uid()) then return; end if;
  update ws_ai_log set session_id = p_session where draft_id = p_draft and user_id = auth.uid() and session_id is null;
end $$;
revoke execute on function ws_ai_link(uuid, uuid) from public, anon;
grant execute on function ws_ai_link(uuid, uuid) to authenticated;

-- Detalle de uso. Admin: de todo el equipo; facilitador: solo lo suyo.
drop function if exists ws_ai_usage(timestamptz, timestamptz);
create function ws_ai_usage(p_from timestamptz default date_trunc('month', now()), p_to timestamptz default now() + interval '1 day')
returns table (id bigint, user_id uuid, user_name text, kind text, draft_id uuid, session_id uuid, label text, session_name text,
               session_code text, model text, input_tokens int, output_tokens int, ok boolean, at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, l.user_id, coalesce(nullif(a.name, ''), a.email, 'Cuenta eliminada'), l.kind, l.draft_id, l.session_id, l.label,
         s.name, s.code, l.model, l.input_tokens, l.output_tokens, l.ok, l.at
  from ws_ai_log l
  left join ws_admins a on a.user_id = l.user_id
  left join ws_sessions s on s.id = l.session_id
  where ws_is_admin() and l.at >= p_from and l.at < p_to and (l.user_id = auth.uid() or ws_is_superadmin())
  order by l.at desc
  limit 5000;
$$;
revoke execute on function ws_ai_usage(timestamptz, timestamptz) from public, anon;
grant execute on function ws_ai_usage(timestamptz, timestamptz) to authenticated;

-- Límites y consumo del mes. Admin: todo el equipo; facilitador: solo su renglón.
drop function if exists ws_ai_limits();
create function ws_ai_limits()
returns table (user_id uuid, name text, email text, role text, active boolean, ai_enabled boolean, ai_monthly_cap int, used_month bigint, calls_month bigint)
language sql stable security definer set search_path = public as $$
  select a.user_id, a.name, a.email, a.role, a.active, a.ai_enabled, a.ai_monthly_cap,
         coalesce((select sum(l.input_tokens + l.output_tokens) from ws_ai_log l where l.user_id = a.user_id and l.at >= date_trunc('month', now())), 0),
         coalesce((select count(*) from ws_ai_log l where l.user_id = a.user_id and l.ok and l.at >= date_trunc('month', now())), 0)
  from ws_admins a
  where ws_is_admin() and (a.user_id = auth.uid() or ws_is_superadmin())
  order by (a.user_id = auth.uid()) desc, a.name nulls last, a.email;
$$;
revoke execute on function ws_ai_limits() from public, anon;
grant execute on function ws_ai_limits() to authenticated;

-- El admin pausa o pone tope (en tokens al mes; vacío = sin tope)
create or replace function ws_set_ai_limit(p_user uuid, p_enabled boolean, p_cap int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede cambiar el uso de IA'; end if;
  if p_cap is not null and (p_cap < 0 or p_cap > 100000000) then raise exception 'Tope no válido'; end if;
  update ws_admins set ai_enabled = coalesce(p_enabled, ai_enabled), ai_monthly_cap = p_cap where user_id = p_user;
  if not found then raise exception 'Esa cuenta no es del equipo'; end if;
end $$;
revoke execute on function ws_set_ai_limit(uuid, boolean, int) from public, anon;
grant execute on function ws_set_ai_limit(uuid, boolean, int) to authenticated;

-- ------------------------------------------------------------
-- 4j) v1.22 · Inicio como tablero: números de solo lectura (admin: equipo; facilitador: lo suyo)
-- ------------------------------------------------------------
create or replace function ws_home_stats(p_from timestamptz default null, p_prev timestamptz default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with ph(id, i) as (values ('lobby',1),('checkin',2),('pains',3),('votes',4),('quickwins',5),('ideas',6),('results',7),('closed',8)),
  vis as (
    select s.*, ph.i as pi, (s.created_at at time zone 'America/Mexico_City') as lt
    from ws_sessions s join ph on ph.id = s.phase
    where ws_is_admin() and (s.owner_id = auth.uid() or ws_is_superadmin())
  ),
  cur as (select * from vis where p_from is null or created_at >= p_from),
  prv as (select * from vis where p_prev is not null and p_from is not null and created_at >= p_prev and created_at < p_from),
  part as (select p.*, v.pi, v.created_at as s_at, v.quickwins as s_qw from ws_participants p join vis v on v.id = p.session_id),
  mon as (select generate_series(date_trunc('month', now() at time zone 'America/Mexico_City') - interval '11 months',
                                 date_trunc('month', now() at time zone 'America/Mexico_City'), interval '1 month') as m)
  select case when not ws_is_admin() then null else jsonb_build_object(
    'months', (select jsonb_agg(jsonb_build_object(
        'm', to_char(mon.m, 'YYYY-MM'),
        'sessions', (select count(*) from vis where date_trunc('month', vis.lt) = mon.m),
        'people',   (select count(*) from part join vis on vis.id = part.session_id where date_trunc('month', vis.lt) = mon.m),
        'cards',    (select count(*) from ws_cards c join vis on vis.id = c.session_id where date_trunc('month', vis.lt) = mon.m),
        'done',     (select count(*) from part join vis on vis.id = part.session_id where date_trunc('month', vis.lt) = mon.m and vis.pi >= 7 and part.done_phases ? 'ideas'),
        'elig',     (select count(*) from part join vis on vis.id = part.session_id where date_trunc('month', vis.lt) = mon.m and vis.pi >= 7)
      ) order by mon.m) from mon),
    'cur', (select jsonb_build_object(
        'sessions', (select count(*) from cur),
        'people',   (select count(*) from ws_participants p join cur on cur.id = p.session_id),
        'cards',    (select count(*) from ws_cards c join cur on cur.id = c.session_id),
        'retos',    (select coalesce(sum(least(coalesce(cur.idea_top, 3),
                       (select count(distinct v.card_id) from ws_votes v where v.session_id = cur.id and v.points > 0))), 0) from cur where cur.pi >= 7),
        'done',     (select count(*) from ws_participants p join cur on cur.id = p.session_id where cur.pi >= 7 and p.done_phases ? 'ideas'),
        'elig',     (select count(*) from ws_participants p join cur on cur.id = p.session_id where cur.pi >= 7))),
    'prev', (select case when p_prev is null or p_from is null then null else jsonb_build_object(
        'sessions', (select count(*) from prv),
        'people',   (select count(*) from ws_participants p join prv on prv.id = p.session_id),
        'cards',    (select count(*) from ws_cards c join prv on prv.id = c.session_id),
        'done',     (select count(*) from ws_participants p join prv on prv.id = p.session_id where prv.pi >= 7 and p.done_phases ? 'ideas'),
        'elig',     (select count(*) from ws_participants p join prv on prv.id = p.session_id where prv.pi >= 7)) end),
    -- Por fase: de quienes estaban en talleres que ya pasaron esa fase, cuántos tocaron «Terminé»
    'funnel', (select jsonb_agg(jsonb_build_object('ph', f.id, 'ws', f.ws, 'n', f.n, 'd', f.d) order by f.i) from (
        select ph.id, ph.i,
          (select count(*) from cur where cur.pi > ph.i and (ph.id <> 'quickwins' or jsonb_array_length(cur.quickwins) > 0)) as ws,
          (select count(*) from ws_participants p join cur on cur.id = p.session_id where cur.pi > ph.i and (ph.id <> 'quickwins' or jsonb_array_length(cur.quickwins) > 0)) as n,
          (select count(*) from ws_participants p join cur on cur.id = p.session_id where cur.pi > ph.i and (ph.id <> 'quickwins' or jsonb_array_length(cur.quickwins) > 0) and p.done_phases ? ph.id) as d
        from ph where ph.id in ('checkin','pains','votes','quickwins','ideas')) f),
    'moods', (select coalesce(jsonb_object_agg(x.mood, x.n), '{}'::jsonb) from (
        select p.mood, count(*) as n from ws_participants p join cur on cur.id = p.session_id where coalesce(p.mood, '') <> '' group by p.mood) x),
    'moodAreas', (select coalesce(jsonb_agg(jsonb_build_object('area', x.area, 'n', x.n, 'neg', x.neg) order by x.neg::numeric / x.n desc, x.n desc), '[]'::jsonb) from (
        select p.area, count(*) as n, count(*) filter (where p.mood in ('saturado','rebasado')) as neg
        from ws_participants p join cur on cur.id = p.session_id
        where coalesce(p.mood, '') <> '' and coalesce(p.area, '') <> '' group by p.area having count(*) >= 3) x),
    'areas', (select coalesce(jsonb_agg(jsonb_build_object('area', x.area, 'cur', x.c, 'prev', x.p) order by x.c desc, x.p desc), '[]'::jsonb) from (
        select coalesce(nullif(p.area, ''), 'Sin área') as area,
               count(*) filter (where p_from is null or v.created_at >= p_from) as c,
               count(*) filter (where p_prev is not null and p_from is not null and v.created_at >= p_prev and v.created_at < p_from) as p
        from ws_cards c join ws_participants p on p.id = c.participant_id join vis v on v.id = c.session_id
        group by 1 order by 2 desc, 3 desc limit 8) x where x.c > 0 or x.p > 0),
    -- Índice 0–100 igual que en Resultados: 3 = 100, 2 = 50, 1 = 0; «No aplica» (0) no cuenta
    'qwTop', (select coalesce(jsonb_agg(x order by x.idx desc, x.n desc), '[]'::jsonb) from (
        select q.value ->> 'text' as text, s.name as ws, s.code, count(*) as n, round(avg((r.score - 1) * 50))::int as idx,
               count(*) filter (where r.score = 3) as top
        from cur s cross join lateral jsonb_array_elements(s.quickwins) q
        join ws_qw_ratings r on r.session_id = s.id and r.qw_id = q.value ->> 'id' and r.score > 0
        where coalesce(q.value ->> 'kind', 'qw') = 'qw'
        group by s.id, s.name, s.code, q.value ->> 'id', q.value ->> 'text'
        having count(*) >= 2
        order by 5 desc, 4 desc limit 4) x),
    'results', (select coalesce(jsonb_agg(x order by x.at desc), '[]'::jsonb) from (
        select s.code, s.name, s.owner_id, s.phase, coalesce(s.closed_at, s.created_at) as at,
          (select count(*) from ws_participants p where p.session_id = s.id) as participants,
          (select count(*) from ws_cards c where c.session_id = s.id) as cards,
          (select count(*) from ws_ideas i where i.session_id = s.id and i.kind = 'idea') as ideas,
          (select coalesce(sum(v.points), 0) from ws_votes v where v.session_id = s.id) as pts,
          (select count(distinct v.participant_id) from ws_votes v where v.session_id = s.id and v.points > 0) as voters,
          t.texto as top_text, coalesce(t.pts, 0) as top_pts, coalesce(t.voters, 0) as top_voters
        from vis s
        left join lateral (
          select c.texto, sum(v.points) as pts, count(distinct v.participant_id) filter (where v.points > 0) as voters
          from ws_cards c join ws_votes v on v.card_id = c.id where c.session_id = s.id
          group by c.id, c.texto, c.created_at order by sum(v.points) desc, c.created_at limit 1) t on true
        where s.pi >= 7 order by coalesce(s.closed_at, s.created_at) desc limit 4) x)
  ) end;
$$;
revoke execute on function ws_home_stats(timestamptz, timestamptz) from public, anon;
grant execute on function ws_home_stats(timestamptz, timestamptz) to authenticated;

-- ------------------------------------------------------------
-- 4k) v1.23 · Resumen con IA de los resultados (lo escribe suggest-workshop, lo edita quien facilita)
-- ------------------------------------------------------------
alter table ws_sessions add column if not exists summary text check (char_length(summary) <= 4000);
alter table ws_sessions add column if not exists summary_at timestamptz;

-- ------------------------------------------------------------
-- 4l) v1.26 · Facilitadores entran con contraseña (admin sigue con segundo paso) y enlaces para crear o
--     restablecer la contraseña (1 uso; 1 h si lo pidió la persona, 72 h si su admin reinició su acceso)
-- ------------------------------------------------------------

-- 1) ¿Entraste con acceso suficiente? Igual que antes para admin; un facilitador activo basta con su sesión.
create or replace function ws_strong() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select ( coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
           and not exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.passkey_only) )
    or ( exists (select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end) e
                 where e ->> 'method' = 'passkey')
         and exists (select 1 from ws_admins a where a.user_id = auth.uid() and cardinality(a.passkeys_trusted) > 0
                     and not exists (select 1 from auth.webauthn_credentials c where c.user_id = a.user_id and not (c.id = any(a.passkeys_trusted)))) )
    -- v1.26 · Facilitador activo: su contraseña (o Face ID) basta. Solo ve y opera sus propios talleres.
    or ( not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
         and exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active and a.role = 'facilitator') );
$$;

-- 2) Aceptar invitación: la de facilitador ya no pide segundo paso (crea su contraseña); la de admin sí.
create or replace function ws_redeem_invite(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare v ws_invites; v_mail text := lower(coalesce(auth.jwt() ->> 'email',''));
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Inicia sesión con tu correo para usar la invitación';
  end if;
  select * into v from ws_invites i where i.code_hash = ws_invite_hash(p_code) for update;
  if v.id is null or v.revoked_at is not null or v.expires_at <= now() then
    raise exception 'La invitación no es válida o venció. Pide una nueva al admin.';
  end if;
  if v.role <> 'facilitator' and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Activa la verificación en dos pasos para usar la invitación';
  end if;
  -- v1.16 · Una invitación ya canjeada nunca vuelve a tocar la cuenta
  if v.used_at is not null then
    if v.used_by = auth.uid() and exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active) then
      return (select a.role from ws_admins a where a.user_id = auth.uid());
    end if;
    raise exception 'Esta invitación ya se usó. Pide una nueva al admin.';
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

-- 3) Aprobar una llave nueva de Face ID: igual que antes, y además un facilitador activo dentro con su contraseña.
create or replace function ws_trust_passkeys(p_cred uuid default null) returns int
language plpgsql security definer set search_path = public, auth as $$
declare n int; v_ok boolean;
begin
  select a.active and (
           (a.role = 'facilitator' and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false))
        or (coalesce(auth.jwt() ->> 'aal', '') = 'aal2' and not a.passkey_only)
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

-- 4) Enlaces para crear o restablecer la contraseña (solo el servidor, con su llave, los lee y escribe)
create table if not exists ws_pw_tokens (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  kind text not null check (kind in ('reset','activate')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index if not exists ws_pw_tokens_user on ws_pw_tokens(user_id, kind);
alter table ws_pw_tokens enable row level security;            -- sin políticas: nadie desde la página
revoke all on ws_pw_tokens from anon, authenticated;

-- ------------------------------------------------------------
-- 5) Tiempo real (solo agrega las tablas que falten)
-- ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['ws_sessions','ws_participants','ws_cards','ws_votes',
                           'ws_qw_ratings','ws_ideas','ws_idea_votes','ws_notifications'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Verificación: deben salir 15 tablas con seguridad activa (rls = true)
select c.relname as tabla, c.relrowsecurity as rls,
       (select count(*) from pg_policies p where p.tablename = c.relname) as reglas
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'ws\_%' and c.relkind = 'r'
order by 1;

-- ============================================================
-- PARTE · v2.0 · Tipos de taller, «Juntar parecidas» y tiempo por fase
-- (de migraciones-anteriores/migracion-v200-tipos.sql)
-- ============================================================
-- Colmena v2.0 · Tipos de taller, «Juntar parecidas» y tiempo por fase
-- Córrelo UNA vez en Supabase → SQL Editor → New query → pegar todo → Run. Se puede repetir sin problema.
-- Qué agrega (los talleres de hoy siguen igual: son tipo «Mejora de procesos»):
--   · Tipo de taller (kind): Mejora de procesos, Definir competencias, Diagnóstico, Lluvia de ideas y Retrospectiva.
--     Todos usan las mismas fases de siempre; cambian las palabras y las preguntas.
--   · Juntar parecidas: quien facilita junta tarjetas que dicen lo mismo. El grupo lleva un nombre y es lo que se vota.
--   · Tiempo por fase: minutos sugeridos por fase, hora en que abrió la fase actual, +1 / +5 min y pausa.
--   · Inicio y avisos: cada taller trae su tipo y sus actividades se nombran como ese tipo.
-- ------------------------------------------------------------

-- 1) Sesiones: tipo, minutos por fase y reloj de la fase actual
alter table ws_sessions add column if not exists kind text not null default 'dt';
alter table ws_sessions drop constraint if exists ws_sessions_kind_check;
alter table ws_sessions add constraint ws_sessions_kind_check check (kind in ('dt','comp','diag','ideas','retro'));
alter table ws_sessions add column if not exists mins jsonb;
alter table ws_sessions drop constraint if exists ws_sessions_mins_check;
alter table ws_sessions add constraint ws_sessions_mins_check check (mins is null or (jsonb_typeof(mins) = 'object' and octet_length(mins::text) <= 400));
alter table ws_sessions add column if not exists phase_at timestamptz;
alter table ws_sessions add column if not exists phase_add int not null default 0;
alter table ws_sessions drop constraint if exists ws_sessions_phase_add_check;
alter table ws_sessions add constraint ws_sessions_phase_add_check check (phase_add between -3600 and 14400);
alter table ws_sessions add column if not exists paused_at timestamptz;

-- Al cambiar de fase, el reloj vuelve a empezar (hora del servidor)
create or replace function ws_session_phase_at() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.phase is distinct from old.phase then
    new.phase_at := now(); new.phase_add := 0; new.paused_at := null;
  end if;
  return new;
end $$;
drop trigger if exists ws_session_phase_at on ws_sessions;
create trigger ws_session_phase_at before insert or update of phase on ws_sessions
  for each row execute function ws_session_phase_at();
update ws_sessions set phase_at = coalesce(phase_at, now()) where phase not in ('results','closed') and phase_at is null;

-- 2) Tarjetas: grupo (parent_id) y nombre del grupo (label, va en la tarjeta que encabeza el grupo)
alter table ws_cards add column if not exists parent_id uuid references ws_cards(id) on delete set null;
alter table ws_cards add column if not exists label text;
alter table ws_cards drop constraint if exists ws_cards_label_check;
alter table ws_cards add constraint ws_cards_label_check check (label is null or char_length(label) between 1 and 120);
alter table ws_cards drop constraint if exists ws_cards_parent_check;
alter table ws_cards add constraint ws_cards_parent_check check (parent_id is null or parent_id <> id);
create index if not exists ws_cards_parent on ws_cards(parent_id);

-- Cada tarjeta nace suelta: solo quien facilita junta (con las funciones de abajo)
create or replace function ws_cards_born_loose() returns trigger
language plpgsql set search_path = public as $$
begin
  new.parent_id := null; new.label := null;
  return new;
end $$;
drop trigger if exists ws_cards_born_loose on ws_cards;
create trigger ws_cards_born_loose before insert on ws_cards
  for each row execute function ws_cards_born_loose();

-- Si alguien borra la tarjeta que encabeza un grupo, la siguiente toma el nombre y el grupo sigue.
-- (Se llama «A_…» para correr antes que la llave foránea, que dejaría sueltas a las demás.)
create or replace function ws_cards_keep_group() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_next uuid;
begin
  if old.label is not null and old.parent_id is null then
    select id into v_next from ws_cards where parent_id = old.id order by created_at, id limit 1;
    if v_next is not null then
      update ws_cards set parent_id = null, label = old.label where id = v_next;
      update ws_cards set parent_id = v_next where parent_id = old.id and id <> v_next;
    end if;
  end if;
  return null;
end $$;
drop trigger if exists "A_ws_cards_keep_group" on ws_cards;
create trigger "A_ws_cards_keep_group" after delete on ws_cards
  for each row execute function ws_cards_keep_group();

-- Votos: solo a tarjetas sueltas o a la que encabeza un grupo
create or replace function ws_votes_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_cap int; v_used int;
begin
  if not exists (select 1 from ws_cards c where c.id = new.card_id and c.session_id = new.session_id) then
    raise exception 'La tarjeta no pertenece a esta sesión';
  end if;
  if exists (select 1 from ws_cards c where c.id = new.card_id and c.parent_id is not null) then
    raise exception 'Esa tarjeta ya está dentro de un grupo: vota por el grupo';
  end if;
  select s.votes_per_user into v_cap from ws_sessions s where s.id = new.session_id;
  select coalesce(sum(v.points), 0) into v_used
  from ws_votes v
  where v.session_id = new.session_id
    and v.participant_id = new.participant_id
    and v.card_id <> new.card_id;
  if v_used + new.points > v_cap then
    raise exception 'Ya usaste todos tus votos (% de %)', v_used, v_cap;
  end if;
  return new;
end $$;

-- 3) Juntar parecidas (solo quien facilita, en la fase de tarjetas y sin votos de por medio)
create or replace function ws_card_group(p_session uuid, p_cards uuid[], p_label text, p_lead uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_lead uuid; v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if not ws_is_owner(p_session) then raise exception 'Solo quien facilita puede juntar tarjetas'; end if;
  if ws_session_phase(p_session) <> 'pains' then raise exception 'Las tarjetas se juntan antes de votar'; end if;
  if coalesce(array_length(p_cards, 1), 0) = 0 then raise exception 'Elige al menos una tarjeta'; end if;
  if char_length(coalesce(v_label, '')) > 120 then raise exception 'El nombre del grupo admite hasta 120 caracteres'; end if;
  if exists (select 1 from unnest(p_cards) x(id) where not exists (select 1 from ws_cards c where c.id = x.id and c.session_id = p_session)) then
    raise exception 'Alguna tarjeta no pertenece a este taller';
  end if;
  if exists (select 1 from ws_votes v where v.session_id = p_session and v.card_id = any(p_cards)) then
    raise exception 'Alguna tarjeta ya tiene votos';
  end if;
  if p_lead is not null then
    if not exists (select 1 from ws_cards c where c.id = p_lead and c.session_id = p_session and c.parent_id is null) then
      raise exception 'Ese grupo no existe';
    end if;
    v_lead := p_lead;
    if v_label is not null then update ws_cards set label = v_label where id = v_lead; end if;
  else
    if v_label is null then raise exception 'Ponle nombre al grupo'; end if;
    v_lead := p_cards[1];
    -- si la primera ya encabezaba un grupo, sus tarjetas se quedan con ella
    update ws_cards set parent_id = null, label = v_label where id = v_lead;
  end if;
  -- las elegidas (y lo que encabezaban) pasan al grupo
  update ws_cards set parent_id = v_lead, label = null
   where session_id = p_session and id <> v_lead
     and (id = any(p_cards) or parent_id = any(p_cards));
  return v_lead;
end $$;

create or replace function ws_card_ungroup(p_card uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare c ws_cards; v_next uuid;
begin
  select * into c from ws_cards where id = p_card;
  if c.id is null then raise exception 'Esa tarjeta ya no existe'; end if;
  if not ws_is_owner(c.session_id) then raise exception 'Solo quien facilita puede separar tarjetas'; end if;
  if ws_session_phase(c.session_id) <> 'pains' then raise exception 'Las tarjetas se separan antes de votar'; end if;
  if c.parent_id is not null then
    update ws_cards set parent_id = null where id = c.id;
  elsif c.label is not null then
    -- encabezaba un grupo: la siguiente tarjeta toma el nombre y el resto se queda con ella
    select id into v_next from ws_cards where parent_id = c.id order by created_at, id limit 1;
    if v_next is not null then
      update ws_cards set parent_id = null, label = c.label where id = v_next;
      update ws_cards set parent_id = v_next where parent_id = c.id and id <> v_next;
    end if;
    update ws_cards set label = null where id = c.id;
  end if;
end $$;

create or replace function ws_card_label(p_lead uuid, p_label text)
returns void
language plpgsql security definer set search_path = public as $$
declare c ws_cards; v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  select * into c from ws_cards where id = p_lead;
  if c.id is null or c.parent_id is not null then raise exception 'Ese grupo no existe'; end if;
  if not ws_is_owner(c.session_id) then raise exception 'Solo quien facilita puede renombrar grupos'; end if;
  if ws_session_phase(c.session_id) <> 'pains' then raise exception 'El nombre se cambia antes de votar'; end if;
  if v_label is null then raise exception 'Ponle nombre al grupo'; end if;
  if char_length(v_label) > 120 then raise exception 'El nombre del grupo admite hasta 120 caracteres'; end if;
  update ws_cards set label = v_label where id = p_lead;
end $$;

-- 4) Reloj de la fase: +1 / +5 min, pausa y reanudar (solo quien facilita)
create or replace function ws_phase_clock(p_session uuid, p_action text, p_seconds int default 60)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare s ws_sessions;
begin
  if not ws_is_owner(p_session) then raise exception 'Solo quien facilita controla el tiempo'; end if;
  select * into s from ws_sessions where id = p_session for update;
  if p_action = 'add' then
    update ws_sessions set phase_add = least(14400, greatest(-3600, phase_add + coalesce(p_seconds, 60))) where id = p_session;
  elsif p_action = 'pause' then
    update ws_sessions set paused_at = coalesce(paused_at, now()) where id = p_session;
  elsif p_action = 'resume' then
    if s.paused_at is not null then
      update ws_sessions set phase_add = least(14400, phase_add + ceil(extract(epoch from now() - s.paused_at))::int), paused_at = null where id = p_session;
    end if;
  else
    raise exception 'Acción desconocida';
  end if;
  select * into s from ws_sessions where id = p_session;
  return jsonb_build_object('phase_at', s.phase_at, 'phase_add', s.phase_add, 'paused_at', s.paused_at, 'now', now());
end $$;

create or replace function ws_now() returns timestamptz
language sql stable as $$ select now() $$;

-- 5) El celular recibe el tipo del taller (cambia el tipo de resultado: se vuelven a crear las dos funciones)
drop function if exists ws_join_lookup(text);
create function ws_join_lookup(p_code text)
returns table (id uuid, code text, name text, facilitator text, phase text,
               votes_per_user int, areas jsonb, stages jsonb,
               q_checkin text, q_expect text, q_pain text, brand text,
               roles jsonb, tools jsonb, quickwins jsonb, q_idea text,
               idea_votes int, idea_top int, tasks jsonb, caso text, kind text)
language sql stable security definer set search_path = public as $$
  select s.id, s.code, s.name, s.facilitator, s.phase, s.votes_per_user, s.areas, s.stages,
         s.q_checkin, s.q_expect, s.q_pain, s.brand,
         s.roles, s.tools, s.quickwins, s.q_idea, s.idea_votes, s.idea_top, s.tasks, s.caso, s.kind
  from ws_sessions s
  where auth.uid() is not null and s.code = upper(trim(p_code));
$$;

drop function if exists ws_pulse(text);
create function ws_pulse(p_code text)
returns table (phase text, ver text, total int, listos int)
language sql stable security definer set search_path = public as $$
  select s.phase,
         md5(concat_ws('|', s.phase, s.name, s.facilitator, s.votes_per_user, s.areas, s.stages,
                       s.q_checkin, s.q_expect, s.q_pain, s.brand, s.roles, s.tools, s.quickwins,
                       s.q_idea, s.idea_votes, s.idea_top, s.tasks, s.caso, s.kind)),
         (select count(*)::int from ws_participants p where p.session_id = s.id),
         (select count(*)::int from ws_participants p where p.session_id = s.id and p.done_phases ? s.phase)
  from ws_sessions s
  where auth.uid() is not null and s.code = upper(trim(p_code));
$$;

-- 6) Inicio: cada taller trae su tipo (para nombrar sus fases)
create or replace function ws_dashboard() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'code', s.code, 'name', s.name, 'phase', s.phase, 'owner_id', s.owner_id,
        'created_at', s.created_at, 'closed_at', s.closed_at, 'kind', s.kind,
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

-- 7) Aviso «Todos terminaron…»: con el nombre de la actividad según el tipo de taller
create or replace function ws_ev_phase_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare s ws_sessions; v_n int; v_t text;
begin
  select * into s from ws_sessions where id = new.session_id;
  if s.id is null or s.phase not in ('checkin','pains','votes','quickwins','ideas') then return new; end if;
  if not (new.done_phases ? s.phase) or coalesce(old.done_phases ? s.phase, false) then return new; end if;
  select count(*) into v_n from ws_participants p where p.session_id = s.id;
  if v_n = 0 or exists (select 1 from ws_participants p where p.session_id = s.id and not (p.done_phases ? s.phase)) then
    return new;
  end if;
  v_t := case s.phase when 'checkin' then 'Check-in'
           when 'pains' then case s.kind when 'comp' then 'Comportamientos' when 'diag' then 'Lo que vivimos'
                                         when 'ideas' then 'Ideas' when 'retro' then 'Qué pasó' else 'Dolores' end
           when 'votes' then 'Votación' when 'quickwins' then 'Validación'
           else case s.kind when 'comp' then 'Cómo se ve' when 'diag' then 'Qué haríamos'
                            when 'ideas' then 'Cómo la hacemos' when 'retro' then 'Acciones' else 'Ideas' end end;
  perform ws_notify(s.owner_id, 'phase_done', 'Todos terminaron ' || v_t || ' en «' || s.name || '»',
    v_n || case v_n when 1 then ' participante listo' else ' participantes listos' end || '. Puedes abrir la siguiente actividad.',
    jsonb_build_object('label','Abrir taller','code',s.code), jsonb_build_object('session',s.id,'phase',s.phase), false,
    'phase_done:' || s.id || ':' || s.phase);
  return new;
end $$;

-- 8) Permisos: solo cuentas con sesión (nunca anónimos sin sesión)
revoke execute on function ws_card_group(uuid, uuid[], text, uuid) from public, anon;
revoke execute on function ws_card_ungroup(uuid) from public, anon;
revoke execute on function ws_card_label(uuid, text) from public, anon;
revoke execute on function ws_phase_clock(uuid, text, int) from public, anon;
revoke execute on function ws_now() from public, anon;
revoke execute on function ws_join_lookup(text) from public, anon;
revoke execute on function ws_pulse(text) from public, anon;
grant execute on function ws_card_group(uuid, uuid[], text, uuid) to authenticated;
grant execute on function ws_card_ungroup(uuid) to authenticated;
grant execute on function ws_card_label(uuid, text) to authenticated;
grant execute on function ws_phase_clock(uuid, text, int) to authenticated;
grant execute on function ws_now() to authenticated;
grant execute on function ws_join_lookup(text) to authenticated;
grant execute on function ws_pulse(text) to authenticated;
revoke execute on function ws_dashboard() from public, anon;
grant execute on function ws_dashboard() to authenticated;

-- Verificación (una sola fila): tipo_y_reloj = 5, grupos = 2, funciones = 9
select
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ws_sessions'
     and column_name in ('kind','mins','phase_at','phase_add','paused_at')) as tipo_y_reloj,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ws_cards'
     and column_name in ('parent_id','label')) as grupos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
     and p.proname in ('ws_card_group','ws_card_ungroup','ws_card_label','ws_phase_clock','ws_now','ws_join_lookup','ws_pulse',
                       'ws_cards_born_loose','ws_cards_keep_group')) as funciones;

-- ============================================================
-- PARTE · v2.1 · Seguridad y datos
-- (de migracion-v210-seguridad.sql)
-- ============================================================
-- Colmena v2.1 · Seguridad y datos
-- Córrela UNA vez en Supabase → SQL Editor → New query → pegar todo → Run. Se puede repetir sin problema.
-- Qué cambia (los talleres, las cuentas y lo capturado siguen igual):
--   · Quien participa solo puede cambiar su perfil, su check-in y su avance. Ya no puede pasarse a otro
--     taller ni marcar como terminada una actividad que todavía no empieza.
--   · Nombre, apellido, área y puesto ya no aceptan los signos < y >.
--   · Votos y apoyos con candado: dos toques al mismo tiempo ya no rebasan el tope de cada persona.
--   · La base guarda su versión (ws_schema_version). setup.sql y las migraciones anteriores la revisan
--     y se detienen con un aviso en lugar de regresar funciones a una versión vieja.
-- Al final sale una sola fila: columnas = 9, candados = 2, version = 2.1
-- ------------------------------------------------------------

-- 1) Versión de la base
create table if not exists ws_schema_version (
  version text primary key check (version ~ '^[0-9]+(\.[0-9]+)*$'),
  applied_at timestamptz not null default now(),
  note text
);
alter table ws_schema_version enable row level security;   -- sin políticas: nadie la lee desde la página
revoke all on ws_schema_version from anon, authenticated;

-- 2) Participantes: solo su perfil, su check-in y su avance
--    (antes podía cambiar cualquier columna de su registro, incluido el taller al que pertenece)
revoke update on ws_participants from authenticated;
grant update (nombre, apellido, area, rol, etapas, emoji, mood, expectativa, done_phases)
  on ws_participants to authenticated;

--    Nombre, apellido, área y puesto sin < ni > (no tienen uso legítimo y así no pueden llevar código).
--    «not valid»: no revisa los registros que ya existen; solo lo nuevo.
alter table ws_participants drop constraint if exists ws_participants_nombre_texto;
alter table ws_participants add constraint ws_participants_nombre_texto check (nombre !~ '[<>]') not valid;
alter table ws_participants drop constraint if exists ws_participants_apellido_texto;
alter table ws_participants add constraint ws_participants_apellido_texto check (apellido !~ '[<>]') not valid;
alter table ws_participants drop constraint if exists ws_participants_area_texto;
alter table ws_participants add constraint ws_participants_area_texto check (area !~ '[<>]') not valid;
alter table ws_participants drop constraint if exists ws_participants_rol_texto;
alter table ws_participants add constraint ws_participants_rol_texto check (rol !~ '[<>]') not valid;

--    Avance real y etapas del taller. Solo revisa lo que se agrega: lo que ya estaba se queda
--    (por ejemplo, si quien facilita regresa a una actividad anterior).
create or replace function ws_participants_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order constant text[] := array['lobby','checkin','pains','votes','quickwins','ideas','results','closed'];
  v_acts  constant text[] := array['checkin','pains','votes','quickwins','ideas'];
  v_phase text; v_stages jsonb; v_cur int; v_old_dp jsonb := '[]'; v_old_et jsonb := '[]'; e jsonb;
begin
  if tg_op = 'UPDATE' then
    if new.session_id is distinct from old.session_id then
      raise exception 'Un participante no puede cambiarse de taller';
    end if;
    v_old_dp := coalesce(old.done_phases, '[]'); v_old_et := coalesce(old.etapas, '[]');
  end if;
  if new.done_phases is distinct from v_old_dp or new.etapas is distinct from v_old_et then
    select s.phase, s.stages into v_phase, v_stages from ws_sessions s where s.id = new.session_id;
  end if;
  if new.done_phases is distinct from v_old_dp then
    if jsonb_array_length(new.done_phases) > 10 then raise exception 'Avance no válido'; end if;
    v_cur := array_position(v_order, v_phase);
    for e in select x from jsonb_array_elements(new.done_phases) x loop
      continue when v_old_dp @> jsonb_build_array(e);
      if jsonb_typeof(e) <> 'string' or not ((e #>> '{}') = any (v_acts)) then
        raise exception 'Avance no válido';
      end if;
      if v_cur is null or array_position(v_order, e #>> '{}') > v_cur then
        raise exception 'Esa actividad todavía no empieza';
      end if;
    end loop;
  end if;
  if new.etapas is distinct from v_old_et then
    for e in select x from jsonb_array_elements(new.etapas) x loop
      continue when v_old_et @> jsonb_build_array(e);
      if not coalesce(v_stages, '[]') @> jsonb_build_array(e) then
        raise exception 'Esa etapa no es de este taller';
      end if;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists ws_participants_guard on ws_participants;
create trigger ws_participants_guard before insert or update on ws_participants
  for each row execute function ws_participants_guard();
revoke execute on function ws_participants_guard() from public, anon, authenticated;

-- 3) Votos con candado: un participante a la vez (dos toques simultáneos ya no rebasan el tope)
--    Mismo cuerpo de la v2.0 (no se vota una tarjeta que ya está dentro de un grupo) + el candado.
create or replace function ws_votes_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cap int; v_used int;
begin
  perform pg_advisory_xact_lock(2101, hashtext(new.participant_id::text));
  if not exists (select 1 from ws_cards c where c.id = new.card_id and c.session_id = new.session_id) then
    raise exception 'La tarjeta no pertenece a esta sesión';
  end if;
  if exists (select 1 from ws_cards c where c.id = new.card_id and c.parent_id is not null) then
    raise exception 'Esa tarjeta ya está dentro de un grupo: vota por el grupo';
  end if;
  select s.votes_per_user into v_cap from ws_sessions s where s.id = new.session_id;
  select coalesce(sum(v.points), 0) into v_used
  from ws_votes v
  where v.session_id = new.session_id
    and v.participant_id = new.participant_id
    and v.card_id <> new.card_id;
  if v_used + new.points > v_cap then
    raise exception 'Ya usaste todos tus votos (% de %)', v_used, v_cap;
  end if;
  return new;
end $$;

--    Apoyos con el mismo candado (mismo cuerpo de la v1.2 + el candado)
create or replace function ws_idea_votes_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cap int; v_used int; v_author uuid; v_kind text;
begin
  perform pg_advisory_xact_lock(2102, hashtext(new.participant_id::text));
  select i.participant_id, i.kind into v_author, v_kind
  from ws_ideas i where i.id = new.idea_id and i.session_id = new.session_id;
  if v_author is null or v_kind <> 'idea' then
    raise exception 'La idea no pertenece a esta sesión';
  end if;
  if v_author = new.participant_id then
    raise exception 'No puedes apoyar tu propia idea';
  end if;
  select s.idea_votes into v_cap from ws_sessions s where s.id = new.session_id;
  select count(*) into v_used from ws_idea_votes v
  where v.session_id = new.session_id and v.participant_id = new.participant_id and v.idea_id <> new.idea_id;
  if v_used + 1 > v_cap then
    raise exception 'Ya usaste todos tus apoyos (% de %)', v_used, v_cap;
  end if;
  return new;
end $$;

-- 4) Esta base ya está en la v2.1
insert into ws_schema_version(version, note) values ('2.1', 'Seguridad y datos: participante, candado de votos, versión de la base')
  on conflict (version) do nothing;

-- Verificación (una sola fila): columnas = 9, candados = 2, version = 2.1
select
  (select count(*) from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'ws_participants'
       and grantee = 'authenticated' and privilege_type = 'UPDATE') as columnas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('ws_votes_guard','ws_idea_votes_guard')
       and p.prosrc like '%pg_advisory_xact_lock%') as candados,
  (select version from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1) as version;

-- ============================================================
-- PARTE · v2.2 · Edición segura en Sala de espera
-- (de migracion-v220-lobby-edit.sql)
-- ============================================================
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

-- ============================================================
-- PARTE · v2.3 · Analítica privada de producto
-- (de migracion-v230-analitica.sql)
-- ============================================================
-- Colmena v2.3 · Analítica privada de producto
-- Córrela en Supabase → SQL Editor después de la v2.2. Se puede repetir sin problema.
-- Registra únicamente eventos técnicos y de recorrido: nunca respuestas, nombres, correos ni códigos.
-- Los eventos detallados duran 90 días; los conteos diarios agregados no vencen.
-- Solo un admin con acceso fuerte puede consultar ws_analytics().
-- Al final sale una fila: funciones = 3, version = 2.3
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.2') then
    raise exception 'Primero corre migracion-v220-lobby-edit.sql (v2.2) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,3] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

create table if not exists ws_telemetry_events (
  id bigint generated by default as identity primary key,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  session_id uuid references ws_sessions(id) on delete set null,
  actor_type text not null check (actor_type in ('participant','facilitator','admin')),
  actor_key text not null check (char_length(actor_key) = 64),
  client_id uuid not null,
  event_name text not null check (char_length(event_name) between 3 and 48),
  flow text check (char_length(flow) <= 32),
  step text check (char_length(step) <= 48),
  duration_ms int check (duration_ms between 0 and 86400000),
  device_family text not null check (device_family in ('mobile','tablet','desktop','other')),
  browser_family text not null check (browser_family in ('chrome','safari','edge','firefox','other')),
  os_family text not null check (os_family in ('ios','android','windows','macos','linux','other')),
  viewport_bucket text not null check (viewport_bucket in ('xs','sm','md','lg','xl')),
  display_mode text not null check (display_mode in ('browser','standalone')),
  connection_type text check (connection_type in ('offline','slow-2g','2g','3g','4g','unknown')),
  properties jsonb not null default '{}' check (jsonb_typeof(properties) = 'object')
);
create index if not exists ws_telemetry_events_at on ws_telemetry_events(occurred_at desc);
create index if not exists ws_telemetry_events_session_at on ws_telemetry_events(session_id, occurred_at desc);
create index if not exists ws_telemetry_events_name_at on ws_telemetry_events(event_name, occurred_at desc);
create index if not exists ws_telemetry_events_client_at on ws_telemetry_events(client_id, occurred_at desc);
create index if not exists ws_telemetry_events_actor_received on ws_telemetry_events(actor_key, received_at desc);

create table if not exists ws_telemetry_daily (
  day date not null,
  session_id uuid,
  actor_type text not null,
  event_name text not null,
  flow text not null default '',
  step text not null default '',
  device_family text not null,
  browser_family text not null,
  display_mode text not null,
  events bigint not null default 0,
  errors bigint not null default 0,
  duration_count bigint not null default 0,
  duration_total_ms bigint not null default 0
);
create index if not exists ws_telemetry_daily_day on ws_telemetry_daily(day desc);
create unique index if not exists ws_telemetry_daily_dims on ws_telemetry_daily
  (day,session_id,actor_type,event_name,flow,step,device_family,browser_family,display_mode) nulls not distinct;

alter table ws_telemetry_events enable row level security;
alter table ws_telemetry_daily enable row level security;
revoke all on ws_telemetry_events, ws_telemetry_daily from anon, authenticated;
revoke all on sequence ws_telemetry_events_id_seq from anon, authenticated;

-- Entrada única. El servidor decide el rol, limita el lote y conserva solo propiedades permitidas.
create or replace function ws_telemetry_ingest(p_events jsonb) returns int
language plpgsql security definer set search_path = public, auth as $$
declare
  e jsonb; n int := 0; sid uuid; cid uuid; en text; fl text; st text; dur int;
  typ text; akey text; props jsonb; allowed text[] := array[
    'app_open','view_opened','creator_started','creator_goal_selected','creator_context_completed',
    'creator_plan_ready','creator_reviewed','workshop_created','workshop_updated','workshop_opened',
    'phase_changed','onboarding_started','onboarding_step','onboarding_back',
    'onboarding_validation_failed','participant_joined','join_failed','phase_viewed','phase_completed',
    'action_succeeded','action_failed','validation_failed','retry','rage_click','app_error'
  ];
begin
  if auth.uid() is null or jsonb_typeof(p_events) <> 'array' then return 0; end if;
  if jsonb_array_length(p_events) > 25 then raise exception 'Demasiados eventos'; end if;
  select case when a.role = 'admin' then 'admin' else 'facilitator' end into typ
    from ws_admins a where a.user_id = auth.uid() and a.active;
  typ := coalesce(typ, 'participant');
  akey := md5(auth.uid()::text || ':colmena-telemetry-v1:a') || md5(auth.uid()::text || ':colmena-telemetry-v1:b');
  if (select count(*) from ws_telemetry_events x where x.actor_key=akey and x.received_at>now()-interval '1 minute') >= 120 then return 0; end if;

  for e in select value from jsonb_array_elements(p_events) loop
    begin
      en := left(coalesce(e->>'name',''), 48);
      if not (en = any(allowed)) then continue; end if;
      cid := (e->>'client_id')::uuid;
      sid := nullif(e->>'session_id','')::uuid;
      if sid is not null and not exists (select 1 from ws_sessions s where s.id = sid) then continue; end if;
      if sid is not null and typ <> 'participant' and not (ws_is_owner(sid) or ws_is_superadmin()) then continue; end if;
      if sid is not null and typ = 'participant' and en not in
        ('workshop_opened','onboarding_started','onboarding_step','onboarding_back','onboarding_validation_failed','participant_joined','join_failed','app_error','rage_click')
        and not ws_is_member(sid) then continue; end if;

      fl := left(nullif(regexp_replace(coalesce(e->>'flow',''), '[^a-z0-9_-]', '', 'g'),''),32);
      st := left(nullif(regexp_replace(coalesce(e->>'step',''), '[^a-z0-9_-]', '', 'g'),''),48);
      dur := greatest(0, least(86400000, coalesce((e->>'duration_ms')::int,0)));
      props := coalesce(e->'properties','{}'::jsonb);
      if jsonb_typeof(props) <> 'object' then props := '{}'::jsonb; end if;
      props := (select coalesce(jsonb_object_agg(key, to_jsonb(left(value,80))), '{}'::jsonb)
                from jsonb_each_text(props)
                where key in ('method','action','reason','target','from','to','result','source','count'));

      insert into ws_telemetry_events(occurred_at,session_id,actor_type,actor_key,client_id,event_name,flow,step,duration_ms,
        device_family,browser_family,os_family,viewport_bucket,display_mode,connection_type,properties)
      values (
        greatest(now()-interval '1 day', least(now()+interval '5 minutes', coalesce((e->>'occurred_at')::timestamptz,now()))),
        sid,typ,akey,cid,en,fl,st,nullif(dur,0),
        case when e->>'device' in ('mobile','tablet','desktop') then e->>'device' else 'other' end,
        case when e->>'browser' in ('chrome','safari','edge','firefox') then e->>'browser' else 'other' end,
        case when e->>'os' in ('ios','android','windows','macos','linux') then e->>'os' else 'other' end,
        case when e->>'viewport' in ('xs','sm','md','lg','xl') then e->>'viewport' else 'md' end,
        case when e->>'display_mode' = 'standalone' then 'standalone' else 'browser' end,
        case when e->>'connection' in ('offline','slow-2g','2g','3g','4g') then e->>'connection' else 'unknown' end,
        props
      );
      n := n + 1;
    exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow then
      continue;
    end;
  end loop;
  return n;
end $$;

-- Consolida días cerrados y elimina detalle con más de 90 días.
create or replace function ws_telemetry_rollup() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_up bigint := 0; n_del bigint := 0;
begin
  insert into ws_telemetry_daily(day,session_id,actor_type,event_name,flow,step,device_family,browser_family,display_mode,events,errors,duration_count,duration_total_ms)
  select (occurred_at at time zone 'America/Mexico_City')::date, session_id, actor_type, event_name,
         coalesce(flow,''), coalesce(step,''), device_family, browser_family, display_mode,
         count(*), count(*) filter (where event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','app_error')),
         count(duration_ms), coalesce(sum(duration_ms),0)
  from ws_telemetry_events
  where occurred_at < date_trunc('day', now() at time zone 'America/Mexico_City') at time zone 'America/Mexico_City'
  group by 1,2,3,4,5,6,7,8,9
  on conflict(day,session_id,actor_type,event_name,flow,step,device_family,browser_family,display_mode)
  do update set events=excluded.events, errors=excluded.errors, duration_count=excluded.duration_count, duration_total_ms=excluded.duration_total_ms;
  get diagnostics n_up = row_count;
  delete from ws_telemetry_events where occurred_at < now() - interval '90 days';
  get diagnostics n_del = row_count;
  return jsonb_build_object('agregados',n_up,'eliminados',n_del);
end $$;

-- Resumen privado para la vista Analítica. El detalle nunca sale de PostgreSQL.
create or replace function ws_analytics(p_from timestamptz default now()-interval '30 days', p_to timestamptz default now(), p_session uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede ver Analítica'; end if;
  p_from := greatest(coalesce(p_from,now()-interval '30 days'), now()-interval '90 days');
  p_to := least(coalesce(p_to,now()), now()+interval '1 day');
  if p_to <= p_from then raise exception 'Periodo no válido'; end if;

  with ev as (
    select * from ws_telemetry_events e
    where e.occurred_at >= p_from and e.occurred_at < p_to and (p_session is null or e.session_id = p_session)
  ),
  pf(stage,ord,event_name) as (values
    ('Abrieron el taller',1,'workshop_opened'),('Iniciaron registro',2,'onboarding_started'),
    ('Entraron a la sala',3,'participant_joined'),('Vieron una actividad',4,'phase_viewed'),('Terminaron una actividad',5,'phase_completed')),
  cf(stage,ord,event_name) as (values
    ('Abrieron el creador',1,'creator_started'),('Eligieron objetivo',2,'creator_goal_selected'),
    ('Completaron contexto',3,'creator_context_completed'),('Revisaron el plan',4,'creator_reviewed'),('Abrieron la sala',5,'workshop_created'))
  select jsonb_build_object(
    'from',p_from,'to',p_to,'retention_days',90,
    'overview',jsonb_build_object(
      'events',(select count(*) from ev),
      'journeys',(select count(distinct client_id) from ev),
      'workshops',(select count(distinct session_id) from ev where session_id is not null),
      'errors',(select count(*) from ev where event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','app_error')),
      'p50_ms',(select coalesce(percentile_disc(.5) within group(order by duration_ms),0) from ev where duration_ms is not null)),
    'participant_funnel',(select coalesce(jsonb_agg(jsonb_build_object('stage',stage,'ord',ord,'journeys',n) order by ord),'[]') from
      (select pf.stage,pf.ord,count(distinct ev.client_id) n from pf left join ev on ev.event_name=pf.event_name and ev.actor_type='participant' group by pf.stage,pf.ord) x),
    'creator_funnel',(select coalesce(jsonb_agg(jsonb_build_object('stage',stage,'ord',ord,'journeys',n) order by ord),'[]') from
      (select cf.stage,cf.ord,count(distinct ev.client_id) n from cf left join ev on ev.event_name=cf.event_name and ev.actor_type in ('admin','facilitator') group by cf.stage,cf.ord) x),
    'friction',(select coalesce(jsonb_agg(to_jsonb(x) order by x.occurrences desc),'[]') from
      (select event_name,coalesce(flow,'') flow,coalesce(step,'') step,count(*) occurrences,count(distinct client_id) journeys,count(distinct session_id) workshops
       from ev where event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','retry','rage_click','app_error')
       group by 1,2,3 order by 4 desc limit 30) x),
    'devices',(select coalesce(jsonb_agg(to_jsonb(x) order by x.journeys desc),'[]') from
      (select device_family device,browser_family browser,display_mode,count(distinct client_id) journeys,count(*) events,
       count(*) filter(where event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','app_error')) errors
       from ev group by 1,2,3 order by 4 desc limit 30) x),
    'workshops',(select coalesce(jsonb_agg(to_jsonb(x) order by x.journeys desc),'[]') from
      (select s.id,s.name,s.code,s.kind,coalesce(a.name,a.email,'Cuenta eliminada') facilitator,
       count(distinct ev.client_id) journeys,count(*) events,
       count(distinct ev.client_id) filter(where ev.event_name='participant_joined') joined,
       count(*) filter(where ev.event_name='phase_completed') completed,
       count(*) filter(where ev.event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','app_error')) errors
       from ev join ws_sessions s on s.id=ev.session_id left join ws_admins a on a.user_id=s.owner_id
       group by s.id,s.name,s.code,s.kind,a.name,a.email order by 6 desc limit 100) x),
    'trend',(select coalesce(jsonb_agg(to_jsonb(x) order by x.day),'[]') from
      (select (occurred_at at time zone 'America/Mexico_City')::date as "day",count(*) events,count(distinct client_id) journeys,
       count(*) filter(where event_name in ('action_failed','join_failed','validation_failed','onboarding_validation_failed','app_error')) errors
       from ev group by 1 order by 1) x)
  ) into out;
  return out;
end $$;

revoke execute on function ws_telemetry_ingest(jsonb), ws_telemetry_rollup(), ws_analytics(timestamptz,timestamptz,uuid) from public, anon;
grant execute on function ws_telemetry_ingest(jsonb), ws_analytics(timestamptz,timestamptz,uuid) to authenticated;

-- En Supabase, corre a las 03:20 de CDMX. En PostgreSQL local se omite si pg_cron no existe.
do $$ begin
  if exists (select 1 from pg_available_extensions where name='pg_cron')
     and exists (select 1 from pg_extension where extname='pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname='colmena-telemetry-rollup';
    perform cron.schedule('colmena-telemetry-rollup','20 9 * * *','select public.ws_telemetry_rollup()');
  end if;
exception when undefined_table or invalid_schema_name then null;
end $$;

insert into ws_schema_version(version) values ('2.3') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('ws_telemetry_ingest','ws_telemetry_rollup','ws_analytics')) as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;

-- ============================================================
-- PARTE · v2.3.1 · Último acceso del equipo
-- (de migracion-v231-ultimo-acceso.sql)
-- ============================================================
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

-- ============================================================
-- Verificación final (una sola fila): version = 2.3.1 y todas las tablas con seguridad activa
-- ============================================================
select
  (select version from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1) as version,
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname like 'ws\_%' and c.relkind = 'r') as tablas,
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname like 'ws\_%' and c.relkind = 'r' and c.relrowsecurity) as con_seguridad;
