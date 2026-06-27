const db = require('../config/database');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

function generateDeliveryCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// Helper to read a single app_config value
function getConfigValue(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? row.value : null;
}

// ── Waive delivery charge (admin or salesman) ────────────────────────────────
function waiveDeliveryCharge(req, res) {
  const orderId = parseInt(req.params.id);
  const { amount, note } = req.body; // amount = how much to waive (null = full charge)

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (['delivered', 'cancelled'].includes(order.status)) {
    return res.status(400).json({ error: 'Cannot waive delivery charge on a delivered or cancelled order' });
  }
  if (!order.delivery_charge || order.delivery_charge <= 0) {
    return res.status(400).json({ error: 'This order has no delivery charge to waive' });
  }

  const waiveAmount = amount != null
    ? Math.min(parseFloat(amount), order.delivery_charge)
    : order.delivery_charge;

  if (waiveAmount <= 0) return res.status(400).json({ error: 'Waive amount must be greater than 0' });

  const newDeliveryCharge = parseFloat((order.delivery_charge - waiveAmount).toFixed(2));
  const newFinalAmount    = parseFloat((order.final_amount - waiveAmount).toFixed(2));

  db.prepare(`
    UPDATE orders SET delivery_charge=?, final_amount=?, updated_at=datetime('now') WHERE id=?
  `).run(newDeliveryCharge, newFinalAmount, orderId);

  const waiversBy = req.user.role === 'admin' || req.user.role === 'subadmin' ? 'Admin' : 'Salesman';
  const description = note
    ? `Delivery charge waived by ${waiversBy} — ${note}`
    : `Delivery charge waived by ${waiversBy}`;

  const newBalance = walletService.credit(
    order.user_id, waiveAmount, 'refund', 'delivery_waiver', orderId, description
  );

  const user = db.prepare('SELECT name FROM users WHERE id=?').get(order.user_id);
  notificationService.sendToUser(order.user_id, 'Delivery Charge Waived! 🎉',
    `₹${waiveAmount.toFixed(0)} delivery charge waived for order #${order.order_number}. Amount credited to your wallet.`);

  res.json({
    message: `₹${waiveAmount.toFixed(0)} delivery charge waived`,
    waived_amount: waiveAmount,
    new_delivery_charge: newDeliveryCharge,
    new_final_amount: newFinalAmount,
    new_wallet_balance: newBalance,
    customer_name: user?.name,
  });
}

function getDashboard(req, res) {
  const stats = {
    total_orders: db.prepare("SELECT COUNT(*) as c FROM orders WHERE date(created_at) = date('now')").get().c,
    pending_orders: db.prepare("SELECT COUNT(*) as c FROM orders WHERE status = 'pending'").get().c,
    active_deliveries: db.prepare("SELECT COUNT(*) as c FROM deliveries d JOIN orders o ON o.id = d.order_id WHERE d.status IN ('assigned','picked') AND o.status != 'cancelled'").get().c,
    agents_online: db.prepare("SELECT COUNT(*) as c FROM delivery_agents WHERE last_seen_at > datetime('now', '-5 minutes')").get().c,
    todays_revenue: db.prepare("SELECT COALESCE(SUM(final_amount),0) as s FROM orders WHERE date(created_at) = date('now') AND status != 'cancelled'").get().s,
    pending_topups: db.prepare("SELECT COUNT(*) as c FROM topup_requests WHERE status = 'pending'").get().c,
    low_stock_products: db.prepare("SELECT COUNT(*) as c FROM products WHERE stock_qty <= low_stock_threshold AND is_active = 1").get().c,
    pending_custom_delivery: db.prepare("SELECT COUNT(*) as c FROM custom_delivery_requests WHERE status = 'pending'").get().c,
  };
  res.json({ stats });
}

function adminListOrders(req, res) {
  const { status, date, date_from, date_to, agent_id, order_type, search, salesman_id, page = 1, limit = 50 } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  let where = '1=1';
  const params = [];
  if (status) { where += ' AND o.status = ?'; params.push(status); }
  if (date) { where += ' AND date(o.delivery_date) = ?'; params.push(date); }
  if (date_from) { where += ' AND date(o.delivery_date) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(o.delivery_date) <= ?'; params.push(date_to); }
  if (order_type) { where += ' AND o.order_type = ?'; params.push(order_type); }
  if (salesman_id) { where += ' AND o.salesman_id = ?'; params.push(parseInt(salesman_id)); }
  if (search) {
    const like = `%${search}%`;
    where += ` AND (
      o.order_number LIKE ?
      OR u.name LIKE ? OR u.phone LIKE ?
      OR o.cancelled_reason LIKE ?
      OR EXISTS (
        SELECT 1 FROM deliveries d2
        JOIN delivery_agents da2 ON da2.id = d2.agent_id
        JOIN users au2 ON au2.id = da2.user_id
        WHERE d2.order_id = o.id AND au2.name LIKE ?
      )
      OR EXISTS (
        SELECT 1 FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        LEFT JOIN categories cat ON cat.id = p.category_id
        WHERE oi.order_id = o.id AND (p.name LIKE ? OR cat.name LIKE ?)
      )
    )`;
    params.push(like, like, like, like, like, like, like);
  }

  const orders = db.prepare(`
    SELECT o.*, u.name as customer_name, u.phone as customer_phone,
           u.wallet_balance as customer_wallet_balance,
           s.label as slot_label, a.address_line, a.city, a.pincode,
           d.status as delivery_status, au.name as agent_name, au.phone as agent_phone,
           sm.name as salesman_name, sm.phone as salesman_phone,
           pc.code as coupon_code, pcu.discount_amount as coupon_discount
    FROM orders o
    JOIN users u ON u.id = o.user_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    LEFT JOIN delivery_agents da ON da.id = d.agent_id
    LEFT JOIN users au ON au.id = da.user_id
    LEFT JOIN users sm ON sm.id = o.salesman_id
    LEFT JOIN promo_code_uses pcu ON pcu.order_id = o.id
    LEFT JOIN promo_codes pc ON pc.id = pcu.promo_code_id
    WHERE ${where}
    ORDER BY o.created_at DESC LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);

  const total = db.prepare(`
    SELECT COUNT(*) as c FROM orders o
    JOIN users u ON u.id = o.user_id
    WHERE ${where}
  `).get(...params).c;
  res.json({ orders, total });
}

function updateOrderStatus(req, res) {
  const { status, reason } = req.body;
  const valid = ['confirmed', 'assigned', 'picked', 'dispatched', 'delivered', 'cancelled'];
  if (!valid.includes(status)) return res.status(400).json({ error: 'Invalid status' });

  // Require reason when cancelling via status update
  if (status === 'cancelled' && (!reason || reason.trim() === '')) {
    return res.status(400).json({ error: 'A reason is required to cancel an order' });
  }

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  db.prepare("UPDATE orders SET status=?, cancelled_reason=?, updated_at=datetime('now') WHERE id=?").run(status, reason || null, order.id);

  // Sync deliveries table
  if (status === 'dispatched') {
    db.prepare("UPDATE deliveries SET status='picked', picked_at=datetime('now') WHERE order_id=?").run(order.id);
  } else if (status === 'delivered') {
    db.prepare("UPDATE deliveries SET status='delivered', delivered_at=datetime('now') WHERE order_id=?").run(order.id);
    db.prepare("UPDATE orders SET payment_status='paid' WHERE id=? AND payment_status='pending'").run(order.id);
  } else if (status === 'cancelled') {
    db.prepare("UPDATE deliveries SET status='cancelled', updated_at=datetime('now') WHERE order_id=? AND status NOT IN ('delivered','cancelled')").run(order.id);
  }

  if (status === 'cancelled' && order.status !== 'cancelled') {
    walletService.credit(order.user_id, order.final_amount, 'refund', 'order', order.id, `Admin cancelled order #${order.order_number}`);
    notificationService.sendToUser(order.user_id, 'Order Cancelled', `Your order #${order.order_number} was cancelled. Refund added to wallet.`);
    const items = db.prepare('SELECT * FROM order_items WHERE order_id = ?').all(order.id);
    for (const item of items) {
      db.prepare('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?').run(item.estimated_qty, item.product_id);
    }
  } else {
    notificationService.sendToUser(order.user_id, 'Order Update', `Your order #${order.order_number} status: ${status}`);
  }

  // Auto-assign default salesman when confirming
  if (status === 'confirmed') {
    const defaultUserId = parseInt(getConfigValue('default_salesman_id') || '0');
    if (defaultUserId > 0) {
      const agentRow = db.prepare('SELECT * FROM delivery_agents WHERE user_id=?').get(defaultUserId);
      if (agentRow) {
        db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now'), delivery_code=? WHERE order_id=?")
          .run(agentRow.id, generateDeliveryCode(), order.id);
        db.prepare("UPDATE orders SET status='assigned', updated_at=datetime('now') WHERE id=?").run(order.id);
        const agentUser = db.prepare('SELECT name FROM users WHERE id=?').get(defaultUserId);
        notificationService.sendToUser(defaultUserId, 'New Delivery Assigned', `Order #${order.order_number} auto-assigned to you`);
        notificationService.sendToUser(order.user_id, 'Agent Assigned', `${agentUser?.name || 'Our team'} will handle your order`);
        return res.json({ message: 'Confirmed and auto-assigned', auto_assigned: true });
      }
    }
  }

  res.json({ message: 'Status updated' });
}

