const db = require('../config/database');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');
const whatsappService = require('../services/whatsappService');
const emailService = require('../services/emailService');
const { checkGeofence } = require('../services/geofenceService');
const wsServer = require('../websocket/server');
const { recalculateCustomerTier } = require('../services/tierService');

function getMyOrder(req, res) {
  const userId = req.user.id;
  const agentUser = db.prepare('SELECT id FROM delivery_agents WHERE user_id = ?').get(userId);

  let delivery;
  if (agentUser) {
    delivery = db.prepare(`
      SELECT d.*, o.order_number, o.delivery_date, o.final_amount,
             s.label as slot_label, s.start_time, s.end_time,
             a.address_line, a.city, a.pincode, a.lat, a.lng,
             u.name as customer_name, u.phone as customer_phone
      FROM deliveries d
      JOIN orders o ON o.id = d.order_id
      LEFT JOIN delivery_slots s ON s.id = o.slot_id
      JOIN addresses a ON a.id = o.address_id
      JOIN users u ON u.id = o.user_id
      WHERE d.agent_id = ? AND d.status IN ('assigned','picked')
      ORDER BY d.assigned_at DESC LIMIT 1
    `).get(agentUser.id);
  }
  // Salesman assigned via orders.salesman_id
  if (!delivery) {
    delivery = db.prepare(`
      SELECT d.*, o.order_number, o.delivery_date, o.final_amount,
             s.label as slot_label, s.start_time, s.end_time,
             a.address_line, a.city, a.pincode, a.lat, a.lng,
             u.name as customer_name, u.phone as customer_phone
      FROM deliveries d
      JOIN orders o ON o.id = d.order_id
      LEFT JOIN delivery_slots s ON s.id = o.slot_id
      LEFT JOIN addresses a ON a.id = o.address_id
      JOIN users u ON u.id = o.user_id
      WHERE o.salesman_id = ? AND d.status IN ('assigned','picked')
      ORDER BY d.assigned_at DESC LIMIT 1
    `).get(userId);
  }

  if (!delivery) return res.json({ delivery: null });

  const items = db.prepare(`
    SELECT oi.*, p.name as product_name, p.unit, p.is_weight_adjusted
    FROM order_items oi JOIN products p ON p.id = oi.product_id
    WHERE oi.order_id = ?
  `).all(delivery.order_id);

  res.json({ delivery, items });
}

function updateLocation(req, res) {
  const { lat, lng } = req.body;
  if (!lat || !lng) return res.status(400).json({ error: 'lat and lng required' });
  const userId = req.user.id;

  // Auto-register salesman in delivery_agents if not present (for location tracking)
  let agent = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(userId);
  if (!agent) {
    db.prepare('INSERT OR IGNORE INTO delivery_agents (user_id, is_available) VALUES (?,1)').run(userId);
    agent = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(userId);
  }
  if (!agent) return res.status(404).json({ error: 'Location tracking not available' });

  db.prepare("UPDATE delivery_agents SET current_lat=?, current_lng=?, last_seen_at=datetime('now') WHERE id=?").run(lat, lng, agent.id);

  // Find active delivery — check both assignment paths:
  // 1. Legacy: deliveries.agent_id (delivery_agents table)
  // 2. Current: orders.salesman_id (direct salesman assignment)
  let delivery = db.prepare("SELECT * FROM deliveries WHERE agent_id = ? AND status IN ('assigned','picked')").get(agent.id);
  if (!delivery) {
    delivery = db.prepare(`
      SELECT d.* FROM deliveries d
      JOIN orders o ON o.id = d.order_id
      WHERE o.salesman_id = ? AND d.status IN ('assigned','picked')
    `).get(userId);
  }
  if (delivery) {
    // Broadcast to WebSocket clients tracking this order
    wsServer.broadcast(delivery.order_id, { type: 'location', lat, lng, order_id: delivery.order_id });
    // Geofence check
    checkGeofence(lat, lng, delivery.order_id);
  }

  res.json({ message: 'Location updated' });
}

