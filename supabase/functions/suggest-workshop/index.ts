// Colmena v1.9 · suggest-workshop
// Con dos o tres líneas del facilitador (cliente, proceso, qué duele) devuelve un borrador completo del taller
// (nombre, áreas, roles, etapas con actividades y herramientas, quick wins, reglas, tiempos y preguntas).
// La página lo carga en el creador paso a paso como borrador EDITABLE: nada se crea solo.
// Seguridad: solo responde a un facilitador o admin activo (sesión válida). La llave de la IA nunca sale de aquí.
// Secretos (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY = sk-ant-…   (console.anthropic.com → API keys)
//   AI_MODEL          = claude-haiku-4-5-20251001   (opcional; Haiku es el más barato: ~1 centavo de dólar por sugerencia)
//   AI_MAX_TOKENS     = 2500   (opcional; tope de la respuesta para que el gasto sea predecible)
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-4-5-20251001";
const MAX_TOKENS = Math.min(4000, Math.max(800, Number(Deno.env.get("AI_MAX_TOKENS")) || 2500));

/* Lo que la página espera (mismo formato que las plantillas de Colmena) */
type Draft = {
  name: string; areas: string[]; roles: string[]; stages: string[];
  tasks: Record<string, string[]>; tools: Record<string, string[]>;
  quickwins: { kind: "qw" | "gate" | "time"; stage: string; text: string; help?: string }[];
  q_checkin: string; q_expect: string; q_pain: string; q_idea: string;
  votes_per_user: number; idea_votes: number; idea_top: number;
};

const SYSTEM = `Eres el asistente de Colmena, una plataforma de Quality & Knowledge (consultora en Ciudad de México) para facilitar workshops de design thinking en vivo: los participantes entran con un QR desde su celular, hacen check-in, publican "dolores" del proceso por etapa, votan, validan una propuesta (quick wins, reglas del nuevo flujo y tiempos por etapa) y proponen ideas para los 3 dolores más votados.

Con la descripción del facilitador, propón un BORRADOR completo del taller en español de México, concreto y en el lenguaje del cliente. El facilitador lo va a editar; prefiere propuestas específicas y verosímiles a genéricas.

Responde SOLO con un objeto JSON válido (sin texto antes ni después, sin markdown) con exactamente estas llaves:
{
 "name": "Nombre corto del taller (Cliente · Proceso)",
 "areas": ["4 a 6 áreas o equipos que participan"],
 "roles": ["4 a 6 puestos o perfiles reales de ese proceso"],
 "stages": ["5 a 8 etapas del proceso, numeradas: '1 Verbo + objeto', '2 …'; la última puede ser 'Transversal (…)'"],
 "tasks": { "<etapa exacta>": ["2 a 3 actividades concretas de esa etapa"] },
 "tools": { "<etapa exacta>": ["1 a 3 sistemas, archivos o formatos que se usan en esa etapa"] },
 "quickwins": [
   { "kind": "qw",   "stage": "<etapa exacta>", "text": "mejora rápida y concreta", "help": "una frase que explique qué cambiaría" },
   { "kind": "gate", "stage": "<etapa exacta>", "text": "regla o candado del nuevo flujo (algo que será obligatorio)" },
   { "kind": "time", "stage": "<etapa exacta>", "text": "<mismo nombre de la etapa>" }
 ],
 "q_checkin": "pregunta corta para el check-in",
 "q_expect": "pregunta corta sobre qué esperan del taller",
 "q_pain": "pregunta que invite a contar dolores de ESE proceso",
 "q_idea": "pregunta '¿Cómo podríamos…?' para la fase de ideas",
 "votes_per_user": 5, "idea_votes": 3, "idea_top": 3
}
Reglas: 6 a 9 quick wins (kind "qw"), 3 a 5 reglas (kind "gate"), y un elemento kind "time" por CADA etapa (text = nombre de la etapa). Las llaves de tasks y tools y los stage de quickwins deben coincidir letra por letra con un elemento de "stages". Nada de comillas tipográficas dentro de los textos. Máximo 100 caracteres por texto y 90 en "help". Sé breve: el JSON completo debe caber en unas 1,500 palabras.`;

const str = (v: unknown, max = 160) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, max);
const list = (v: unknown, max: number, len = 120) => (Array.isArray(v) ? v : []).map((x) => str(x, len)).filter(Boolean).slice(0, max);