// Mark pickup order as collected by customer
function markPickupCollected(req, res) {
  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (order.order_type !== 'pickup') return res.status(400).json({ error: 'Not a pickup order' });
  if (order.status === 'delivered') return res.status(400).json({ error: 'Already collected' });
  if (order.status === 'cancelled') return res.status(400).json({ error: 'Order is cancelled' });

  db.prepare("UPDATE orders SET status='delivered', payment_status='paid', updated_at=datetime('now') WHERE id=?").run(order.id);
  db.prepare("UPDATE deliveries SET status='delivered', delivered_at=datetime('now') WHERE order_id=?").run(order.id);
  notificationService.sendToUser(order.user_id, 'Order Collected ✅',
    `Pickup order #${order.order_number} marked as collected. Thank you!`);
  res.json({ message: 'Pickup marked as collected' });
}

function assignAgent(req, res) {
  const { agent_id } = req.body;
  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  // agent_id is a user ID — could be a salesman or a delivery agent
  const user = db.prepare("SELECT * FROM users WHERE id = ? AND role IN ('salesman','agent')").get(agent_id);
  if (!user) return res.status(404).json({ error: 'Salesman/agent not found' });

  if (user.role === 'salesman') {
    // Assign salesman directly on orders table
    db.prepare("UPDATE orders SET salesman_id=?, status='assigned', updated_at=datetime('now') WHERE id=?").run(agent_id, order.id);
    // Ensure a deliveries row exists with a delivery code
    const delivery = db.prepare('SELECT id FROM deliveries WHERE order_id=?').get(order.id);
    if (delivery) {
      db.prepare("UPDATE deliveries SET status='assigned', assigned_at=datetime('now') WHERE order_id=?").run(order.id);
    } else {
      db.prepare("INSERT INTO deliveries (order_id, status, delivery_code, assigned_at) VALUES (?,?,?,datetime('now'))").run(order.id, 'assigned', generateDeliveryCode());
    }
    notificationService.sendToUser(agent_id, 'Order Assigned', `Order #${order.order_number} assigned to you`);
  } else {
    // Legacy: delivery agent path via delivery_agents table
    const agent = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(agent_id);
    if (!agent) return res.status(404).json({ error: 'Delivery agent record not found' });
    db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now'), delivery_code=COALESCE(delivery_code,?) WHERE order_id=?").run(agent.id, generateDeliveryCode(), order.id);
    db.prepare("UPDATE orders SET status='assigned', updated_at=datetime('now') WHERE id=?").run(order.id);
    notificationService.sendToUser(agent_id, 'New Delivery Assigned', `Order #${order.order_number} assigned to you`);
  }

  notificationService.sendToUser(order.user_id, 'Salesman Assigned', 'A salesman has been assigned to your order');
  res.json({ message: 'Assigned successfully' });
}

function getAgents(req, res) {
  const agents = db.prepare(`
    SELECT da.*, u.name, u.phone, u.is_active, u.role
    FROM delivery_agents da
    JOIN users u ON u.id = da.user_id
    ORDER BY u.name
  `).all();
  res.json({ agents });
}

function createAgent(req, res) {
  const { name, phone, password } = req.body;
  if (!name || !phone) return res.status(400).json({ error: 'name and phone are required' });
  if (!/^[0-9]{10}$/.test(phone)) return res.status(400).json({ error: 'Phone must be 10 digits' });

  const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(phone);
  if (existing) return res.status(400).json({ error: 'Phone already registered' });

  const bcrypt = require('bcryptjs');
  const hash = password && password.length >= 6 ? bcrypt.hashSync(password, 10) : null;

  const userResult = db.prepare(
    "INSERT INTO users (name, phone, password_hash, password_set, role) VALUES (?,?,?,?,?)"
  ).run(name.trim(), phone, hash, hash ? 1 : 0, 'agent');

  const userId = userResult.lastInsertRowid;
  db.prepare('INSERT INTO delivery_agents (user_id) VALUES (?)').run(userId);

  const agent = db.prepare(`
    SELECT da.*, u.name, u.phone, u.is_active
    FROM delivery_agents da JOIN users u ON u.id = da.user_id
    WHERE da.user_id = ?
  `).get(userId);

  res.status(201).json({ message: 'Agent created', agent });
}

function toggleAgent(req, res) {
  const da = db.prepare('SELECT da.*, u.is_active FROM delivery_agents da JOIN users u ON u.id=da.user_id WHERE da.id=?').get(req.params.id);
  if (!da) return res.status(404).json({ error: 'Agent not found' });
  const newActive = da.is_active ? 0 : 1;
  db.prepare('UPDATE users SET is_active=? WHERE id=?').run(newActive, da.user_id);
  res.json({ message: newActive ? 'Agent activated' : 'Agent deactivated', is_active: newActive });
}

// ── Credit advance (admin gives wallet credit before payment) ─────────────────
function creditTopupAdmin(req, res) {
  const { user_id, amount, note } = req.body;
  if (!user_id || !amount || amount <= 0) return res.status(400).json({ error: 'user_id and valid amount required' });

  const user = db.prepare('SELECT id, name FROM users WHERE id = ? AND role = ?').get(user_id, 'customer');
  if (!user) return res.status(404).json({ error: 'Customer not found' });

  const result = db.prepare(`
    INSERT INTO topup_requests (user_id, amount, payment_method, collected_by, status, resolved_at, payment_received, credited_by_role, credited_by_id, admin_note)
    VALUES (?,?,'credit_advance',?,  'approved', datetime('now'), 0, 'admin', ?, ?)
  `).run(user_id, amount, String(req.user.id), req.user.id, note || null);

  const topupId = result.lastInsertRowid;
  const newBalance = walletService.credit(user_id, amount, 'credit', 'topup', topupId,
    `Credit advance by admin ${req.user.name || req.user.id}${note ? ': ' + note : ''}`);
  notificationService.sendToUser(user_id, 'Wallet Credited 💳',
    `₹${amount} credit advance added to your wallet by admin. Please pay when convenient.`);
  res.status(201).json({ message: 'Credit advance given', topup_id: topupId, new_balance: newBalance });
}

// ── Mark a credit advance as paid ────────────────────────────────────────────
function markCreditTopupPaid(req, res) {
  const tr = db.prepare("SELECT * FROM topup_requests WHERE id = ? AND payment_method = 'credit_advance' AND payment_received = 0").get(req.params.id);
  if (!tr) return res.status(404).json({ error: 'Credit advance not found or already marked paid' });

  db.prepare("UPDATE topup_requests SET payment_received=1, payment_received_at=datetime('now'), paid_by_role='admin', updated_at=datetime('now') WHERE id=?").run(tr.id);
  const user = db.prepare('SELECT name FROM users WHERE id=?').get(tr.user_id);
  notificationService.sendToUser(tr.user_id, 'Payment Received ✅',
    `Your payment of ₹${tr.amount} has been received. Thank you!`);
  res.json({ message: `Payment of ₹${tr.amount} marked as received from ${user?.name ?? 'customer'}` });
}

