-- Colmena v2.5 · Eliminar mi cuenta (cada persona, desde Ajustes)
-- Córrela en Supabase → SQL Editor después de la v2.3.2. Se puede repetir sin problema.
-- Cada persona del equipo puede borrar su propia cuenta. Antes, sus talleres, borradores y lo que capturó
-- pasan a una persona admin activa (quien la invitó, si sigue siendo admin; si no, la admin más antigua),
-- para que el equipo no pierda resultados. Nadie puede dejar a Colmena sin una persona admin.
-- La cuenta en sí la borra la función «account» (acción self-delete) después de confirmar la contraseña.
-- Al final sale una fila: funciones = 3, version = 2.5.0
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.3.2') then
    raise exception 'Primero corre migracion-v232-mapa-interacciones.sql (v2.3.2) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,5,0] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- ¿Quién recibe los talleres de esta persona? Quien la invitó (si sigue siendo admin activa) o, si no,
-- la persona admin activa más antigua. Nunca ella misma. Vacío = no hay a quién pasarlos.
create or replace function ws_self_heir(p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select i.created_by from ws_invites i join ws_admins a on a.user_id = i.created_by
      where i.used_by = p_user and a.active and a.role = 'admin' and a.user_id <> p_user
      order by i.used_at desc nulls last limit 1),
    (select a.user_id from ws_admins a
      where a.active and a.role = 'admin' and a.user_id <> p_user
      order by a.created_at, a.user_id limit 1));
$$;
revoke execute on function ws_self_heir(uuid) from public, anon, authenticated;

-- Antes de confirmar: qué pasará (cuántos talleres y borradores, a quién pasan) o por qué no se puede.
create or replace function ws_self_remove_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v ws_admins; h ws_admins; v_heir uuid; n_ses int; n_dra int;
begin
  if not ws_is_admin() then raise exception 'Inicia sesión para eliminar tu cuenta'; end if;
  select * into v from ws_admins where user_id = auth.uid();
  select count(*) into n_ses from ws_sessions where owner_id = v.user_id;
  select count(*) into n_dra from ws_drafts where owner_id = v.user_id;
  v_heir := ws_self_heir(v.user_id);
  if v_heir is null then
    return jsonb_build_object('puede', false, 'rol', v.role, 'talleres', n_ses, 'borradores', n_dra,
      'motivo', case when v.role = 'admin' then 'ultimo_admin' else 'sin_admin' end);
  end if;
  select * into h from ws_admins where user_id = v_heir;
  return jsonb_build_object('puede', true, 'rol', v.role, 'talleres', n_ses, 'borradores', n_dra,
    'para', jsonb_build_object('nombre', coalesce(nullif(trim(h.name), ''), h.email), 'correo', h.email));
end $$;
revoke execute on function ws_self_remove_info() from public, anon;
grant execute on function ws_self_remove_info() to authenticated;

-- Con la sesión de la persona: sus talleres, borradores, lo capturado e invitaciones pendientes pasan a la
-- persona admin que los recibe, se cancelan las invitaciones para su correo y sale del equipo. Todo o nada.
-- Después, la función «account» borra su cuenta (ws_sessions y ws_drafts se borrarían en cascada con ella).
create or replace function ws_self_remove() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v ws_admins; h ws_admins; v_me uuid := auth.uid(); v_heir uuid; v_who text; v_body text;
        n_ses int := 0; n_dra int := 0; n_par int := 0;
begin
  if not ws_is_admin() then raise exception 'Inicia sesión para eliminar tu cuenta'; end if;
  -- Candado en orden fijo sobre las admins activas y la propia fila: dos bajas al mismo tiempo no dejan a Colmena sin admin
  perform 1 from ws_admins a where (a.active and a.role = 'admin') or a.user_id = v_me order by a.user_id for update;
  select * into v from ws_admins a where a.user_id = v_me;
  v_heir := ws_self_heir(v_me);
  if v_heir is null then
    if v.role = 'admin' then
      raise exception 'Eres la única persona admin de Colmena. Antes de eliminar tu cuenta, haz admin a alguien más en Equipo.';
    end if;
    raise exception 'No hay una persona admin activa que reciba tus talleres. Pide ayuda a quien administra Colmena.';
  end if;
  select * into h from ws_admins a where a.user_id = v_heir;
  v_who := coalesce(nullif(trim(v.name), ''), v.email, 'Alguien');

  update ws_sessions set owner_id = v_heir where owner_id = v_me;
  get diagnostics n_ses = row_count;
  update ws_drafts set owner_id = v_heir where owner_id = v_me;
  get diagnostics n_dra = row_count;
  -- Lo que capturó como participante con su cuenta del panel también pasa (si quien recibe ya participó
  -- en ese mismo taller, se conserva su registro y el de la persona se va con su cuenta)
  update ws_participants p set user_id = v_heir where p.user_id = v_me
     and not exists (select 1 from ws_participants q where q.session_id = p.session_id and q.user_id = v_heir);
  get diagnostics n_par = row_count;
  -- Invitaciones pendientes que mandó: ahora son de quien recibe; las que eran para su correo se cancelan
  update ws_invites set created_by = v_heir where created_by = v_me and used_at is null and revoked_at is null;
  update ws_invites set revoked_at = now()
   where lower(email) = lower(v.email) and used_at is null and revoked_at is null;
  delete from ws_admins where user_id = v_me;

  v_body := case when n_ses = 0 and n_dra = 0 then 'No tenía talleres ni borradores a su nombre.'
    else 'Ahora están a tu nombre ' || concat_ws(' y ',
           case when n_ses = 1 then 'su taller' when n_ses > 1 then 'sus ' || n_ses || ' talleres' end,
           case when n_dra = 1 then 'su borrador' when n_dra > 1 then 'sus ' || n_dra || ' borradores' end) || ', con todo lo capturado.' end;
  perform ws_notify(v_heir, 'member_left', v_who || ' eliminó su cuenta', v_body,
    case when n_ses + n_dra > 0 then jsonb_build_object('label', 'Ver mis talleres', 'view', 'mine') else jsonb_build_object('label', 'Ver equipo', 'view', 'team') end,
    jsonb_build_object('email', v.email), true, null);

  return jsonb_build_object('talleres', n_ses, 'borradores', n_dra, 'participaciones', n_par,
    'email', v.email, 'nombre', v.name,
    'para', jsonb_build_object('nombre', coalesce(nullif(trim(h.name), ''), h.email), 'correo', h.email));
end $$;
revoke execute on function ws_self_remove() from public, anon;
grant execute on function ws_self_remove() to authenticated;

insert into ws_schema_version(version) values ('2.5.0') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('ws_self_heir','ws_self_remove_info','ws_self_remove')) as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
