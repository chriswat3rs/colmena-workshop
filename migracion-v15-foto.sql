-- COLMENA v1.5 · foto de perfil (solo si ya corriste setup.sql v1.5 sin la foto).
-- setup.sql completo también lo incluye: correr cualquiera de los dos da el mismo resultado.
alter table ws_admins add column if not exists avatar text;
alter table ws_admins drop constraint if exists ws_admins_avatar_check;
alter table ws_admins add constraint ws_admins_avatar_check
  check (avatar is null or (avatar ~ '^data:image/(webp|jpeg|png);base64,[A-Za-z0-9+/=]+$' and octet_length(avatar) <= 150000));

drop function if exists ws_me();
create function ws_me() returns table (role text, name text, email text, active boolean, avatar text)
language sql stable security definer set search_path = public as $$
  select a.role, a.name, a.email, a.active, a.avatar from ws_admins a
  where a.user_id = auth.uid() and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

create or replace function ws_set_my_avatar(p_avatar text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ws_is_admin() then raise exception 'Inicia sesión con tu segundo factor para cambiar tu foto'; end if;
  update ws_admins set avatar = nullif(p_avatar, '') where user_id = auth.uid();
end $$;

revoke execute on function ws_me(), ws_set_my_avatar(text) from public, anon;
grant execute on function ws_me(), ws_set_my_avatar(text) to authenticated;

select 'foto de perfil lista' as resultado,
       exists (select 1 from information_schema.columns where table_name='ws_admins' and column_name='avatar') as columna_avatar;