function creditWallet(req, res) {
  const { user_id, amount, description } = req.body;
  if (!user_id || !amount || amount <= 0) return res.status(400).json({ error: 'user_id and valid amount required' });

  const user = db.prepare('SELECT id, name FROM users WHERE id = ?').get(user_id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const newBalance = walletService.credit(user_id, amount, 'credit', 'admin', req.user.id, description || 'Admin credit');
  notificationService.sendToUser(user_id, 'Wallet Credited!', `₹${amount} added to your wallet. New balance: ₹${newBalance}`);
  res.json({ message: 'Wallet credited', new_balance: newBalance });
}

function debitWallet(req, res) {
  const { user_id, amount, description, order_id } = req.body;
  if (!user_id || !amount || amount <= 0) return res.status(400).json({ error: 'user_id and valid amount required' });
  if (!description || description.trim() === '') return res.status(400).json({ error: 'Reason/description is required for deduction' });

  const user = db.prepare('SELECT id, name, wallet_balance FROM users WHERE id = ?').get(user_id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  // Admin can deduct below zero — no balance check

  const refType = order_id ? 'order' : 'admin';
  const refId = order_id || req.user.id;
  const newBalance = walletService.debit(user_id, amount, 'debit', refType, refId, description.trim(), 0);
  notificationService.sendToUser(user_id, 'Wallet Deducted',
    `₹${amount} deducted from your wallet by admin. Reason: ${description.trim()}. Balance: ₹${newBalance}`);
  res.json({ message: 'Wallet deducted', new_balance: newBalance, deducted: amount });
}

function listUsers(req, res) {
  const { search, page = 1, limit = 50, wallet, sort = 'name', is_active } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  let where = "u.role = 'customer'";
  const params = [];

  if (search) {
    where += ' AND (u.name LIKE ? OR u.phone LIKE ? OR u.email LIKE ?)';
    params.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (wallet === 'negative')  { where += ' AND u.wallet_balance < 0'; }
  if (wallet === 'zero')      { where += ' AND u.wallet_balance = 0'; }
  if (wallet === 'positive')  { where += ' AND u.wallet_balance > 0'; }
  if (wallet === 'low')       { where += ' AND u.wallet_balance > 0 AND u.wallet_balance < 100'; }
  if (is_active === '1')      { where += ' AND u.is_active = 1'; }
  if (is_active === '0')      { where += ' AND u.is_active = 0'; }

  const orderBy = sort === 'wallet_asc'  ? 'u.wallet_balance ASC'
                : sort === 'wallet_desc' ? 'u.wallet_balance DESC'
                : sort === 'recent'      ? 'u.created_at DESC'
                : 'u.name';

  const users = db.prepare(`
    SELECT u.id, u.name, u.phone, u.email, u.wallet_balance, u.is_active, u.created_at,
           u.tier_id, ct.name as tier_name, ct.color as tier_color,
           ct.max_wallet_negative_limit as tier_neg_limit,
           ct.cashback_multiplier as tier_cashback_multiplier,
           CASE WHEN u.fcm_token IS NOT NULL THEN 1 ELSE 0 END as has_app
    FROM users u
    LEFT JOIN customer_tiers ct ON ct.id = u.tier_id
    WHERE ${where} ORDER BY ${orderBy} LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);
  const total = db.prepare(`SELECT COUNT(*) as c FROM users u WHERE ${where}`).get(...params).c;
  res.json({ users, total, page: parseInt(page), limit: parseInt(limit) });
}

function getConfig(req, res) {
  const config = db.prepare('SELECT key, value FROM app_config').all();
  const obj = {};
  config.forEach(r => { obj[r.key] = r.value; });
  res.json({ config: obj });
}

function updateConfig(req, res) {
  const { config } = req.body;
  if (!config || typeof config !== 'object') return res.status(400).json({ error: 'config object required' });

  const update = db.prepare("INSERT OR REPLACE INTO app_config (key, value, updated_at) VALUES (?,?,datetime('now'))");
  for (const [key, value] of Object.entries(config)) {
    update.run(key, String(value));
  }
  res.json({ message: 'Config updated' });
}

function listTopupRequests(req, res) {
  const { status, date_from, date_to, approved_by, search, collector_name, settlement_status, credited_by_role } = req.query;
  const conditions = [];
  const params = [];
  if (status && status !== 'all') { conditions.push("tr.status = ?"); params.push(status); }
  if (date_from) { conditions.push("date(tr.created_at) >= ?"); params.push(date_from); }
  if (date_to)   { conditions.push("date(tr.created_at) <= ?"); params.push(date_to); }
  if (approved_by === 'admin')    conditions.push("tr.approved_by_role = 'admin'");
  if (approved_by === 'salesman') conditions.push("tr.approved_by_role = 'salesman'");
  if (credited_by_role === 'admin')    conditions.push("tr.credited_by_role = 'admin'");
  if (credited_by_role === 'salesman') conditions.push("tr.credited_by_role = 'salesman'");
  // payment_received for credit advances: '0' = unpaid, '1' = paid
  if (req.query.payment_received === '0') conditions.push("tr.payment_received = 0");
  if (req.query.payment_received === '1') conditions.push("tr.payment_received = 1");
  if (collector_name) {
    const like = `%${collector_name}%`;
    conditions.push("s.name LIKE ?");
    params.push(like);
  }
  if (settlement_status === 'settled')   conditions.push("tr.settlement_id IS NOT NULL");
  if (settlement_status === 'unsettled') conditions.push("tr.settlement_id IS NULL");
  if (search) {
    const like = `%${search}%`;
    conditions.push("(u.name LIKE ? OR u.phone LIKE ? OR CAST(tr.amount AS TEXT) LIKE ?)");
    params.push(like, like, like);
  }
  // Only return actual topup requests — credit advances have their own tab
  conditions.push("tr.payment_method != 'credit_advance'");
  const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';
  const requests = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone,
           s.name as collector_name,
           cb.name as credited_by_name,
           ab.name as approved_by_name,
           ss.settled_by as settlement_acknowledged
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    LEFT JOIN users s ON s.id = CAST(tr.collected_by AS INTEGER)
    LEFT JOIN users cb ON cb.id = tr.credited_by_id
    LEFT JOIN users ab ON ab.id = tr.approved_by_id
    LEFT JOIN salesman_settlements ss ON ss.id = tr.settlement_id
    ${where}
    ORDER BY tr.created_at DESC
    LIMIT 200
  `).all(...params);

  // Summary stats
  const summary = db.prepare(`
    SELECT status,
           COUNT(*) as count,
           COALESCE(SUM(amount), 0) as total
    FROM topup_requests
    WHERE payment_method != 'credit_advance'
    GROUP BY status
  `).all();

  // Cash settlement records for the topups tab
  const cashRaisedSettlements = db.prepare(`
    SELECT ss.*, u.name as acknowledged_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    WHERE ss.settlement_type IN ('cash','mixed')
      ${date_from ? `AND date(ss.created_at) >= '${date_from}'` : ''}
      ${date_to   ? `AND date(ss.created_at) <= '${date_to}'`   : ''}
    ORDER BY ss.created_at DESC
  `).all();

  res.json({
    requests,
    summary,
    raised_settlements: cashRaisedSettlements.filter(s => !s.settled_by),
    settlements: cashRaisedSettlements.filter(s => !!s.settled_by),
  });
}

function listCreditAdvances(req, res) {
  const { date_from, date_to, credited_by_role, search } = req.query;
  const conditions = ["tr.payment_method = 'credit_advance'"];
  const params = [];

  if (date_from) { conditions.push("date(tr.created_at) >= ?"); params.push(date_from); }
  if (date_to)   { conditions.push("date(tr.created_at) <= ?"); params.push(date_to); }
  if (credited_by_role === 'admin')    conditions.push("tr.credited_by_role = 'admin'");
  if (credited_by_role === 'salesman') conditions.push("tr.credited_by_role = 'salesman'");
  if (req.query.payment_received === '0') conditions.push("tr.payment_received = 0");
  if (req.query.payment_received === '1') conditions.push("tr.payment_received = 1");
  if (search) {
    const like = `%${search}%`;
    conditions.push("(u.name LIKE ? OR u.phone LIKE ? OR CAST(tr.amount AS TEXT) LIKE ?)");
    params.push(like, like, like);
  }

  const where = 'WHERE ' + conditions.join(' AND ');
  const requests = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone,
           cb.name as credited_by_name,
           ss.settled_by as settlement_acknowledged
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    LEFT JOIN users cb ON cb.id = CAST(tr.credited_by_id AS INTEGER)
    LEFT JOIN salesman_settlements ss ON ss.id = tr.settlement_id
    ${where}
    ORDER BY tr.created_at DESC
    LIMIT 300
  `).all(...params);

  // Settlement records for raised credit advance settlements (pending + done)
  const raisedSettlements = db.prepare(`
    SELECT ss.*, u.name as acknowledged_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    WHERE ss.settlement_type = 'credit_advance'
      ${date_from ? `AND date(ss.created_at) >= '${date_from}'` : ''}
      ${date_to   ? `AND date(ss.created_at) <= '${date_to}'`   : ''}
    ORDER BY ss.created_at DESC
  `).all();

  res.json({
    requests,
    raised_settlements: raisedSettlements.filter(s => !s.settled_by),
    settlements: raisedSettlements.filter(s => !!s.settled_by),
  });
}

function approveTopup(req, res) {
  const { note } = req.body;
  const request = db.prepare('SELECT * FROM topup_requests WHERE id = ?').get(req.params.id);
  if (!request || request.status !== 'pending') return res.status(404).json({ error: 'Request not found or already processed' });

  const newBalance = walletService.credit(request.user_id, request.amount, 'credit', 'topup', request.id, 'Manual top-up approved');
  db.prepare("UPDATE topup_requests SET status='approved', admin_note=?, resolved_at=datetime('now'), approved_by_id=?, approved_by_role='admin' WHERE id=?").run(note || null, req.user.id, request.id);
  notificationService.sendToUser(request.user_id, 'Wallet Top-up Approved!', `₹${request.amount} added to your wallet. Balance: ₹${newBalance}`);
  res.json({ message: 'Approved', new_balance: newBalance });
}

function adminListProducts(req, res) {
  const { search, category_id, stock } = req.query;

  let where = '1=1';
  const params = [];

  if (search) {
    where += ' AND (p.name LIKE ? OR p.name_odia LIKE ?)';
    params.push(`%${search}%`, `%${search}%`);
  }
  if (category_id) {
    where += ' AND p.category_id = ?';
    params.push(parseInt(category_id));
  }
  if (stock === 'out') {
    where += ' AND p.stock_qty <= 0';
  } else if (stock === 'low') {
    where += ' AND p.stock_qty > 0 AND p.stock_qty <= p.low_stock_threshold';
  } else if (stock === 'ok') {
    where += ' AND p.stock_qty > p.low_stock_threshold';
  }

  const products = db.prepare(`
    SELECT p.*, c.name as category_name FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE ${where}
    ORDER BY p.name
  `).all(...params);
  res.json({ products });
}

function rejectTopup(req, res) {
  const { note } = req.body;
  const request = db.prepare('SELECT * FROM topup_requests WHERE id = ?').get(req.params.id);
  if (!request || request.status !== 'pending') return res.status(404).json({ error: 'Request not found or already processed' });

  db.prepare("UPDATE topup_requests SET status='rejected', admin_note=?, resolved_at=datetime('now') WHERE id=?").run(note || null, request.id);
  notificationService.sendToUser(request.user_id, 'Top-up Request Rejected', `Your top-up request of ₹${request.amount} was not approved. Please contact support.`);
  res.json({ message: 'Rejected' });
}

// ── Salesman cash summary ──────────────────────────────────────────────────────
function getSalesmanSummary(req, res) {
  // Summary grouped by salesman — approved cash not yet settled
  const collected = db.prepare(`
    SELECT tr.collected_by,
           COALESCE(u.name, tr.collected_by) as salesman_name,
           u.phone as salesman_phone,
           COUNT(*) as request_count,
           SUM(tr.amount) as total_collected,
           GROUP_CONCAT(tr.id) as request_ids,
           MIN(tr.created_at) as first_date,
           MAX(tr.created_at) as last_date
    FROM topup_requests tr
    LEFT JOIN users u ON u.id = CAST(tr.collected_by AS INTEGER)
    WHERE tr.payment_method = 'cash'
      AND tr.status = 'approved'
      AND tr.collected_by IS NOT NULL
      AND tr.id NOT IN (
        SELECT CAST(value AS INTEGER) FROM (
          SELECT json_each.value FROM salesman_settlements, json_each(salesman_settlements.topup_request_ids)
        ) WHERE 1=1
      )
    GROUP BY tr.collected_by
    ORDER BY total_collected DESC
  `).all();

  // Individual collection items — both pending (salesman hasn't approved) and
  // approved-not-raised (salesman approved but hasn't settled with admin)
  const collectionItems = db.prepare(`
    SELECT tr.*,
           cu.name  as customer_name,
           cu.phone as customer_phone,
           COALESCE(sm.name, tr.collected_by) as salesman_name,
           sm.phone as salesman_phone
    FROM topup_requests tr
    JOIN  users cu ON cu.id = tr.user_id
    LEFT JOIN users sm ON sm.id = CAST(tr.collected_by AS INTEGER)
    WHERE tr.payment_method = 'cash'
      AND tr.collected_by IS NOT NULL
      AND tr.status IN ('pending', 'approved')
      AND (
        tr.status = 'pending'
        OR (
          tr.status = 'approved'
          AND tr.settlement_id IS NULL
          AND tr.settled_at IS NULL
        )
      )
    ORDER BY tr.created_at DESC
    LIMIT 200
  `).all();

  // Settlement history
  const settlements = db.prepare(`
    SELECT ss.*, u.name as settled_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    ORDER BY ss.created_at DESC LIMIT 50
  `).all();

  // Pending cash requests (not yet approved) — kept for backward compat
  const pending = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    WHERE tr.payment_method = 'cash' AND tr.status = 'pending'
    ORDER BY tr.created_at DESC
  `).all();

  res.json({ collected, collection_items: collectionItems, settlements, pending });
}

function settleSalesman(req, res) {
  const { salesman_name, request_ids, note } = req.body;
  if (!salesman_name || !request_ids?.length) {
    return res.status(400).json({ error: 'salesman_name and request_ids required' });
  }

  // Sum up amounts
  const placeholders = request_ids.map(() => '?').join(',');
  const requests = db.prepare(
    `SELECT id, amount FROM topup_requests WHERE id IN (${placeholders}) AND collected_by = ? AND status = 'approved'`
  ).all(...request_ids, salesman_name);

  if (!requests.length) return res.status(400).json({ error: 'No matching approved requests found' });

  const totalAmount = requests.reduce((s, r) => s + r.amount, 0);

  db.prepare(
    'INSERT INTO salesman_settlements (salesman_name, amount, topup_request_ids, note, settled_by) VALUES (?,?,?,?,?)'
  ).run(salesman_name, totalAmount, JSON.stringify(request_ids), note || null, req.user.id);

  res.json({
    message: `Marked ₹${totalAmount.toFixed(2)} from ${salesman_name} as settled to central account`,
    total_settled: totalAmount,
    requests_settled: requests.length,
  });
}

function createCustomer(req, res) {
  const { name, phone, email, password } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });
  if (!phone && !email) return res.status(400).json({ error: 'Phone or email is required' });
  if (phone && !/^[0-9]{10}$/.test(phone.trim())) return res.status(400).json({ error: 'Phone must be 10 digits' });
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return res.status(400).json({ error: 'Invalid email address' });

  if (phone) {
    const dup = db.prepare('SELECT id FROM users WHERE phone = ?').get(phone.trim());
    if (dup) return res.status(409).json({ error: 'Phone number already registered' });
  }
  if (email) {
    const dup = db.prepare('SELECT id FROM users WHERE email = ?').get(email.trim().toLowerCase());
    if (dup) return res.status(409).json({ error: 'Email already registered' });
  }

  const bcrypt = require('bcryptjs');
  const hash = password && password.length >= 6 ? bcrypt.hashSync(password, 10) : null;
  const finalPhone = phone ? phone.trim() : `email_${Date.now()}`;

  const result = db.prepare(
    "INSERT INTO users (name, phone, email, password_hash, password_set, role, tier_id) VALUES (?,?,?,?,?,?,?)"
  ).run(name.trim(), finalPhone, email ? email.trim().toLowerCase() : null, hash, hash ? 1 : 0, 'customer',
    db.prepare("SELECT id FROM customer_tiers WHERE name='Normal' LIMIT 1").get()?.id ?? null);

  const user = db.prepare(
    'SELECT id, name, phone, email, wallet_balance, is_active, created_at FROM users WHERE id = ?'
  ).get(result.lastInsertRowid);
  res.status(201).json({ user, message: `Customer ${name.trim()} created` });
}

