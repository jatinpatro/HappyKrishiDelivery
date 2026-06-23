const https = require('https');
const db = require('../config/database');

const PHONE_ID = process.env.WHATSAPP_PHONE_ID;
const TOKEN = process.env.WHATSAPP_TOKEN;

const TEMPLATES = {
  order_confirmed: { name: 'order_confirmed', language: 'en' },
  order_dispatched: { name: 'order_dispatched', language: 'en' },
  agent_nearby: { name: 'agent_nearby', language: 'en' },
  order_delivered: { name: 'order_delivered', language: 'en' },
  weight_adjusted: { name: 'weight_adjusted', language: 'en' },
  payment_reminder: { name: 'payment_reminder', language: 'en' },
};

function sendTemplate(userId, templateKey, components = []) {
  if (!PHONE_ID || !TOKEN) return;

  const user = db.prepare('SELECT phone FROM users WHERE id = ?').get(userId);
  if (!user?.phone) return;

  const tpl = TEMPLATES[templateKey];
  if (!tpl) return;

  const phone = user.phone.startsWith('+') ? user.phone : '+91' + user.phone;
  const payload = JSON.stringify({
    messaging_product: 'whatsapp',
    to: phone,
    type: 'template',
    template: {
      name: tpl.name,
      language: { code: tpl.language },
      components: components.length ? components : undefined,
    },
  });

  const options = {
    hostname: 'graph.facebook.com',
    path: `/v19.0/${PHONE_ID}/messages`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
    },
  };

  const req = https.request(options, res => {
    res.on('data', () => {});
  });
  req.on('error', err => console.error('WhatsApp send error:', err.message));
  req.write(payload);
  req.end();
}

function sendTextMessage(phone, text) {
  if (!PHONE_ID || !TOKEN) {
    console.log(`[DEV WhatsApp] To ${phone}: ${text.substring(0, 60)}...`);
    return;
  }
  const formattedPhone = phone.startsWith('+') ? phone : '+91' + phone;
  const payload = JSON.stringify({
    messaging_product: 'whatsapp',
    to: formattedPhone,
    type: 'text',
    text: { body: text },
  });
  const options = {
    hostname: 'graph.facebook.com',
    path: `/v19.0/${PHONE_ID}/messages`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
    },
  };
  const req = https.request(options, res => { res.on('data', () => {}); });
  req.on('error', err => console.error('WhatsApp text error:', err.message));
  req.write(payload);
  req.end();
}

module.exports = { sendTemplate, sendTextMessage };
