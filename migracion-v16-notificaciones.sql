-- COLMENA v1.6 · Centro de notificaciones (corre esto si ya tienes la v1.5; setup.sql completo también lo incluye)

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
    'Crea tu primer taller con una plantilla y proyecta el QR: la sala entra desde su celular.',
    jsonb_build_object('label','Crear mi primer taller','view','mine'), '{}', false, 'welcome:' || new.user_id);
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
    and coalesce(auth.jwt() ->> 'aal','') = 'aal2';
$$;
create or replace function ws_mark_all_read() returns void
language sql security definer set search_path = public as $$
  update ws_notifications set read_at = now()
  where user_id = auth.uid() and read_at is null and coalesce(auth.jwt() ->> 'aal','') = 'aal2';
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
  select a.email_prefs from ws_admins a where a.user_id = auth.uid() and coalesce(auth.jwt() ->> 'aal','') = 'aal2';
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
  using (user_id = auth.uid() and coalesce(auth.jwt() ->> 'aal','') = 'aal2');
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

-- URL de las funciones de ESTE proyecto (la usa la tarea programada de correos)
insert into ws_config (key, value) values ('functions_url', 'https://drgtkbievjlmhwzebzmg.supabase.co/functions/v1')
on conflict (key) do update set value = excluded.value;

-- Tiempo real para la campana
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ws_notifications') then
    alter publication supabase_realtime add table public.ws_notifications;
  end if;
end $$;

select 'centro de notificaciones listo' as resultado,
       (select count(*) from pg_trigger where tgname like 'ws_ev_%') as disparadores,
       (select string_agg(jobname, ', ') from cron.job where jobname like 'colmena-%') as tareas_programadas;