function markPicked(req, res) {
  const { id } = req.params;
  const userId = req.user.id;

  // Support both: agent (delivery_agents) and salesman (orders.salesman_id)
  const agent = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(userId);

  let delivery;
  if (agent) {
    delivery = db.prepare('SELECT * FROM deliveries WHERE id = ? AND agent_id = ?').get(id, agent.id);
  }
  // Fallback: salesman assigned via orders.salesman_id
  if (!delivery) {
    delivery = db.prepare('SELECT d.* FROM deliveries d JOIN orders o ON o.id = d.order_id WHERE d.id = ? AND o.salesman_id = ?').get(id, userId);
  }
  if (!delivery) return res.status(404).json({ error: 'Delivery not found or not assigned to you' });
  if (delivery.status !== 'assigned') return res.status(400).json({ error: 'Order not in assigned state' });

  db.prepare("UPDATE deliveries SET status='picked', picked_at=datetime('now') WHERE id=?").run(id);
  db.prepare("UPDATE orders SET status='dispatched', updated_at=datetime('now') WHERE id=?").run(delivery.order_id);

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(delivery.order_id);
  const deliveryCode = db.prepare('SELECT delivery_code FROM deliveries WHERE id=?').get(id)?.delivery_code;
  notificationService.sendToUser(order.user_id, 'Order On the Way! 🚚',
    `Your salesman is heading to you. Open the app to see your delivery code${deliveryCode ? ' (${deliveryCode})' : ''} — share it when they arrive.`);
  whatsappService.sendTemplate(order.user_id, 'order_dispatched', []);
  wsServer.broadcast(delivery.order_id, { type: 'status', status: 'dispatched' });

  res.json({ message: 'Marked as picked up' });
}