function toggleCustomer(req, res) {
  const user = db.prepare("SELECT id, name, is_active FROM users WHERE id = ? AND role = 'customer'").get(req.params.id);
  if (!user) return res.status(404).json({ error: 'Customer not found' });
  const newActive = user.is_active ? 0 : 1;
  db.prepare('UPDATE users SET is_active=? WHERE id=?').run(newActive, user.id);
  res.json({ message: newActive ? `${user.name} activated` : `${user.name} deactivated`, is_active: newActive });
}

function updateCustomer(req, res) {
  const customer = db.prepare("SELECT * FROM users WHERE id = ? AND role = 'customer'").get(req.params.id);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  const { name, email, phone } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });

  const trimmedEmail = email ? email.trim().toLowerCase() : null;
  if (trimmedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
    return res.status(400).json({ error: 'Invalid email address' });
  }
  if (trimmedEmail) {
    const dup = db.prepare('SELECT id FROM users WHERE email = ? AND id != ?').get(trimmedEmail, customer.id);
    if (dup) return res.status(400).json({ error: 'Email already in use' });
  }

  const trimmedPhone = phone ? phone.trim() : customer.phone;
  if (!/^[0-9]{10}$/.test(trimmedPhone)) {
    return res.status(400).json({ error: 'Phone must be 10 digits' });
  }
  if (trimmedPhone !== customer.phone) {
    const dup = db.prepare('SELECT id FROM users WHERE phone = ? AND id != ?').get(trimmedPhone, customer.id);
    if (dup) return res.status(400).json({ error: 'Phone already in use' });
  }

  db.prepare('UPDATE users SET name=?, email=?, phone=? WHERE id=?').run(name.trim(), trimmedEmail, trimmedPhone, customer.id);
  const updated = db.prepare('SELECT id, name, phone, email, wallet_balance, is_active FROM users WHERE id=?').get(customer.id);
  res.json({ message: 'Customer updated', user: updated });
}

