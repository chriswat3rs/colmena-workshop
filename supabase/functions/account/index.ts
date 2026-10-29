// Colmena v1.26 · account
// Cuatro acciones de cuenta sin contraseñas ni pasos técnicos:
//   · invite-start  (sin sesión)  El invitado abre su enlace → entra con un toque (enlace mágico de un solo uso).
//                                 Si alguien había creado antes una cuenta con ese correo, se le quitan sus métodos.
//   · access-link   (sin sesión)  «Olvidé mi contraseña / Entrar sin contraseña»: manda por correo un enlace para entrar.
//                                 Siempre responde lo mismo (no revela si el correo existe). Máx. 3 por hora por correo.
//   · admin-reset   (admin)       Reinicia el acceso de alguien que perdió su teléfono y le manda un enlace para
//                                 volver a activar Face ID o su app.
//   · admin-remove  (admin)       v1.17 · Elimina a alguien del equipo (cuenta ya desactivada). Primero, con la sesión
//                                 del admin, ws_admin_remove_member pasa sus talleres, borradores y todo lo capturado a
//                                 nombre del admin y lo saca del equipo; solo si eso salió bien se borra su cuenta.
//                                 Body: { action: "admin-remove", user_id }.
// v1.26 · Contraseñas para facilitadores (admin sigue con segundo paso):
//   · pw-forgot     (sin sesión)  «¿Olvidaste tu contraseña?»: manda un enlace para crear una nueva. Siempre responde
//                                 lo mismo (no revela si el correo existe). Máx. 3 por hora por correo. Vence en 1 hora.
//   · pw-check      (sin sesión)  La página revisa el enlace antes de mostrar el formulario (vigente, vencido o usado).
//   · pw-set        (sin sesión)  Guarda la contraseña nueva con el enlace (1 solo uso) y valida las reglas aquí también:
//                                 8 a 72 caracteres, mayúscula, minúscula y número; nada obvio ni su correo.
//   · admin-reset de un facilitador: le quita sus llaves y su contraseña y le manda un enlace para crear una nueva (72 h).
// Las cuentas de admin no se saltan el segundo paso: después de entrar se pide Face ID / huella o el código de la app.
// v2.5.2 · invite-start: si la cuenta ya existía (la persona abrió su invitación antes y no terminó), se le cambia la
//           contraseña y DESPUÉS se genera el enlace de un solo uso. Supabase anula los enlaces existentes al cambiar
//           la contraseña; antes se devolvía el enlace ya anulado y salía «Email link is invalid or has expired».
// v2.5 · self-delete (con su sesión)  «Eliminar mi cuenta» desde Ajustes. Body: { action: "self-delete", confirm: "ELIMINAR",
//           password }. Confirma la contraseña; con su sesión, ws_self_remove pasa sus talleres, borradores y lo capturado
//           a una persona admin y la saca del equipo; después se borra su cuenta y le llega un correo de confirmación.
//           Requiere migracion-v250-eliminar-cuenta.sql. La última persona admin no puede eliminarse.
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
const SITE = (Deno.env.get("SITE_URL") || "https://colmena.work/app/").replace(/\/?$/, "/");
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const mailOk = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const uuidOk = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

