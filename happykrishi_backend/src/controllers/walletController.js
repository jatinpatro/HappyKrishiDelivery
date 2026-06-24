const db = require('../config/database');
const walletService = require('../services/walletService');
const notificationService = require('../services/notificationService');

function getWallet(req, res) {
  const user = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(req.user.id);
  const recent = db.prepare(
    'SELECT * FROM wallet_transactions WHERE user_id = ? ORDER BY created_at DESC LIMIT 5'
  ).all(req.user.id);
  res.json({ balance: user.wallet_balance, recent_transactions: recent });
}

function getTransactions(req, res) {
  const { page = 1, limit = 50, type, date_from, date_to } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);

  // Build dynamic WHERE clause for type filter
  let where = 'user_id = ?';
  const params = [req.user.id];

  if (type) {
    switch (type) {
      case 'topup':    where += " AND type='credit' AND reference_type='topup'";  break;
      case 'order':    where += " AND type='debit' AND reference_type='order'";   break;
      case 'refund':   where += " AND type='refund'";                             break;
      case 'cashback': where += " AND type='discount' AND reference_type='reward'"; break;
      case 'admin':    where += " AND reference_type='admin'";                    break;
      case 'adjust':   where += " AND type='adjustment'";                         break;
      case 'fee':      where += " AND type='debit' AND reference_type='system'";  break;
    }
  }
  if (date_from) { where += ' AND date(created_at) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(created_at) <= ?'; params.push(date_to); }

  const txns = db.prepare(
    `SELECT * FROM wallet_transactions WHERE ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).all(...params, parseInt(limit), offset);
  const total = db.prepare(`SELECT COUNT(*) as c FROM wallet_transactions WHERE ${where}`).get(...params).c;

  // ── Summary aggregates (always over all transactions, unfiltered) ─────────
  const all = db.prepare('SELECT type, reference_type, amount FROM wallet_transactions WHERE user_id = ?').all(req.user.id);

  let totalSpentOrders = 0, totalRefunds = 0, totalTopups = 0,
      totalCashback = 0, totalAdminCredit = 0, totalAdminDebit = 0,
      totalFees = 0, totalAdjustments = 0;

  for (const t of all) {
    const ref = t.reference_type || '';
    const amt = Math.abs(t.amount);
    if (t.type === 'debit' && ref === 'order')    totalSpentOrders += amt;
    else if (t.type === 'refund')                  totalRefunds     += amt;
    else if (t.type === 'credit' && ref === 'topup') totalTopups   += amt;
    else if (t.type === 'discount' && ref === 'reward') totalCashback += amt;
    else if (t.type === 'credit' && ref === 'admin')  totalAdminCredit += amt;
    else if (t.type === 'debit' && ref === 'admin')   totalAdminDebit  += amt;
    else if (t.type === 'debit' && ref === 'system')  totalFees        += amt;
    else if (t.type === 'adjustment')                 totalAdjustments += Math.abs(t.amount);
  }

  res.json({
    transactions: txns,
    total,
    summary: {
      total_spent_orders:  parseFloat(totalSpentOrders.toFixed(2)),
      total_refunds:       parseFloat(totalRefunds.toFixed(2)),
      total_topups:        parseFloat(totalTopups.toFixed(2)),
      total_cashback:      parseFloat(totalCashback.toFixed(2)),
      total_admin_credit:  parseFloat(totalAdminCredit.toFixed(2)),
      total_admin_debit:   parseFloat(totalAdminDebit.toFixed(2)),
      total_fees:          parseFloat(totalFees.toFixed(2)),
      total_adjustments:   parseFloat(totalAdjustments.toFixed(2)),
    },
  });
}

function requestTopup(req, res) {
  const { amount, payment_method, transaction_ref, collected_by } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ error: 'Valid amount required' });

  const method = payment_method || 'cash';
  if (!['cash', 'upi'].includes(method)) {
    return res.status(400).json({ error: 'payment_method must be cash or upi' });
  }
  if (method === 'upi' && !transaction_ref) {
    return res.status(400).json({ error: 'UPI transaction reference (UTR) is required' });
  }
  if (method === 'cash' && !collected_by) {
    return res.status(400).json({ error: 'Please select the salesman who collected the cash' });
  }

  const result = db.prepare(
    'INSERT INTO topup_requests (user_id, amount, payment_method, transaction_ref, collected_by) VALUES (?,?,?,?,?)'
  ).run(req.user.id, amount, method, transaction_ref || null, collected_by || null);

  const msg = method === 'upi'
    ? `UPI payment request submitted. UTR: ${transaction_ref}. Admin will verify and credit shortly.`
    : `Cash request submitted. ${collected_by} will hand it to admin. Wallet will be credited soon.`;

  const requester = db.prepare('SELECT name FROM users WHERE id=?').get(req.user.id);
  notificationService.sendToAdmins('Top-up Request 💰', `${requester?.name || 'Customer'} requested ₹${amount} top-up via ${method}`, { type: 'topup_request', request_id: String(result.lastInsertRowid) });

  res.status(201).json({ message: msg, request_id: result.lastInsertRowid });
}

function getMyTopupRequests(req, res) {
  const requests = db.prepare(`
    SELECT tr.*, s.name as collector_name
    FROM topup_requests tr
    LEFT JOIN users s ON s.id = CAST(tr.collected_by AS INTEGER)
    WHERE tr.user_id = ?
    ORDER BY tr.created_at DESC
  `).all(req.user.id);
  res.json({ requests });
}

module.exports = { getWallet, getTransactions, requestTopup, getMyTopupRequests };
