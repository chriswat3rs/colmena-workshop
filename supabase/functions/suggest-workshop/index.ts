// Colmena v1.23 · suggest-workshop (v1.12.2: verificación con tiempo límite y reintento; v1.21: registro de tokens, pausa y tope por persona;
//   v1.23: resumen con IA de los resultados de un taller, acción «summary»; v1.26: mensaje claro si la cuenta de Anthropic se queda sin saldo;
//   v2.0: el resumen usa las palabras del tipo de taller y viene en puntos con etiqueta;
//   v2.8: reglas por tipo de taller sin inventar consenso ni huecos, y acción «deliverable»: definiciones sugeridas
//         para el modelo de competencias, una vez por taller;
//   v2.11: si la base no contesta al revisar los límites, NO se llama a la IA; el resumen y las definiciones respetan
//         la pausa y el tope mensual, y su «una vez por taller» se aparta en un solo paso (ws_ai_once); cada renglón de
//         Uso de IA se cierra con done_at aunque la IA falle. Requiere migracion-v2-11-cuenta-e-ia.sql)
// Con un formulario corto del facilitador (cliente, proceso, qué duele, objetivo, gente, duración…) devuelve
// una PROPUESTA completa del taller. La IA decide el contenido; el código decide números, topes y estructura.
// La página la muestra para revisar y editar: nada se crea solo.
// Seguridad: solo un facilitador o admin activo. La llave nunca sale de aquí. Máximo 30 propuestas por persona al día.
// v1.21 · Antes de llamar a la IA pregunta a ws_ai_begin (pausa y tope mensual que pone el admin) y, al terminar, guarda los
//         tokens de entrada y salida en ws_ai_log con la llave de servidor (la persona no puede alterar su propio consumo).
// Secretos (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY = sk-ant-api03-…   (console.anthropic.com → API keys)
//   AI_MODEL          = claude-haiku-4-5-20251001   (opcional; Haiku: ~1 centavo de dólar por propuesta)
//   AI_MAX_TOKENS     = 2200   (opcional; tope de la respuesta)
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// v1.26 · La cuenta de Anthropic se quedó sin saldo (Anthropic responde 400 «credit balance is too low»)
const MSG_NO_CREDIT = "La IA de Colmena se quedó sin saldo. Avísale a tu admin: se recarga en console.anthropic.com → Plans & Billing.";
const MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-4-5-20251001";
const MAX_TOKENS = Math.min(3000, Math.max(1200, Number(Deno.env.get("AI_MAX_TOKENS")) || 2200));

/* v1.12.2 · Tiempos límite. La página espera 45 s; la función siempre contesta antes. */
const RPC_TIMEOUT_MS = 6000;   // cada intento de hablar con la base (ws_me, ws_ai_begin, ws_ai_once)
const DEADLINE_MS = 38000;     // tope total de la función (incluye a la IA)
const MSG_RETRY = "No pudimos verificar tu cuenta, intenta de nuevo.";
const MSG_DENIED = "Solo facilitadores activos pueden pedir propuestas";
const MSG_FAIL = "No pudimos armar la propuesta esta vez. Intenta de nuevo o ármala a mano.";

/* Deja una línea en Supabase → Edge Functions → suggest-workshop → Logs */
const logErr = (o: Record<string, unknown>) => console.error(JSON.stringify({ fn: "suggest-workshop", ...o }));

type RpcOut = { data: unknown; error: { message?: string; code?: string; details?: string } | null; status: number; transient: boolean; ms: number };

/* Llama una función de la base con tiempo límite. Si falla por red, tiempo agotado o error del servidor
   (status 0, 408, 429 o 5xx) reintenta `retries` veces. Un error «de permiso» (401/403/4xx) no se reintenta. */
// deno-lint-ignore no-explicit-any
async function callRpc(sb: any, fn: string, retries: number, req: string, args?: Record<string, unknown>): Promise<RpcOut> {
  let out: RpcOut = { data: null, error: null, status: 0, transient: false, ms: 0 };
  for (let attempt = 0; attempt <= retries; attempt++) {
    const t0 = Date.now();
    try {
      const { data, error, status } = await sb.rpc(fn, args).abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
      out = { data, error, status: Number(status) || 0, transient: false, ms: Date.now() - t0 };
    } catch (e) {   // por si alguna versión de supabase-js lanza en vez de devolver { error }
      out = { data: null, error: { message: String((e as Error)?.message || e) }, status: 0, transient: true, ms: Date.now() - t0 };
    }
    if (!out.error) return out;
    out.transient = out.status === 0 || out.status === 408 || out.status === 429 || out.status >= 500;
    logErr({ req, rpc: fn, attempt: attempt + 1, of: retries + 1, status: out.status, ms: out.ms, transient: out.transient,
      code: out.error.code ?? "", message: String(out.error.message ?? "").slice(0, 300), details: String(out.error.details ?? "").slice(0, 300) });
    if (!out.transient || attempt === retries) return out;
    await new Promise((r) => setTimeout(r, 400 + Math.random() * 400));
  }
  return out;
}