// ── Admin: reset any customer's password ──────────────────────────────────────
function resetCustomerPassword(req, res) {
  const { new_password } = req.body;
  if (!new_password || new_password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  const user = db.prepare("SELECT * FROM users WHERE id = ? AND role = 'customer'").get(req.params.id);
  if (!user) return res.status(404).json({ error: 'Customer not found' });

  const bcrypt = require('bcryptjs');
  const hash = bcrypt.hashSync(new_password, 10);
  db.prepare("UPDATE users SET password_hash=?, password_set=1, password_changed_at=datetime('now') WHERE id=?")
    .run(hash, user.id);

  notificationService.sendToUser(user.id, 'Password Reset by Admin',
    'Your account password has been reset by admin. Please log in with your new password.');

  res.json({ message: `Password reset for ${user.name}` });
}

// ── Update actual weight/quantity → adjust wallet immediately ─────────────────
function updateOrderItemWeights(req, res) {
  const { items } = req.body;
  if (!items?.length) return res.status(400).json({ error: 'items array required' });

  const orderId = parseInt(req.params.id);
  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (order.status === 'cancelled') {
    return res.status(400).json({ error: 'Cannot update a cancelled order' });
  }

  let totalDiff = 0;
  let itemsUpdated = 0;

  db.transaction(() => {
    for (const entry of items) {
      const item = db.prepare('SELECT * FROM order_items WHERE id = ? AND order_id = ?')
        .get(entry.order_item_id, orderId);
      if (!item) continue;

      const newQty = parseFloat(parseFloat(entry.actual_qty).toFixed(3));
      const newTotal = parseFloat((item.unit_price * newQty).toFixed(2));
      const prevTotal = item.actual_total ?? item.estimated_total;
      const diff = newTotal - prevTotal;

      db.prepare('UPDATE order_items SET actual_qty=?, actual_total=? WHERE id=?')
        .run(newQty, newTotal, item.id);

      totalDiff += diff;
      itemsUpdated++;
    }

    // Recalculate subtotal from items
    const allItems = db.prepare('SELECT estimated_total, actual_total FROM order_items WHERE order_id = ?').all(orderId);
    const newSubtotal = parseFloat(allItems.reduce((s, i) => s + (i.actual_total ?? i.estimated_total), 0).toFixed(2));

    // Recalculate delivery charge — check custom pincode rules and free-delivery threshold
    let newDeliveryCharge = order.delivery_charge; // default: keep existing
    if (order.order_type === 'pickup') {
      newDeliveryCharge = 0;
    } else {
      // Check for custom pincode rule
      const address = order.address_id
        ? db.prepare('SELECT pincode, lat, lng FROM addresses WHERE id = ?').get(order.address_id)
        : null;

      if (address?.pincode) {
        const pinRule = db.prepare('SELECT custom_delivery_charge FROM pincode_cache WHERE pincode = ? AND deliverable = 1').get(address.pincode);
        if (pinRule?.custom_delivery_charge != null) {
          newDeliveryCharge = pinRule.custom_delivery_charge;
        } else {
          // Check free delivery threshold from app_config
          const freeAbove = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='free_delivery_above'").get()?.value || '500');
          if (newSubtotal >= freeAbove) {
            newDeliveryCharge = 0;
          } else {
            // Recalculate distance-based charge
            const { calcDeliveryCharge } = require('../services/deliveryChargeService');
            newDeliveryCharge = calcDeliveryCharge(address.lat, address.lng, newSubtotal);
          }
        }
      }
    }

    const deliveryChargeDiff = parseFloat((newDeliveryCharge - order.delivery_charge).toFixed(2));

    // Re-evaluate coupon discount on new actual quantities
    let newDiscount = 0;
    const promoUse = db.prepare('SELECT pcu.*, pc.discount_type, pc.discount_value, pc.max_discount_amount, pc.allowed_product_ids, pc.allowed_category_ids FROM promo_code_uses pcu JOIN promo_codes pc ON pc.id = pcu.promo_code_id WHERE pcu.order_id = ?').get(orderId);
    if (promoUse) {
      const updatedItems = db.prepare('SELECT product_id, actual_total, estimated_total FROM order_items WHERE order_id = ?').all(orderId);
      const allProductIds = updatedItems.map(i => i.product_id);
      let qualifyingTotal = newSubtotal;
      if (promoUse.allowed_product_ids) {
        const allowed = JSON.parse(promoUse.allowed_product_ids).map(Number);
        qualifyingTotal = updatedItems.filter(i => allowed.includes(i.product_id)).reduce((s, i) => s + (i.actual_total ?? i.estimated_total), 0);
      } else if (promoUse.allowed_category_ids) {
        const allowed = JSON.parse(promoUse.allowed_category_ids).map(Number);
        const cats = db.prepare(`SELECT id,category_id FROM products WHERE id IN (${allProductIds.map(()=>'?').join(',')})`).all(...allProductIds);
        const qIds = cats.filter(p => allowed.includes(p.category_id)).map(p => p.id);
        qualifyingTotal = updatedItems.filter(i => qIds.includes(i.product_id)).reduce((s, i) => s + (i.actual_total ?? i.estimated_total), 0);
      }
      newDiscount = promoUse.discount_type === 'percent'
        ? (qualifyingTotal * promoUse.discount_value / 100)
        : promoUse.discount_value;
      if (promoUse.max_discount_amount) newDiscount = Math.min(newDiscount, promoUse.max_discount_amount);
      newDiscount = Math.min(newDiscount, newSubtotal + newDeliveryCharge);
      newDiscount = Math.round(newDiscount * 100) / 100;
      // Update the stored discount_amount in promo_code_uses
      db.prepare('UPDATE promo_code_uses SET discount_amount = ? WHERE order_id = ?').run(newDiscount, orderId);
    }
    const discountDiff = parseFloat((newDiscount - (order.discount_amount || 0)).toFixed(2));

    const newFinalAmount = parseFloat((newSubtotal + newDeliveryCharge - newDiscount).toFixed(2));
    db.prepare("UPDATE orders SET final_amount=?, subtotal=?, delivery_charge=?, discount_amount=?, payment_status='adjusted', updated_at=datetime('now') WHERE id=?")
      .run(newFinalAmount, newSubtotal, newDeliveryCharge, newDiscount, orderId);

    // Total wallet diff = item weight change + delivery charge change − coupon discount change
    const netDiff = parseFloat((totalDiff + deliveryChargeDiff - discountDiff).toFixed(2));

    // Wallet adjustment — allowed to go negative (collected later by salesman)
    if (Math.abs(netDiff) > 0.01) {
      const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(order.user_id);
      let newBal;
      let txnType;
      if (netDiff > 0) {
        // Customer owes more — debit wallet, can go negative
        newBal = parseFloat((userRow.wallet_balance - netDiff).toFixed(2));
        txnType = 'adjustment';
      } else {
        // Customer overpaid (smaller items + lower delivery) — refund
        newBal = parseFloat((userRow.wallet_balance + Math.abs(netDiff)).toFixed(2));
        txnType = 'refund';
      }
      db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBal, order.user_id);

      let desc = `Weight adjustment — order #${order.order_number}`;
      const parts = [];
      if (Math.abs(totalDiff - (netDiff)) > 0.01 || Math.abs(deliveryChargeDiff) > 0.01 || Math.abs(discountDiff) > 0.01) {
        if (Math.abs(totalDiff) > 0.01) parts.push(`items ${totalDiff >= 0 ? '+' : ''}₹${(totalDiff - discountDiff).toFixed(2)}`);
        if (Math.abs(deliveryChargeDiff) > 0.01) parts.push(`delivery ${deliveryChargeDiff >= 0 ? '+' : ''}₹${deliveryChargeDiff.toFixed(2)}`);
        if (Math.abs(discountDiff) > 0.01) parts.push(`coupon discount ${discountDiff >= 0 ? '+' : ''}₹${discountDiff.toFixed(2)}`);
        if (parts.length) desc += ` (${parts.join(', ')})`;
      }
      db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description) VALUES (?,?,?,?,?,?,?)`)
        .run(order.user_id, txnType, Math.abs(netDiff), newBal, 'order', orderId, desc);

      const sign = netDiff > 0 ? '-' : '+';
      notificationService.sendToUser(order.user_id, 'Order Updated ⚖️',
        `Order #${order.order_number} updated. Wallet ${sign}₹${Math.abs(netDiff).toFixed(2)}. New balance: ₹${newBal.toFixed(2)}`);
    }

    totalDiff = netDiff; // expose net diff to response
  })();

  const updatedOrder = db.prepare('SELECT final_amount, subtotal, delivery_charge, discount_amount FROM orders WHERE id = ?').get(orderId);
  const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(order.user_id);

  res.json({
    message: `${itemsUpdated} item(s) updated`,
    items_updated: itemsUpdated,
    wallet_adjustment: parseFloat(totalDiff.toFixed(2)),
    new_wallet_balance: userRow.wallet_balance,
    new_subtotal: updatedOrder.subtotal,
    new_delivery_charge: updatedOrder.delivery_charge,
    new_final_amount: updatedOrder.final_amount,
  });
}

