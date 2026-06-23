const db = require('../config/database');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

// ── CRUD for reward rules ─────────────────────────────────────────────────────

function listRules(req, res) {
  const rules = db.prepare('SELECT * FROM reward_rules ORDER BY created_at DESC').all();
  res.json({ rules });
}

function createRule(req, res) {
  const { name, type, target_id, target_name, cashback_percent, min_qty, min_spend } = req.body;
  if (!name || !type || !target_name || cashback_percent == null) {
    return res.status(400).json({ error: 'name, type, target_name, and cashback_percent are required' });
  }
  if (!['product_cashback', 'category_cashback'].includes(type)) {
    return res.status(400).json({ error: 'type must be product_cashback or category_cashback' });
  }
  if (cashback_percent <= 0 || cashback_percent > 100) {
    return res.status(400).json({ error: 'cashback_percent must be between 0 and 100' });
  }

  const result = db.prepare(`
    INSERT INTO reward_rules (name, type, target_id, target_name, cashback_percent, min_qty, min_spend)
    VALUES (?,?,?,?,?,?,?)
  `).run(name, type, target_id || null, target_name, cashback_percent,
    parseFloat(min_qty || 0), parseFloat(min_spend || 0));

  res.status(201).json({ rule: db.prepare('SELECT * FROM reward_rules WHERE id=?').get(result.lastInsertRowid) });
}

function updateRule(req, res) {
  const rule = db.prepare('SELECT * FROM reward_rules WHERE id=?').get(req.params.id);
  if (!rule) return res.status(404).json({ error: 'Rule not found' });

  const { name, cashback_percent, min_qty, min_spend, is_active } = req.body;
  db.prepare(`
    UPDATE reward_rules SET name=?, cashback_percent=?, min_qty=?, min_spend=?, is_active=? WHERE id=?
  `).run(
    name ?? rule.name,
    cashback_percent ?? rule.cashback_percent,
    parseFloat(min_qty ?? rule.min_qty),
    parseFloat(min_spend ?? rule.min_spend),
    is_active != null ? (is_active ? 1 : 0) : rule.is_active,
    rule.id
  );

  res.json({ rule: db.prepare('SELECT * FROM reward_rules WHERE id=?').get(rule.id) });
}

function deleteRule(req, res) {
  const rule = db.prepare('SELECT * FROM reward_rules WHERE id=?').get(req.params.id);
  if (!rule) return res.status(404).json({ error: 'Rule not found' });
  db.prepare('DELETE FROM reward_rules WHERE id=?').run(rule.id);
  res.json({ message: 'Rule deleted' });
}

// ── Calculate cashback — one payout per eligible order per rule ───────────────

function calculateRewards(req, res) {
  const { month } = req.body;
  let targetMonth = month;
  if (!targetMonth) {
    const now = new Date();
    targetMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }

  const monthStart = `${targetMonth}-01`;
  const monthEnd   = `${targetMonth}-31`;

  const rules = db.prepare('SELECT * FROM reward_rules WHERE is_active=1').all();
  if (!rules.length) return res.json({ message: 'No active rules', targetMonth, newPayouts: 0 });

  let totalCalculated = 0;
  let newPayouts      = 0;
  let skipped         = 0;
  const payouts       = [];

  for (const rule of rules) {
    // Find every eligible order NOT yet in reward_payouts for this rule
    let orderQuery;
    if (rule.type === 'product_cashback') {
      orderQuery = db.prepare(`
        SELECT o.id as order_id, o.user_id,
               SUM(oi.estimated_total) as spend_amount,
               SUM(oi.estimated_qty)   as qty_purchased
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        WHERE oi.product_id = ?
          AND o.status = 'delivered'
          AND date(o.created_at) BETWEEN ? AND ?
          AND o.id NOT IN (
            SELECT order_id FROM reward_payouts
            WHERE rule_id = ? AND order_id IS NOT NULL AND status IN ('pending','approved')
          )
        GROUP BY o.id, o.user_id
      `);
    } else {
      orderQuery = db.prepare(`
        SELECT o.id as order_id, o.user_id,
               SUM(oi.estimated_total) as spend_amount,
               SUM(oi.estimated_qty)   as qty_purchased
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        JOIN products p ON p.id = oi.product_id
        WHERE p.category_id = ?
          AND o.status = 'delivered'
          AND date(o.created_at) BETWEEN ? AND ?
          AND o.id NOT IN (
            SELECT order_id FROM reward_payouts
            WHERE rule_id = ? AND order_id IS NOT NULL AND status IN ('pending','approved')
          )
        GROUP BY o.id, o.user_id
      `);
    }

    const orders = orderQuery.all(rule.target_id, monthStart, monthEnd, rule.id);

    for (const order of orders) {
      if (rule.min_qty   > 0 && order.qty_purchased < rule.min_qty)   { skipped++; continue; }
      if (rule.min_spend > 0 && order.spend_amount  < rule.min_spend) { skipped++; continue; }

      // Wallet ≥ ₹100 check
      const user = db.prepare('SELECT wallet_balance FROM users WHERE id=?').get(order.user_id);
      if (!user || user.wallet_balance < 100) { skipped++; continue; }

      const cashback = parseFloat((order.spend_amount * rule.cashback_percent / 100).toFixed(2));
      if (cashback <= 0) continue;

      const result = db.prepare(`
        INSERT INTO reward_payouts
          (user_id, rule_id, order_id, month, spend_amount, qty_purchased, cashback_amount, status)
        VALUES (?,?,?,?,?,?,?,'pending')
      `).run(order.user_id, rule.id, order.order_id, targetMonth,
             order.spend_amount, order.qty_purchased, cashback);

      payouts.push({ payout_id: result.lastInsertRowid, order_id: order.order_id,
                     user_id: order.user_id, rule: rule.name, cashback });
      totalCalculated += cashback;
      newPayouts++;
    }
  }

  res.json({
    message: newPayouts > 0
      ? `${newPayouts} new payout${newPayouts > 1 ? 's' : ''} created for ${targetMonth}. Review and approve in the Payout History tab.`
      : `No new eligible orders found for ${targetMonth}.`,
    targetMonth, newPayouts, totalCalculated, skipped, payouts,
  });
}

