// Colmena v1.5 · send-invite
// Envía el correo de invitación (HTML con diseño) en cuanto el admin crea la invitación.
// Seguridad: solo responde a un ADMIN con segundo factor, y solo a correos con una invitación vigente.
// Secretos (Supabase → Edge Functions → Secrets). Usa UNO de los dos métodos:
//   A) Gmail u otro SMTP:  SMTP_USER = tu@gmail.com · SMTP_PASS = contraseña de aplicación (16 letras)
//                          (opcionales: SMTP_HOST = smtp.gmail.com · SMTP_PORT = 465)
//   B) Resend (dominio propio verificado): RESEND_API_KEY = re_xxx…  → si existe, tiene prioridad
//   INVITE_FROM = Colmena · Quality & Knowledge <correo@remitente>   (con Gmail debe ser el mismo SMTP_USER)
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Inicia sesión como admin" });

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("INVITE_FROM") || (smtpUser ? `Colmena · Quality & Knowledge <${smtpUser}>` : "");
  if (!apiKey && !(smtpUser && smtpPass)) return json(500, { error: "Falta configurar el envío en Supabase (SMTP_USER y SMTP_PASS, o RESEND_API_KEY)." });
  if (!from) return json(500, { error: "Falta configurar INVITE_FROM en Supabase" });

  // Cliente con la sesión de quien llama: la base aplica sus reglas (RLS) como si fuera la página
  // Llave pública: la del entorno o la que manda la página (publishable). Nunca se usa la secreta.
  const pubKey = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, pubKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });

  const { data: isAdmin, error: e1 } = await sb.rpc("ws_is_superadmin");
  if (e1 || isAdmin !== true) return json(403, { error: "Solo un admin con verificación en dos pasos puede enviar invitaciones" });

  let body: { email?: string; subject?: string; html?: string; text?: string };
  try { body = await req.json(); } catch { return json(400, { error: "Solicitud inválida" }); }
  const email = String(body.email ?? "").trim().toLowerCase();
  const subject = String(body.subject ?? "").slice(0, 200);
  const html = String(body.html ?? "");
  const text = String(body.text ?? "");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(400, { error: "Correo no válido" });
  if (!subject || !html || html.length > 120_000 || text.length > 20_000) return json(400, { error: "Correo incompleto o demasiado grande" });
  if (!/[?&]inv=[A-Z0-9-]{8,}/i.test(html)) return json(400, { error: "El correo no trae enlace de invitación" });

  // Solo a quien tiene una invitación vigente (el admin la acaba de crear)
  const { data: inv, error: e2 } = await sb.from("ws_invites").select("id")
    .eq("email", email).is("used_at", null).is("revoked_at", null)
    .gt("expires_at", new Date().toISOString()).limit(1);
  if (e2) return json(500, { error: "No se pudo verificar la invitación" });
  if (!inv || !inv.length) return json(404, { error: "Ese correo no tiene una invitación vigente" });

  // Quien invita recibe las respuestas
  const { data: me } = await sb.rpc("ws_me");
  const replyTo = me && me[0] && me[0].email ? String(me[0].email) : undefined;

  if (apiKey) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [email], subject, html, text, ...(replyTo ? { reply_to: replyTo } : {}) }),
    });
    const out = await r.json().catch(() => ({}));
    if (!r.ok) return json(502, { error: "Resend no aceptó el envío: " + ((out as { message?: string }).message ?? r.status) });
    return json(200, { ok: true, via: "resend", id: (out as { id?: string }).id });
  }

  // SMTP (Gmail): puerto 465 con TLS (Supabase bloquea 25 y 587)
  const port = Number(Deno.env.get("SMTP_PORT") || 465);
  try {
    const transport = nodemailer.createTransport({
      host: Deno.env.get("SMTP_HOST") || "smtp.gmail.com",
      port,
      secure: port === 465,
      auth: { user: smtpUser, pass: String(smtpPass).replace(/\s+/g, "") },
    });
    const info = await transport.sendMail({ from, to: email, subject, html, text, ...(replyTo ? { replyTo } : {}) });
    return json(200, { ok: true, via: "smtp", id: info.messageId });
  } catch (err) {
    const m = String((err as Error)?.message || err);
    const hint = /Invalid login|Username and Password not accepted|535/i.test(m)
      ? "Gmail rechazó el usuario o la contraseña de aplicación (revisa SMTP_USER y SMTP_PASS)."
      : "El servidor de correo no aceptó el envío: " + m.slice(0, 160);
    return json(502, { error: hint });
  }
});
