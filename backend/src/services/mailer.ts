import nodemailer, { type Transporter } from 'nodemailer';

// Any SMTP provider works: Gmail (app password), Brevo, Resend, SendGrid, Zoho, etc.
// SMTP_PORT 465 uses TLS from the start; 587 upgrades with STARTTLS.
let transporter: Transporter | null = null;

export const isMailerConfigured = () => Boolean(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);

function mailer() {
  if (!isMailerConfigured()) throw new Error('Email sending is not configured. Set SMTP_HOST, SMTP_USER and SMTP_PASS.');
  const port = Number(process.env.SMTP_PORT || 587);
  transporter ??= nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure: port === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  return transporter;
}

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]!);

export async function sendCodeEmail(input: { to: string; code: string; name?: string | null; purpose: 'signup' | 'verify'; expiresInMinutes: number }) {
  const greeting = input.name ? `Hi ${escapeHtml(input.name)},` : 'Hi there,';
  const action = input.purpose === 'signup' ? 'finish creating your Office Gossip account' : 'verify your email on Office Gossip';
  const html = `<!doctype html><html><body style="margin:0;background:#f8f7f4;font-family:Arial,Helvetica,sans-serif;color:#24222a">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:32px 16px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px;background:#ffffff;border:1px solid #eeece9;border-radius:16px;padding:32px">
<tr><td style="font-size:20px;font-weight:800;letter-spacing:-0.5px">office<span style="color:#7357E8">gossip</span></td></tr>
<tr><td style="padding-top:24px;font-size:15px;line-height:1.6">${greeting}<br>Use this code to ${action}:</td></tr>
<tr><td style="padding:20px 0;font-size:34px;font-weight:800;letter-spacing:10px;color:#7357E8">${input.code}</td></tr>
<tr><td style="font-size:13px;line-height:1.6;color:#77727c">It expires in ${input.expiresInMinutes} minutes. If you didn’t ask for this, you can ignore this email.</td></tr>
</table></td></tr></table></body></html>`;
  await mailer().sendMail({
    from: process.env.MAIL_FROM || `Office Gossip <${process.env.SMTP_USER}>`,
    to: input.to,
    subject: `${input.code} is your Office Gossip code`,
    text: `${input.name ? `Hi ${input.name},` : 'Hi there,'}\n\nYour Office Gossip code is ${input.code}. Use it to ${action}.\nIt expires in ${input.expiresInMinutes} minutes. If you didn't ask for this, ignore this email.`,
    html,
  });
}