function getCustomerWalletHistory(req, res) {
  const { page = 1, limit = 50, type, date_from, date_to } = req.query;
  const customerId = parseInt(req.params.id);
  const customer = db.prepare("SELECT id, name, phone, wallet_balance FROM users WHERE id=? AND role='customer'").get(customerId);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  const offset = (parseInt(page) - 1) * parseInt(limit);
  let where = 'user_id = ?';
  const params = [customerId];

  if (type) {
    switch (type) {
      case 'topup':    where += " AND type='credit' AND reference_type='topup'";  break;
      case 'order':    where += " AND type='debit' AND reference_type='order'";   break;
      case 'refund':   where += " AND type='refund'";                             break;
      case 'cashback': where += " AND type='discount' AND reference_type='reward'"; break;
      case 'admin':    where += " AND reference_type='admin'";                    break;
      case 'adjust':   where += " AND type='adjustment'";                         break;
    }
  }
  if (date_from) { where += ' AND date(created_at) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(created_at) <= ?'; params.push(date_to); }

  const transactions = db.prepare(
    `SELECT * FROM wallet_transactions WHERE ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).all(...params, parseInt(limit), offset);
  const total = db.prepare(`SELECT COUNT(*) as c FROM wallet_transactions WHERE ${where}`).get(...params).c;

  res.json({ customer, transactions, total, page: parseInt(page), limit: parseInt(limit) });
}

function getAllWalletTransactions(req, res) {
  const { page = 1, limit = 50, type, date_from, date_to, customer_search } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);

  let where = "wt.id IS NOT NULL";
  const params = [];

  if (type) {
    switch (type) {
      case 'topup':          where += " AND wt.type='credit' AND wt.reference_type='topup' AND (wt.description NOT LIKE 'Credit advance%' OR wt.description IS NULL)";  break;
      case 'order':          where += " AND wt.type='debit' AND wt.reference_type='order'";   break;
      case 'refund':         where += " AND wt.type='refund'";                               break;
      case 'cashback':       where += " AND wt.type='discount' AND wt.reference_type='reward'"; break;
      case 'admin':          where += " AND wt.reference_type='admin'";                      break;
      case 'adjust':         where += " AND wt.type='adjustment'";                           break;
      case 'debit':          where += " AND wt.type='debit'";                                break;
      case 'credit':         where += " AND wt.type IN ('credit','discount','refund')";      break;
      case 'credit_advance': where += " AND wt.reference_type='topup' AND wt.description LIKE 'Credit advance%'"; break;
      case 'referral':       where += " AND wt.reference_type IN ('referral_signup','referral_bonus')"; break;
    }
  }
  if (date_from) { where += ' AND date(wt.created_at) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(wt.created_at) <= ?'; params.push(date_to); }
  if (customer_search) {
    where += ' AND (u.name LIKE ? OR u.phone LIKE ?)';
    params.push(`%${customer_search}%`, `%${customer_search}%`);
  }

  const transactions = db.prepare(`
    SELECT wt.*, u.name as customer_name, u.phone as customer_phone,
           CASE WHEN wt.reference_type IN ('topup') THEN sm.name ELSE NULL END as collector_name,
           CASE WHEN wt.reference_type IN ('topup') THEN ab.name ELSE NULL END as approved_by_name,
           CASE WHEN wt.reference_type IN ('topup') THEN tr.approved_by_role ELSE NULL END as approved_by_role
    FROM wallet_transactions wt
    JOIN users u ON u.id = wt.user_id
    LEFT JOIN topup_requests tr ON tr.id = wt.reference_id AND wt.reference_type = 'topup'
    LEFT JOIN users sm ON sm.id = CAST(tr.collected_by AS INTEGER)
    LEFT JOIN users ab ON ab.id = tr.approved_by_id
    WHERE ${where}
    ORDER BY wt.created_at DESC LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);

  const total = db.prepare(`
    SELECT COUNT(*) as c FROM wallet_transactions wt
    JOIN users u ON u.id = wt.user_id
    LEFT JOIN topup_requests tr ON tr.id = wt.reference_id AND wt.reference_type = 'topup'
    WHERE ${where}
  `).get(...params).c;

  // Summary totals
  const summary = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN type IN ('credit','refund','discount') THEN amount ELSE 0 END), 0) as total_credited,
      COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE 0 END), 0) as total_debited,
      COUNT(DISTINCT user_id) as unique_customers,
      COUNT(*) as total_count
    FROM wallet_transactions wt
    JOIN users u ON u.id = wt.user_id WHERE ${where}
  `).get(...params);

  res.json({ transactions, total, page: parseInt(page), limit: parseInt(limit), summary });
}

function getWalletTransactionsSummary(req, res) {
  const { type, date_from, date_to, customer_search } = req.query;

  let where = "wt.id IS NOT NULL";
  const params = [];

  if (type) {
    switch (type) {
      case 'topup':          where += " AND wt.type='credit' AND wt.reference_type='topup' AND (wt.description NOT LIKE 'Credit advance%' OR wt.description IS NULL)";  break;
      case 'order':          where += " AND wt.type='debit' AND wt.reference_type='order'";   break;
      case 'refund':         where += " AND wt.type='refund'";                               break;
      case 'cashback':       where += " AND wt.type='discount' AND wt.reference_type='reward'"; break;
      case 'admin':          where += " AND wt.reference_type='admin'";                      break;
      case 'adjust':         where += " AND wt.type='adjustment'";                           break;
      case 'debit':          where += " AND wt.type='debit'";                                break;
      case 'credit':         where += " AND wt.type IN ('credit','discount','refund')";      break;
      case 'credit_advance': where += " AND wt.reference_type='topup' AND wt.description LIKE 'Credit advance%'"; break;
      case 'referral':       where += " AND wt.reference_type IN ('referral_signup','referral_bonus')"; break;
    }
  }
  if (date_from) { where += ' AND date(wt.created_at) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(wt.created_at) <= ?'; params.push(date_to); }
  if (customer_search) {
    where += ' AND (u.name LIKE ? OR u.phone LIKE ?)';
    params.push(`%${customer_search}%`, `%${customer_search}%`);
  }

  // Overall totals
  const summary = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN wt.type IN ('credit','refund','discount') THEN wt.amount ELSE 0 END), 0) as total_credited,
      COALESCE(SUM(CASE WHEN wt.type = 'debit' THEN wt.amount ELSE 0 END), 0) as total_debited,
      COUNT(DISTINCT wt.user_id) as unique_customers,
      COUNT(*) as total_count
    FROM wallet_transactions wt
    JOIN users u ON u.id = wt.user_id WHERE ${where}
  `).get(...params);

  // Per-type breakdown — group by reference_type + type combination
  const byTypeRaw = db.prepare(`
    SELECT wt.type, wt.reference_type,
           COUNT(*) as cnt,
           COALESCE(SUM(wt.amount), 0) as total,
           MAX(CASE WHEN wt.description LIKE 'Credit advance%' THEN 1 ELSE 0 END) as is_advance
    FROM wallet_transactions wt
    JOIN users u ON u.id = wt.user_id
    WHERE ${where}
    GROUP BY wt.type, wt.reference_type
    ORDER BY total DESC
  `).all(...params);

  // Map raw rows to labelled type buckets (same logic as frontend _style)
  const labelMap = {
    'topup':          { label: '💵 Topup',      color: '#E65100' },
    'order':          { label: '🛒 Order',       color: '#C62828' },
    'refund':         { label: '↩️ Refund',      color: '#00695C' },
    'cashback':       { label: '🎁 Cashback',    color: '#6A1B9A' },
    'admin':          { label: '🔧 Admin',       color: '#1565C0' },
    'adjust':         { label: '⚖️ Adjustment',  color: '#E65100' },
    'credit_advance': { label: '💳 Advance',     color: '#3949AB' },
    'referral':       { label: '🔗 Referral',    color: '#6A1B9A' },
    'other_credit':   { label: '+ Credit',       color: '#2E7D32' },
    'other_debit':    { label: '- Debit',        color: '#C62828' },
  };

  const buckets = {};
  for (const row of byTypeRaw) {
    let key;
    if (row.type === 'discount' && row.reference_type === 'reward') key = 'cashback';
    else if (row.reference_type === 'admin') key = 'admin';
    else if (row.type === 'credit' && row.reference_type === 'topup' && row.is_advance) key = 'credit_advance';
    else if (row.type === 'credit' && row.reference_type === 'topup') key = 'topup';
    else if (row.type === 'debit' && row.reference_type === 'order') key = 'order';
    else if (row.type === 'refund') key = 'refund';
    else if (row.type === 'adjustment') key = 'adjust';
    else if (row.reference_type === 'referral_signup' || row.reference_type === 'referral_bonus') key = 'referral';
    else if (['credit','discount','refund'].includes(row.type)) key = 'other_credit';
    else key = 'other_debit';

    if (!buckets[key]) buckets[key] = { ...labelMap[key], key, count: 0, total: 0 };
    buckets[key].count += row.cnt;
    buckets[key].total += row.total;
  }

  const by_type = Object.values(buckets).sort((a, b) => b.total - a.total);

  res.json({ summary, by_type });
}