const SYSTEM = `Eres el asistente de Colmena (Quality & Knowledge, CDMX). Diseñas talleres de design thinking en vivo: los participantes, desde su celular, publican dolores por etapa del proceso, votan, califican quick wins y reglas del nuevo flujo, estiman cuánto tarda cada etapa y proponen ideas para los dolores más votados.
Con los datos del facilitador propón el contenido del taller en español de México, con el vocabulario del cliente. Específico y verosímil, nunca genérico.
Responde SOLO un objeto JSON, sin markdown ni texto extra, con esta forma:
{"name":"Cliente · Proceso","caso":"un|una + unidad del proceso","areas":[""],"roles":[""],
"stages":[{"n":"Verbo + objeto","tasks":["",""],"tools":[""]}],
"qw":[{"s":1,"t":"","h":""}],"gates":[{"s":1,"t":"","h":""}],
"q":{"checkin":"","expect":"","pain":"","idea":""}}
Reglas:
- stages: en orden real, del inicio al fin indicado; "n" = infinitivo + objeto, 2 a 5 palabras, sin número. Puedes cerrar con "Transversal (tema)". No pases el máximo de etapas.
- tasks: 2 a 3 acciones concretas por etapa (infinitivo). tools: 1 a 3 sistemas, archivos o formatos (sustantivos); usa los nombres que dé el facilitador.
- "s" = número de etapa (1 = primera).
- qw: cambios concretos y rápidos (qué cambia y dónde), máximo 2 por etapa; al menos uno por cada dolor mencionado. "h": qué pasa hoy y qué cambiaría, una frase.
- gates: candados que un sistema pueda exigir: "No se X sin Y", "X se cierra solo con Y", "Máximo N horas para X". Nada de "procurar" o "fomentar".
- areas: equipos (incluye los que dé el facilitador); roles: puestos, no áreas.
- q.pain: invita a contar qué roba tiempo o frustra en ESTE proceso, nombrándolo. q.idea: empieza con "¿Cómo podríamos" y sirve para cualquier dolor (no nombres uno). checkin y expect: cortas.
- Usa el trato indicado (tú o usted). Textos de 100 caracteres como máximo; "h" de 120. Sin comillas tipográficas.
Ejemplo de estilo (otro proceso, no lo copies):
{"n":"Dictaminar el siniestro","tasks":["Revisar fotos y presupuesto","Asignar ajustador"],"tools":["Portal de talleres","SISE"]}
qw {"s":3,"t":"Presupuesto de taller con formato único en el portal","h":"Hoy cada taller manda su Excel y se recaptura."}
gate {"s":3,"t":"No se dictamina sin fotos y presupuesto completos","h":"El caso no avanza y el portal avisa al taller."}`;

type Fields = { cliente: string; industria: string; proceso: string; dolor: string; objetivo: string;
  gente: string; duracion: string; participantes: string[]; herramientas: string; trato: string };

const clean = (v: unknown) => String(v ?? "").replace(/[“”«»]/g, '"').replace(/[‘’]/g, "'")
  .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/gu, "").replace(/\s+/g, " ").trim();
/* corta en palabra completa */
const cut = (v: unknown, max: number) => { const s = clean(v); if (s.length <= max) return s; const c = s.slice(0, max); const i = c.lastIndexOf(" "); return (i > max * 0.6 ? c.slice(0, i) : c).replace(/[,;:.\-–]+$/, "").trim(); };
const list = (v: unknown, max: number, len = 60) => (Array.isArray(v) ? v : []).map((x) => cut(x, len)).filter(Boolean).slice(0, max);
const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9ñ ]/g, " ").replace(/\s+/g, " ").trim();
const uniq = (a: string[]) => { const seen = new Set<string>(); return a.filter((x) => { const k = norm(x); if (!k || seen.has(k)) return false; seen.add(k); return true; }); };
const words = (s: string) => new Set(norm(s).split(" ").filter((w) => w.length > 3));
const jaccard = (a: string, b: string) => { const A = words(a), B = words(b); if (!A.size || !B.size) return 0; let i = 0; A.forEach((w) => { if (B.has(w)) i++; }); return i / (A.size + B.size - i); };
const isInf = (w: string) => /^[a-záéíóúñ]+(ar|er|ir)(se|lo|la|los|las)?$/i.test(w || "");
const stripNum = (s: string) => s.replace(/^\s*\d+[\s.)-]*/, "").trim();
const isTrans = (s: string) => /^transversal/i.test(stripNum(s));

/* Topes y números que decide el código (no la IA) */
function limits(f: Fields) {
  const dur = f.duracion === "60" ? 60 : f.duracion === "120" ? 120 : f.duracion === "240" ? 240 : 90;
  const gente = f.gente === "10" ? 10 : f.gente === "50" ? 50 : f.gente === "60" ? 60 : 25;
  const maxStages = dur === 60 ? 5 : dur === 90 ? 6 : dur === 120 ? 7 : 8;
  let maxQw = f.objetivo === "priorizar" ? 8 : 7; if (dur === 60) maxQw = 5;
  let maxGates = f.objetivo === "validar" ? 6 : 4; if (dur === 60) maxGates = 3;
  const cartasPP = dur === 60 ? 2 : 3;
  const votes = Math.min(6, Math.max(3, Math.round(1.6 * cartasPP) - (gente > 25 ? 1 : 0)));
  return { dur, gente, maxStages, maxQw, maxGates, votes, ideaTop: dur === 60 ? 2 : 3, ideaVotes: 3 };
}
const OBJ: Record<string, string> = {
  dolores: "Encontrar dolores y quick wins", validar: "Validar un nuevo flujo (más reglas del nuevo flujo)",
  priorizar: "Priorizar mejoras (más quick wins)", sistema: "Arrancar un sistema (reglas y herramientas claras)",
};
function userMsg(f: Fields, L: ReturnType<typeof limits>, adjust: string, keep: string[]) {
  return [
    `Cliente: ${f.cliente}${f.industria ? ` (${f.industria})` : ""}`,
    `Proceso: ${f.proceso}`,
    `Qué duele hoy: ${f.dolor}`,
    `Objetivo: ${OBJ[f.objetivo] || OBJ.dolores}`,
    f.participantes.length ? `En la sala: ${f.participantes.join(", ")}` : "",
    f.herramientas ? `Herramientas conocidas: ${f.herramientas}` : "",
    `Trato: ${f.trato === "usted" ? "usted" : "tú"}`,
    `Máximo: ${L.maxStages} etapas, ${L.maxQw} quick wins, ${L.maxGates} reglas.`,
    adjust ? `Ajuste pedido: ${adjust}` : "",
    adjust && keep.length ? `Etapas actuales: ${keep.map((s, i) => `${i + 1} ${stripNum(s)}`).join("; ")} (consérvalas salvo que el ajuste diga lo contrario)` : "",
  ].filter(Boolean).join("\n");
}