function markDelivered(req, res) {
  const { id } = req.params;
  const { actual_weights, code } = req.body;
  const userId = req.user.id;

  const agent = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(userId);

  let delivery;
  if (agent) {
    delivery = db.prepare('SELECT * FROM deliveries WHERE id = ? AND agent_id = ?').get(id, agent.id);
  }
  // Fallback: salesman assigned via orders.salesman_id
  if (!delivery) {
    delivery = db.prepare('SELECT d.* FROM deliveries d JOIN orders o ON o.id = d.order_id WHERE d.id = ? AND o.salesman_id = ?').get(id, userId);
  }
  if (!delivery) return res.status(404).json({ error: 'Delivery not found or not assigned to you' });
  if (!['picked', 'assigned'].includes(delivery.status)) {
    return res.status(400).json({ error: 'Order must be picked up or assigned (pickup orders)' });
  }

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(delivery.order_id);
  // Pickup orders skip "picked" step — only allow if it's a pickup
  if (delivery.status === 'assigned' && order.order_type !== 'pickup') {
    return res.status(400).json({ error: 'Delivery orders must be marked picked first' });
  }

  // ── Delivery code check ────────────────────────────────────────────────────
  const requireCode = db.prepare("SELECT value FROM app_config WHERE key='require_delivery_code'").get()?.value !== '0';
  if (requireCode && order.order_type === 'delivery') {
    const alreadyConfirmed = !!delivery.customer_confirmed_at;
    if (!alreadyConfirmed) {
      if (!code) return res.status(400).json({ error: 'delivery_code_required', message: 'Enter the 6-digit code from the customer' });
      if (String(code).trim() !== String(delivery.delivery_code)) {
        return res.status(400).json({ error: 'invalid_delivery_code', message: 'Incorrect code — ask the customer to check their app' });
      }
    }
  }
  // ──────────────────────────────────────────────────────────────────────────
  const items = db.prepare('SELECT oi.*, p.name as product_name, p.unit FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?').all(order.id);

  const adjustments = [];

  db.transaction(() => {
    for (const item of items) {
      if (!item.is_weight_adjusted) continue;
      const actualEntry = (actual_weights || []).find(w => w.order_item_id === item.id);
      if (!actualEntry) continue;

      const actualQty = parseFloat(actualEntry.actual_qty);
      const actualTotal = parseFloat((item.unit_price * actualQty).toFixed(2));

      // Diff against whatever is already billed (actual_total if admin already adjusted, else estimated_total)
      const previousTotal = item.actual_total != null ? item.actual_total : item.estimated_total;
      const diffAmount = parseFloat((actualTotal - previousTotal).toFixed(2));

      db.prepare("UPDATE order_items SET actual_qty=?, actual_total=? WHERE id=?").run(actualQty, actualTotal, item.id);
      adjustments.push({
        name: item.product_name,
        unit: item.unit || '',
        estimated_qty: item.estimated_qty,
        actual_qty: actualQty,
        estimated_total: item.estimated_total,
        actual_total: actualTotal,
        diff: diffAmount,
        diff_amount: diffAmount,
      });
    }

    db.prepare("UPDATE deliveries SET status='delivered', delivered_at=datetime('now'), actual_weight_recorded_at=datetime('now') WHERE id=?").run(id);
    db.prepare("UPDATE orders SET status='delivered', payment_status='adjusted', updated_at=datetime('now') WHERE id=?").run(order.id);

    // Process weight adjustments inline (avoid nested transaction)
    const netAdjustments = adjustments.filter(a => Math.abs(a.diff_amount) > 0.005);
    if (netAdjustments.length > 0) {
      let totalDiff = netAdjustments.reduce((s, a) => s + a.diff_amount, 0);
      const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(order.user_id);
      let newBal;

      // Build a compact per-product detail string stored in description:
      // "ProductName: 1.2kg→0.9kg (₹-6); OtherProduct: 0.5kg→0.7kg (₹+4)"
      const detailParts = netAdjustments.map(a => {
        const sign = a.diff > 0 ? '+' : '';
        const u = a.unit ? a.unit : '';
        return `${a.name}: ${a.estimated_qty}${u}→${a.actual_qty}${u} (₹${sign}${a.diff.toFixed(2)})`;
      });
      const detail = detailParts.join('; ');

      if (totalDiff > 0) {
        // Customer owes more — debit (floor at 0)
        if (userRow.wallet_balance - totalDiff < 0) totalDiff = userRow.wallet_balance;
        newBal = parseFloat((userRow.wallet_balance - totalDiff).toFixed(2));
        db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBal, order.user_id);
        db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description) VALUES (?,?,?,?,?,?,?)`)
          .run(order.user_id, 'adjustment', totalDiff, newBal, 'order', order.id,
               `Weight adjustment: ${detail}`);
      } else if (totalDiff < 0) {
        // Refund
        newBal = parseFloat((userRow.wallet_balance + Math.abs(totalDiff)).toFixed(2));
        db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBal, order.user_id);
        db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description) VALUES (?,?,?,?,?,?,?)`)
          .run(order.user_id, 'refund', Math.abs(totalDiff), newBal, 'order', order.id,
               `Weight adjustment (refund): ${detail}`);
      }
      setImmediate(() => recalculateCustomerTier(order.user_id));
    }
  })();

  const updatedUser = db.prepare('SELECT wallet_balance, email FROM users WHERE id = ?').get(order.user_id);
  notificationService.sendToUser(order.user_id, 'Order Delivered!', `Your order #${order.order_number} has been delivered.`);
  const deliveredCustomer = db.prepare('SELECT name FROM users WHERE id=?').get(order.user_id);
  notificationService.sendToAdmins('Order Delivered ✅', `Order #${order.order_number} delivered to ${deliveredCustomer?.name ?? 'customer'} — ₹${order.final_amount?.toFixed(2) ?? ''}`, { type: 'order_delivered', order_id: String(order.id) });

  // ── Referral first-order bonus — fires on delivery (not on order placement) ──
  try {
    const deliveredCount = db.prepare("SELECT COUNT(*) as c FROM orders WHERE user_id=? AND status='delivered'").get(order.user_id).c;
    if (deliveredCount === 1) { // this IS the first delivered order
      const coupon = db.prepare('SELECT * FROM referral_coupons WHERE used_by_user_id=? AND bonus_credited_at IS NULL').get(order.user_id);
      if (coupon) {
        const bonusAmount = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='referral_first_order_bonus'").get()?.value || '0');
        if (bonusAmount > 0) {
          walletService.credit(coupon.owner_user_id, bonusAmount, 'credit', 'referral_bonus', coupon.id,
            `Referral bonus — your friend received their first delivery`);
          db.prepare("UPDATE referral_coupons SET bonus_credit_amount=?, bonus_credited_at=datetime('now') WHERE id=?").run(bonusAmount, coupon.id);
          notificationService.sendToUser(coupon.owner_user_id, 'Referral Bonus! 🎁',
            `₹${bonusAmount} added to your wallet — your referral just received their first delivery!`);
        }
      }
    }
  } catch (e) { console.error('[Referral delivery bonus]', e); }
  // ──────────────────────────────────────────────────────────────────────────
  whatsappService.sendTemplate(order.user_id, 'order_delivered', []);
  const netAdjustmentsOut = adjustments.filter(a => Math.abs(a.diff_amount) > 0.005);
  if (netAdjustmentsOut.length > 0) {
    whatsappService.sendTemplate(order.user_id, 'weight_adjusted', []);
    if (updatedUser.email) emailService.sendWeightAdjustmentReceipt(updatedUser.email, order, netAdjustmentsOut).catch(() => {});
  }
  wsServer.broadcast(delivery.order_id, { type: 'status', status: 'delivered' });

  res.json({ message: 'Delivered', adjustments, wallet_balance: updatedUser.wallet_balance });
}

module.exports = { getMyOrder, updateLocation, markPicked, markDelivered };
