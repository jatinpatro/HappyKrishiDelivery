const db = require('../config/database');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

// Helper to read a single app_config value
function getConfigValue(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? row.value : null;
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
           d.status as delivery_status, au.name as agent_name, au.phone as agent_phone
    FROM orders o
    JOIN users u ON u.id = o.user_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    LEFT JOIN delivery_agents da ON da.id = d.agent_id
    LEFT JOIN users au ON au.id = da.user_id
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
        db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now') WHERE order_id=?")
          .run(agentRow.id, order.id);
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

  const agent = db.prepare('SELECT * FROM delivery_agents WHERE id = ?').get(agent_id);
  if (!agent) return res.status(404).json({ error: 'Agent not found' });

  db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now') WHERE order_id=?").run(agent_id, order.id);
  db.prepare("UPDATE orders SET status='assigned', updated_at=datetime('now') WHERE id=?").run(order.id);

  notificationService.sendToUser(agent.user_id, 'New Delivery Assigned', `Order #${order.order_number} assigned to you`);
  notificationService.sendToUser(order.user_id, 'Agent Assigned', 'A delivery agent has been assigned to your order');

  res.json({ message: 'Agent assigned' });
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
  if (user.wallet_balance < amount) {
    return res.status(400).json({
      error: `Insufficient wallet balance. Current: ₹${user.wallet_balance.toFixed(2)}, Requested deduction: ₹${amount}`
    });
  }

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
  let where = "role = 'customer'";
  const params = [];

  if (search) {
    where += ' AND (name LIKE ? OR phone LIKE ? OR email LIKE ?)';
    params.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (wallet === 'negative')  { where += ' AND wallet_balance < 0'; }
  if (wallet === 'zero')      { where += ' AND wallet_balance = 0'; }
  if (wallet === 'positive')  { where += ' AND wallet_balance > 0'; }
  if (wallet === 'low')       { where += ' AND wallet_balance > 0 AND wallet_balance < 100'; }
  if (is_active === '1')      { where += ' AND is_active = 1'; }
  if (is_active === '0')      { where += ' AND is_active = 0'; }

  const orderBy = sort === 'wallet_asc'  ? 'wallet_balance ASC'
                : sort === 'wallet_desc' ? 'wallet_balance DESC'
                : sort === 'recent'      ? 'created_at DESC'
                : 'name';

  const users = db.prepare(`
    SELECT id, name, phone, email, wallet_balance, is_active, created_at
    FROM users WHERE ${where} ORDER BY ${orderBy} LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);
  const total = db.prepare(`SELECT COUNT(*) as c FROM users WHERE ${where}`).get(...params).c;
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
  const { status } = req.query; // optional: pending | approved | rejected | all
  const where = status && status !== 'all' ? `WHERE tr.status = '${status}'` : '';
  const requests = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    ${where}
    ORDER BY tr.created_at DESC
    LIMIT 200
  `).all();

  // Summary stats
  const summary = db.prepare(`
    SELECT status,
           COUNT(*) as count,
           COALESCE(SUM(amount), 0) as total
    FROM topup_requests
    GROUP BY status
  `).all();

  res.json({ requests, summary });
}

function approveTopup(req, res) {
  const { note } = req.body;
  const request = db.prepare('SELECT * FROM topup_requests WHERE id = ?').get(req.params.id);
  if (!request || request.status !== 'pending') return res.status(404).json({ error: 'Request not found or already processed' });

  const newBalance = walletService.credit(request.user_id, request.amount, 'credit', 'topup', request.id, 'Manual top-up approved');
  db.prepare("UPDATE topup_requests SET status='approved', admin_note=?, resolved_at=datetime('now') WHERE id=?").run(note || null, request.id);
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
  // Total collected (approved cash requests) per salesman, not yet settled
  const collected = db.prepare(`
    SELECT collected_by, COUNT(*) as request_count,
           SUM(amount) as total_collected,
           GROUP_CONCAT(id) as request_ids,
           MIN(created_at) as first_date,
           MAX(created_at) as last_date
    FROM topup_requests
    WHERE payment_method = 'cash'
      AND status = 'approved'
      AND collected_by IS NOT NULL
      AND id NOT IN (
        SELECT CAST(value AS INTEGER) FROM (
          SELECT json_each.value FROM salesman_settlements, json_each(salesman_settlements.topup_request_ids)
        ) WHERE 1=1
      )
    GROUP BY collected_by
    ORDER BY total_collected DESC
  `).all();

  // Settlement history
  const settlements = db.prepare(`
    SELECT ss.*, u.name as settled_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    ORDER BY ss.created_at DESC LIMIT 50
  `).all();

  // Pending cash requests (not yet approved)
  const pending = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    WHERE tr.payment_method = 'cash' AND tr.status = 'pending'
    ORDER BY tr.created_at DESC
  `).all();

  res.json({ collected, settlements, pending });
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
    "INSERT INTO users (name, phone, email, password_hash, password_set, role) VALUES (?,?,?,?,?,?)"
  ).run(name.trim(), finalPhone, email ? email.trim().toLowerCase() : null, hash, hash ? 1 : 0, 'customer');

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
    const newFinalAmount = parseFloat((newSubtotal + newDeliveryCharge).toFixed(2));
    db.prepare("UPDATE orders SET final_amount=?, subtotal=?, delivery_charge=?, payment_status='adjusted', updated_at=datetime('now') WHERE id=?")
      .run(newFinalAmount, newSubtotal, newDeliveryCharge, orderId);

    // Total wallet diff = item weight change + delivery charge change
    const netDiff = parseFloat((totalDiff + deliveryChargeDiff).toFixed(2));

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
      if (Math.abs(deliveryChargeDiff) > 0.01) {
        desc += ` (items ${totalDiff >= 0 ? '+' : ''}₹${totalDiff.toFixed(2)}, delivery ${deliveryChargeDiff >= 0 ? '+' : ''}₹${deliveryChargeDiff.toFixed(2)})`;
      }
      db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description) VALUES (?,?,?,?,?,?,?)`)
        .run(order.user_id, txnType, Math.abs(netDiff), newBal, 'order', orderId, desc);

      const sign = netDiff > 0 ? '-' : '+';
      notificationService.sendToUser(order.user_id, 'Order Updated ⚖️',
        `Order #${order.order_number} updated. Wallet ${sign}₹${Math.abs(netDiff).toFixed(2)}. New balance: ₹${newBal.toFixed(2)}`);
    }

    totalDiff = netDiff; // expose net diff to response
  })();

  const updatedOrder = db.prepare('SELECT final_amount, subtotal, delivery_charge FROM orders WHERE id = ?').get(orderId);
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

module.exports = {
  getDashboard, adminListOrders, updateOrderStatus, assignAgent, getAgents, createAgent, toggleAgent,
  creditWallet, debitWallet, listUsers, createCustomer, toggleCustomer, getConfig, updateConfig,
  listTopupRequests, approveTopup, rejectTopup, adminListProducts,
  resetCustomerPassword, updateOrderItemWeights, markPickupCollected,
};