/* Deja la propuesta en el formato exacto de Colmena y corrige lo que no cuadre (nunca pregunta) */
function normalize(raw: any, f: Fields, L: ReturnType<typeof limits>) {
  const rawSt = (Array.isArray(raw?.stages) ? raw.stages : []).map((x: any) => typeof x === "string" ? { n: x } : x || {});
  // etapas: sin número, sin repetir, la transversal al final
  const seen = new Set<string>(); let st: any[] = [];
  rawSt.forEach((x: any, i: number) => { const n = cut(stripNum(String(x.n || x.name || "")), 50); const k = norm(n);
    if (!n || seen.has(k) || /^(otros?|general|varios)$/i.test(n)) return; seen.add(k); st.push({ ...x, n, src: i + 1 }); });
  const trans = st.filter((x) => isTrans(x.n)).slice(0, 1); st = st.filter((x) => !isTrans(x.n)).slice(0, L.maxStages).concat(trans);
  if (st.filter((x) => !isTrans(x.n)).length < 3) return null;
  let k = 0; const names = st.map((x) => isTrans(x.n) ? x.n : `${++k} ${x.n}`);
  const bySrc = new Map<number, string>(); st.forEach((x, i) => bySrc.set(x.src, names[i]));
  const tasks: Record<string, string[]> = {}, tools: Record<string, string[]> = {};
  st.forEach((x, i) => {
    let tl = uniq(list(x.tools, 6, 40)); const moved = tl.filter((t) => isInf(t.split(" ")[0])); tl = tl.filter((t) => !moved.includes(t));
    const ts = uniq(list(x.tasks, 4, 80).concat(moved)).filter((t) => norm(t) !== norm(x.n)).slice(0, 3);
    if (ts.length) tasks[names[i]] = ts; if (tl.length) tools[names[i]] = tl.slice(0, 3);
  });
  // quick wins y reglas ligadas a etapa por número; si no cuadra, por parecido; si nada, general ("")
  const stageOf = (q: any) => { const s = Number(q?.s); if (bySrc.has(s)) return bySrc.get(s)!;
    let best = "", sc = 0.2; names.forEach((n) => { const v = Math.max(jaccard(String(q?.t || ""), n), ...(tasks[n] || []).map((t) => jaccard(String(q?.t || ""), t))); if (v > sc) { sc = v; best = n; } }); return best; };
  const items: any[] = [];
  const take = (arr: any, kind: "qw" | "gate", max: number) => {
    const per: Record<string, number> = {}; let n = 0;
    for (const q of (Array.isArray(arr) ? arr : [])) {
      const text = cut(q?.t || q?.text, 100); if (!text || n >= max) continue;
      if (items.some((o) => jaccard(o.text, text) > 0.6 || norm(o.text) === norm(text))) continue;
      const stage = stageOf(q); if (stage && (per[stage] || 0) >= 2) continue;
      per[stage] = (per[stage] || 0) + 1; n++;
      const help = cut(q?.h || q?.help, 120);
      items.push({ kind, stage, text, ...(help ? { help } : {}) });
    }
  };
  take(raw?.qw, "qw", L.maxQw); take(raw?.gates, "gate", L.maxGates);
  names.filter((n) => !isTrans(n)).forEach((n) => items.push({ kind: "time", stage: n, text: stripNum(n) }));
  const q = raw?.q || {};
  let idea = cut(q.idea, 140); if (!/^¿?c[oó]mo podr[ií]amos/i.test(idea)) idea = "¿Cómo podríamos resolverlo?"; if (!idea.startsWith("¿")) idea = "¿" + idea;
  const usted = f.trato === "usted";
  let caso = cut(raw?.caso, 40); if (!/^(un|una)\s/i.test(caso)) caso = "un caso";
  return {
    name: cut(raw?.name, 80) || cut(`${f.cliente} · ${f.proceso}`, 80), caso,
    areas: uniq(f.participantes.concat(list(raw?.areas, 8, 50))).slice(0, 8),
    roles: uniq(list(raw?.roles, 6, 50)).filter((r) => !f.participantes.some((p) => norm(p) === norm(r))),
    stages: names, tasks, tools, quickwins: items,
    q_checkin: cut(q.checkin, 70) || (usted ? "¿Cómo llega a este taller?" : "¿Cómo llegas a este taller?"),
    q_expect: cut(q.expect, 70) || (usted ? "En una frase: ¿qué espera de este taller?" : "En una frase: ¿qué esperas de este taller?"),
    q_pain: cut(q.pain, 200) || `Piensa en tu día a día en ${f.proceso}. ¿Qué es lo que más tiempo te roba o más te frustra?`,
    q_idea: idea, votes_per_user: L.votes, idea_votes: L.ideaVotes, idea_top: L.ideaTop, ai: true,
  };
}
/* Recupera el JSON aunque venga cortado o con texto alrededor */
function parse(text: string) {
  const t = ("{" + text).replace(/```(?:json)?/gi, "").trim();
  try { return JSON.parse(t); } catch { /* sigue */ }
  let depth = 0, inStr = false, esc = false, last = -1;
  for (let i = 0; i < t.length; i++) { const c = t[i];
    if (inStr) { if (esc) esc = false; else if (c === "\\") esc = true; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true; else if (c === "{" || c === "[") depth++; else if (c === "}" || c === "]") { depth--; if (depth === 2 && c === "}") last = i; if (depth === 0) { try { return JSON.parse(t.slice(0, i + 1)); } catch { break; } } } }
  // respuesta cortada por tope: cerrar en el último objeto completo de una lista
  if (last > 0) { const head = t.slice(0, last + 1); for (const tail of ["]}", "]}}", "]}]}"]) { try { return JSON.parse(head + tail); } catch { /* otro */ } } }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });
  const t0 = Date.now(), reqId = crypto.randomUUID().slice(0, 8);
  try {
    return await handle(req, t0, reqId);
  } catch (e) {
    // Nunca dejar escapar una excepción: sin esto la respuesta sale sin CORS y la página la lee como «sin conexión».
    logErr({ req: reqId, unhandled: String((e as Error)?.stack || e).slice(0, 800) });
    return json(500, { error: MSG_FAIL, req: reqId });
  }
});

async function handle(req: Request, t0: number, reqId: string): Promise<Response> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión" });
  const apiKey = (Deno.env.get("ANTHROPIC_API_KEY") || "").replace(/\s+/g, "");

  let body: { fields?: Partial<Fields>; brief?: string; adjust?: string; keepStages?: string[]; ping?: boolean; regen?: boolean; draft_id?: string; label?: string; action?: string; session_id?: string; stats?: unknown; items?: unknown };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }

  const pubKey = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, pubKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });

  // 1) ¿Quién llama? Tiempo límite + 1 reintento. Un problema de red NO es «no tienes permiso».
  const me = await callRpc(sb, "ws_me", 1, reqId);
  if (me.error) {
    if (me.transient) return json(503, { error: MSG_RETRY, retry: true, req: reqId });
    if (me.status === 401) return json(401, { error: "Tu sesión expiró. Entra de nuevo.", req: reqId });
    if (me.status === 404 || me.error.code === "PGRST202")
      return json(500, { error: "Falta actualizar la base de datos (función ws_me). Avísale al admin.", req: reqId });
    return json(403, { error: MSG_DENIED, req: reqId });
  }
  const row = (Array.isArray(me.data) ? me.data[0] : me.data) as { role?: string; active?: boolean } | null | undefined;
  if (!row || !row.role || row.active === false) {
    console.warn(JSON.stringify({ fn: "suggest-workshop", req: reqId, denied: !row
      ? "ws_me vacío: la cuenta no es del equipo o la sesión no es fuerte (aal2 / llave aprobada)"
      : row.active === false ? "cuenta desactivada" : "sin rol", ms: me.ms }));
    return json(403, { error: MSG_DENIED, req: reqId });
  }

  if (body.ping) return json(200, { enabled: !!apiKey, model: apiKey ? MODEL : null });
  if (!apiKey) return json(501, { error: "La IA no está disponible por ahora. Puedes armar el taller a mano con lo que escribiste." });
  if (body.action === "summary") return await summarize(sb, auth, body, apiKey, reqId, t0);
  if (body.action === "deliverable") return await deliverable(sb, auth, body, apiKey, reqId, t0);

  const F = body.fields || {};
  const f: Fields = {
    cliente: cut(F.cliente, 120), industria: cut(F.industria, 40), proceso: cut(F.proceso, 120), dolor: cut(F.dolor, 300),
    objetivo: ["dolores", "validar", "priorizar", "sistema"].includes(String(F.objetivo)) ? String(F.objetivo) : "dolores",
    gente: cut(F.gente, 4), duracion: cut(F.duracion, 4), participantes: uniq(list(F.participantes, 8, 40)),
    herramientas: cut(F.herramientas, 150), trato: F.trato === "usted" ? "usted" : "tu",
  };
  if (!F.cliente && body.brief) { f.proceso = cut(body.brief, 120); f.dolor = cut(body.brief, 300); f.cliente = "Cliente"; }   // compatibilidad
  if ((f.cliente + f.proceso + f.dolor).length < 40 || f.cliente.length < 2 || f.proceso.length < 3)
    return json(400, { error: "Cuéntanos un poco más del proceso o de lo que duele." });
  const adjust = cut(body.adjust, 200), keep = list(body.keepStages, 10, 60);

  // 2) Límite diario por persona (30). Sin reintento (cada intento cuenta).
  //    v1.21 · ws_ai_begin además revisa la pausa y el tope mensual que pone el admin, y deja el renglón para los tokens.
  //    v2.11 · Si la base no contesta o falta la función, NO se llama a la IA (antes seguía sin límites y sin registrar
  //            los tokens). Los pedidos de una misma persona pasan de uno en uno por ws_ai_begin.
  const uuidOk = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const kind = adjust ? "ajuste" : body.regen ? "otra" : "propuesta";
  const label = cut(body.label || [f.cliente, f.proceso].filter(Boolean).join(" · "), 160);
  const beg = await callRpc(sb, "ws_ai_begin", 0, reqId, { p_kind: kind, p_draft: uuidOk.test(String(body.draft_id || "")) ? body.draft_id : null, p_label: label });
  if (beg.error) {
    if (beg.transient) return json(503, { error: MSG_RETRY, retry: true, req: reqId });
    if (beg.status === 404 || beg.error.code === "PGRST202")
      return json(500, { error: "Falta actualizar la base de datos (función ws_ai_begin). Avísale al admin.", req: reqId });
    return json(403, { error: MSG_DENIED, req: reqId });
  }
  const b = (beg.data || {}) as { ok?: boolean; reason?: string; id?: number; used?: number; cap?: number | null };
  if (!b.ok) {
    if (b.reason === "paused") return json(403, { error: "Tu admin pausó la IA para tu cuenta. Puedes armar el taller a mano.", ai: "paused" });
    if (b.reason === "cap") return json(429, { error: `Llegaste a tu tope de IA de este mes (${Number(b.cap || 0).toLocaleString("es-MX")} tokens). Pídele a tu admin que lo amplíe o arma el taller a mano.`, ai: "cap" });
    if (b.reason === "daily") return json(429, { error: "Llegaste al límite de propuestas de hoy. Mañana se renueva." });
    return json(403, { error: MSG_DENIED, req: reqId });
  }
  const logId = Number(b.id) || null, usedBefore = Number(b.used) || 0, cap = b.cap ?? null;
  if (!logId) return json(503, { error: MSG_RETRY, retry: true, req: reqId });

  // 3) La IA, con tope de tiempo: la función contesta antes de que la página se rinda
  const L = limits(f);
  const left = () => DEADLINE_MS - (Date.now() - t0);
  const call = (temperature: number) => fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: MAX_TOKENS, temperature, system: SYSTEM,
      messages: [{ role: "user", content: userMsg(f, L, adjust, keep) }, { role: "assistant", content: "{" }] }),
    signal: AbortSignal.timeout(Math.max(1000, left())),
  });
  // deno-lint-ignore no-explicit-any
  let usage: any = null, draft: any = null;
  // v2.11 · El renglón de Uso de IA se cierra siempre (también si la IA falla o tarda): tokens, si salió bien y done_at
  try {
    const temps = [body.regen ? 0.8 : 0.5, 0.3];
    for (let i = 0; i < temps.length; i++) {
      if (i > 0 && left() < 10000) { logErr({ req: reqId, anthropic: "sin tiempo para el segundo intento", ms: Date.now() - t0 }); break; }
      // deno-lint-ignore no-explicit-any
      let out: any;
      try {
        const r = await call(temps[i]);
        if (!r.ok) {
          const t = await r.text(); logErr({ req: reqId, anthropic: r.status, body: t.slice(0, 300) });
          const msg = r.status === 401 ? "La llave de la IA no es válida: revísala en Supabase → Edge Functions → Secrets."
            : r.status === 429 || r.status === 529 ? "La IA está ocupada. Intenta en un minuto."
            : r.status === 400 && /credit/i.test(t) ? MSG_NO_CREDIT
            : MSG_FAIL;
          return json(r.status === 429 || r.status === 529 ? 429 : 502, { error: msg, req: reqId });
        }
        out = await r.json();
      } catch (e) {
        const name = String((e as Error)?.name || ""), timeout = /Timeout|Abort/i.test(name);
        logErr({ req: reqId, anthropic: "fetch", name, timeout, ms: Date.now() - t0, message: String((e as Error)?.message || e).slice(0, 300) });
        if (timeout) return json(504, { error: "La IA tardó demasiado en responder. Intenta de nuevo o arma el taller a mano.", retry: true, req: reqId });
        if (e instanceof TypeError) return json(503, { error: "No pudimos conectar con la IA. Intenta de nuevo en un momento.", retry: true, req: reqId });
        return json(502, { error: MSG_FAIL, req: reqId });
      }
      usage = out?.usage || null;
      const text = (out?.content || []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
      const raw = parse(text);
      draft = raw ? normalize(raw, f, L) : null;
      if (out?.stop_reason === "max_tokens") console.warn("max_tokens", usage);
      if (draft) break;
    }
    if (!draft) return json(502, { error: MSG_FAIL, req: reqId });
    const tin = Number(usage?.input_tokens) || 0, tout = Number(usage?.output_tokens) || 0;
    return json(200, { draft, model: MODEL, usage, ai: { used: usedBefore + tin + tout, cap } });
  } finally {
    // v1.21 · Guardar los tokens (aunque la propuesta no haya salido bien: también se cobraron)
    await finishLog(logId, reqId, { tin: Number(usage?.input_tokens) || 0, tout: Number(usage?.output_tokens) || 0, ok: !!draft });
  }
}

/* v2.11 · Cierra el renglón de Uso de IA con los tokens, el modelo, si salió bien y cuándo terminó (done_at).
   Si la base aún no tiene done_at (falta la migración), guarda lo demás para no perder el registro de tokens. */
async function finishLog(logId: number | null, reqId: string, v: { tin: number; tout: number; ok: boolean; session_id?: string }) {
  if (!logId) return;
  try {
    const svc = createClient(Deno.env.get("SUPABASE_URL")!, serverKey(), { auth: { persistSession: false, autoRefreshToken: false } });
    const row: Record<string, unknown> = { input_tokens: v.tin, output_tokens: v.tout, model: MODEL, ok: v.ok, done_at: new Date().toISOString() };
    if (v.session_id) row.session_id = v.session_id;
    let { error } = await svc.from("ws_ai_log").update(row).eq("id", logId);
    if (error && /done_at/.test(String(error.message || ""))) {
      delete row.done_at;
      ({ error } = await svc.from("ws_ai_log").update(row).eq("id", logId));
    }
    if (error) logErr({ req: reqId, usage_log: String(error.message || error).slice(0, 200) });
  } catch (e) { logErr({ req: reqId, usage_log: String((e as Error)?.message || e).slice(0, 200) }); }
}

/* v2.11 · Antes de gastar tokens en el resumen o en las definiciones: ws_ai_once, con la sesión de quien facilita,
   revisa que el taller sea suyo, la pausa y el tope del mes que pone el admin, y aparta en un solo paso su «una vez
   por taller» (dos pedidos al mismo tiempo ya no generan dos llamadas). Si la base no contesta, NO se llama a la IA. */
// deno-lint-ignore no-explicit-any
async function aiOnce(sb: any, sid: string, kind: "insights" | "entregable", reqId: string): Promise<number | Response> {
  const r = await callRpc(sb, "ws_ai_once", 0, reqId, { p_session: sid, p_kind: kind });
  if (r.error) {
    if (r.transient) return json(503, { error: MSG_RETRY, retry: true, req: reqId });
    if (r.status === 404 || r.error.code === "PGRST202")
      return json(500, { error: "Falta correr migracion-v2-11-cuenta-e-ia.sql en Supabase. Avísale al admin.", req: reqId });
    return json(403, { error: MSG_DENIED, req: reqId });
  }
  const b = (r.data || {}) as { ok?: boolean; reason?: string; id?: number; cap?: number | null };
  if (b.ok && Number(b.id)) return Number(b.id);
  const sum = kind === "insights";
  if (b.reason === "once") return json(409, { ai: "once", error: sum
    ? "Este taller ya tiene su resumen con IA. Puedes editarlo, pero no volver a generarlo."
    : "Este taller ya usó sus definiciones con IA. Puedes editarlas, pero no volver a pedirlas." });
  if (b.reason === "busy") return json(409, { ai: "busy", retry: true, error: "La IA ya está trabajando en este taller. Espera unos segundos y vuelve a intentarlo." });
  if (b.reason === "paused") return json(403, { ai: "paused", error: "Tu admin pausó la IA para tu cuenta." });
  if (b.reason === "cap") return json(429, { ai: "cap", error: `Llegaste a tu tope de IA de este mes (${Number(b.cap || 0).toLocaleString("es-MX")} tokens). Pídele a tu admin que lo amplíe.` });
  return json(403, { req: reqId, error: sum ? "Solo quien facilita el taller puede generar el resumen." : "Solo quien facilita el taller puede pedir las definiciones." });
}

function serverKey() {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); return String(Object.values(k)[0] || ""); } catch { return ""; }
}

/* v1.23 · Resumen ejecutivo de los resultados de un taller. Solo quien lo facilita; cuenta como «insights» en Uso de IA.
   v1.26 · Una sola regla: se genera UNA vez por taller terminado (Resultados o Cierre). El servidor guarda el resumen.
   v2.11 · Lo frenan la pausa y el tope mensual que pone el admin (el límite diario de propuestas no) y su «una vez»
           se aparta en la base antes de llamar a la IA (ws_ai_once). Sus tokens se registran en Uso de IA. */
const SUMMARY_SYSTEM = `Eres analista de Colmena (Quality & Knowledge). Con los resultados de un taller escribe un resumen ejecutivo en español de México para quien facilitó y para el cliente.
Formato (respétalo exactamente, sin títulos, saludos ni despedidas):
- Primera línea: una sola oración de contexto (quiénes participaron y qué se trabajó), máximo 30 palabras.
- Después, de 3 a 4 líneas que empiecen con "- " y una etiqueta corta en **negritas** seguida de dos puntos, por ejemplo: - **Dónde duele:** … Cada línea es una sola oración.
- Máximo 130 palabras en total.
Reglas:
- Usa solo los datos que recibes. No inventes cifras, causas, nombres ni recomendaciones que no se desprendan de los datos. Si un dato no viene, no lo menciones.
- Consenso: di que la sala coincide o que hay consenso solo si votaron 3 personas o más (votos.votantes) y retosPct o elegidosPct es 35 o más. Si es menor a 35, di que los votos quedaron repartidos. Si votaron menos de 3 personas, di que aún hay pocos votos y no hables de consenso ni de prioridades firmes.
- No inventes huecos: no digas que algo falta, que hay una brecha, una debilidad o un área de oportunidad si los datos no lo dicen.
- Si los datos no traen «tipo», es un taller de mejora de procesos. Cubre, si hay datos: dónde se concentra el dolor (etapas), el reto más votado y si los votos quedaron repartidos (retosPct menor a 35), las mejoras con más respaldo con su índice 0–100, las reglas con fricción (índice menor a 50) y la etapa más lenta.
- Si los datos traen «tipo», usa las palabras de «palabras» y no hables de dolores, retos ni etapas. Cubre, si hay datos, según «clave»:
  · comp (Definir competencias): las competencias elegidas, cuántos comportamientos forman cada una y la propuesta más apoyada de cómo se ve. La sala describió lo que hace bien alguien en ese rol: no evaluó a nadie, así que no digas que el equipo o una persona tiene o no tiene una competencia.
  · diag (Diagnóstico): qué domina entre lo que funciona y lo que estorba (tarjetas.porCategoria), los temas elegidos y lo más apoyado de qué haríamos.
  · ideas (Lluvia de ideas): las ideas elegidas, cuántas ideas parecidas juntó cada una y los pasos más apoyados.
  · retro (Retrospectiva): el balance entre lo que funcionó, lo que no funcionó y lo que aprendimos (tarjetas.porCategoria), los temas elegidos y las acciones más apoyadas.
  · En cualquier tipo: si los votos quedaron repartidos (elegidosPct menor a 35), dilo.
- Fuera de las etiquetas, resalta con **negritas** como máximo una frase clave por línea.
- Tono claro, concreto y profesional.`;

function jwtSub(auth: string): string {
  try { const p = auth.replace(/^Bearer\s+/i, "").split(".")[1]; const j = JSON.parse(atob(p.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(p.length / 4) * 4, "="))); return String(j.sub || ""); } catch { return ""; }
}

// deno-lint-ignore no-explicit-any
async function summarize(sb: any, auth: string, body: any, apiKey: string, reqId: string, t0: number): Promise<Response> {
  const sid = String(body.session_id || "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sid)) return json(400, { error: "Solicitud inválida" });
  const { data: ses, error: se } = await sb.from("ws_sessions").select("id,name,owner_id,phase").eq("id", sid).maybeSingle();
  if (se) { logErr({ req: reqId, summary: "ws_sessions", message: String(se.message || se).slice(0, 200) }); return json(503, { error: MSG_RETRY, retry: true, req: reqId }); }
  if (!ses) return json(404, { error: "No encontramos el taller." });
  const uid = jwtSub(auth);
  if (ses.owner_id !== uid) return json(403, { error: "Solo quien facilita el taller puede generar el resumen." });
  if (!["results", "closed"].includes(String(ses.phase))) return json(409, { error: "El resumen con IA se genera cuando el taller termina (Resultados o Cierre).", ai: "phase" });
  const stats = JSON.stringify(body.stats ?? {});
  if (stats.length < 20) return json(400, { error: "Aún hay pocos datos para resumir este taller." });

  // v1.26 · Una vez por taller: si ya hubo un resumen con IA que salió bien, no se vuelve a generar (se puede editar).
  // v2.11 · Lo revisa y lo aparta la base en un solo paso, con la pausa y el tope del mes (antes: aquí, sin candado).
  const once = await aiOnce(sb, sid, "insights", reqId);
  if (once instanceof Response) return once;
  const logId = once;
  const svc = createClient(Deno.env.get("SUPABASE_URL")!, serverKey(), { auth: { persistSession: false, autoRefreshToken: false } });

  const left = () => DEADLINE_MS - (Date.now() - t0);
  // deno-lint-ignore no-explicit-any
  let out: any, usage: any = null, saved = false;
  try {
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: MODEL, max_tokens: 500, temperature: 0.4, system: SUMMARY_SYSTEM,
          messages: [{ role: "user", content: "Resultados del taller (JSON):\n" + stats.slice(0, 7000) }] }),
        signal: AbortSignal.timeout(Math.max(1000, left())),
      });
      if (!r.ok) {
        const t = await r.text(); logErr({ req: reqId, summary: r.status, body: t.slice(0, 300) });
        // v1.26 · Mismos mensajes claros que la propuesta (antes: «No pudimos escribir el resumen» aunque fuera falta de saldo)
        const busy = r.status === 429 || r.status === 529;
        const msg = busy ? "La IA está ocupada. Intenta en un minuto."
          : r.status === 400 && /credit/i.test(t) ? MSG_NO_CREDIT
          : r.status === 401 ? "La llave de la IA no es válida: revísala en Supabase → Edge Functions → Secrets."
          : "No pudimos escribir el resumen esta vez. Intenta de nuevo.";
        return json(busy ? 429 : 502, { error: msg, ai: /credit/i.test(t) ? "credit" : undefined, req: reqId });
      }
      out = await r.json();
    } catch (e) {
      const timeout = /Timeout|Abort/i.test(String((e as Error)?.name || ""));
      logErr({ req: reqId, summary: "fetch", timeout, message: String((e as Error)?.message || e).slice(0, 300) });
      return json(timeout ? 504 : 503, { error: timeout ? "La IA tardó demasiado. Intenta de nuevo." : "No pudimos conectar con la IA. Intenta de nuevo en un momento.", retry: true, req: reqId });
    }
    usage = out?.usage || null;
    const text = (out?.content || []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("").trim().slice(0, 1400);
    // v1.26 · Primero se guarda el resumen en el taller y solo entonces cuenta como «ya generado»: si no se pudo guardar,
    //         el taller conserva su oportunidad (los tokens sí quedan registrados en Uso de IA).
    const at = new Date().toISOString();
    if (text) {
      const { error } = await svc.from("ws_sessions").update({ summary: text, summary_at: at }).eq("id", sid);
      if (error) logErr({ req: reqId, summary_save: String(error.message || error).slice(0, 200) }); else saved = true;
    }
    if (!text) return json(502, { error: "No pudimos escribir el resumen esta vez. Intenta de nuevo.", req: reqId });
    if (!saved) return json(503, { error: "No pudimos guardar el resumen. Intenta de nuevo.", retry: true, req: reqId });
    return json(200, { summary: text, summary_at: at, model: MODEL, usage, ai: null });
  } finally {
    // El renglón de Uso de IA se cierra siempre (también si la IA falló): así no queda «en curso»
    await finishLog(logId, reqId, { tin: Number(usage?.input_tokens) || 0, tout: Number(usage?.output_tokens) || 0, ok: saved, session_id: sid });
  }
}

/* v2.8 · Entregable: definiciones sugeridas para el modelo de competencias (Definir competencias).
   Solo quien facilita y con el taller terminado; UNA vez por taller (Uso de IA: kind «entregable»). v2.11 · La frenan
   la pausa y el tope mensual, igual que el resumen, y su «una vez» se aparta con ws_ai_once; sus tokens se registran. La IA solo redacta definiciones con los
   comportamientos y «Cómo se ve» que escribió la sala. Se guardan marcadas como sugeridas (src «ai», «por validar»)
   y nunca reemplazan una definición que quien facilita ya revisó o escribió (src «ok»). */
const DELIV_SYSTEM = `Eres analista de Colmena (Quality & Knowledge). En un taller para definir competencias, la sala escribió comportamientos de alguien que hace bien un rol, los juntó en competencias y propuso cómo se ve cada una en el día a día.
Para cada competencia redacta una definición sugerida para un modelo de competencias.
Reglas:
- Una sola oración por competencia, de 15 a 30 palabras: qué hace la persona y para qué le sirve al rol. En tercera persona y en presente.
- Básate solo en sus comportamientos y en cómo se ve. No agregues conductas, niveles, porcentajes, herramientas ni ejemplos que no estén en los datos.
- No copies los comportamientos al pie de la letra ni los enlistes.
- Escribe en el mismo idioma en que vienen los comportamientos.
- Sin títulos, comillas ni explicaciones.
Responde SOLO con JSON válido: {"d":["definición de la competencia 1","definición de la competencia 2"]}, una definición por competencia y en el mismo orden.`;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/* {"d":[…]} aunque la respuesta venga con texto de más o cortada */
function parseDefs(text: string, n: number): string[] {
  const t = ("{" + text).replace(/```(?:json)?/gi, "").trim();
  // deno-lint-ignore no-explicit-any
  let arr: any = null;
  try { arr = JSON.parse(t).d; } catch { /* sigue */ }
  if (!Array.isArray(arr)) {
    const i = t.indexOf("["); arr = [];
    if (i >= 0) for (const m of t.slice(i).matchAll(/"((?:[^"\\]|\\.)*)"/g)) { try { arr.push(JSON.parse('"' + m[1] + '"')); } catch { /* otra */ } }
  }
  return Array.from({ length: n }, (_, k) => cut(String(arr[k] ?? "").replace(/^["'\s]+|["'\s]+$/g, ""), 400));
}

// deno-lint-ignore no-explicit-any
async function deliverable(sb: any, auth: string, body: any, apiKey: string, reqId: string, t0: number): Promise<Response> {
  const MSG_DFAIL = "No pudimos sugerir las definiciones esta vez. Intenta de nuevo.";
  const sid = String(body.session_id || "");
  if (!UUID.test(sid)) return json(400, { error: "Solicitud inválida" });
  const { data: ses, error: se } = await sb.from("ws_sessions").select("id,name,owner_id,phase,kind").eq("id", sid).maybeSingle();
  if (se) { logErr({ req: reqId, deliverable: "ws_sessions", message: String(se.message || se).slice(0, 200) }); return json(503, { error: MSG_RETRY, retry: true, req: reqId }); }
  if (!ses) return json(404, { error: "No encontramos el taller." });
  const uid = jwtSub(auth);
  if (ses.owner_id !== uid) return json(403, { error: "Solo quien facilita el taller puede pedir las definiciones." });
  if (!["results", "closed"].includes(String(ses.phase))) return json(409, { error: "Las definiciones con IA se piden cuando el taller termina (Resultados o Cierre).", ai: "phase" });
  if (String(ses.kind) !== "comp") return json(400, { error: "Las definiciones con IA son para talleres de Definir competencias." });

  // Lo que manda la página: [{k: id de la competencia, n: nombre, c: comportamientos, v: cómo se ve}]
  // deno-lint-ignore no-explicit-any
  const raw: any[] = Array.isArray(body.items) ? body.items.slice(0, 8) : [];
  const items = raw.map((x) => ({ k: String(x?.k || ""), n: cut(x?.n, 120),
    c: (Array.isArray(x?.c) ? x.c : []).slice(0, 15).map((s: unknown) => cut(s, 160)).filter(Boolean),
    v: (Array.isArray(x?.v) ? x.v : []).slice(0, 5).map((s: unknown) => cut(s, 160)).filter(Boolean) }))
    .filter((x) => UUID.test(x.k) && x.n && x.c.length);
  if (!items.length) return json(400, { error: "Aún no hay competencias elegidas para definir." });

  const svc = createClient(Deno.env.get("SUPABASE_URL")!, serverKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  // Solo competencias de este taller (las tarjetas o grupos que votó la sala)
  const { data: cards, error: ce } = await svc.from("ws_cards").select("id").eq("session_id", sid).in("id", items.map((x) => x.k));
  if (ce) { logErr({ req: reqId, deliverable: "ws_cards", message: String(ce.message || ce).slice(0, 200) }); return json(503, { error: MSG_RETRY, retry: true, req: reqId }); }
  const mine = new Set((cards || []).map((c: { id: string }) => c.id));
  const list = items.filter((x) => mine.has(x.k));
  if (!list.length) return json(400, { error: "Aún no hay competencias elegidas para definir." });

  // Antes de gastar tokens: la tabla existe y el taller no ha usado su oportunidad
  const { data: cur, error: re } = await svc.from("ws_deliverables").select("data").eq("session_id", sid).maybeSingle();
  if (re) {
    logErr({ req: reqId, deliverable: "ws_deliverables", message: String(re.message || re).slice(0, 200) });
    return /ws_deliverables|does not exist|schema cache/i.test(String(re.message || ""))
      ? json(500, { error: "Falta correr migracion-v280-entregable.sql en Supabase. Avísale al admin.", req: reqId })
      : json(503, { error: MSG_RETRY, retry: true, req: reqId });
  }
  if (cur?.data && cur.data.ai_at) return json(409, { error: "Este taller ya usó sus definiciones con IA. Puedes editarlas, pero no volver a pedirlas.", ai: "once" });
  // v2.11 · La base revisa la pausa y el tope del mes y aparta el «una vez» en un solo paso (antes: aquí, sin candado)
  const once = await aiOnce(sb, sid, "entregable", reqId);
  if (once instanceof Response) return once;
  const logId = once;

  const left = () => DEADLINE_MS - (Date.now() - t0);
  const payload = JSON.stringify(list.map((x, i) => ({ n: i + 1, competencia: x.n, comportamientos: x.c, comoSeVe: x.v })));
  // deno-lint-ignore no-explicit-any
  let out: any, usage: any = null, saved = false;
  try {
    try {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: MODEL, max_tokens: 900, temperature: 0.3, system: DELIV_SYSTEM,
          messages: [{ role: "user", content: "Taller: " + cut(ses.name, 160) + "\n\nCompetencias (JSON):\n" + payload.slice(0, 9000) }, { role: "assistant", content: "{" }] }),
        signal: AbortSignal.timeout(Math.max(1000, left())),
      });
      if (!r.ok) {
        const tx = await r.text(); logErr({ req: reqId, deliverable: r.status, body: tx.slice(0, 300) });
        const busy = r.status === 429 || r.status === 529;
        const msg = busy ? "La IA está ocupada. Intenta en un minuto."
          : r.status === 400 && /credit/i.test(tx) ? MSG_NO_CREDIT
          : r.status === 401 ? "La llave de la IA no es válida: revísala en Supabase → Edge Functions → Secrets."
          : MSG_DFAIL;
        return json(busy ? 429 : 502, { error: msg, ai: /credit/i.test(tx) ? "credit" : undefined, req: reqId });
      }
      out = await r.json();
    } catch (e) {
      const timeout = /Timeout|Abort/i.test(String((e as Error)?.name || ""));
      logErr({ req: reqId, deliverable: "fetch", timeout, message: String((e as Error)?.message || e).slice(0, 300) });
      return json(timeout ? 504 : 503, { error: timeout ? "La IA tardó demasiado. Intenta de nuevo." : "No pudimos conectar con la IA. Intenta de nuevo en un momento.", retry: true, req: reqId });
    }
    usage = out?.usage || null;
    const text = (out?.content || []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
    const defs = parseDefs(text, list.length);

    // Se guarda junto con lo que ya completó quien facilita. Primero se guarda y solo entonces cuenta como «ya usado».
    // v2.11.1 · La base mezcla las definiciones con lo ÚLTIMO guardado y con candado (ws_deliverable_ai_merge). Antes se
    //           guardaba lo leído antes de llamar a la IA y se perdía lo que quien facilita editó mientras tanto.
    const at = new Date().toISOString();
    const defsBy: Record<string, string> = {};
    list.forEach((x, i) => { if (defs[i]) defsBy[x.k] = defs[i]; });
    if (!Object.keys(defsBy).length) return json(502, { error: MSG_DFAIL, req: reqId });
    const { data: m, error: me } = await svc.rpc("ws_deliverable_ai_merge", { p_session: sid, p_defs: defsBy, p_at: at, p_by: uid });
    if (me) {
      logErr({ req: reqId, deliverable_save: String(me.message || me).slice(0, 200), code: me.code });
      if (me.code === "PGRST202" || me.code === "42883") {   // la base aún no tiene la v2.11.1
        return json(500, { error: "Falta correr migracion-v2-11-1-ia-y-entregable.sql en Supabase. Avísale al admin.", req: reqId });
      }
      return json(503, { error: "No pudimos guardar las definiciones. Intenta de nuevo.", retry: true, req: reqId });
    }
    if (m?.reason === "once") return json(409, { error: "Este taller ya usó sus definiciones con IA. Puedes editarlas, pero no volver a pedirlas.", ai: "once" });
    const n = Number(m?.n) || 0;
    if (!n) return json(502, { error: MSG_DFAIL, req: reqId });
    saved = true;
    return json(200, { data: m.data, at, n, model: MODEL, usage, ai: null });
  } finally {
    // El renglón de Uso de IA se cierra siempre (también si la IA falló): así no queda «en curso»
    await finishLog(logId, reqId, { tin: Number(usage?.input_tokens) || 0, tout: Number(usage?.output_tokens) || 0, ok: saved, session_id: sid });
  }
}
