const db = require('../config/database');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const notificationService = require('../services/notificationService');

function issueToken(user) {
  return jwt.sign({ id: user.id, role: user.role, tv: user.token_version ?? 0 }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '30d',
  });
}

// ── List all salesmen ─────────────────────────────────────────────────────────
function listSalesmen(req, res) {
  const salesmen = db.prepare(
    "SELECT id, name, phone, is_active, created_at, last_login_at, last_active_at FROM users WHERE role = 'salesman' ORDER BY name"
  ).all();

  const result = salesmen.map(s => {
    const pending = db.prepare(
      "SELECT COUNT(*) as c, COALESCE(SUM(amount),0) as total FROM topup_requests WHERE collected_by=? AND status='pending'"
    ).get(s.name);
    const unsettled = db.prepare(
      "SELECT COUNT(*) as c, COALESCE(SUM(amount),0) as total FROM topup_requests WHERE collected_by=? AND status='approved'"
    ).get(s.name);
    return { ...s, pending_count: pending.c, pending_total: pending.total,
              unsettled_count: unsettled.c, unsettled_total: unsettled.total };
  });

  res.json({ salesmen: result });
}

// ── Create salesman ───────────────────────────────────────────────────────────
function createSalesman(req, res) {
  const { name, phone, password } = req.body;
  if (!name || !phone || !password) {
    return res.status(400).json({ error: 'name, phone, and password are required' });
  }
  if (!/^[0-9]{10}$/.test(phone)) return res.status(400).json({ error: 'Phone must be 10 digits' });
  if (password.length < 6) return res.status(400).json({ error: 'Password must be at least 6 characters' });

  const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(phone);
  if (existing) return res.status(400).json({ error: 'Phone already registered' });

  const hash = bcrypt.hashSync(password, 10);
  const result = db.prepare(
    "INSERT INTO users (name, phone, password_hash, password_set, role) VALUES (?,?,?,1,'salesman')"
  ).run(name, phone, hash);

  // Salesmen are also delivery agents — auto-register them
  db.prepare('INSERT INTO delivery_agents (user_id) VALUES (?)').run(result.lastInsertRowid);

  res.status(201).json({
    message: 'Salesman account created',
    salesman: db.prepare('SELECT id,name,phone,role,is_active FROM users WHERE id=?').get(result.lastInsertRowid),
  });
}

// ── Toggle active ─────────────────────────────────────────────────────────────
function toggleSalesman(req, res) {
  const s = db.prepare("SELECT * FROM users WHERE id=? AND role='salesman'").get(req.params.id);
  if (!s) return res.status(404).json({ error: 'Salesman not found' });
  const active = s.is_active ? 0 : 1;
  db.prepare('UPDATE users SET is_active=? WHERE id=?').run(active, s.id);
  res.json({ message: active ? `${s.name} activated` : `${s.name} deactivated`, is_active: active });
}