// ── Admin approves payouts → credit wallets ───────────────────────────────────

function approvePayouts(req, res) {
  const { payout_ids, approve_all_month } = req.body;

  let targets;
  if (approve_all_month) {
    targets = db.prepare("SELECT * FROM reward_payouts WHERE month=? AND status='pending'").all(approve_all_month);
  } else if (payout_ids?.length) {
    const ph = payout_ids.map(() => '?').join(',');
    targets = db.prepare(`SELECT * FROM reward_payouts WHERE id IN (${ph}) AND status='pending'`).all(...payout_ids);
  } else {
    return res.status(400).json({ error: 'payout_ids or approve_all_month required' });
  }

  if (!targets.length) return res.json({ message: 'No pending payouts to approve', approved: 0 });

  let totalApproved = 0;
  for (const payout of targets) {
    // Fetch rule details for rich description
    const rule = db.prepare('SELECT name, cashback_percent, target_name FROM reward_rules WHERE id=?').get(payout.rule_id);
    const desc = rule
      ? `${rule.cashback_percent}% cashback on ${rule.target_name} (${rule.name}) — ₹${payout.spend_amount.toFixed(0)} spent in ${payout.month}`
      : `Cashback reward (${payout.month})`;

    const newBalance = walletService.credit(
      payout.user_id, payout.cashback_amount, 'discount', 'reward', payout.id, desc
    );
    db.prepare("UPDATE reward_payouts SET status='approved' WHERE id=?").run(payout.id);
    notificationService.sendToUser(
      payout.user_id,
      'Cashback Credited! 🎉',
      `₹${payout.cashback_amount.toFixed(2)} cashback for ${rule ? rule.target_name : 'purchase'} (${rule ? rule.cashback_percent + '%' : ''}) in ${payout.month}. New balance: ₹${newBalance.toFixed(2)}`
    );
    totalApproved += payout.cashback_amount;
  }

  res.json({ message: `${targets.length} payouts approved. ₹${totalApproved.toFixed(2)} credited.`, approved: targets.length, total_credited: totalApproved });
}

// ── Admin rejects payouts ─────────────────────────────────────────────────────

function rejectPayouts(req, res) {
  const { payout_ids } = req.body;
  if (!payout_ids?.length) return res.status(400).json({ error: 'payout_ids required' });
  const ph = payout_ids.map(() => '?').join(',');
  db.prepare(`UPDATE reward_payouts SET status='rejected' WHERE id IN (${ph}) AND status='pending'`).run(...payout_ids);
  res.json({ message: `${payout_ids.length} payouts rejected` });
}

// ── List payouts ──────────────────────────────────────────────────────────────

function listPayouts(req, res) {
  const { month, user_id, status, page = 1, limit = 50 } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  let where = '1=1';
  const params = [];
  if (month) { where += ' AND rp.month = ?'; params.push(month); }
  if (user_id) { where += ' AND rp.user_id = ?'; params.push(user_id); }
  if (status) { where += ' AND rp.status = ?'; params.push(status); }

  const payouts = db.prepare(`
    SELECT rp.*, u.name as customer_name, u.phone as customer_phone,
           rr.name as rule_name, rr.cashback_percent, rr.target_name, u.wallet_balance
    FROM reward_payouts rp
    JOIN users u ON u.id = rp.user_id
    JOIN reward_rules rr ON rr.id = rp.rule_id
    WHERE ${where}
    ORDER BY rp.created_at DESC LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);

  const currentMonth = month || new Date().toISOString().substring(0, 7);
  const summary = db.prepare(`
    SELECT status, COUNT(*) as count, COALESCE(SUM(cashback_amount),0) as total
    FROM reward_payouts WHERE month = ? GROUP BY status
  `).all(currentMonth);

  const months = db.prepare('SELECT DISTINCT month FROM reward_payouts ORDER BY month DESC LIMIT 12').all();
  res.json({ payouts, summary, months: months.map(m => m.month) });
}

function getProductsForRules(req, res) {
  const products = db.prepare('SELECT id, name, unit, category_id FROM products WHERE is_active=1 ORDER BY name').all();
  const categories = db.prepare('SELECT id, name FROM categories WHERE is_active=1 ORDER BY name').all();
  res.json({ products, categories });
}

module.exports = {
  listRules, createRule, updateRule, deleteRule,
  calculateRewards, approvePayouts, rejectPayouts, listPayouts, getProductsForRules,
};