/* Deja el borrador en el formato exacto de Colmena y quita lo que no cuadre (etapas que no existen, listas vacías…) */
function normalize(raw: any): Draft {
  const stages = list(raw?.stages, 12, 80);
  const has = (s: string) => stages.includes(s);
  const near = (s: string) => { s = str(s, 80); if (has(s)) return s; const f = stages.find((x) => x.toLowerCase() === s.toLowerCase() || x.replace(/^\d+\s*/, "").toLowerCase() === s.replace(/^\d+\s*/, "").toLowerCase()); return f || ""; };
  const map = (o: any, max: number) => { const out: Record<string, string[]> = {}; if (o && typeof o === "object") for (const k of Object.keys(o)) { const st = near(k); const l = list(o[k], max); if (st && l.length) out[st] = (out[st] || []).concat(l).slice(0, max); } return out; };
  const seen = new Set<string>();
  const quickwins = (Array.isArray(raw?.quickwins) ? raw.quickwins : []).map((q: any) => {
    const kind = ["qw", "gate", "time"].includes(q?.kind) ? q.kind : "qw"; const stage = near(q?.stage);
    const text = kind === "time" ? (stage || str(q?.text, 80)) : str(q?.text, 120); const help = str(q?.help, 220);
    return { kind, stage, text, ...(help ? { help } : {}) };
  }).filter((q: any) => q.text && !seen.has(q.kind + q.text) && seen.add(q.kind + q.text)).slice(0, 40);
  if (!quickwins.some((q: any) => q.kind === "time")) stages.forEach((s) => quickwins.push({ kind: "time", stage: s, text: s }));
  const n = (v: unknown, d: number, lo: number, hi: number) => { const x = Number(v); return Number.isFinite(x) ? Math.min(hi, Math.max(lo, Math.round(x))) : d; };
  return {
    name: str(raw?.name, 160), areas: list(raw?.areas, 12, 60), roles: list(raw?.roles, 12, 60), stages,
    tasks: map(raw?.tasks, 8), tools: map(raw?.tools, 8), quickwins,
    q_checkin: str(raw?.q_checkin, 140) || "¿Cómo llegas a esta sesión?",
    q_expect: str(raw?.q_expect, 140) || "En una frase: ¿qué esperas de este workshop?",
    q_pain: str(raw?.q_pain, 200) || "¿Qué es lo que más tiempo te roba o más te frustra en este proceso?",
    q_idea: str(raw?.q_idea, 200) || "¿Cómo podríamos resolverlo?",
    votes_per_user: n(raw?.votes_per_user, 5, 1, 20), idea_votes: n(raw?.idea_votes, 3, 1, 10), idea_top: n(raw?.idea_top, 3, 1, 10),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión" });
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY") || "";

  let body: { brief?: string; ping?: boolean };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }

  // Solo facilitadores o admins activos (la base decide con la sesión de quien llama)
  const pubKey = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, pubKey, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: me, error: e1 } = await sb.rpc("ws_me");
  const row = Array.isArray(me) ? me[0] : me;
  if (e1 || !row || !row.role || row.active === false) return json(403, { error: "Solo facilitadores activos pueden pedir sugerencias" });

  if (body.ping) return json(200, { enabled: !!apiKey, model: apiKey ? MODEL : null });
  if (!apiKey) return json(501, { error: "La IA no está configurada en Supabase (falta ANTHROPIC_API_KEY)." });

  const brief = str(body.brief, 600);
  if (brief.length < 12) return json(400, { error: "Cuéntame un poco más: cliente, proceso y qué duele (mínimo una línea)." });

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL, max_tokens: MAX_TOKENS, temperature: 0.7, system: SYSTEM,
      messages: [{ role: "user", content: `Descripción del facilitador:\n${brief}\n\nDevuelve solo el JSON.` }],
    }),
  });
  if (!r.ok) {
    const t = await r.text();
    const msg = r.status === 401 ? "La llave de la IA no es válida (ANTHROPIC_API_KEY)." : r.status === 429 ? "La IA está saturada; intenta en un momento." : `La IA respondió ${r.status}.`;
    console.error("anthropic", r.status, t.slice(0, 300));
    return json(502, { error: msg });
  }
  const out = await r.json();
  const text = (out?.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
  let raw: any = null;
  try { raw = JSON.parse(text.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "").trim()); }
  catch { const m = text.match(/\{[\s\S]*\}/); try { raw = m ? JSON.parse(m[0]) : null; } catch { raw = null; } }
  if (!raw) return json(502, { error: "La IA no devolvió un borrador legible; intenta de nuevo." });
  const draft = normalize(raw);
  if (draft.stages.length < 3 || !draft.name) return json(502, { error: "El borrador salió incompleto; intenta con más detalle." });
  return json(200, { draft, model: MODEL, usage: out?.usage || null });
});
