-- COLMENA v1.7 · Inicio (dashboard), perfil editable (nombre y puesto) y creador paso a paso.
-- Corre esto si ya tienes la v1.6; setup.sql completo también lo incluye.

-- Puesto en el perfil
alter table ws_admins add column if not exists title text;
alter table ws_admins drop constraint if exists ws_admins_title_check;
alter table ws_admins add constraint ws_admins_title_check check (char_length(title) <= 120);

drop function if exists ws_me();
create function ws_me() returns table (role text, name text, email text, active boolean, avatar text, title text)
language sql stable security definer set search_path = public as $$
  select a.role, a.name, a.email, a.active, a.avatar, a.title from ws_admins a
  where a.user_id = auth.uid() and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
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

select 'inicio y perfil listos' as resultado;
