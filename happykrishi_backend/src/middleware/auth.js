const jwt = require('jsonwebtoken');
const db = require('../config/database');

// IST = UTC+5:30 — SQLite needs modifiers as separate arguments
const istNow = () => "datetime('now', '+5 hours', '+30 minutes')";

function authenticate(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing token' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    const user = db.prepare('SELECT id, name, phone, email, role, wallet_balance, is_active, tier_id, token_version FROM users WHERE id = ?').get(payload.id);
    if (!user || !user.is_active) return res.status(401).json({ error: 'User not found or inactive' });
    if ((user.token_version ?? 0) !== (payload.tv ?? 0)) {
      return res.status(401).json({ error: 'Session expired — please log in again' });
    }
    req.user = user;
    // Update last_active_at on every authenticated request (non-blocking)
    db.prepare(`UPDATE users SET last_active_at=${istNow()} WHERE id=?`).run(user.id);
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = { authenticate, istNow };
