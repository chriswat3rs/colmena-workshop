-- Colmena v1.15 · Talleres grandes (hasta ~200 personas en el plan gratis de Supabase)
-- Córrelo UNA vez en Supabase → SQL Editor → New query → pegar todo → Run. Se puede repetir sin problema.
-- Qué agrega: una consulta mínima («pulso») que usan los celulares en lugar de la conexión en tiempo real,
-- y dos índices para que las listas de ideas y tarjetas respondan rápido con mucha gente.
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

-- Verificación: debe salir ws_pulse
select proname from pg_proc where proname = 'ws_pulse';
