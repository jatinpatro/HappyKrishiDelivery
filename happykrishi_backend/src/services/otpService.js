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
  const payload = JSON.stringify({
    template_id: templateId,
    mobile: formattedPhone,
    otp: code,
  });
  const options = {
    hostname: 'control.msg91.com',
    path: '/api/v5/otp',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'authkey': authKey,
    },
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

// ── Email OTP ─────────────────────────────────────────────────────────────────

async function sendEmailOtp(email, code, name, purpose = 'login') {
  const nodemailer = require('nodemailer');

  if (!process.env.SMTP_HOST || !process.env.SMTP_USER) {
    console.log(`\n========================================`);
    console.log(`[DEV EMAIL OTP] To: ${email}`);
    console.log(`[DEV EMAIL OTP] Code: ${code}`);
    console.log(`========================================\n`);
    return true;
  }

  const subjectMap = {
    login: `Your HappyKrishi login OTP: ${code}`,
    verify_email: `Verify your HappyKrishi email: ${code}`,
    change_password: `HappyKrishi password change OTP: ${code}`,
  };
  const headingMap = {
    login: 'Your Login OTP',
    verify_email: 'Verify Your Email',
    change_password: 'Password Change OTP',
  };
  const bodyMap = {
    login: 'Use this code to log in to your HappyKrishi account.',
    verify_email: 'Use this code to verify your email address.',
    change_password: 'Use this code to confirm your password change.',
  };

  const subject = subjectMap[purpose] || subjectMap.login;
  const heading = headingMap[purpose] || headingMap.login;
  const bodyText = bodyMap[purpose] || bodyMap.login;

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
      subject,
      html: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto">
          <h2 style="color:#2E7D32">HappyKrishi — ${heading}</h2>
          <p>Hi ${name || 'there'},</p>
          <p>${bodyText}</p>
          <div style="font-size:36px;font-weight:bold;letter-spacing:10px;
               background:#E8F5E9;padding:20px;border-radius:8px;
               text-align:center;color:#1B5E20">${code}</div>
          <p style="color:#888;margin-top:16px">Valid for 10 minutes. Do not share this code with anyone.</p>
          <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
          <p style="color:#bbb;font-size:12px">If you didn't request this, please ignore this email or contact us at ${process.env.SUPPORT_EMAIL || 'support@happykrishi.com'}.</p>
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
  const user = db.prepare("SELECT email, name, role, email_verified FROM users WHERE phone = ?").get(phone);

  const isAdmin = user && (user.role === 'admin' || user.role === 'subadmin');

  // Admins always get OTP via email (no SMS for admins)
  if (isAdmin && user?.email) {
    const sent = await sendEmailOtp(user.email, code, user.name, 'login');
    if (sent) console.log(`[OTP] Sent to email: ${user.email}`);
    return sent;
  }

  // Customers with VERIFIED email get OTP via email (free)
  if (user?.email && user.email_verified) {
    const sent = await sendEmailOtp(user.email, code, user.name, 'login');
    if (sent) {
      console.log(`[OTP] Sent to email: ${user.email}`);
      return true;
    }
    // Email failed — fall through to SMS
  }

  // No verified email → try SMS/WhatsApp

  const whatsappConfigured = !!(process.env.WHATSAPP_TOKEN && process.env.WHATSAPP_PHONE_ID);
  const smsConfigured = !!process.env.MSG91_AUTH_KEY;

  if (!whatsappConfigured && !smsConfigured) {
    devLog(phone, code);
    return false; // no SMS channel configured
  }

  if (whatsappConfigured) {
    const sent = await sendWhatsAppOtp(phone, code);
    if (sent) return true;
    console.warn('[OTP] WhatsApp failed, falling back to SMS');
  }

  if (smsConfigured) {
    try {
      sendSmsOtp_msg91(phone, code);
      return true;
    } catch (e) {
      console.error('[OTP] SMS failed:', e);
      return false;
    }
  } else if (!user?.email) {
    devLog(phone, code);
  }
  return false;
}

module.exports = { generateOtp, saveOtp, verifyOtp, sendSmsOtp, sendEmailOtp };
