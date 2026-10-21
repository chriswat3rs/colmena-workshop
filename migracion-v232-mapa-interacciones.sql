-- Colmena v2.3.2 · Mapa de calor por acciones
-- Córrela en Supabase → SQL Editor después de la v2.3.1. Se puede repetir sin problema.
-- Registra nombres técnicos de acciones, nunca texto, respuestas, coordenadas ni contenido del DOM.
-- Al final sale una fila: funciones = 2, version = 2.3.2
-- ------------------------------------------------------------

do $$
declare v text;
begin
  if to_regclass('public.ws_schema_version') is null
     or not exists (select 1 from ws_schema_version where version = '2.3.1') then
    raise exception 'Primero corre migracion-v231-ultimo-acceso.sql (v2.3.1) y después esta migración.';
  end if;
  select version into v from ws_schema_version order by string_to_array(version, '.')::int[] desc limit 1;
  if v is not null and string_to_array(v, '.')::int[] > array[2,3,2] then
    raise exception 'Tu base ya está en la versión %; no corras una migración anterior.', v;
  end if;
end $$;

-- La misma entrada privada incorpora ui_action a su catálogo cerrado.
create or replace function ws_telemetry_ingest(p_events jsonb) returns int
language plpgsql security definer set search_path = public, auth as $$
declare
  e jsonb; n int := 0; sid uuid; cid uuid; en text; fl text; st text; dur int;
  typ text; akey text; props jsonb; allowed text[] := array[
    'app_open','view_opened','creator_started','creator_goal_selected','creator_context_completed',
    'creator_plan_ready','creator_reviewed','workshop_created','workshop_updated','workshop_opened',
    'phase_changed','onboarding_started','onboarding_step','onboarding_back',
    'onboarding_validation_failed','participant_joined','join_failed','phase_viewed','phase_completed',
    'action_succeeded','action_failed','validation_failed','retry','rage_click','app_error','ui_action'
  ]; allowed_actions text[] := array[
    'join_attempt','onboarding_start','onboarding_continue','onboarding_back','avatar_select','onboarding_area_select',
    'onboarding_role_select','onboarding_stage_select',
    'phase_start','notice_dismiss','mood_select','checkin_submit','checkin_edit','card_category_select',
    'card_task_select','card_tool_select','card_severity_select','card_publish','cards_complete','vote_add',
    'vote_remove','vote_filter','rating_select','validation_step_select','improvement_stage_select',
    'improvement_propose','validation_complete','validation_continue','validation_next_pending',
    'idea_challenge_select','idea_publish','ideas_complete','idea_support_add','idea_support_remove',
    'creator_start','creator_goal_select','creator_prepare','creator_back','creator_continue','creator_manual',
    'ai_retry','ai_regenerate','ai_adjust','ai_cover','workshop_open','qr_present','link_copy','phase_advance',
    'phase_open','workshop_edit','timer_open','results_present','results_share','results_export',
    'summary_generate','summary_edit','summary_copy','invite_start','invite_send','dashboard_open_list',
    'navigate_home','navigate_mine','navigate_all','navigate_team','navigate_analytics','navigate_ai'
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
        ('workshop_opened','onboarding_started','onboarding_step','onboarding_back','onboarding_validation_failed','participant_joined','join_failed','app_error','rage_click','ui_action')
        and not ws_is_member(sid) then continue; end if;

      fl := left(nullif(regexp_replace(coalesce(e->>'flow',''), '[^a-z0-9_-]', '', 'g'),''),32);
      st := left(nullif(regexp_replace(coalesce(e->>'step',''), '[^a-z0-9_-]', '', 'g'),''),48);
      dur := greatest(0, least(86400000, coalesce((e->>'duration_ms')::int,0)));
      props := coalesce(e->'properties','{}'::jsonb);
      if jsonb_typeof(props) <> 'object' then props := '{}'::jsonb; end if;
      props := (select coalesce(jsonb_object_agg(key, to_jsonb(left(value,80))), '{}'::jsonb)
                from jsonb_each_text(props)
                where key in ('method','action','reason','target','from','to','result','source','count'));
      if en = 'ui_action' and not (coalesce(props->>'action','') = any(allowed_actions)) then continue; end if;

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

-- Agregado para el mapa: acción técnica, pantalla, audiencia y dispositivo.
-- El detalle, el actor_key y el client_id nunca salen de PostgreSQL.
create or replace function ws_interaction_map(p_from timestamptz default now()-interval '30 days', p_to timestamptz default now(), p_session uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not ws_is_superadmin() then raise exception 'Solo un admin puede ver el mapa de interacciones'; end if;
  p_from := greatest(coalesce(p_from,now()-interval '30 days'), now()-interval '90 days');
  p_to := least(coalesce(p_to,now()), now()+interval '1 day');
  if p_to <= p_from then raise exception 'Periodo no válido'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.interactions desc, x.step, x.action),'[]'::jsonb) into out
  from (
    select case when e.actor_type='participant' then 'participant'
                when e.flow='creator' then 'creator' else 'facilitator' end as audience,
           coalesce(e.flow,'app') as flow, coalesce(e.step,'app') as step,
           e.properties->>'action' as action, e.device_family as device,
           count(*) as interactions, count(distinct e.client_id) as journeys,
           count(distinct e.session_id) as workshops
    from ws_telemetry_events e
    where e.event_name='ui_action' and e.occurred_at>=p_from and e.occurred_at<p_to
      and (p_session is null or e.session_id=p_session)
      and nullif(e.properties->>'action','') is not null
    group by 1,2,3,4,5
    order by 6 desc limit 300
  ) x;
  return out;
end $$;

revoke execute on function ws_interaction_map(timestamptz,timestamptz,uuid) from public, anon;
grant execute on function ws_interaction_map(timestamptz,timestamptz,uuid) to authenticated;

insert into ws_schema_version(version) values ('2.3.2') on conflict (version) do nothing;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('ws_telemetry_ingest','ws_interaction_map')) as funciones,
  (select version from ws_schema_version order by string_to_array(version,'.')::int[] desc limit 1) as version;