// ── Reset password ────────────────────────────────────────────────────────────
function resetSalesmanPassword(req, res) {
  const { new_password } = req.body;
  if (!new_password || new_password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  const s = db.prepare("SELECT * FROM users WHERE id=? AND role='salesman'").get(req.params.id);
  if (!s) return res.status(404).json({ error: 'Salesman not found' });
  db.prepare("UPDATE users SET password_hash=?, password_set=1 WHERE id=?").run(bcrypt.hashSync(new_password, 10), s.id);
  res.json({ message: `Password reset for ${s.name}` });
}

// ── Update salesman name/phone ─────────────────────────────────────────────────
function updateSalesman(req, res) {
  const { name, phone } = req.body;
  const s = db.prepare("SELECT * FROM users WHERE id=? AND role='salesman'").get(req.params.id);
  if (!s) return res.status(404).json({ error: 'Salesman not found' });

  if (phone && !/^[0-9]{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Phone must be 10 digits' });
  }
  if (phone && phone !== s.phone) {
    const existing = db.prepare('SELECT id FROM users WHERE phone=? AND id!=?').get(phone, s.id);
    if (existing) return res.status(400).json({ error: 'Phone number already in use' });
  }

  db.prepare('UPDATE users SET name=?, phone=? WHERE id=?').run(
    name ?? s.name,
    phone ?? s.phone,
    s.id
  );
  res.json({ message: 'Salesman updated', salesman: db.prepare('SELECT id,name,phone,role,is_active FROM users WHERE id=?').get(s.id) });
}

// ── Cash summary ──────────────────────────────────────────────────────────────
function getSalesmanSummary(req, res) {
  const { date_from, date_to, salesman, approved_by, search } = req.query;

  // Date/salesman filter conditions
  const dateFilter = (alias) => {
    let c = '';
    if (date_from) c += ` AND date(${alias}.created_at) >= '${date_from}'`;
    if (date_to)   c += ` AND date(${alias}.created_at) <= '${date_to}'`;
    return c;
  };
  const salesmanFilter = salesman
    ? ` AND CAST(tr.collected_by AS INTEGER) IN (SELECT id FROM users WHERE name LIKE '%${salesman.replace(/'/g,'')}%' AND role='salesman')`
    : '';
  const approvedByFilter = approved_by === 'admin' ? ` AND tr.approved_by_role = 'admin'`
    : approved_by === 'salesman' ? ` AND tr.approved_by_role = 'salesman'`
    : '';
  const searchFilter = search
    ? ` AND (u.name LIKE '%${search.replace(/'/g,'')}%' OR u.phone LIKE '%${search.replace(/'/g,'')}%' OR CAST(tr.amount AS TEXT) LIKE '%${search.replace(/'/g,'')}%')`
    : '';
  const searchFilterCu = search
    ? ` AND (cu.name LIKE '%${search.replace(/'/g,'')}%' OR cu.phone LIKE '%${search.replace(/'/g,'')}%' OR CAST(tr.amount AS TEXT) LIKE '%${search.replace(/'/g,'')}%')`
    : '';

  // Approved cash NOT yet settled — individual requests per customer
  const collected = db.prepare(`
    SELECT tr.*, u.name as customer_name, u.phone as customer_phone,
           s.name as salesman_name
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    LEFT JOIN users s ON s.id = CAST(tr.collected_by AS INTEGER)
    WHERE tr.payment_method='cash' AND tr.status='approved' AND tr.settled_at IS NULL
      AND tr.settlement_id IS NULL
      ${dateFilter('tr')}${salesmanFilter}${approvedByFilter}${searchFilter}
    ORDER BY tr.resolved_at DESC
  `).all();

  // Individual collection items — pending cash + approved-not-raised cash + credit advance repayments not raised
  const collectionItems = db.prepare(`
    SELECT tr.*,
           cu.name  as customer_name,
           cu.phone as customer_phone,
           COALESCE(sm.name, tr.collected_by) as salesman_name,
           sm.phone as salesman_phone,
           ab.name  as approved_by_name,
           ss.settled_by as settlement_acknowledged
    FROM topup_requests tr
    JOIN  users cu ON cu.id = tr.user_id
    LEFT JOIN users sm ON sm.id = CAST(tr.collected_by AS INTEGER)
    LEFT JOIN users ab ON ab.id = tr.approved_by_id
    LEFT JOIN salesman_settlements ss ON ss.id = tr.settlement_id
    WHERE tr.collected_by IS NOT NULL
      AND (
        -- Cash: pending approval or approved but not raised
        (tr.payment_method = 'cash' AND tr.status IN ('pending','approved')
          AND (tr.status = 'pending' OR (tr.settlement_id IS NULL AND tr.settled_at IS NULL)))
        OR
        -- Credit advance: customer paid salesman, salesman hasn't raised it yet
        (tr.payment_method = 'credit_advance' AND tr.payment_received = 1
          AND (tr.paid_by_role IS NULL OR tr.paid_by_role = 'salesman')
          AND tr.settlement_id IS NULL AND tr.settled_at IS NULL)
      )
      ${dateFilter('tr')}${salesmanFilter}${approvedByFilter}${searchFilterCu}
    ORDER BY tr.created_at DESC
    LIMIT 200
  `).all();

  // Settlement requests raised by salesmen — pending admin acknowledgement
  const raisedSettlements = db.prepare(`
    SELECT ss.*, u.name as acknowledged_by_name
    FROM salesman_settlements ss
    LEFT JOIN users u ON u.id = ss.settled_by
    WHERE ss.settled_by IS NULL
      ${date_from ? `AND date(ss.created_at) >= '${date_from}'` : ''}
      ${date_to   ? `AND date(ss.created_at) <= '${date_to}'`   : ''}
      ${salesman  ? `AND ss.salesman_name LIKE '%${salesman.replace(/'/g,'')}%'` : ''}
    ORDER BY ss.created_at DESC
  `).all();

  const settlements = db.prepare(`
    SELECT ss.*, u.name as settled_by_name FROM salesman_settlements ss
    LEFT JOIN users u ON u.id=ss.settled_by
    WHERE ss.settled_by IS NOT NULL
      ${date_from ? `AND date(ss.created_at) >= '${date_from}'` : ''}
      ${date_to   ? `AND date(ss.created_at) <= '${date_to}'`   : ''}
      ${salesman  ? `AND ss.salesman_name LIKE '%${salesman.replace(/'/g,'')}%'` : ''}
    ORDER BY ss.created_at DESC LIMIT 200
  `).all();

  const pending = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone,
           s.name as collector_name
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    LEFT JOIN users s ON s.id = CAST(tr.collected_by AS INTEGER)
    WHERE tr.payment_method='cash' AND tr.status='pending'
    ORDER BY tr.created_at DESC
  `).all();

  res.json({ collected, collection_items: collectionItems, raised_settlements: raisedSettlements, settlements, pending });
}

