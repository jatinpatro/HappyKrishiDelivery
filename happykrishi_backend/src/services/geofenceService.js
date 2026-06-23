const db = require('../config/database');
const { haversineKm } = require('./deliveryChargeService');
const notificationService = require('./notificationService');
const whatsappService = require('./whatsappService');

function getConfig(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? parseFloat(row.value) : null;
}

function checkGeofence(agentLat, agentLng, orderId) {
  const order = db
    .prepare(`
      SELECT o.id, o.user_id, a.lat, a.lng
      FROM orders o
      JOIN addresses a ON a.id = o.address_id
      WHERE o.id = ?
    `)
    .get(orderId);

  if (!order || !order.lat || !order.lng) return;

  const radiusM = getConfig('geofence_radius_m') || 500;
  const distKm = haversineKm(agentLat, agentLng, order.lat, order.lng);

  if (distKm * 1000 <= radiusM) {
    // Avoid duplicate alerts — check if already sent in last 10 min
    const alreadySent = db
      .prepare(`
        SELECT id FROM notifications
        WHERE user_id = ? AND type = 'agent_nearby'
          AND reference_id = ?
          AND created_at > datetime('now', '-10 minutes')
      `)
      .get(order.user_id, orderId);

    if (!alreadySent) {
      notificationService.sendToUser(order.user_id, 'Delivery is near!', 'Your delivery agent is nearby 🚚');
      whatsappService.sendTemplate(order.user_id, 'agent_nearby', []);
    }
  }
}

module.exports = { checkGeofence };
