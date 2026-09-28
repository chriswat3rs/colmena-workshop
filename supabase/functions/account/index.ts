// Colmena v1.12 · account
// Tres acciones de cuenta sin contraseñas ni pasos técnicos:
//   · invite-start  (sin sesión)  El invitado abre su enlace → entra con un toque (enlace mágico de un solo uso).
//                                 Si alguien había creado antes una cuenta con ese correo, se le quitan sus métodos.
//   · access-link   (sin sesión)  «Olvidé mi contraseña / Entrar sin contraseña»: manda por correo un enlace para entrar.
//                                 Siempre responde lo mismo (no revela si el correo existe). Máx. 3 por hora por correo.
//   · admin-reset   (admin)       Reinicia el acceso de alguien que perdió su teléfono y le manda un enlace para
//                                 volver a activar Face ID o su app.
// Ningún enlace se salta el segundo paso: después de entrar se pide Face ID / huella o el código de la app.
// Secretos: los mismos de send-invite (SMTP_USER/SMTP_PASS o RESEND_API_KEY, INVITE_FROM) y opcional SITE_URL.
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const SITE = (Deno.env.get("SITE_URL") || "https://chriswat3rs.github.io/colmena-workshop/").replace(/\/?$/, "/");
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const mailOk = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function serverKey() {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); return String(Object.values(k)[0] || ""); } catch { return ""; }
}
const admin = () => createClient(Deno.env.get("SUPABASE_URL")!, serverKey(),
  { auth: { persistSession: false, autoRefreshToken: false, experimental: { passkey: true } } as never });

async function codeHash(code: string) {
  const norm = String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(norm));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const randomPassword = () => [...crypto.getRandomValues(new Uint8Array(24))].map((b) => b.toString(36)).join("") + "Aa1!";

/* Límite simple por correo y tipo (tabla ws_auth_mail_log, solo servidor) */
async function rateOk(sb: ReturnType<typeof admin>, email: string, kind: string, max: number) {
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await sb.from("ws_auth_mail_log").select("id", { count: "exact", head: true }).eq("email", email).eq("kind", kind).gte("at", since);
  if ((count ?? 0) >= max) return false;
  await sb.from("ws_auth_mail_log").insert({ email, kind });
  return true;
}

/* Quita los métodos de acceso de una cuenta (segundo factor y llaves de Face ID) */
async function wipeMethods(sb: ReturnType<typeof admin>, userId: string) {
  try {
    const { data } = await sb.auth.admin.mfa.listFactors({ userId });
    for (const f of (data?.factors || [])) await sb.auth.admin.mfa.deleteFactor({ userId, id: f.id });
  } catch (e) { console.error("factors", e); }
  try {
    // deno-lint-ignore no-explicit-any
    const a = sb.auth.admin as any;
    if (typeof a._adminListPasskeys === "function") {
      const { data } = await a._adminListPasskeys({ userId });
      const list = Array.isArray(data) ? data : (data?.passkeys || []);
      for (const k of list) await a._adminDeletePasskey({ userId, passkeyId: k.id });
    }
  } catch (e) { console.error("passkeys", e); }
}

/* Enlace de un solo uso para entrar como ese correo (crea la cuenta si no existe) */
async function oneTimeLink(sb: ReturnType<typeof admin>, email: string) {
  let created = false;
  const c = await sb.auth.admin.createUser({ email, email_confirm: true, password: randomPassword() });
  if (!c.error) created = true;
  else if (!/already|registered|exists/i.test(c.error.message)) throw c.error;
  const { data, error } = await sb.auth.admin.generateLink({ type: "magiclink", email });
  if (error || !data?.properties?.hashed_token) throw (error || new Error("No se pudo generar el enlace"));
  return { hashed: data.properties.hashed_token, userId: data.user?.id as string, created };
}