// ── Acknowledge a salesman-raised settlement ──────────────────────────────────
function acknowledgeSettlement(req, res) {
  const settlementId = parseInt(req.params.id);
  const settlement = db.prepare('SELECT * FROM salesman_settlements WHERE id=?').get(settlementId);

  if (!settlement) return res.status(404).json({ error: 'Settlement not found' });
  if (settlement.settled_by) return res.status(400).json({ error: 'Already acknowledged' });

  db.prepare("UPDATE salesman_settlements SET settled_by=?, updated_at=datetime('now') WHERE id=?").run(req.user.id, settlementId);

  // Mark all topup_requests in this settlement as settled
  const ids = JSON.parse(settlement.topup_request_ids);
  const stmt = db.prepare("UPDATE topup_requests SET settled_at=datetime('now') WHERE id=?");
  for (const id of ids) { stmt.run(id); }

  const notificationService = require('../services/notificationService');
  const salesman = db.prepare("SELECT id FROM users WHERE name=? AND role='salesman'").get(settlement.salesman_name);
  if (salesman) {
    notificationService.sendToUser(salesman.id, 'Settlement Acknowledged ✅',
      `Admin confirmed receipt of ₹${settlement.amount.toFixed(0)} from you.`);
  }

  res.json({ message: `Settlement of ₹${settlement.amount.toFixed(2)} acknowledged`, settlement_id: settlementId });
}

// ── Settle ────────────────────────────────────────────────────────────────────
function settleSalesman(req, res) {
  const { salesman_name, request_ids, note } = req.body;
  if (!salesman_name || !request_ids?.length) {
    return res.status(400).json({ error: 'salesman_name and request_ids required' });
  }
  const placeholders = request_ids.map(() => '?').join(',');
  // Match by request IDs only — admin passes exact IDs, no need to re-filter by collector
  const requests = db.prepare(
    `SELECT id, amount FROM topup_requests
     WHERE id IN (${placeholders}) AND status='approved'
       AND settled_at IS NULL AND settlement_id IS NULL`
  ).all(...request_ids);

  if (!requests.length) return res.status(400).json({ error: 'No matching unsettled approved requests found — these may have already been settled' });
  const totalAmount = requests.reduce((s, r) => s + r.amount, 0);

  // Record settlement
  const settlementResult = db.prepare(
    'INSERT INTO salesman_settlements (salesman_name,amount,topup_request_ids,note,settled_by) VALUES (?,?,?,?,?)'
  ).run(salesman_name, totalAmount, JSON.stringify(requests.map(r => r.id)), note || null, req.user.id);

  // Mark each request as settled — both columns
  const settleStmt = db.prepare("UPDATE topup_requests SET settled_at=datetime('now'), settlement_id=? WHERE id=?");
  for (const r of requests) {
    settleStmt.run(settlementResult.lastInsertRowid, r.id);
  }

  res.json({ message: `₹${totalAmount.toFixed(2)} from ${salesman_name} marked as settled`, total_settled: totalAmount });
}

