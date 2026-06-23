const db = require('../config/database');
const { getFirebaseAdmin } = require('../config/firebase');

async function sendToUser(userId, title, body, data = {}) {
  try {
    const user = db.prepare('SELECT fcm_token FROM users WHERE id = ?').get(userId);
    if (!user?.fcm_token) return;

    const admin = getFirebaseAdmin();
    if (!admin) return;

    await admin.messaging().send({
      token: user.fcm_token,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    // Store in DB
    db.prepare(
      'INSERT INTO notifications (user_id, title, body, type, data_json) VALUES (?,?,?,?,?)'
    ).run(userId, title, body, data.type || null, data ? JSON.stringify(data) : null);
  } catch (err) {
    console.error('FCM send error:', err.message);
  }
}

async function sendToMany(userIds, title, body, data = {}) {
  await Promise.all(userIds.map(id => sendToUser(id, title, body, data)));
}

module.exports = { sendToUser, sendToMany };
