const db = require('../config/database');

// ── Customer: submit a custom delivery request ────────────────────────────────
async function submitRequest(req, res) {
  const userId = req.user.id;
  const { pincode, address, note } = req.body;

  if (!pincode || !address) {
    return res.status(400).json({ error: 'pincode and address are required' });
  }
  if (!/^\d{6}$/.test(pincode.trim())) {
    return res.status(400).json({ error: 'Enter a valid 6-digit pincode' });
  }

  const user = db.prepare('SELECT name, phone FROM users WHERE id = ?').get(userId);

  // Check if already has a pending request for this pincode
  const existing = db.prepare(
    "SELECT id FROM custom_delivery_requests WHERE user_id = ? AND pincode = ? AND status = 'pending'"
  ).get(userId, pincode.trim());
  if (existing) {
    return res.status(409).json({ error: 'You already have a pending request for this pincode' });
  }

  // Get distance from cache if available
  const cached = db.prepare('SELECT distance_km FROM pincode_cache WHERE pincode = ?').get(pincode.trim());

  const result = db.prepare(`
    INSERT INTO custom_delivery_requests (user_id, name, phone, pincode, address, note, distance_km)
    VALUES (?,?,?,?,?,?,?)
  `).run(userId, user.name, user.phone, pincode.trim(), address.trim(), note?.trim() || null,
         cached?.distance_km || null);

  res.status(201).json({
    message: 'Request submitted! We will review and contact you shortly.',
    id: result.lastInsertRowid,
  });
}

// ── Customer: list own requests ───────────────────────────────────────────────
function myRequests(req, res) {
  const requests = db.prepare(
    'SELECT * FROM custom_delivery_requests WHERE user_id = ? ORDER BY created_at DESC'
  ).all(req.user.id);
  res.json({ requests });
}

// ── Admin: list all requests ──────────────────────────────────────────────────
function listRequests(req, res) {
  const { status } = req.query;
  let sql = `SELECT r.*, u.email FROM custom_delivery_requests r
             LEFT JOIN users u ON u.id = r.user_id`;
  const params = [];
  if (status) { sql += ' WHERE r.status = ?'; params.push(status); }
  sql += ' ORDER BY r.created_at DESC';
  res.json({ requests: db.prepare(sql).all(...params) });
}

// ── Admin: approve ────────────────────────────────────────────────────────────
function approveRequest(req, res) {
  const id = parseInt(req.params.id);
  const { admin_note, min_order_amount, allowed_product_ids, custom_delivery_charge } = req.body;
  const row = db.prepare('SELECT * FROM custom_delivery_requests WHERE id = ?').get(id);
  if (!row) return res.status(404).json({ error: 'Request not found' });

  db.prepare(
    "UPDATE custom_delivery_requests SET status='approved', admin_note=?, updated_at=datetime('now') WHERE id=?"
  ).run(admin_note || null, id);

  // Whitelist the pincode with custom rules
  const allowedIds = Array.isArray(allowed_product_ids) && allowed_product_ids.length > 0
    ? JSON.stringify(allowed_product_ids.map(Number))
    : null;

  db.prepare(
    `INSERT OR REPLACE INTO pincode_cache
       (pincode, lat, lng, district, state, deliverable, distance_km,
        min_order_amount, allowed_product_ids, custom_delivery_charge)
     VALUES (?,
       COALESCE((SELECT lat FROM pincode_cache WHERE pincode=?), NULL),
       COALESCE((SELECT lng FROM pincode_cache WHERE pincode=?), NULL),
       COALESCE((SELECT district FROM pincode_cache WHERE pincode=?), ''),
       COALESCE((SELECT state FROM pincode_cache WHERE pincode=?), ''),
       1,
       COALESCE((SELECT distance_km FROM pincode_cache WHERE pincode=?), NULL),
       ?, ?, ?)`
  ).run(
    row.pincode,
    row.pincode, row.pincode, row.pincode, row.pincode, row.pincode,
    min_order_amount ? parseFloat(min_order_amount) : null,
    allowedIds,
    custom_delivery_charge ? parseFloat(custom_delivery_charge) : null
  );

  try {
    const notificationService = require('../services/notificationService');
    notificationService.sendToUser(row.user_id,
      'Delivery Approved! 🎉',
      `Great news! We can now deliver to pincode ${row.pincode}. You can now place orders to this area.`
    );
  } catch (_) {}

  res.json({ message: 'Request approved and pincode whitelisted' });
}

