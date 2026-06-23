const db = require('../config/database');
const https = require('https');
const fs = require('fs');
const path = require('path');

const OTP_EXPIRY_MINUTES = 10;

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function saveOtp(phone, code) {
  db.prepare('UPDATE otp_codes SET is_used = 1 WHERE phone = ?').run(phone);
  const expiry = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000);
  const expiresAt = expiry.toISOString().replace('T', ' ').replace('Z', '').slice(0, 19);
  db.prepare('INSERT INTO otp_codes (phone, code, expires_at) VALUES (?,?,?)').run(phone, code, expiresAt);
}

function verifyOtp(phone, code) {
  const row = db.prepare(
    `SELECT id FROM otp_codes
     WHERE phone = ? AND code = ? AND is_used = 0
       AND expires_at > datetime('now')
     ORDER BY id DESC LIMIT 1`
  ).get(phone, code);
  if (!row) return false;
  db.prepare('UPDATE otp_codes SET is_used = 1 WHERE id = ?').run(row.id);
  return true;
}

function devLog(phone, code) {
  const msg = `\n========================================\n[DEV OTP] Phone: ${phone}  Code: ${code}\n========================================\n`;
  process.stdout.write(msg);
  const logPath = path.join(__dirname, '../../../data/otp_dev.log');
  try { fs.appendFileSync(logPath, `${new Date().toISOString()} | ${phone} | ${code}\n`); } catch (_) {}
}

// ── WhatsApp OTP (Meta Cloud API) ─────────────────────────────────────────────
// Uses authentication template — cheapest channel, ~₹0.35/msg, 1000 free/month
// Template must be approved in Meta Business Manager:
//   Name:     otp_verification  (or set WHATSAPP_OTP_TEMPLATE in .env)
//   Category: AUTHENTICATION
//   Body:     "Your HappyKrishi OTP is {{1}}. Valid for 10 minutes. Do not share."
//   Button:   One-tap autofill (optional) with OTP code {{1}}

function sendWhatsAppOtp(phone, code) {
  const token = process.env.WHATSAPP_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_ID;
  const templateName = process.env.WHATSAPP_OTP_TEMPLATE || 'otp_verification';

  if (!token || !phoneId) return false; // not configured

  const formatted = phone.startsWith('+') ? phone : '+91' + phone;

  const payload = JSON.stringify({
    messaging_product: 'whatsapp',
    to: formatted,
    type: 'template',
    template: {
      name: templateName,
      language: { code: 'en' },
      components: [
        {
          type: 'body',
          parameters: [{ type: 'text', text: code }],
        },
        // Uncomment if you added a one-tap autofill button in your template:
        // {
        //   type: 'button',
        //   sub_type: 'url',
        //   index: '0',
        //   parameters: [{ type: 'text', text: code }],
        // },
      ],
    },
  });

  const options = {
    hostname: 'graph.facebook.com',
    path: `/v19.0/${phoneId}/messages`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
  };

  return new Promise((resolve) => {
    const req = https.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const result = JSON.parse(data);
        if (result.error) {
          console.error('[WhatsApp OTP] Error:', result.error.message);
          resolve(false);
        } else {
          console.log(`[WhatsApp OTP] Sent to ${phone}`);
          resolve(true);
        }
      });
    });
    req.on('error', e => { console.error('[WhatsApp OTP] Network error:', e.message); resolve(false); });
    req.write(payload);
    req.end();
  });
}

// ── SMS OTP (MSG91 fallback) ──────────────────────────────────────────────────

function sendSmsOtp_msg91(phone, code) {
  const authKey = process.env.MSG91_AUTH_KEY;
  const templateId = process.env.MSG91_TEMPLATE_ID;
  if (!authKey) return;

  const formattedPhone = phone.startsWith('91') ? phone : '91' + phone;
  const payload = JSON.stringify({ template_id: templateId, mobile: formattedPhone, authkey: authKey, otp: code });
  const options = {
    hostname: 'control.msg91.com',
    path: '/api/v5/otp',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  };
  const req = https.request(options, res => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => console.log('[SMS OTP] MSG91 response:', data));
  });
  req.on('error', e => console.error('[SMS OTP] Error:', e.message));
  req.write(payload);
  req.end();
}

// ── Email OTP (for admin users) ───────────────────────────────────────────────

async function sendEmailOtp(email, code, name) {
  const nodemailer = require('nodemailer');

  if (!process.env.SMTP_HOST || !process.env.SMTP_USER) {
    // Dev mode — just log it
    console.log(`\n========================================`);
    console.log(`[DEV EMAIL OTP] To: ${email}`);
    console.log(`[DEV EMAIL OTP] Code: ${code}`);
    console.log(`========================================\n`);
    return true;
  }

  try {
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT || '587'),
      secure: process.env.SMTP_PORT === '465',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });

    await transporter.sendMail({
      from: `"${process.env.FROM_NAME || 'HappyKrishi'}" <${process.env.FROM_EMAIL || process.env.SMTP_USER}>`,
      to: email,
      subject: `Your HappyKrishi Admin OTP: ${code}`,
      html: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto">
          <h2 style="color:#2E7D32">HappyKrishi Admin OTP</h2>
          <p>Hi ${name || 'Admin'},</p>
          <p>Your one-time login code is:</p>
          <div style="font-size:36px;font-weight:bold;letter-spacing:10px;
               background:#E8F5E9;padding:20px;border-radius:8px;
               text-align:center;color:#1B5E20">${code}</div>
          <p style="color:#888;margin-top:16px">Valid for 10 minutes. Do not share.</p>
        </div>
      `,
    });
    console.log(`[Email OTP] Sent to ${email}`);
    return true;
  } catch (err) {
    console.error('[Email OTP] Error:', err.message);
    return false;
  }
}

// ── Main entry — email for admin; email+WhatsApp/SMS for customers ─────────────

async function sendSmsOtp(phone, code) {
  const db = require('../config/database');
  const user = db.prepare("SELECT email, name, role FROM users WHERE phone = ?").get(phone);

  const isAdmin = user && (user.role === 'admin' || user.role === 'subadmin');

  // Always send to email if the user has one
  if (user?.email) {
    const sent = await sendEmailOtp(user.email, code, user.name);
    if (sent) console.log(`[OTP] Sent to email: ${user.email}`);
    // For admins: email is the primary channel, don't fall through to SMS
    if (isAdmin && sent) return;
  }

  // For admins without email (or email failed) — still try WhatsApp/SMS
  // For all customers — send via WhatsApp/SMS too (parallel delivery)
  const whatsappConfigured = !!(process.env.WHATSAPP_TOKEN && process.env.WHATSAPP_PHONE_ID);
  const smsConfigured = !!process.env.MSG91_AUTH_KEY;

  if (!whatsappConfigured && !smsConfigured) {
    if (!user?.email) devLog(phone, code);   // only dev-log if email wasn't sent
    return;
  }

  if (whatsappConfigured) {
    const sent = await sendWhatsAppOtp(phone, code);
    if (sent) return;
    console.warn('[OTP] WhatsApp failed, falling back to SMS');
  }

  if (smsConfigured) {
    sendSmsOtp_msg91(phone, code);
  } else if (!user?.email) {
    devLog(phone, code);
  }
}

module.exports = { generateOtp, saveOtp, verifyOtp, sendSmsOtp, sendEmailOtp };
