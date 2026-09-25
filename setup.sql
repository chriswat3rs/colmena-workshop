-- ============================================================
-- COLMENA v1.5 · esquema seguro para Supabase
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

-- ¿Eres facilitador (o admin) activo Y entraste con segundo factor?
-- (el nombre se conserva por compatibilidad: significa «cuenta con acceso al panel»)
create or replace function ws_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active)
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

-- v1.5 · ¿Eres admin (rol que ve todos los talleres) activo con segundo factor?
create or replace function ws_is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ws_admins a where a.user_id = auth.uid() and a.active and a.role = 'admin')
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
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
  where a.user_id = auth.uid() and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
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
-- 5) Tiempo real (solo agrega las tablas que falten)
-- ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['ws_sessions','ws_participants','ws_cards','ws_votes',
                           'ws_qw_ratings','ws_ideas','ws_idea_votes'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Verificación: deben salir 9 tablas con seguridad activa (rls = true)
select c.relname as tabla, c.relrowsecurity as rls,
       (select count(*) from pg_policies p where p.tablename = c.relname) as reglas
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'ws\_%' and c.relkind = 'r'
order by 1;
