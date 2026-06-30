const db = require('../config/database');
const bcrypt = require('bcryptjs');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

// ── Salesman: search/list their customers ─────────────────────────────────────
function listMyCustomers(req, res) {
  const { search, wallet, sort = 'name' } = req.query;
  let where = "u.role = 'customer' AND u.is_active = 1";
  const params = [];
  if (search) {
    where += ' AND (u.name LIKE ? OR u.phone LIKE ? OR u.email LIKE ?)';
    params.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (wallet === 'negative') where += ' AND u.wallet_balance < 0';
  else if (wallet === 'zero') where += ' AND u.wallet_balance = 0';
  else if (wallet === 'positive') where += ' AND u.wallet_balance > 0';
  else if (wallet === 'low') where += ' AND u.wallet_balance > 0 AND u.wallet_balance < 100';

  const orderBy = sort === 'wallet_desc' ? 'u.wallet_balance DESC'
                : sort === 'wallet_asc'  ? 'u.wallet_balance ASC'
                : sort === 'recent'      ? 'u.created_at DESC'
                : 'u.name ASC';

  const customers = db.prepare(`
    SELECT u.id, u.name, u.phone, u.email, u.wallet_balance, u.created_at,
           t.name as tier_name, t.color as tier_color, t.max_wallet_negative_limit
    FROM users u
    LEFT JOIN customer_tiers t ON t.id = u.tier_id
    WHERE ${where} ORDER BY ${orderBy} LIMIT 100
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
  db.prepare("UPDATE topup_requests SET status='approved', resolved_at=datetime('now'), approved_by_id=?, approved_by_role='salesman' WHERE id=?")
    .run(req.user.id, request.id);

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

  // Approved but not yet raised for settlement (cash + paid credit advances)
  const unsettled = db.prepare(`
    SELECT tr.*, u.name as customer_name, u.phone as customer_phone
    FROM topup_requests tr JOIN users u ON u.id = tr.user_id
    WHERE (
      (tr.collected_by = ? AND tr.payment_method = 'cash' AND tr.status = 'approved'
        AND tr.settled_at IS NULL AND tr.settlement_id IS NULL)
      OR
      (CAST(tr.credited_by_id AS INTEGER) = ? AND tr.payment_method = 'credit_advance'
        AND tr.payment_received = 1 AND (tr.paid_by_role IS NULL OR tr.paid_by_role = 'salesman')
        AND tr.settled_at IS NULL AND tr.settlement_id IS NULL)
    )
    ORDER BY tr.resolved_at DESC
  `).all(salesmanId, salesmanId);

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
  // settlement_type: 'cash' | 'credit_advance' | 'mixed'
  const { note, request_ids, settlement_type = 'cash' } = req.body;

  // Validate type
  if (!['cash', 'credit_advance', 'mixed'].includes(settlement_type)) {
    return res.status(400).json({ error: 'settlement_type must be cash, credit_advance, or mixed' });
  }

  let requests;
  if (Array.isArray(request_ids) && request_ids.length > 0) {
    const placeholders = request_ids.map(() => '?').join(',');
    // Allow both cash and credit_advance items when raising by specific IDs
    requests = db.prepare(`
      SELECT id, amount, payment_method FROM topup_requests
      WHERE id IN (${placeholders}) AND status IN ('approved', 'approved')
        AND settled_at IS NULL AND settlement_id IS NULL
        AND (
          (collected_by = ? AND payment_method = 'cash')
          OR
          (CAST(credited_by_id AS INTEGER) = ? AND payment_method = 'credit_advance'
            AND payment_received = 1 AND (paid_by_role IS NULL OR paid_by_role = 'salesman'))
        )
    `).all(...request_ids, salesmanId, salesmanId);
    if (!requests.length) {
      return res.status(400).json({ error: 'No matching unsettled collections found' });
    }
  } else if (settlement_type === 'credit_advance') {
    requests = db.prepare(`
      SELECT id, amount, payment_method FROM topup_requests
      WHERE CAST(credited_by_id AS INTEGER) = ? AND payment_method = 'credit_advance'
        AND payment_received = 1 AND (paid_by_role IS NULL OR paid_by_role = 'salesman')
        AND settled_at IS NULL AND settlement_id IS NULL
    `).all(salesmanId);
    if (!requests.length) {
      return res.status(400).json({ error: 'No credit advance repayments to raise' });
    }
  } else {
    // cash (default) — only cash collections
    requests = db.prepare(`
      SELECT id, amount, payment_method FROM topup_requests
      WHERE collected_by = ? AND payment_method = 'cash' AND status = 'approved'
        AND settled_at IS NULL AND settlement_id IS NULL
    `).all(salesmanId);
    if (!requests.length) {
      return res.status(400).json({ error: 'No unsettled cash collections to raise' });
    }
  }

  // Detect actual type based on what was selected
  const hasOnly = (method) => requests.every(r => r.payment_method === method);
  const actualType = hasOnly('cash') ? 'cash'
      : hasOnly('credit_advance') ? 'credit_advance'
      : 'mixed';

  const totalAmount = requests.reduce((s, r) => s + r.amount, 0);
  const requestIds = JSON.stringify(requests.map(r => r.id));

  const result = db.prepare(
    'INSERT INTO salesman_settlements (salesman_name, amount, topup_request_ids, note, settlement_type) VALUES (?,?,?,?,?)'
  ).run(salesmanName, totalAmount, requestIds, note || null, actualType);

  const settlementId = result.lastInsertRowid;

  const stmt = db.prepare('UPDATE topup_requests SET settlement_id=? WHERE id=?');
  for (const r of requests) {
    stmt.run(settlementId, r.id);
  }

  const notificationService = require('../services/notificationService');
  const admins = db.prepare("SELECT id FROM users WHERE role IN ('admin','subadmin') AND is_active=1").all();
  const typeLabel = actualType === 'credit_advance' ? 'credit advance repayments'
      : actualType === 'mixed' ? 'collections'
      : 'cash collections';
  for (const admin of admins) {
    notificationService.sendToUser(
      admin.id,
      'Settlement Request',
      `${salesmanName} has raised a settlement of ₹${totalAmount.toFixed(0)} (${requests.length} ${typeLabel})`
    );
  }

  res.json({
    message: `Settlement request raised for ₹${totalAmount.toFixed(2)}`,
    settlement_id: settlementId,
    settlement_type: actualType,
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
  creditTopupSalesman,
  markCreditTopupPaidSalesman,
};

// ── Salesman: give credit advance to a customer ───────────────────────────────
function creditTopupSalesman(req, res) {
  const { user_id, amount, note } = req.body;
  if (!user_id || !amount || amount <= 0) return res.status(400).json({ error: 'user_id and valid amount required' });

  const user = db.prepare("SELECT id, name FROM users WHERE id = ? AND role = 'customer'").get(user_id);
  if (!user) return res.status(404).json({ error: 'Customer not found' });

  const result = db.prepare(`
    INSERT INTO topup_requests (user_id, amount, payment_method, collected_by, status, resolved_at, payment_received, credited_by_role, credited_by_id, admin_note)
    VALUES (?,?,'credit_advance',?, 'approved', datetime('now'), 0, 'salesman', ?, ?)
  `).run(user_id, amount, String(req.user.id), req.user.id, note || null);

  const topupId = result.lastInsertRowid;
  const newBalance = walletService.credit(user_id, amount, 'credit', 'topup', topupId,
    `Credit advance by salesman ${req.user.name || req.user.id}${note ? ': ' + note : ''}`);
  notificationService.sendToUser(user_id, 'Wallet Credited 💳',
    `₹${amount} credit advance from your salesman. Please pay when you can.`);
  res.status(201).json({ message: 'Credit advance given', topup_id: topupId, new_balance: newBalance });
}

// ── Salesman: mark a credit advance as paid by customer ──────────────────────
function markCreditTopupPaidSalesman(req, res) {
  const tr = db.prepare(`
    SELECT * FROM topup_requests
    WHERE id = ? AND payment_method = 'credit_advance' AND payment_received = 0
      AND credited_by_role = 'salesman' AND CAST(credited_by_id AS INTEGER) = ?
  `).get(req.params.id, req.user.id);
  if (!tr) return res.status(404).json({ error: 'Credit advance not found or already marked paid' });

  db.prepare("UPDATE topup_requests SET payment_received=1, payment_received_at=datetime('now'), paid_by_role='salesman', updated_at=datetime('now') WHERE id=?").run(tr.id);
  const user = db.prepare('SELECT name FROM users WHERE id=?').get(tr.user_id);
  notificationService.sendToUser(tr.user_id, 'Payment Received ✅',
    `Your payment of ₹${tr.amount} has been received by your salesman. Thank you!`);
  res.json({ message: `Payment of ₹${tr.amount} received from ${user?.name ?? 'customer'}` });
}