// ── Salesman login ────────────────────────────────────────────────────────────
function salesmanLogin(req, res) {
  const { phone, password } = req.body;
  if (!phone || !password) return res.status(400).json({ error: 'phone and password required' });
  const user = db.prepare("SELECT * FROM users WHERE phone=? AND role='salesman'").get(phone);
  if (!user) return res.status(401).json({ error: 'Salesman account not found' });
  if (!user.is_active) return res.status(401).json({ error: 'Account deactivated. Contact admin.' });
  if (!bcrypt.compareSync(password, user.password_hash || '')) {
    return res.status(401).json({ error: 'Incorrect password' });
  }
  db.prepare("UPDATE users SET last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?").run(user.id);
  const token = issueToken(user);
  res.json({ token, user: { id: user.id, name: user.name, phone: user.phone, role: user.role } });
}

// ── Salesman history (delivered + cancelled + collections) by date range ──────
function salesmanHistory(req, res) {
  const userId = req.user.id;
  const name = req.user.name;

  const now = new Date();
  const defaultFrom = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-01`;
  const defaultTo   = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(new Date(now.getFullYear(), now.getMonth()+1, 0).getDate()).padStart(2,'0')}`;

  const dateFrom = req.query.date_from || defaultFrom;
  const dateTo   = req.query.date_to   || defaultTo;
  const search   = req.query.search || '';
  const like     = `%${search}%`;

  const agentRow = db.prepare('SELECT id FROM delivery_agents WHERE user_id=?').get(userId);

  const orderSearchClause = search ? `
    AND (
      o.order_number LIKE ?
      OR cu.name LIKE ? OR cu.phone LIKE ?
      OR EXISTS (
        SELECT 1 FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        LEFT JOIN categories cat ON cat.id = p.category_id
        WHERE oi.order_id = o.id AND (p.name LIKE ? OR cat.name LIKE ?)
      )
    )` : '';
  const sp = search ? [like, like, like, like, like] : [];

  // Completed orders: via delivery_agents OR via orders.salesman_id
  const completedByAgent = agentRow ? db.prepare(`
    SELECT o.*, d.id as delivery_id, d.delivered_at,
           cu.name as customer_name, cu.wallet_balance as customer_wallet_balance,
           a.city, s.label as slot_label
    FROM deliveries d
    JOIN orders o ON o.id = d.order_id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE d.agent_id = ? AND d.status = 'delivered'
      AND date(d.delivered_at) >= ? AND date(d.delivered_at) <= ?
      ${orderSearchClause}
    ORDER BY d.delivered_at DESC
  `).all(agentRow.id, dateFrom, dateTo, ...sp) : [];

  const completedBySalesman = db.prepare(`
    SELECT o.*, d.id as delivery_id, d.delivered_at,
           cu.name as customer_name, cu.wallet_balance as customer_wallet_balance,
           a.city, s.label as slot_label
    FROM orders o
    JOIN deliveries d ON d.order_id = o.id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE o.salesman_id = ? AND d.agent_id IS NULL AND d.status = 'delivered'
      AND date(d.delivered_at) >= ? AND date(d.delivered_at) <= ?
      ${orderSearchClause}
    ORDER BY d.delivered_at DESC
  `).all(userId, dateFrom, dateTo, ...sp);

  const seenCompleted = new Set();
  const completedOrders = [...completedByAgent, ...completedBySalesman].filter(o => {
    if (seenCompleted.has(o.id)) return false;
    seenCompleted.add(o.id);
    return true;
  });

  const completedWithItems = completedOrders.map(o => ({
    ...o,
    items: db.prepare(`
      SELECT oi.*, p.name as product_name, p.unit
      FROM order_items oi JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = ?
    `).all(o.id),
  }));

  // Cancelled orders: via delivery_agents OR via orders.salesman_id
  const cancelledByAgent = agentRow ? db.prepare(`
    SELECT o.*, d.id as delivery_id, d.assigned_at,
           cu.name as customer_name, cu.phone as customer_phone,
           cu.wallet_balance as customer_wallet_balance,
           a.city, a.address_line, s.label as slot_label
    FROM deliveries d
    JOIN orders o ON o.id = d.order_id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE d.agent_id = ? AND o.status = 'cancelled'
      AND date(o.updated_at) >= ? AND date(o.updated_at) <= ?
      ${orderSearchClause}
    ORDER BY o.updated_at DESC
  `).all(agentRow.id, dateFrom, dateTo, ...sp) : [];

  const cancelledBySalesman = db.prepare(`
    SELECT o.*, d.id as delivery_id, d.assigned_at,
           cu.name as customer_name, cu.phone as customer_phone,
           cu.wallet_balance as customer_wallet_balance,
           a.city, a.address_line, s.label as slot_label
    FROM orders o
    JOIN deliveries d ON d.order_id = o.id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE o.salesman_id = ? AND d.agent_id IS NULL AND o.status = 'cancelled'
      AND date(o.updated_at) >= ? AND date(o.updated_at) <= ?
      ${orderSearchClause}
    ORDER BY o.updated_at DESC
  `).all(userId, dateFrom, dateTo, ...sp);

  const seenCancelled = new Set();
  const cancelledOrders = [...cancelledByAgent, ...cancelledBySalesman].filter(o => {
    if (seenCancelled.has(o.id)) return false;
    seenCancelled.add(o.id);
    return true;
  });

  const approvedCollections = db.prepare(`
    SELECT tr.*, u.name as customer_name FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    WHERE tr.collected_by = ? AND tr.status = 'approved'
      AND date(tr.resolved_at) >= ? AND date(tr.resolved_at) <= ?
      ${search ? 'AND (u.name LIKE ? OR u.phone LIKE ?)' : ''}
    ORDER BY tr.resolved_at DESC
  `).all(name, dateFrom, dateTo, ...(search ? [like, like] : []));

  const settlements = db.prepare(`
    SELECT * FROM salesman_settlements
    WHERE salesman_name = ?
      AND date(created_at) >= ? AND date(created_at) <= ?
    ORDER BY created_at DESC
  `).all(name, dateFrom, dateTo);

  // In-progress orders: assigned / picked (dispatched) — not yet delivered or cancelled
  const inProgressByAgent = agentRow ? db.prepare(`
    SELECT o.*, d.id as delivery_id, d.assigned_at, d.status as delivery_status,
           cu.name as customer_name, cu.phone as customer_phone,
           cu.wallet_balance as customer_wallet_balance,
           a.city, a.address_line, s.label as slot_label
    FROM deliveries d
    JOIN orders o ON o.id = d.order_id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE d.agent_id = ? AND d.status IN ('assigned','picked')
      AND date(d.assigned_at) >= ? AND date(d.assigned_at) <= ?
      ${orderSearchClause}
    ORDER BY d.assigned_at DESC
  `).all(agentRow.id, dateFrom, dateTo, ...sp) : [];

  const inProgressBySalesman = db.prepare(`
    SELECT o.*, d.id as delivery_id, d.assigned_at, d.status as delivery_status,
           cu.name as customer_name, cu.phone as customer_phone,
           cu.wallet_balance as customer_wallet_balance,
           a.city, a.address_line, s.label as slot_label
    FROM orders o
    JOIN deliveries d ON d.order_id = o.id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE o.salesman_id = ? AND d.agent_id IS NULL AND d.status IN ('assigned','picked')
      AND date(d.assigned_at) >= ? AND date(d.assigned_at) <= ?
      ${orderSearchClause}
    ORDER BY d.assigned_at DESC
  `).all(userId, dateFrom, dateTo, ...sp);

  const seenInProgress = new Set();
  const inProgressOrders = [...inProgressByAgent, ...inProgressBySalesman].filter(o => {
    if (seenInProgress.has(o.id)) return false;
    seenInProgress.add(o.id);
    return true;
  });

  res.json({
    date_from: dateFrom,
    date_to: dateTo,
    completed_orders: completedWithItems,
    in_progress_orders: inProgressOrders,
    cancelled_orders: cancelledOrders,
    approved_collections: approvedCollections,
    settlements,
  });
}


