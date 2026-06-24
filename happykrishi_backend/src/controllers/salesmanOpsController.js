const db = require('../config/database');
const bcrypt = require('bcryptjs');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

// ── Salesman: search/list their customers ─────────────────────────────────────
function listMyCustomers(req, res) {
  const { search, wallet, sort = 'name' } = req.query;
  let where = "role = 'customer' AND is_active = 1";
  const params = [];
  if (search) {
    where += ' AND (name LIKE ? OR phone LIKE ? OR email LIKE ?)';
    params.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (wallet === 'negative') where += ' AND wallet_balance < 0';
  else if (wallet === 'zero') where += ' AND wallet_balance = 0';
  else if (wallet === 'positive') where += ' AND wallet_balance > 0';
  else if (wallet === 'low') where += ' AND wallet_balance > 0 AND wallet_balance < 100';

  const orderBy = sort === 'wallet_desc' ? 'wallet_balance DESC'
                : sort === 'wallet_asc'  ? 'wallet_balance ASC'
                : sort === 'recent'      ? 'created_at DESC'
                : 'name ASC';

  const customers = db.prepare(`
    SELECT id, name, phone, email, wallet_balance, created_at
    FROM users WHERE ${where} ORDER BY ${orderBy} LIMIT 100
  `).all(...params);
  res.json({ customers });
}

// ── Salesman: add a new customer ──────────────────────────────────────────────
function addCustomer(req, res) {
  const { name, phone, password } = req.body;
  if (!name || !phone) return res.status(400).json({ error: 'name and phone required' });
  if (!/^[0-9]{10}$/.test(phone)) return res.status(400).json({ error: 'Phone must be 10 digits' });

  const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(phone);
  if (existing) return res.status(400).json({ error: 'Phone already registered' });

  let hash = null;
  if (password && password.length >= 6) {
    hash = bcrypt.hashSync(password, 10);
  }

  const result = db.prepare(
    "INSERT INTO users (name, phone, password_hash, password_set, role, tier_id) VALUES (?,?,?,?,?,?)"
  ).run(name.trim(), phone, hash, hash ? 1 : 0, 'customer',
    db.prepare("SELECT id FROM customer_tiers WHERE name='Normal' LIMIT 1").get()?.id ?? null);

  const customer = db.prepare('SELECT id,name,phone,wallet_balance,role FROM users WHERE id=?')
    .get(result.lastInsertRowid);

  res.status(201).json({ message: 'Customer added', customer });
}

// ── Salesman: reset a customer's password ─────────────────────────────────────
function resetCustomerPasswordBySalesman(req, res) {
  const { new_password } = req.body;
  if (!new_password || new_password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  const customer = db.prepare("SELECT * FROM users WHERE id=? AND role='customer'").get(req.params.id);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  const hash = bcrypt.hashSync(new_password, 10);
  db.prepare("UPDATE users SET password_hash=?, password_set=1 WHERE id=?").run(hash, customer.id);

  notificationService.sendToUser(customer.id, 'Password Updated',
    `Your password was updated by our salesman ${req.user.name}.`);

  res.json({ message: `Password updated for ${customer.name}` });
}

// ── Salesman: approve a cash collection → credit customer wallet immediately ──
function approveMyCollection(req, res) {
  const salesmanId = req.user.id;
  const salesmanName = req.user.name;
  const request = db.prepare(
    "SELECT * FROM topup_requests WHERE id=? AND collected_by=? AND status='pending'"
  ).get(req.params.id, salesmanId);

  if (!request) {
    return res.status(404).json({ error: 'Request not found or not yours' });
  }
  if (request.payment_method !== 'cash') {
    return res.status(400).json({ error: 'Can only approve cash collections' });
  }

  // Credit customer wallet
  const newBalance = walletService.credit(
    request.user_id,
    request.amount,
    'credit',
    'topup',
    request.id,
    `Cash collected by ${salesmanName}`
  );

  // Mark request approved
  db.prepare("UPDATE topup_requests SET status='approved', resolved_at=datetime('now') WHERE id=?")
    .run(request.id);

  notificationService.sendToUser(
    request.user_id,
    'Wallet Credited ✅',
    `₹${request.amount.toFixed(0)} added by ${salesmanName}. New balance: ₹${newBalance.toFixed(2)}`
  );

  res.json({
    message: `₹${request.amount} credited to customer wallet`,
    new_customer_balance: newBalance,
  });
}

// ── Salesman: list their pending (unapproved) collections ─────────────────────
function myPendingCollections(req, res) {
  const salesmanId = req.user.id;
  const pending = db.prepare(`
    SELECT tr.*, u.name as customer_name, u.phone as customer_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    WHERE tr.collected_by = ? AND tr.status = 'pending'
    ORDER BY tr.created_at DESC
  `).all(salesmanId);

  const total = pending.reduce((s, r) => s + r.amount, 0);
  res.json({ pending, total_pending: total, count: pending.length });
}

// ── Salesman: list their approved (unsettled) collections ─────────────────────
function myApprovedCollections(req, res) {
  const salesmanId = req.user.id;

  // Approved but not yet raised for settlement
  const unsettled = db.prepare(`
    SELECT tr.*, u.name as customer_name, u.phone as customer_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    WHERE tr.collected_by = ? AND tr.status = 'approved'
      AND (tr.settled_at IS NULL AND tr.settlement_id IS NULL)
    ORDER BY tr.resolved_at DESC
  `).all(salesmanId);

  // My settlement requests (raised by me) — settlements still use salesman name
  const salesman = db.prepare('SELECT name FROM users WHERE id=?').get(salesmanId);
  const salesmanName = salesman?.name || '';
  const settlements = db.prepare(`
    SELECT ss.*, u.name as acknowledged_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    WHERE ss.salesman_name = ?
    ORDER BY ss.created_at DESC
  `).all(salesmanName);

  const unsettledTotal = unsettled.reduce((s, r) => s + r.amount, 0);

  res.json({
    unsettled,
    unsettled_total: parseFloat(unsettledTotal.toFixed(2)),
    settlements,
  });
}

// ── Salesman: raise a settlement request to admin ─────────────────────────────
function raiseSettlementRequest(req, res) {
  const salesmanId = req.user.id;
  const salesmanName = req.user.name;
  const { note, request_ids } = req.body;

  // If specific request_ids provided, raise only those; otherwise raise all unsettled
  let requests;
  if (Array.isArray(request_ids) && request_ids.length > 0) {
    const placeholders = request_ids.map(() => '?').join(',');
    requests = db.prepare(`
      SELECT id, amount FROM topup_requests
      WHERE id IN (${placeholders}) AND collected_by = ? AND status = 'approved'
        AND settled_at IS NULL AND settlement_id IS NULL
    `).all(...request_ids, salesmanId);
    if (!requests.length) {
      return res.status(400).json({ error: 'No matching unsettled approved collections found' });
    }
  } else {
    // All unsettled
    requests = db.prepare(`
      SELECT id, amount FROM topup_requests
      WHERE collected_by = ? AND status = 'approved'
        AND settled_at IS NULL AND settlement_id IS NULL
    `).all(salesmanId);
    if (!requests.length) {
      return res.status(400).json({ error: 'No unsettled approved collections to raise for settlement' });
    }
  }

  const totalAmount = requests.reduce((s, r) => s + r.amount, 0);
  const requestIds = JSON.stringify(requests.map(r => r.id));

  const result = db.prepare(
    'INSERT INTO salesman_settlements (salesman_name, amount, topup_request_ids, note) VALUES (?,?,?,?)'
  ).run(salesmanName, totalAmount, requestIds, note || null);

  const settlementId = result.lastInsertRowid;

  // Mark all requests as part of this settlement (pending admin acknowledgement)
  const stmt = db.prepare('UPDATE topup_requests SET settlement_id=? WHERE id=?');
  for (const r of requests) {
    stmt.run(settlementId, r.id);
  }

  // Notify admin
  const admins = db.prepare("SELECT id FROM users WHERE role IN ('admin','subadmin') AND is_active=1").all();
  const notificationService = require('../services/notificationService');
  for (const admin of admins) {
    notificationService.sendToUser(
      admin.id,
      'Settlement Request',
      `${salesmanName} has raised a settlement of ₹${totalAmount.toFixed(0)} (${requests.length} collections)`
    );
  }

  res.json({
    message: `Settlement request raised for ₹${totalAmount.toFixed(2)}`,
    settlement_id: settlementId,
    amount: totalAmount,
    request_count: requests.length,
  });
}

module.exports = {
  listMyCustomers,
  addCustomer,
  resetCustomerPasswordBySalesman,
  approveMyCollection,
  myPendingCollections,
  myApprovedCollections,
  raiseSettlementRequest,
};