/* v1.26 · Enlaces para crear o restablecer la contraseña: el token viaja en el correo; aquí solo se guarda su huella */
const tokenOk = /^[A-Za-z0-9_-]{32,80}$/;
const newToken = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
async function sha256Hex(s: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const firstName = (n: unknown) => String(n || "").trim().split(/\s+/)[0] || "";
/* Mismas reglas que la página: 8 a 72, mayúscula, minúscula y número; nada obvio ni el nombre del correo */
function pwProblem(pw: string, email: string) {
  if (pw.length < 8) return "Usa al menos 8 caracteres.";
  if (pw.length > 72) return "Usa máximo 72 caracteres.";
  if (!/[A-Z]/.test(pw)) return "Agrega al menos una mayúscula.";
  if (!/[a-z]/.test(pw)) return "Agrega al menos una minúscula.";
  if (!/[0-9]/.test(pw)) return "Agrega al menos un número.";
  const low = pw.toLowerCase(), user = String(email || "").split("@")[0].toLowerCase();
  if (/colmena|password|contrase(n|ñ)a|qwerty|123456|abc123|111111/.test(low) || (user.length >= 4 && low.includes(user)))
    return "Esa contraseña es fácil de adivinar. Prueba con otra.";
  return "";
}
/* Crea un enlace nuevo y cancela los anteriores del mismo tipo (solo el último sirve) */
async function issuePwToken(sb: ReturnType<typeof admin>, userId: string, email: string, kind: "reset" | "activate", hours: number) {
  await sb.from("ws_pw_tokens").update({ used_at: new Date().toISOString() }).eq("user_id", userId).eq("kind", kind).is("used_at", null);
  const token = newToken();
  const { error } = await sb.from("ws_pw_tokens").insert({ user_id: userId, email, token_hash: await sha256Hex(token), kind,
    expires_at: new Date(Date.now() + hours * 3600_000).toISOString() });
  if (error) throw error;
  return token;
}

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

/* Enlace de un solo uso para entrar como ese correo. Cambiar la contraseña después lo anula: generarlo al final. */
async function magicHash(sb: ReturnType<typeof admin>, email: string) {
  const { data, error } = await sb.auth.admin.generateLink({ type: "magiclink", email });
  if (error || !data?.properties?.hashed_token) throw (error || new Error("No se pudo generar el enlace"));
  return { hashed: data.properties.hashed_token as string, userId: data.user?.id as string };
}
/* Igual, pero crea la cuenta si no existe */
async function oneTimeLink(sb: ReturnType<typeof admin>, email: string) {
  let created = false;
  const c = await sb.auth.admin.createUser({ email, email_confirm: true, password: randomPassword() });
  if (!c.error) created = true;
  else if (!/already|registered|exists/i.test(c.error.message)) throw c.error;
  const { hashed, userId } = await magicHash(sb, email);
  return { hashed, userId, created };
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
  let body: { action?: string; code?: string; email?: string; user_id?: string; token?: string; password?: string };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }
  const sb = admin();

  /* ---------- El invitado abre su enlace ---------- */
  if (body.action === "invite-start") {
    const hash = await codeHash(body.code || "");
    const { data: inv } = await sb.from("ws_invites").select("id,email,used_at,used_by,revoked_at,expires_at").eq("code_hash", hash).maybeSingle();
    if (!inv) return json(404, { error: "No encontramos esta invitación. Revisa el enlace completo." });
    if (inv.revoked_at || new Date(inv.expires_at).getTime() <= Date.now()) return json(410, { error: "Tu invitación venció o se canceló. Pide una nueva." });
    // v1.16 · Una invitación ya usada no vuelve a dar acceso (antes servía 7 días a quien la había usado)
    if (inv.used_at) return json(410, { error: "Esta invitación ya se usó. Entra con tu contraseña o toca «¿La olvidaste?»." });
    if (!(await rateOk(sb, inv.email, "invite-start", 10))) return json(429, { error: "Demasiados intentos. Espera unos minutos." });
    try {
      const link = await oneTimeLink(sb, inv.email);
      let hashed = link.hashed;
      if (!link.created && !inv.used_at) {
        // La cuenta existía pero nunca entró al equipo: nadie más debe conservar acceso a ella
        const { data: staff } = await sb.from("ws_admins").select("user_id").eq("user_id", link.userId).maybeSingle();
        if (!staff) {
          await wipeMethods(sb, link.userId);
          await sb.auth.admin.updateUserById(link.userId, { password: randomPassword() });
          hashed = (await magicHash(sb, inv.email)).hashed;   // v2.5.2 · el enlace anterior quedó anulado con el cambio
        }
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

  /* ---------- v1.26 · «¿Olvidaste tu contraseña?» ---------- */
  if (body.action === "pw-forgot") {
    const email = String(body.email || "").trim().toLowerCase();
    const generic = { ok: true, message: "Si ese correo tiene cuenta en Colmena, te llegó un enlace para crear una nueva contraseña. Revisa también spam." };
    if (!mailOk.test(email)) return json(400, { error: "Escribe un correo válido." });
    if (!(await rateOk(sb, email, "pw-forgot", 3))) return json(200, generic);
    const { data: staff } = await sb.from("ws_admins").select("user_id,name,active").eq("email", email).maybeSingle();
    if (!staff || !staff.active) return json(200, generic);
    try {
      const token = await issuePwToken(sb, staff.user_id, email, "reset", 1);
      const m = mailHTML({ kicker: "Tu contraseña", title: "Crea una nueva contraseña", first: firstName(staff.name),
        body: "Recibimos una solicitud para cambiar tu contraseña de Colmena. Toca el botón para crear una nueva.",
        label: "Crear nueva contraseña", url: `${SITE}?pr=${encodeURIComponent(token)}#admin`,
        foot: "El enlace sirve una sola vez y vence en 1 hora. Si no lo pediste, ignora este correo: tu contraseña actual sigue funcionando y nadie puede cambiarla sin este enlace." });
      await sendMail(email, "Crea una nueva contraseña · Colmena", m.html, m.text);
    } catch (e) { console.error("pw-forgot", e); }
    return json(200, generic);
  }

  /* ---------- v1.26 · La página revisa el enlace antes de mostrar el formulario ---------- */
  if (body.action === "pw-check") {
    const t = String(body.token || "");
    if (!tokenOk.test(t)) return json(410, { error: "Este enlace no es válido.", expired: true });
    const { data: r } = await sb.from("ws_pw_tokens").select("user_id,email,kind,expires_at,used_at").eq("token_hash", await sha256Hex(t)).maybeSingle();
    if (!r) return json(410, { error: "Este enlace no es válido.", expired: true });
    if (r.used_at || new Date(r.expires_at).getTime() <= Date.now()) return json(410, { error: "Este enlace ya venció o ya se usó.", expired: true, email: r.email });
    const { data: st } = await sb.from("ws_admins").select("name,role,active").eq("user_id", r.user_id).maybeSingle();
    if (!st || !st.active) return json(403, { error: "Tu acceso al panel está desactivado. Si es un error, habla con tu admin." });
    return json(200, { ok: true, email: r.email, kind: r.kind, role: st.role, first: firstName(st.name) });
  }

  /* ---------- v1.26 · Guardar la contraseña nueva con el enlace (1 solo uso) ---------- */
  if (body.action === "pw-set") {
    const t = String(body.token || ""), pw = String(body.password || "");
    if (!tokenOk.test(t)) return json(410, { error: "Este enlace no es válido.", expired: true });
    const h = await sha256Hex(t);
    const { data: r0 } = await sb.from("ws_pw_tokens").select("email").eq("token_hash", h).maybeSingle();
    if (!r0) return json(410, { error: "Este enlace no es válido.", expired: true });
    const problem = pwProblem(pw, r0.email);
    if (problem) return json(400, { error: problem });
    if (!(await rateOk(sb, r0.email, "pw-set", 10))) return json(429, { error: "Demasiados intentos. Espera unos minutos." });
    const now = new Date().toISOString();
    const { data: r } = await sb.from("ws_pw_tokens").update({ used_at: now }).eq("token_hash", h).is("used_at", null).gt("expires_at", now)
      .select("user_id,email,kind").maybeSingle();
    if (!r) return json(410, { error: "Este enlace ya venció o ya se usó.", expired: true, email: r0.email });
    const { data: st } = await sb.from("ws_admins").select("role,active").eq("user_id", r.user_id).maybeSingle();
    if (!st || !st.active) return json(403, { error: "Tu acceso al panel está desactivado. Si es un error, habla con tu admin." });
    const { error: e1 } = await sb.auth.admin.updateUserById(r.user_id, { password: pw });
    if (e1) {
      console.error("pw-set", r.user_id, e1);
      await sb.from("ws_pw_tokens").update({ used_at: null }).eq("token_hash", h);     // el enlace sigue sirviendo para reintentar
      return json(400, { error: /weak|should|character|length/i.test(e1.message || "")
        ? "Esa contraseña no cumple las reglas: al menos 8 caracteres, una mayúscula, una minúscula y un número."
        : "No pudimos guardar tu contraseña. Intenta de nuevo." });
    }
    if (st.role === "facilitator") await sb.from("ws_admins").update({ reenroll_until: null }).eq("user_id", r.user_id);
    return json(200, { ok: true, email: r.email, kind: r.kind, role: st.role });
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
    const { data: target } = await sb.from("ws_admins").select("user_id,email,name,role").eq("user_id", uid).maybeSingle();
    if (!target) return json(404, { error: "Esa cuenta no es del equipo" });
    const { data: who } = await me.auth.getUser();
    if (who?.user?.id === uid) return json(400, { error: "No puedes reiniciar tu propio acceso" });
    await wipeMethods(sb, uid);
    const { error: e2 } = await me.rpc("ws_admin_reset_access", { p_user: uid });
    if (e2) return json(400, { error: e2.message });
    /* v1.26 · Facilitador: su contraseña deja de servir y le llega un enlace para crear una nueva (72 h) */
    if (target.role === "facilitator") {
      try {
        await sb.auth.admin.updateUserById(uid, { password: randomPassword() });
        const token = await issuePwToken(sb, uid, target.email, "activate", 72);
        const m = mailHTML({ kicker: "Tu acceso", title: "Crea una nueva contraseña", first: firstName(target.name),
          body: "Tu admin reinició tu acceso a Colmena. Crea una contraseña nueva para volver a entrar. Tus talleres siguen intactos.",
          label: "Crear nueva contraseña", url: `${SITE}?pr=${encodeURIComponent(token)}#admin`,
          foot: "El botón sirve una sola vez y vence en 72 horas. Si vence, en la pantalla de entrada toca «¿La olvidaste?» y te mandamos otro." });
        await sendMail(target.email, "Crea una nueva contraseña · Colmena", m.html, m.text);
        return json(200, { ok: true, email: target.email, sent: true, kind: "password" });
      } catch (e) { console.error("admin-reset (facilitador)", e); return json(200, { ok: true, email: target.email, sent: false, kind: "password" }); }
    }
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

  /* ---------- v2.5 · Eliminar mi cuenta (la persona misma, desde Ajustes) ---------- */
  if (body.action === "self-delete") {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión para eliminar tu cuenta." });
    const pub = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
    const me = createClient(Deno.env.get("SUPABASE_URL")!, pub, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: who } = await me.auth.getUser();
    const uid = String(who?.user?.id || ""), email = String(who?.user?.email || "").trim().toLowerCase();
    if (!uuidOk.test(uid) || !mailOk.test(email)) return json(401, { error: "Tu sesión expiró. Entra de nuevo." });
    if (String(body.confirm || "").trim().toUpperCase() !== "ELIMINAR") return json(400, { error: "Escribe ELIMINAR para confirmar.", field: "confirm" });
    if (!(await rateOk(sb, email, "self-delete", 5))) return json(429, { error: "Demasiados intentos. Espera unos minutos." });
    // 1) Confirma con su contraseña, en un cliente aparte que no guarda nada; esa sesión de prueba se cierra enseguida
    const check = createClient(Deno.env.get("SUPABASE_URL")!, pub, { auth: { persistSession: false, autoRefreshToken: false } });
    const { error: pe } = await check.auth.signInWithPassword({ email, password: String(body.password || "") });
    if (pe) return json(400, { error: "La contraseña no es correcta. Si no la recuerdas, cámbiala en Ajustes → Acceso y vuelve a intentarlo.", field: "password" });
    try { await check.auth.signOut({ scope: "local" }); } catch (_e) { /* la cuenta se borra en un momento de todos modos */ }
    // 2) Con SU sesión (auth.uid() = la persona): talleres, borradores y lo capturado pasan a una persona admin y sale
    //    del equipo, todo o nada. Si es la última admin, la base no lo permite.
    const { data: moved, error: e2 } = await me.rpc("ws_self_remove");
    if (e2) {
      console.error("self-delete", uid, e2);
      if (e2.code === "PGRST202") return json(500, { error: "Falta correr migracion-v250-eliminar-cuenta.sql en Supabase." });
      return json(400, { error: e2.message || "No pudimos eliminar tu cuenta. Intenta de nuevo." });
    }
    const r = (moved || {}) as { talleres?: number; borradores?: number; nombre?: string; para?: { nombre?: string; correo?: string } };
    // 3) Se borra la cuenta, solo si ya no tiene talleres ni borradores a su nombre (se borrarían en cascada).
    //    Si algo falla, ya no tiene acceso (salió del equipo): queda el detalle en Logs para borrarla a mano.
    let deleted = false;
    try {
      const [ses, dra] = await Promise.all([
        sb.from("ws_sessions").select("id", { count: "exact", head: true }).eq("owner_id", uid),
        sb.from("ws_drafts").select("id", { count: "exact", head: true }).eq("owner_id", uid),
      ]);
      if (ses.error || dra.error) throw (ses.error || dra.error);
      if ((ses.count ?? 0) > 0 || (dra.count ?? 0) > 0) throw new Error(`aún tiene ${ses.count} talleres y ${dra.count} borradores a su nombre`);
      const { error: e3 } = await sb.auth.admin.deleteUser(uid);
      if (e3) throw e3;
      deleted = true;
    } catch (e) { console.error("self-delete: salió del equipo pero no se borró su cuenta", uid, email, e); }
    // 4) Correo de confirmación (si no sale, la baja ya está hecha)
    try {
      const tuvo = ((r.talleres ?? 0) + (r.borradores ?? 0)) > 0;
      const quien = tuvo && r.para?.nombre ? ` Tus talleres quedaron a cargo de ${esc(r.para.nombre)}, para que tu equipo no pierda los resultados.` : "";
      const m = mailHTML({ kicker: "Tu cuenta", title: "Eliminamos tu cuenta de Colmena", first: firstName(r.nombre),
        body: `Tu cuenta, tu acceso y tus datos de perfil se borraron.${quien} Gracias por usar Colmena.`,
        label: "Ir a Colmena", url: SITE.replace(/app\/$/, ""),
        foot: "Si no fuiste tú, escríbenos de inmediato a admonrh@qacg.com." });
      await sendMail(email, "Eliminamos tu cuenta de Colmena", m.html, m.text);
    } catch (e) { console.error("self-delete: correo de confirmación", e); }
    await sb.from("ws_auth_mail_log").delete().eq("email", email);
    return json(200, { ok: true, deleted, email, talleres: r.talleres ?? 0, borradores: r.borradores ?? 0, para: r.para ?? null });
  }

  /* ---------- v1.17 · El admin elimina a alguien del equipo ---------- */
  if (body.action === "admin-remove") {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión como admin" });
    const pub = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
    const me = createClient(Deno.env.get("SUPABASE_URL")!, pub, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: isAdm } = await me.rpc("ws_is_superadmin");
    if (isAdm !== true) return json(403, { error: "Solo un admin puede eliminar cuentas" });
    const uid = String(body.user_id || "");
    if (!uuidOk.test(uid)) return json(400, { error: "Falta indicar a quién eliminar" });
    const { data: who } = await me.auth.getUser();
    if (who?.user?.id === uid) return json(400, { error: "No puedes eliminar tu propia cuenta" });
    // 1) Con la sesión del ADMIN (auth.uid() = admin): sus talleres, borradores y lo capturado pasan a nombre del
    //    admin, se cancelan sus invitaciones y sale del equipo. Todo o nada, en una sola transacción.
    const { data: moved, error: e2 } = await me.rpc("ws_admin_remove_member", { p_user: uid });
    if (e2) {
      console.error("admin-remove", uid, e2);
      if (e2.code === "PGRST202") return json(500, { error: "Falta correr migracion-v117-eliminar-usuarios.sql en Supabase." });
      const msg = e2.message || "No se pudo eliminar la cuenta. Intenta de nuevo.";
      return json(/no es del equipo/i.test(msg) ? 404 : 400, { error: msg });
    }
    const r = (moved || {}) as { talleres?: number; borradores?: number; participaciones?: number; email?: string };
    // 2) Solo si lo anterior salió bien: se borra su cuenta. Antes se confirma que ya no tiene talleres ni borradores
    //    a su nombre (se borrarían en cascada con la cuenta). Si algo falla, ya no tiene acceso (salió del equipo):
    //    se responde bien y queda el detalle en Logs para borrar la cuenta a mano en Authentication → Users.
    let deleted = false;
    try {
      const [ses, dra] = await Promise.all([
        sb.from("ws_sessions").select("id", { count: "exact", head: true }).eq("owner_id", uid),
        sb.from("ws_drafts").select("id", { count: "exact", head: true }).eq("owner_id", uid),
      ]);
      if (ses.error || dra.error) throw (ses.error || dra.error);
      if ((ses.count ?? 0) > 0 || (dra.count ?? 0) > 0) throw new Error(`aún tiene ${ses.count} talleres y ${dra.count} borradores a su nombre`);
      const { error: e3 } = await sb.auth.admin.deleteUser(uid);
      if (e3) throw e3;
      deleted = true;
    } catch (e) { console.error("admin-remove: salió del equipo pero no se borró su cuenta", uid, r.email, e); }
    return json(200, { ok: true, removed: true, account_deleted: deleted, email: r.email ?? "",
      talleres: r.talleres ?? 0, borradores: r.borradores ?? 0, participaciones: r.participaciones ?? 0 });
  }

  return json(400, { error: "Acción no válida" });
});