// ── Admin: reject ─────────────────────────────────────────────────────────────
function rejectRequest(req, res) {
  const id = parseInt(req.params.id);
  const { admin_note } = req.body;
  const row = db.prepare('SELECT * FROM custom_delivery_requests WHERE id = ?').get(id);
  if (!row) return res.status(404).json({ error: 'Request not found' });

  db.prepare(
    "UPDATE custom_delivery_requests SET status='rejected', admin_note=?, updated_at=datetime('now') WHERE id=?"
  ).run(admin_note || null, id);

  try {
    const notificationService = require('../services/notificationService');
    notificationService.sendToUser(row.user_id,
      'Delivery Request Update',
      `Unfortunately, we're unable to deliver to pincode ${row.pincode} at this time.${admin_note ? ' ' + admin_note : ''}`
    );
  } catch (_) {}

  res.json({ message: 'Request rejected' });
}

// ── Admin: list all whitelisted (custom) pincodes ─────────────────────────────
function listWhitelistedPincodes(req, res) {
  const pincodes = db.prepare(`
    SELECT pc.pincode, pc.district, pc.state, pc.distance_km,
           pc.min_order_amount, pc.allowed_product_ids, pc.custom_delivery_charge,
           pc.checked_at,
           COUNT(DISTINCT a.id) as address_count,
           r.id as request_id, r.name as requester_name, r.phone as requester_phone
    FROM pincode_cache pc
    LEFT JOIN addresses a ON a.pincode = pc.pincode
    LEFT JOIN custom_delivery_requests r
      ON r.pincode = pc.pincode AND r.status = 'approved'
    WHERE pc.deliverable = 1
      AND (
        pc.distance_km IS NOT NULL
        OR pc.min_order_amount IS NOT NULL
        OR pc.allowed_product_ids IS NOT NULL
        OR pc.custom_delivery_charge IS NOT NULL
      )
    GROUP BY pc.pincode
    ORDER BY COALESCE(pc.distance_km, 9999) ASC
  `).all();

  res.json({
    pincodes: pincodes.map(p => ({
      ...p,
      allowed_product_ids: p.allowed_product_ids ? JSON.parse(p.allowed_product_ids) : null,
    })),
  });
}

// ── Admin: remove a custom pincode whitelist ───────────────────────────────────
function removeWhitelistedPincode(req, res) {
  const { pincode } = req.params;
  if (!pincode) return res.status(400).json({ error: 'pincode required' });

  const row = db.prepare('SELECT * FROM pincode_cache WHERE pincode = ? AND deliverable = 1').get(pincode);
  if (!row) return res.status(404).json({ error: 'Pincode not found or not whitelisted' });

  // Mark as not deliverable instead of deleting — so existing addresses are blocked at order time
  db.prepare(
    "UPDATE pincode_cache SET deliverable=0, min_order_amount=NULL, allowed_product_ids=NULL, custom_delivery_charge=NULL WHERE pincode=?"
  ).run(pincode);

  // Mark any approved requests for this pincode as revoked
  db.prepare(`
    UPDATE custom_delivery_requests SET status='rejected', admin_note='Delivery area removed by admin', updated_at=datetime('now')
    WHERE pincode = ? AND status = 'approved'
  `).run(pincode);

  try {
    // Notify affected customers
    const affected = db.prepare(`
      SELECT DISTINCT u.id FROM users u
      JOIN addresses a ON a.user_id = u.id
      WHERE a.pincode = ?
    `).all(pincode);
    const notificationService = require('../services/notificationService');
    for (const user of affected) {
      notificationService.sendToUser(user.id,
        'Delivery Area Update',
        `Unfortunately, we've had to stop deliveries to pincode ${pincode}. Please contact us for alternatives.`
      );
    }
  } catch (_) {}

  res.json({ message: `Pincode ${pincode} removed from delivery area` });
}

// ── Admin: update rules for an existing whitelisted pincode ───────────────────
function updateWhitelistedPincode(req, res) {
  const { pincode } = req.params;
  const { min_order_amount, allowed_product_ids, custom_delivery_charge } = req.body;

  const row = db.prepare('SELECT * FROM pincode_cache WHERE pincode = ? AND deliverable = 1').get(pincode);
  if (!row) return res.status(404).json({ error: 'Pincode not found or not whitelisted' });

  const allowedIds = Array.isArray(allowed_product_ids) && allowed_product_ids.length > 0
    ? JSON.stringify(allowed_product_ids.map(Number))
    : null;

  db.prepare(`
    UPDATE pincode_cache
    SET min_order_amount = ?,
        allowed_product_ids = ?,
        custom_delivery_charge = ?
    WHERE pincode = ?
  `).run(
    min_order_amount != null ? parseFloat(min_order_amount) : null,
    allowedIds,
    custom_delivery_charge != null ? parseFloat(custom_delivery_charge) : null,
    pincode
  );

  res.json({ message: 'Pincode rules updated', pincode });
}

module.exports = {
  submitRequest, myRequests,
  listRequests, approveRequest, rejectRequest,
  listWhitelistedPincodes, removeWhitelistedPincode, updateWhitelistedPincode,
};