// ── Admin: generate referral code for a phone number ─────────────────────────
function adminGenerateReferral(req, res) {
  const { phone, phones } = req.body;
  // Accepts a single phone or a batch array
  const targets = phones
    ? Array.isArray(phones) ? phones : [phones]
    : phone ? [phone] : [];

  if (targets.length === 0) return res.status(400).json({ error: 'phone or phones required' });

  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  function generateCode() {
    let code, attempts = 0;
    do {
      code = 'HK';
      for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
      attempts++;
    } while (db.prepare('SELECT id FROM referral_coupons WHERE code = ?').get(code) && attempts < 30);
    return code;
  }

  const adminUser = db.prepare('SELECT id FROM users WHERE role = ? LIMIT 1').get('admin');
  if (!adminUser) return res.status(500).json({ error: 'No admin user found' });

  const results = [];
  for (const p of targets) {
    const cleaned = String(p).trim().replace(/^(\+91|91)/, '');
    if (!/^[0-9]{10}$/.test(cleaned)) {
      results.push({ phone: p, error: 'Invalid phone number' });
      continue;
    }
    // Already registered?
    const existing = db.prepare("SELECT id FROM users WHERE phone = ? AND role = 'customer'").get(cleaned);
    if (existing) { results.push({ phone: cleaned, error: 'Already registered' }); continue; }
    // Already has an admin-generated invite?
    const dup = db.prepare("SELECT id, code FROM referral_coupons WHERE invited_phone = ? AND owner_user_id = ?").get(cleaned, req.user.id);
    if (dup) { results.push({ phone: cleaned, code: dup.code, skipped: true }); continue; }

    const code = generateCode();
    db.prepare("INSERT INTO referral_coupons (code, owner_user_id, invited_phone) VALUES (?,?,?)").run(code, req.user.id, cleaned);
    results.push({ phone: cleaned, code });
  }

  res.status(201).json({ results });
}