function mailHTML(o: { kicker: string; title: string; body: string; label: string; url: string; foot: string; first?: string }) {
  const F = "font-family:Montserrat,'Segoe UI',Helvetica,Arial,sans-serif;";
  const html = `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.title)}</title></head>
<body style="margin:0;padding:0;background:#EEF3F9;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#EEF3F9" style="background:#EEF3F9;"><tr><td align="center" style="padding:32px 12px;">
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="#FFFFFF" style="width:100%;max-width:600px;background:#FFFFFF;border:1px solid #DCE3EE;border-radius:16px;border-collapse:separate;">
    <tr><td height="6" bgcolor="#278FD8" style="height:6px;line-height:6px;font-size:0;background:#278FD8;border-radius:16px 16px 0 0;">&nbsp;</td></tr>
    <tr><td align="center" style="padding:30px 40px 4px 40px;"><img src="${SITE}email/colmena-qk.png" width="140" alt="Colmena + Quality &amp; Knowledge" style="display:block;width:140px;height:auto;border:0;"></td></tr>
    <tr><td align="center" style="${F}padding:14px 40px 0 40px;font-size:12px;font-weight:800;letter-spacing:2px;color:#1B6FAE;text-transform:uppercase;">${esc(o.kicker)}</td></tr>
    <tr><td align="center" style="${F}padding:10px 40px 0 40px;font-size:24px;line-height:31px;font-weight:800;color:#01133B;">${esc(o.title)}</td></tr>
    <tr><td align="center" style="${F}padding:12px 48px 0 48px;font-size:15px;line-height:24px;color:#46536E;">${o.first ? `Hola ${esc(o.first)},<br>` : ""}${o.body}</td></tr>
    <tr><td align="center" style="padding:26px 40px 10px 40px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" bgcolor="#01133B" style="border-radius:12px;background:#01133B;">
        <a href="${esc(o.url)}" target="_blank" style="${F}display:inline-block;padding:15px 32px;font-size:15px;font-weight:700;color:#FFFFFF;text-decoration:none;border-radius:12px;">${esc(o.label)}</a>
      </td></tr></table></td></tr>
    <tr><td align="center" style="${F}padding:6px 40px 30px 40px;font-size:12.5px;line-height:19px;color:#616D87;">${o.foot}</td></tr>
  </table>
  <p style="${F}font-size:11.5px;color:#8A94A8;margin:18px 0 0;">Colmena · Quality &amp; Knowledge</p>
</td></tr></table></body></html>`;
  const text = `${o.first ? "Hola " + o.first + ",\n\n" : ""}${o.title}\n\n${o.body.replace(/<[^>]+>/g, "")}\n\n${o.label}: ${o.url}\n\n${o.foot.replace(/<[^>]+>/g, "")}\n\n— Colmena · Quality & Knowledge`;
  return { html, text };
}