function salesmanDashboard(req, res) {
  const userId = req.user.id;
  const name = req.user.name;

  // Cash collections — now using userId (integer FK)
  const pending = db.prepare(`
    SELECT tr.*, u.name as customer_name, u.phone as customer_phone
    FROM topup_requests tr JOIN users u ON u.id=tr.user_id
    WHERE CAST(tr.collected_by AS INTEGER)=? AND tr.status='pending'
    ORDER BY tr.created_at DESC
  `).all(userId);

  // Approved — not yet settled (no settlement_id)
  const approvedNotRaised = db.prepare(`
    SELECT tr.*, u.name as customer_name FROM topup_requests tr
    JOIN users u ON u.id=tr.user_id
    WHERE CAST(tr.collected_by AS INTEGER)=? AND tr.status='approved'
      AND tr.payment_method != 'credit_advance'
      AND tr.settlement_id IS NULL AND tr.settled_at IS NULL
    ORDER BY tr.created_at DESC
  `).all(userId);

  // Approved — raised settlement (has settlement_id, settlement not yet acknowledged by admin)
  const approvedRaisedPending = db.prepare(`
    SELECT tr.*, u.name as customer_name FROM topup_requests tr
    JOIN users u ON u.id=tr.user_id
    WHERE CAST(tr.collected_by AS INTEGER)=? AND tr.status='approved'
      AND tr.payment_method != 'credit_advance'
      AND tr.settlement_id IS NOT NULL AND tr.settled_at IS NULL
    ORDER BY tr.created_at DESC
  `).all(userId);

  // Approved — fully settled (admin acknowledged)
  const approvedSettled = db.prepare(`
    SELECT tr.*, u.name as customer_name FROM topup_requests tr
    JOIN users u ON u.id=tr.user_id
    WHERE CAST(tr.collected_by AS INTEGER)=? AND tr.status='approved'
      AND tr.payment_method != 'credit_advance'
      AND tr.settled_at IS NOT NULL
    ORDER BY tr.settled_at DESC LIMIT 20
  `).all(userId);

  const settlements = db.prepare(
    'SELECT * FROM salesman_settlements WHERE salesman_name=? ORDER BY created_at DESC LIMIT 10'
  ).all(name);

  // Delivery orders — via delivery_agents (old flow) OR salesman_id (new flow)
  const agentRow = db.prepare('SELECT id FROM delivery_agents WHERE user_id=?').get(userId);

  // Orders assigned via salesman_id on orders table (admin assigns salesman directly)
  const salesmanAssigned = db.prepare(`
    SELECT o.*, d.id as delivery_id, d.status as delivery_status, d.delivery_code, d.customer_confirmed_at,
           cu.name as customer_name, cu.phone as customer_phone,
           a.address_line, a.city, a.lat as addr_lat, a.lng as addr_lng, s.label as slot_label
    FROM orders o
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    WHERE o.salesman_id = ? AND o.status IN ('assigned','confirmed','dispatched')
      AND o.status != 'cancelled'
    ORDER BY o.delivery_date ASC
  `).all(userId);

  // Orders assigned via delivery_agents (legacy agent flow)
  const agentAssigned = agentRow ? db.prepare(`
    SELECT o.*, d.id as delivery_id, d.status as delivery_status, d.delivery_code, d.customer_confirmed_at,
           cu.name as customer_name, cu.phone as customer_phone,
           a.address_line, a.city, a.lat as addr_lat, a.lng as addr_lng, s.label as slot_label
    FROM deliveries d
    JOIN orders o ON o.id = d.order_id
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    WHERE d.agent_id = ? AND d.status NOT IN ('delivered') AND o.status != 'cancelled'
    ORDER BY o.delivery_date ASC
  `).all(agentRow.id) : [];

  // Merge, dedup by order_id (salesman_id takes priority)
  const seenIds = new Set();
  const assignedOrders = [...salesmanAssigned, ...agentAssigned].filter(o => {
    if (seenIds.has(o.id)) return false;
    seenIds.add(o.id);
    return true;
  });

  const completedToday = {
    c: (agentRow ? db.prepare(`
      SELECT COUNT(*) as c FROM deliveries WHERE agent_id=? AND status='delivered' AND date(delivered_at)=date('now')
    `).get(agentRow.id).c : 0)
    + db.prepare(`
      SELECT COUNT(*) as c FROM orders WHERE salesman_id=? AND status='delivered' AND date(updated_at)=date('now')
    `).get(userId).c,
  };

  const assignedWithItems = assignedOrders.map(o => ({
    ...o,
    items: db.prepare(`
      SELECT oi.*, p.name as product_name, p.unit, p.is_weight_adjusted
      FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?
    `).all(o.id),
  }));

  // Combined approved list for backward compat
  const approved = [...approvedNotRaised, ...approvedRaisedPending, ...approvedSettled];

  // Credit advances given by this salesman — outstanding (not paid) and recently paid
  const creditAdvances = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    WHERE tr.payment_method = 'credit_advance'
      AND tr.credited_by_role = 'salesman'
      AND CAST(tr.credited_by_id AS INTEGER) = ?
    ORDER BY tr.created_at DESC LIMIT 50
  `).all(userId);

  res.json({
    salesman: name,
    agent_id: agentRow?.id || null,
    pending_collections: {
      items: pending,
      total: pending.reduce((s,r)=>s+r.amount,0),
      count: pending.length,
    },
    approved_collections: {
      items: approved,
      total: approved.reduce((s,r)=>s+r.amount,0),
      count: approved.length,
      not_raised: { items: approvedNotRaised, total: approvedNotRaised.reduce((s,r)=>s+r.amount,0), count: approvedNotRaised.length },
      raised_pending: { items: approvedRaisedPending, total: approvedRaisedPending.reduce((s,r)=>s+r.amount,0), count: approvedRaisedPending.length },
      settled: { items: approvedSettled, total: approvedSettled.reduce((s,r)=>s+r.amount,0), count: approvedSettled.length },
    },
    credit_advances: {
      items: creditAdvances,
      unpaid: creditAdvances.filter(a => !a.payment_received),
      unpaid_total: creditAdvances.filter(a => !a.payment_received).reduce((s,r)=>s+r.amount,0),
    },
    settlements,
    assigned_orders: assignedWithItems,
    completed_orders: [],
    cancelled_orders: [],
    completed_today: completedToday.c,
  });
}

module.exports = {
  listSalesmen, createSalesman, toggleSalesman, resetSalesmanPassword, updateSalesman,
  getSalesmanSummary, settleSalesman, acknowledgeSettlement, salesmanLogin, salesmanDashboard,
  salesmanHistory, listActiveSalesmen, getSalesmanPendingOrders, confirmAndAssignOrder,
};

function listActiveSalesmen(req, res) {
  const salesmen = db.prepare(
    "SELECT u.id, u.name, u.phone FROM users u WHERE u.role='salesman' AND u.is_active=1 ORDER BY u.name"
  ).all();
  res.json({ salesmen });
}

// ── Pending orders that this salesman can approve ────────────────────────────
// Returns orders with status='pending' — salesman sees them if they are the
// default_salesman_id in config OR if the order has no agent assigned yet.
function getSalesmanPendingOrders(req, res) {
  const { search } = req.query;
  let where = "o.status = 'pending'";
  const params = [];
  if (search) {
    const like = `%${search}%`;
    where += ` AND (
      o.order_number LIKE ?
      OR cu.name LIKE ? OR cu.phone LIKE ?
      OR EXISTS (
        SELECT 1 FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        LEFT JOIN categories cat ON cat.id = p.category_id
        WHERE oi.order_id = o.id AND (p.name LIKE ? OR cat.name LIKE ?)
      )
    )`;
    params.push(like, like, like, like, like);
  }

  const orders = db.prepare(`
    SELECT o.*, d.id as delivery_id,
           cu.name as customer_name, cu.phone as customer_phone,
           cu.wallet_balance as customer_wallet_balance,
           a.address_line, a.city, s.label as slot_label,
           pc.code as coupon_code
    FROM orders o
    JOIN users cu ON cu.id = o.user_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    LEFT JOIN promo_code_uses pcu ON pcu.order_id = o.id
    LEFT JOIN promo_codes pc ON pc.id = pcu.promo_code_id
    WHERE ${where}
    ORDER BY o.created_at ASC
  `).all(...params);

  const withItems = orders.map(o => ({
    ...o,
    items: db.prepare(`
      SELECT oi.estimated_qty, oi.unit_price, oi.estimated_total, p.name as product_name, p.unit
      FROM order_items oi JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = ?
    `).all(o.id),
  }));

  res.json({ orders: withItems, count: withItems.length });
}

// ── Confirm a pending order and assign it to a salesman ─────────────────────
// salesman_id in body = assign to that salesman; omit = assign to self
function confirmAndAssignOrder(req, res) {
  const selfUserId = req.user.id;
  const orderId = parseInt(req.params.id);
  const { salesman_id, actual_weights } = req.body;

  const assignToUserId = salesman_id ? parseInt(salesman_id) : selfUserId;

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (order.status !== 'pending') {
    return res.status(400).json({ error: `Order is already ${order.status}` });
  }

  const agentRow = db.prepare('SELECT * FROM delivery_agents WHERE user_id = ?').get(assignToUserId);
  if (!agentRow) return res.status(400).json({ error: 'Target salesman is not registered as a delivery agent' });

  const assignedUser = db.prepare('SELECT name FROM users WHERE id = ?').get(assignToUserId);

  db.transaction(() => {
    db.prepare("UPDATE orders SET status='assigned', salesman_id=?, updated_at=datetime('now') WHERE id=?").run(assignToUserId, orderId);
    db.prepare(`
      UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now'), delivery_code=?
      WHERE order_id=?
    `).run(agentRow.id, String(Math.floor(100000 + Math.random() * 900000)), orderId);

    // Apply actual weights if provided (weight-adjusted items)
    if (Array.isArray(actual_weights) && actual_weights.length > 0) {
      for (const w of actual_weights) {
        if (!w.order_item_id || w.actual_qty == null) continue;
        const item = db.prepare('SELECT * FROM order_items WHERE id = ? AND order_id = ?')
          .get(parseInt(w.order_item_id), orderId);
        if (!item) continue;
        const actualQty = parseFloat(w.actual_qty);
        const actualTotal = parseFloat((actualQty * item.unit_price).toFixed(2));
        db.prepare('UPDATE order_items SET actual_qty=?, actual_total=? WHERE id=?')
          .run(actualQty, actualTotal, item.id);
      }
      // Recalculate order total from items
      const updatedItems = db.prepare('SELECT * FROM order_items WHERE order_id = ?').all(orderId);
      const newSubtotal = updatedItems.reduce((s, i) => s + (i.actual_total ?? i.estimated_total), 0);

      // Re-evaluate coupon discount on new actual quantities
      let newDiscount = order.discount_amount || 0;
      const promoUse = db.prepare('SELECT pcu.*, pc.discount_type, pc.discount_value, pc.max_discount_amount, pc.allowed_product_ids, pc.allowed_category_ids FROM promo_code_uses pcu JOIN promo_codes pc ON pc.id = pcu.promo_code_id WHERE pcu.order_id = ?').get(orderId);
      if (promoUse) {
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
        newDiscount = Math.min(newDiscount, newSubtotal + order.delivery_charge);
        newDiscount = Math.round(newDiscount * 100) / 100;
        db.prepare('UPDATE promo_code_uses SET discount_amount = ? WHERE order_id = ?').run(newDiscount, orderId);
      }

      const newFinal = parseFloat((newSubtotal + order.delivery_charge - newDiscount).toFixed(2));
      db.prepare('UPDATE orders SET subtotal=?, final_amount=?, discount_amount=? WHERE id=?')
        .run(parseFloat(newSubtotal.toFixed(2)), newFinal, newDiscount, orderId);
      // Adjust wallet: deduct difference from estimated
      const diff = newFinal - order.final_amount;
      if (Math.abs(diff) > 0.01) {
        const walletService = require('../services/walletService');
        if (diff > 0) {
          walletService.debit(order.user_id, diff, 'adjustment', 'order', orderId,
            `Weight adjustment on order #${order.order_number}`);
        } else {
          walletService.credit(order.user_id, Math.abs(diff), 'refund', 'order', orderId,
            `Weight adjustment refund on order #${order.order_number}`);
        }
      }
    }
  })();

  const notificationService = require('../services/notificationService');
  notificationService.sendToUser(
    order.user_id,
    'Order Confirmed!',
    `Your order #${order.order_number} has been confirmed and assigned to ${assignedUser?.name ?? 'a salesman'}.`
  );
  const selfUser = db.prepare('SELECT name FROM users WHERE id=?').get(selfUserId);
  notificationService.sendToAdmins('Order Assigned 🚚', `Order #${order.order_number} assigned to ${assignedUser?.name ?? 'salesman'} by ${selfUser?.name ?? 'salesman'}`, { type: 'order_assigned', order_id: String(orderId) });

  res.json({
    message: `Order confirmed and assigned to ${assignedUser?.name ?? 'salesman'}`,
    order_id: orderId,
    assigned_to: assignedUser?.name,
  });
}
