// Colmena v1.12 · suggest-workshop
// Con un formulario corto del facilitador (cliente, proceso, qué duele, objetivo, gente, duración…) devuelve
// una PROPUESTA completa del taller. La IA decide el contenido; el código decide números, topes y estructura.
// La página la muestra para revisar y editar: nada se crea solo.
// Seguridad: solo un facilitador o admin activo. La llave nunca sale de aquí. Máximo 30 propuestas por persona al día.
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

const MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-4-5-20251001";
const MAX_TOKENS = Math.min(3000, Math.max(1200, Number(Deno.env.get("AI_MAX_TOKENS")) || 2200));

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

const clean = (v: unknown, max = 160) => String(v ?? "").replace(/[“”«»]/g, '"').replace(/[‘’]/g, "'")
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
    q_checkin: cut(q.checkin, 70) || (usted ? "¿Cómo llega a esta sesión?" : "¿Cómo llegas a esta sesión?"),
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
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión" });
  const apiKey = (Deno.env.get("ANTHROPIC_API_KEY") || "").replace(/\s+/g, "");

  let body: { fields?: Partial<Fields>; brief?: string; adjust?: string; keepStages?: string[]; ping?: boolean; regen?: boolean };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }

  const pubKey = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, pubKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: me, error: e1 } = await sb.rpc("ws_me");
  const row = Array.isArray(me) ? me[0] : me;
  if (e1 || !row || !row.role || row.active === false) return json(403, { error: "Solo facilitadores activos pueden pedir propuestas" });

  if (body.ping) return json(200, { enabled: !!apiKey, model: apiKey ? MODEL : null });
  if (!apiKey) return json(501, { error: "La IA no está disponible por ahora. Puedes armar el taller a mano con lo que escribiste." });

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

  // límite diario por persona (30); si la función de la base no existe aún, no bloquea
  const { data: okDay, error: eLim } = await sb.rpc("ws_ai_take");
  if (!eLim && okDay === false) return json(429, { error: "Llegaste al límite de propuestas de hoy. Mañana se renueva." });

  const L = limits(f);
  const call = (temperature: number) => fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: MAX_TOKENS, temperature, system: SYSTEM,
      messages: [{ role: "user", content: userMsg(f, L, adjust, keep) }, { role: "assistant", content: "{" }] }),
  });
  let usage: any = null, draft: any = null;
  for (const temp of [body.regen ? 0.8 : 0.5, 0.3]) {
    const r = await call(temp);
    if (!r.ok) {
      const t = await r.text(); console.error("anthropic", r.status, t.slice(0, 300));
      const msg = r.status === 401 ? "La llave de la IA no es válida: revísala en Supabase → Edge Functions → Secrets."
        : r.status === 429 || r.status === 529 ? "La IA está ocupada. Intenta en un minuto."
        : r.status === 400 && /credit/i.test(t) ? "La cuenta de Anthropic no tiene saldo: agrega crédito en console.anthropic.com → Billing."
        : "No pudimos armar la propuesta esta vez. Intenta de nuevo o ármala a mano.";
      return json(r.status === 429 || r.status === 529 ? 429 : 502, { error: msg });
    }
    const out = await r.json(); usage = out?.usage || null;
    const text = (out?.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
    const raw = parse(text);
    draft = raw ? normalize(raw, f, L) : null;
    if (out?.stop_reason === "max_tokens") console.warn("max_tokens", usage);
    if (draft) break;
  }
  if (!draft) return json(502, { error: "No pudimos armar la propuesta esta vez. Intenta de nuevo o ármala a mano." });
  return json(200, { draft, model: MODEL, usage });
});