async function sendMail(to: string, subject: string, html: string, text: string) {
  const apiKey = Deno.env.get("RESEND_API_KEY"), user = Deno.env.get("SMTP_USER"), pass = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("INVITE_FROM") || (user ? `Colmena · Quality & Knowledge <${user}>` : "");
  if (apiKey) {
    const r = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [to], subject, html, text }) });
    if (!r.ok) throw new Error("Resend " + r.status);
    return;
  }
  if (!(user && pass)) throw new Error("Falta configurar el correo (SMTP_USER y SMTP_PASS)");
  const port = Number(Deno.env.get("SMTP_PORT") || 465);
  const t = nodemailer.createTransport({ host: Deno.env.get("SMTP_HOST") || "smtp.gmail.com", port, secure: port === 465, auth: { user, pass: String(pass).replace(/\s+/g, "") } });
  await t.sendMail({ from, to, subject, html, text });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });
  let body: { action?: string; code?: string; email?: string; user_id?: string };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }
  const sb = admin();

  /* ---------- El invitado abre su enlace ---------- */
  if (body.action === "invite-start") {
    const hash = await codeHash(body.code || "");
    const { data: inv } = await sb.from("ws_invites").select("id,email,used_at,used_by,revoked_at,expires_at").eq("code_hash", hash).maybeSingle();
    if (!inv) return json(404, { error: "No encontramos esta invitación. Revisa el enlace completo." });
    if (inv.revoked_at || new Date(inv.expires_at).getTime() <= Date.now()) return json(410, { error: "Tu invitación venció o se canceló. Pide una nueva." });
    if (!(await rateOk(sb, inv.email, "invite-start", 10))) return json(429, { error: "Demasiados intentos. Espera unos minutos." });
    try {
      const { hashed, userId, created } = await oneTimeLink(sb, inv.email);
      if (inv.used_at && inv.used_by !== userId) return json(410, { error: "Esta invitación ya se usó." });
      if (!created && !inv.used_at) {
        // La cuenta existía pero nunca entró al equipo: nadie más debe conservar acceso a ella
        const { data: staff } = await sb.from("ws_admins").select("user_id").eq("user_id", userId).maybeSingle();
        if (!staff) { await wipeMethods(sb, userId); await sb.auth.admin.updateUserById(userId, { password: randomPassword() }); }
      }
      return json(200, { token_hash: hashed, email: inv.email });
    } catch (e) { console.error(e); return json(500, { error: "No pudimos abrir tu invitación. Intenta de nuevo." }); }
  }

  /* ---------- «Olvidé mi contraseña» / entrar sin contraseña ---------- */
  if (body.action === "access-link") {
    const email = String(body.email || "").trim().toLowerCase();
    const generic = { ok: true, message: "Si ese correo tiene acceso a Colmena, te llegó un enlace para entrar. Revisa también spam." };
    if (!mailOk.test(email)) return json(400, { error: "Escribe un correo válido." });
    if (!(await rateOk(sb, email, "access-link", 3))) return json(200, generic);
    const { data: staff } = await sb.from("ws_admins").select("user_id,name,active").ilike("email", email).maybeSingle();
    if (!staff || !staff.active) return json(200, generic);
    try {
      const { hashed } = await oneTimeLink(sb, email);
      const first = String(staff.name || "").trim().split(/\s+/)[0];
      const m = mailHTML({ kicker: "Tu acceso", title: "Tu enlace para entrar a Colmena", first,
        body: "Toca el botón para entrar. Después confirma con tu Face ID, tu huella o el código de tu app, como siempre.",
        label: "Entrar a Colmena", url: `${SITE}?lt=${encodeURIComponent(hashed)}#admin`,
        foot: "El enlace sirve una sola vez y vence en 1 hora. Si no lo pediste, ignora este correo: sin tu Face ID o tu código nadie puede entrar." });
      await sendMail(email, "Tu enlace para entrar a Colmena", m.html, m.text);
    } catch (e) { console.error(e); }
    return json(200, generic);
  }

  /* ---------- El admin reinicia el acceso de alguien ---------- */
  if (body.action === "admin-reset") {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión como admin" });
    const pub = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
    const me = createClient(Deno.env.get("SUPABASE_URL")!, pub, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: isAdm } = await me.rpc("ws_is_superadmin");
    if (isAdm !== true) return json(403, { error: "Solo un admin puede reiniciar accesos" });
    const uid = String(body.user_id || "");
    const { data: target } = await sb.from("ws_admins").select("user_id,email,name").eq("user_id", uid).maybeSingle();
    if (!target) return json(404, { error: "Esa cuenta no es del equipo" });
    const { data: who } = await me.auth.getUser();
    if (who?.user?.id === uid) return json(400, { error: "No puedes reiniciar tu propio acceso" });
    await wipeMethods(sb, uid);
    const { error: e2 } = await me.rpc("ws_admin_reset_access", { p_user: uid });
    if (e2) return json(400, { error: e2.message });
    try {
      const { hashed } = await oneTimeLink(sb, target.email);
      const first = String(target.name || "").trim().split(/\s+/)[0];
      const m = mailHTML({ kicker: "Tu acceso", title: "Reiniciamos tu acceso a Colmena", first,
        body: "Tu admin reinició tu acceso (por ejemplo, porque cambiaste de teléfono). Entra con el botón y vuelve a activar tu Face ID, tu huella o tu app autenticadora. Tus talleres siguen intactos.",
        label: "Entrar y activar", url: `${SITE}?lt=${encodeURIComponent(hashed)}#admin`,
        foot: "El enlace sirve una sola vez y vence en 1 hora. Si vence, en la pantalla de entrada usa «Recibir un enlace para entrar»." });
      await sendMail(target.email, "Reiniciamos tu acceso a Colmena", m.html, m.text);
      return json(200, { ok: true, email: target.email, sent: true });
    } catch (e) { console.error(e); return json(200, { ok: true, email: target.email, sent: false }); }
  }

  return json(400, { error: "Acción no válida" });
});
