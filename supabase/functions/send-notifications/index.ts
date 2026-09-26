// Colmena v1.6 · send-notifications
// Envía la «bandeja de salida» del centro de notificaciones (avisos importantes) con la plantilla de Colmena.
// La llama una tarea programada cada 5 minutos (pg_cron + pg_net) solo cuando hay correos pendientes.
// Llamarla de más no hace daño: solo envía lo que ya está pendiente y a su destinatario legítimo.
// Usa los mismos secretos que send-invite (SMTP_USER/SMTP_PASS o RESEND_API_KEY, INVITE_FROM).
// Opcional: SITE_URL = https://tu-usuario.github.io/colmena-workshop/
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const SITE = (Deno.env.get("SITE_URL") || "https://chriswat3rs.github.io/colmena-workshop/").replace(/\/?$/, "/");
const ORG = "Quality &amp; Knowledge";
const KICKER: Record<string, string> = {
  invite_accepted: "Tu equipo", role_changed: "Tu cuenta", reactivated: "Tu cuenta", retention: "Privacidad de datos",
};
const PREF: Record<string, string> = {
  invite_accepted: "invitaciones aceptadas", role_changed: "cambios de rol", reactivated: "cambios de acceso",
  retention: "recordatorios de talleres cerrados",
};
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

type Row = { id: string; email: string; name: string | null; type: string; title: string; body: string | null; action: Record<string, string> };

function linkFor(a: Record<string, string>) {
  if (a?.code) return `${SITE}?s=${encodeURIComponent(a.code)}#admin`;
  if (a?.view) return `${SITE}?view=${encodeURIComponent(a.view)}#admin`;
  return `${SITE}#admin`;
}

function render(n: Row) {
  const F = "font-family:Montserrat,'Segoe UI',Helvetica,Arial,sans-serif;";
  const first = String(n.name || "").trim().split(/\s+/)[0];
  const url = linkFor(n.action || {});
  const label = n.action?.label || "Abrir Colmena";
  const kicker = KICKER[n.type] || "Aviso";
  const html = `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(n.title)}</title></head>
<body style="margin:0;padding:0;background:#EEF3F9;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#EEF3F9" style="background:#EEF3F9;"><tr><td align="center" style="padding:32px 12px;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;color:#EEF3F9;">${esc(n.body || n.title)}</div>
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="#FFFFFF" style="width:100%;max-width:600px;background:#FFFFFF;border:1px solid #DCE3EE;border-radius:16px;border-collapse:separate;">
    <tr><td height="6" bgcolor="#278FD8" style="height:6px;line-height:6px;font-size:0;background:#278FD8;border-radius:16px 16px 0 0;">&nbsp;</td></tr>
    <tr><td align="center" style="padding:30px 40px 4px 40px;"><img src="${SITE}email/colmena-qk.png" width="140" alt="Colmena + ${ORG}" style="display:block;width:140px;height:auto;border:0;"></td></tr>
    <tr><td align="center" style="${F}padding:14px 40px 0 40px;font-size:12px;font-weight:800;letter-spacing:2px;color:#1B6FAE;text-transform:uppercase;">${esc(kicker)}</td></tr>
    <tr><td align="center" style="${F}padding:10px 40px 0 40px;font-size:24px;line-height:31px;font-weight:800;color:#01133B;">${esc(n.title)}</td></tr>
    ${n.body ? `<tr><td align="center" style="${F}padding:12px 48px 0 48px;font-size:15px;line-height:24px;color:#46536E;">${first ? `Hola ${esc(first)},<br>` : ""}${esc(n.body)}</td></tr>` : ""}
    <tr><td align="center" style="padding:26px 40px 34px 40px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" bgcolor="#01133B" style="border-radius:12px;background:#01133B;">
        <a href="${esc(url)}" target="_blank" style="${F}display:inline-block;padding:15px 32px;font-size:15px;font-weight:700;color:#FFFFFF;text-decoration:none;border-radius:12px;">${esc(label)}</a>
      </td></tr></table>
    </td></tr>
  </table>
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">
    <tr><td align="center" style="${F}padding:24px 20px 6px 20px;font-size:11px;font-weight:700;letter-spacing:2px;color:#616D87;text-transform:uppercase;">Una plataforma de</td></tr>
    <tr><td align="center" style="padding:4px 20px 10px 20px;"><img src="${SITE}email/quality-knowledge.png" width="140" alt="${ORG}" style="display:block;width:140px;height:auto;border:0;"></td></tr>
    <tr><td align="center" style="${F}padding:4px 30px 0 30px;font-size:11.5px;line-height:17px;color:#8A94A8;">Recibes este correo por los avisos de ${esc(PREF[n.type] || "Colmena")}. Puedes apagarlos en Colmena → tu perfil → Correos de avisos.</td></tr>
  </table>
</td></tr></table></body></html>`;
  const text = `${first ? "Hola " + first + ",\n\n" : ""}${n.title}\n\n${n.body || ""}\n\n${label}: ${url}\n\n— Colmena · Quality & Knowledge\nPuedes apagar estos correos en Colmena → tu perfil.`;
  return { html, text };
}

function serverKey() {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); return String(Object.values(k)[0] || ""); } catch { return ""; }
}

Deno.serve(async () => {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPass = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("INVITE_FROM") || (smtpUser ? `Colmena · Quality & Knowledge <${smtpUser}>` : "");
  if (!apiKey && !(smtpUser && smtpPass)) return Response.json({ error: "Sin método de envío configurado" }, { status: 500 });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, serverKey(), { auth: { persistSession: false } });
  const { data, error } = await sb.rpc("ws_claim_email_batch", { p_limit: 20 });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  const rows = (data || []) as Row[];

  const port = Number(Deno.env.get("SMTP_PORT") || 465);
  const transport = apiKey ? null : nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") || "smtp.gmail.com", port, secure: port === 465,
    auth: { user: smtpUser, pass: String(smtpPass).replace(/\s+/g, "") },
  });

  let sent = 0, failed = 0;
  for (const n of rows) {
    const { html, text } = render(n);
    try {
      if (apiKey) {
        const r = await fetch("https://api.resend.com/emails", {
          method: "POST", headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({ from, to: [n.email], subject: n.title, html, text }),
        });
        if (!r.ok) throw new Error("Resend " + r.status + " " + (await r.text()).slice(0, 200));
      } else {
        await transport!.sendMail({ from, to: n.email, subject: n.title, html, text });
      }
      await sb.rpc("ws_finish_email", { p_id: n.id, p_ok: true });
      sent++;
    } catch (e) {
      await sb.rpc("ws_finish_email", { p_id: n.id, p_ok: false, p_error: String((e as Error)?.message || e) });
      failed++;
    }
  }
  return Response.json({ ok: true, sent, failed });
});