// ── Admin: create generic referral code ──────────────────────────────────────
function adminCreateGenericCode(req, res) {
  const { code, label, custom_signup_credit, max_uses } = req.body;

  let codeValue = code ? code.trim().toUpperCase() : null;
  if (!codeValue) {
    // Auto-generate a short memorable code
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let attempts = 0;
    do {
      codeValue = 'HK';
      for (let i = 0; i < 6; i++) codeValue += chars[Math.floor(Math.random() * chars.length)];
      attempts++;
    } while (db.prepare('SELECT id FROM referral_coupons WHERE code = ?').get(codeValue) && attempts < 30);
  } else {
    const existing = db.prepare('SELECT id FROM referral_coupons WHERE code = ?').get(codeValue);
    if (existing) return res.status(400).json({ error: `Code "${codeValue}" already exists` });
  }

  const credit = parseFloat(custom_signup_credit ?? 0);
  if (credit < 0) return res.status(400).json({ error: 'Signup credit must be 0 or more' });

  const result = db.prepare(`
    INSERT INTO referral_coupons (code, owner_user_id, is_generic, label, custom_signup_credit, max_uses, use_count)
    VALUES (?, ?, 1, ?, ?, ?, 0)
  `).run(codeValue, req.user.id, label || null, credit || null, max_uses ? parseInt(max_uses) : null);

  const created = db.prepare('SELECT * FROM referral_coupons WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ code: created });
}

function adminUpdateGenericCode(req, res) {
  const id = parseInt(req.params.id);
  const { label, custom_signup_credit, max_uses, is_active } = req.body;

  const existing = db.prepare('SELECT * FROM referral_coupons WHERE id = ? AND is_generic = 1').get(id);
  if (!existing) return res.status(404).json({ error: 'Generic code not found' });

  db.prepare(`
    UPDATE referral_coupons
    SET label = ?, custom_signup_credit = ?, max_uses = ?
    WHERE id = ?
  `).run(
    label !== undefined ? label : existing.label,
    custom_signup_credit !== undefined ? parseFloat(custom_signup_credit) : existing.custom_signup_credit,
    max_uses !== undefined ? (max_uses ? parseInt(max_uses) : null) : existing.max_uses,
    id,
  );

  res.json({ message: 'Updated' });
}

function adminDeleteGenericCode(req, res) {
  const id = parseInt(req.params.id);
  const existing = db.prepare('SELECT * FROM referral_coupons WHERE id = ? AND is_generic = 1').get(id);
  if (!existing) return res.status(404).json({ error: 'Generic code not found' });
  db.prepare('DELETE FROM referral_coupons WHERE id = ?').run(id);
  res.json({ message: 'Deleted' });
}

function listReferrals(req, res) {
  const { page = 1, limit = 50 } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  const rows = db.prepare(`
    SELECT rc.*,
           ou.name as owner_name, ou.phone as owner_phone, ou.role as owner_role,
           uu.name as used_by_name, uu.phone as used_by_phone
    FROM referral_coupons rc
    JOIN users ou ON ou.id = rc.owner_user_id
    LEFT JOIN users uu ON uu.id = rc.used_by_user_id
    WHERE rc.is_generic = 0 OR rc.is_generic IS NULL
    ORDER BY rc.created_at DESC
    LIMIT ? OFFSET ?
  `).all(parseInt(limit), offset);
  const total = db.prepare('SELECT COUNT(*) as c FROM referral_coupons WHERE is_generic = 0 OR is_generic IS NULL').get().c;

  // Generic codes — all of them regardless of page
  const genericCodes = db.prepare(`
    SELECT rc.*, ou.name as owner_name
    FROM referral_coupons rc
    JOIN users ou ON ou.id = rc.owner_user_id
    WHERE rc.is_generic = 1
    ORDER BY rc.created_at DESC
  `).all();

  const stats = db.prepare(`
    SELECT
      COUNT(*) as total_codes,
      COUNT(used_by_user_id) as total_used,
      COALESCE(SUM(signup_credit_amount),0) as total_signup_credits,
      COALESCE(SUM(bonus_credit_amount),0) as total_bonuses
    FROM referral_coupons WHERE is_generic = 0 OR is_generic IS NULL
  `).get();

  // Include referral config values so screen has everything in one request
  const signupCredit = getConfigValue('referral_signup_credit') ?? '50';
  const firstOrderBonus = getConfigValue('referral_first_order_bonus') ?? '100';
  const enabled = getConfigValue('referral_enabled') ?? '1';

  res.json({
    referrals: rows, total, stats, generic_codes: genericCodes, page: parseInt(page),
    config: { referral_signup_credit: signupCredit, referral_first_order_bonus: firstOrderBonus, referral_enabled: enabled },
  });
}

// ── Admin: raise settlement on behalf of a salesman ──────────────────────────
function raiseSettlementForSalesman(req, res) {
  const salesmanUserId = parseInt(req.params.id);
  // settlement_type: 'cash' | 'credit_advance' — which type to raise; default raises both (mixed)
  const { note, settlement_type } = req.body;

  const salesman = db.prepare("SELECT id, name FROM users WHERE id = ? AND role = 'salesman'").get(salesmanUserId);
  if (!salesman) return res.status(404).json({ error: 'Salesman not found' });

  let whereClause;
  if (settlement_type === 'credit_advance') {
    whereClause = `CAST(credited_by_id AS INTEGER) = ? AND payment_method = 'credit_advance'
      AND payment_received = 1 AND (paid_by_role IS NULL OR paid_by_role = 'salesman')
      AND settled_at IS NULL AND settlement_id IS NULL`;
  } else if (settlement_type === 'cash') {
    whereClause = `collected_by = ? AND payment_method = 'cash' AND status = 'approved'
      AND settled_at IS NULL AND settlement_id IS NULL`;
  } else {
    // all
    whereClause = `(
      (collected_by = ? AND payment_method = 'cash' AND status = 'approved'
        AND settled_at IS NULL AND settlement_id IS NULL)
      OR
      (CAST(credited_by_id AS INTEGER) = ? AND payment_method = 'credit_advance'
        AND payment_received = 1 AND (paid_by_role IS NULL OR paid_by_role = 'salesman')
        AND settled_at IS NULL AND settlement_id IS NULL)
    )`;
  }

  const isMixed = !settlement_type;
  const params  = isMixed ? [String(salesmanUserId), salesmanUserId] : [String(salesmanUserId)];
  const requests = db.prepare(`SELECT id, amount, payment_method FROM topup_requests WHERE ${whereClause}`).all(...params);

  if (!requests.length) {
    const typeLabel = settlement_type === 'credit_advance' ? 'credit advance repayments'
        : settlement_type === 'cash' ? 'cash collections'
        : 'collections';
    return res.status(400).json({ error: `No unsettled ${typeLabel} found for this salesman` });
  }

  // Detect actual type
  const hasOnly = (m) => requests.every(r => r.payment_method === m);
  const actualType = hasOnly('cash') ? 'cash' : hasOnly('credit_advance') ? 'credit_advance' : 'mixed';

  const totalAmount = requests.reduce((s, r) => s + r.amount, 0);
  const requestIds  = JSON.stringify(requests.map(r => r.id));
  const adminNote   = note || `Raised by admin on behalf of ${salesman.name}`;

  const result = db.prepare(
    'INSERT INTO salesman_settlements (salesman_name, amount, topup_request_ids, note, settlement_type) VALUES (?,?,?,?,?)'
  ).run(salesman.name, totalAmount, requestIds, adminNote, actualType);

  const settlementId = result.lastInsertRowid;

  const stmt = db.prepare('UPDATE topup_requests SET settlement_id=? WHERE id=?');
  for (const r of requests) stmt.run(settlementId, r.id);

  notificationService.sendToUser(salesmanUserId, 'Settlement Raised by Admin',
    `Admin raised a ${actualType === 'credit_advance' ? 'credit advance' : 'cash'} settlement of ₹${totalAmount.toFixed(0)} (${requests.length} item${requests.length === 1 ? '' : 's'}) on your behalf.`);

  res.json({
    message: `Settlement of ₹${totalAmount.toFixed(0)} raised for ${salesman.name}`,
    settlement_id: settlementId,
    settlement_type: actualType,
    amount: totalAmount,
    request_count: requests.length,
  });
}

function forceLogout(req, res) {
  const userId = parseInt(req.params.id);
  const user = db.prepare('SELECT id, name, role FROM users WHERE id = ?').get(userId);
  if (!user) return res.status(404).json({ error: 'User not found' });
  db.prepare('UPDATE users SET token_version = COALESCE(token_version, 0) + 1 WHERE id = ?').run(userId);
  res.json({ message: `${user.name} has been logged out` });
}

function getAgentLocations(req, res) {
  const agents = db.prepare(`
    SELECT da.id, da.current_lat, da.current_lng, da.last_seen_at, da.is_available,
           u.name, u.phone, u.role,
           (SELECT COUNT(*) FROM deliveries d
            JOIN orders o ON o.id = d.order_id
            WHERE (d.agent_id = da.id OR o.salesman_id = da.user_id)
              AND d.status IN ('assigned','picked')) as active_deliveries
    FROM delivery_agents da
    JOIN users u ON u.id = da.user_id
    WHERE u.is_active = 1 AND u.role = 'salesman'
    ORDER BY u.name
  `).all();
  res.json({ agents });
}

module.exports = {
  getDashboard, adminListOrders, updateOrderStatus, assignAgent,
  creditWallet, debitWallet, listUsers, createCustomer, toggleCustomer, updateCustomer, getConfig, updateConfig,
  getCustomerWalletHistory, getAllWalletTransactions, getWalletTransactionsSummary,
  listTopupRequests, listCreditAdvances, approveTopup, rejectTopup, adminListProducts,
  resetCustomerPassword, updateOrderItemWeights, markPickupCollected, forceLogout, listReferrals, adminGenerateReferral,
  adminCreateGenericCode, adminUpdateGenericCode, adminDeleteGenericCode,
  creditTopupAdmin, markCreditTopupPaid, raiseSettlementForSalesman, waiveDeliveryCharge,
  getAgentLocations,
};
