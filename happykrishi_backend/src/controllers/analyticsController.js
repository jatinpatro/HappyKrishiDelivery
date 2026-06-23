const db = require('../config/database');
const notificationService = require('../services/notificationService');
const whatsappService = require('../services/whatsappService');

// ── Analytics ─────────────────────────────────────────────────────────────────

function getAnalytics(req, res) {
  const { from, to } = req.query;
  const dateFrom = from || new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  const dateTo = to || new Date().toISOString().split('T')[0];

  // Revenue over time (daily)
  const revenueByDay = db.prepare(`
    SELECT date(created_at) as day,
           COUNT(*) as orders,
           COALESCE(SUM(final_amount),0) as revenue,
           COALESCE(SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END),0) as cancelled
    FROM orders
    WHERE date(created_at) BETWEEN ? AND ?
    GROUP BY date(created_at)
    ORDER BY day
  `).all(dateFrom, dateTo);

  // Top products
  const topProducts = db.prepare(`
    SELECT p.name, p.unit,
           COUNT(DISTINCT oi.order_id) as order_count,
           SUM(oi.estimated_qty) as total_qty,
           SUM(oi.estimated_total) as total_revenue
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    JOIN orders o ON o.id = oi.order_id
    WHERE o.status != 'cancelled' AND date(o.created_at) BETWEEN ? AND ?
    GROUP BY p.id ORDER BY total_revenue DESC LIMIT 10
  `).all(dateFrom, dateTo);

  // Top customers
  const topCustomers = db.prepare(`
    SELECT u.id, u.name, u.phone, u.wallet_balance,
           COUNT(o.id) as order_count,
           COALESCE(SUM(o.final_amount),0) as total_spent,
           MAX(o.created_at) as last_order
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id AND o.status != 'cancelled'
    WHERE u.role = 'customer'
    GROUP BY u.id
    ORDER BY total_spent DESC LIMIT 20
  `).all();

  // Customer activity summary
  const activity = db.prepare(`
    SELECT
      COUNT(DISTINCT u.id) as total_customers,
      COUNT(DISTINCT CASE WHEN o.created_at > datetime('now', '-7 days') THEN u.id END) as active_7d,
      COUNT(DISTINCT CASE WHEN o.created_at > datetime('now', '-30 days') THEN u.id END) as active_30d,
      COUNT(DISTINCT CASE WHEN o.id IS NULL THEN u.id END) as no_orders
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id
    WHERE u.role = 'customer'
  `).get();

  // Due amounts (customers with outstanding wallet balance less than orders)
  const dueCustomers = db.prepare(`
    SELECT u.id, u.name, u.phone, u.wallet_balance,
           COUNT(o.id) as pending_orders,
           COALESCE(SUM(o.final_amount),0) as total_pending
    FROM users u
    JOIN orders o ON o.user_id = u.id
    WHERE u.role = 'customer'
      AND o.payment_status = 'pending'
    GROUP BY u.id
    ORDER BY total_pending DESC
  `).all();

  // Status breakdown
  const statusBreakdown = db.prepare(`
    SELECT status, COUNT(*) as count
    FROM orders
    WHERE date(created_at) BETWEEN ? AND ?
    GROUP BY status
  `).all(dateFrom, dateTo);

  // Financial summary — revenue vs expenses (cashbacks, admin credits, refunds)
  const financialSummary = db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN type='discount' AND reference_type='reward' THEN amount ELSE 0 END),0) as total_cashback_rewards,
      COALESCE(SUM(CASE WHEN type='credit' AND reference_type='admin' THEN amount ELSE 0 END),0) as total_admin_credits,
      COALESCE(SUM(CASE WHEN type='debit' AND reference_type='admin' THEN amount ELSE 0 END),0) as total_admin_deductions,
      COALESCE(SUM(CASE WHEN type='refund' THEN amount ELSE 0 END),0) as total_refunds,
      COALESCE(SUM(CASE WHEN type='credit' AND reference_type='topup' THEN amount ELSE 0 END),0) as total_topups_credited,
      COALESCE(SUM(CASE WHEN type='debit' AND reference_type='system' THEN amount ELSE 0 END),0) as total_service_fees
    FROM wallet_transactions
    WHERE date(created_at) BETWEEN ? AND ?
  `).get(dateFrom, dateTo);

  // Cashback by month (for expenses trend)
  const cashbackByMonth = db.prepare(`
    SELECT strftime('%Y-%m', created_at) as month,
           COALESCE(SUM(cashback_amount),0) as total_cashback,
           COUNT(*) as payout_count
    FROM reward_payouts
    WHERE status='approved' AND date(created_at) BETWEEN ? AND ?
    GROUP BY month ORDER BY month
  `).all(dateFrom, dateTo);

  res.json({
    period: { from: dateFrom, to: dateTo },
    activity,
    revenueByDay,
    topProducts,
    topCustomers,
    dueCustomers,
    statusBreakdown,
    financialSummary,
    cashbackByMonth,
  });
}

// ── Customer Activity List (for messaging) ─────────────────────────────────────

function getCustomerActivity(req, res) {
  const { segment } = req.query;
  // segment: all | active | inactive | due | no_orders | high_value

  let where = "u.role = 'customer'";
  if (segment === 'active') where += " AND o.created_at > datetime('now', '-30 days')";
  if (segment === 'inactive') where += " AND (o.id IS NULL OR o.created_at < datetime('now', '-30 days'))";
  if (segment === 'no_orders') where = "u.role = 'customer' AND o.id IS NULL";

  const customers = db.prepare(`
    SELECT u.id, u.name, u.phone, u.wallet_balance,
           COUNT(DISTINCT o.id) as order_count,
           COALESCE(SUM(o.final_amount),0) as total_spent,
           MAX(o.created_at) as last_order,
           MIN(u.created_at) as joined
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id AND o.status != 'cancelled'
    WHERE ${where}
    GROUP BY u.id
    ORDER BY total_spent DESC
  `).all();

  res.json({ customers, segment: segment || 'all', total: customers.length });
}

// ── Broadcast Message ─────────────────────────────────────────────────────────

function broadcastMessage(req, res) {
  const { user_ids, message, channels } = req.body;
  // channels: ['push', 'whatsapp']
  if (!user_ids?.length || !message) {
    return res.status(400).json({ error: 'user_ids and message required' });
  }

  const sendChannels = channels || ['push'];
  let sent = 0;

  for (const userId of user_ids) {
    const user = db.prepare('SELECT id, name, phone FROM users WHERE id = ?').get(userId);
    if (!user) continue;

    if (sendChannels.includes('push')) {
      notificationService.sendToUser(userId, 'Message from HappyKrishi', message, { type: 'broadcast' });
    }
    if (sendChannels.includes('whatsapp')) {
      // Send free-form text (works in 24h window; use template outside)
      whatsappService.sendTextMessage(user.phone, message);
    }
    sent++;
  }

  res.json({ message: `Sent to ${sent} customers`, sent });
}

// ── Sales Report ──────────────────────────────────────────────────────────────

function getSalesReport(req, res) {
  const { from, to, group_by } = req.query;
  const dateFrom = from || new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  const dateTo = to || new Date().toISOString().split('T')[0];
  const groupBy = group_by || 'day';

  const groupExpr = groupBy === 'month'
    ? "strftime('%Y-%m', created_at)"
    : groupBy === 'week'
    ? "strftime('%Y-W%W', created_at)"
    : "date(created_at)";

  const rows = db.prepare(`
    SELECT
      ${groupExpr} as period,
      COUNT(*) as total_orders,
      COUNT(CASE WHEN status='delivered' THEN 1 END) as delivered,
      COUNT(CASE WHEN status='cancelled' THEN 1 END) as cancelled,
      COALESCE(SUM(CASE WHEN status != 'cancelled' THEN final_amount ELSE 0 END),0) as revenue,
      COALESCE(SUM(CASE WHEN status != 'cancelled' THEN delivery_charge ELSE 0 END),0) as delivery_revenue,
      COUNT(DISTINCT user_id) as unique_customers
    FROM orders
    WHERE date(created_at) BETWEEN ? AND ?
    GROUP BY ${groupExpr}
    ORDER BY period
  `).all(dateFrom, dateTo);

  const totals = db.prepare(`
    SELECT
      COUNT(*) as total_orders,
      COALESCE(SUM(CASE WHEN status != 'cancelled' THEN final_amount ELSE 0 END),0) as total_revenue,
      COUNT(DISTINCT user_id) as unique_customers,
      COALESCE(AVG(CASE WHEN status != 'cancelled' THEN final_amount END),0) as avg_order_value,
      COUNT(CASE WHEN status='delivered' THEN 1 END) as delivered,
      COUNT(CASE WHEN status='cancelled' THEN 1 END) as cancelled
    FROM orders
    WHERE date(created_at) BETWEEN ? AND ?
  `).get(dateFrom, dateTo);

  res.json({ period: { from: dateFrom, to: dateTo, group_by: groupBy }, rows, totals });
}

// ── Due Reminder ──────────────────────────────────────────────────────────────

function sendDueReminders(req, res) {
  const { user_ids, message } = req.body;

  // If no user_ids, find all with low wallet / pending orders
  const targets = user_ids?.length
    ? user_ids.map(id => db.prepare('SELECT id, name, phone, wallet_balance FROM users WHERE id = ?').get(id)).filter(Boolean)
    : db.prepare(`
        SELECT DISTINCT u.id, u.name, u.phone, u.wallet_balance
        FROM users u
        JOIN topup_requests tr ON tr.user_id = u.id
        WHERE tr.status = 'pending'
        UNION
        SELECT u.id, u.name, u.phone, u.wallet_balance
        FROM users u
        WHERE u.wallet_balance < 100 AND u.role = 'customer'
      `).all();

  let sent = 0;
  for (const user of targets) {
    const customMessage = message ||
      `Hi ${user.name}! Your HappyKrishi wallet balance is ₹${user.wallet_balance.toFixed(2)}. Please top up to continue ordering fresh farm produce. 🌿`;

    notificationService.sendToUser(
      user.id,
      'Wallet Reminder 💰',
      customMessage,
      { type: 'due_reminder' }
    );
    whatsappService.sendTextMessage(user.phone, customMessage);
    sent++;
  }

  res.json({ message: `Reminders sent to ${sent} customers`, sent, targets: targets.map(u => ({ id: u.id, name: u.name })) });
}

// ── Single customer behaviour ─────────────────────────────────────────────────

function getCustomerBehaviour(req, res) {
  const userId = parseInt(req.params.id);
  const now = new Date();
  const defaultFrom = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-01`;
  const defaultTo   = new Date().toISOString().split('T')[0];
  const dateFrom = req.query.date_from || defaultFrom;
  const dateTo   = req.query.date_to   || defaultTo;

  const customer = db.prepare(`
    SELECT id, name, phone, email, wallet_balance, created_at
    FROM users WHERE id = ? AND role = 'customer'
  `).get(userId);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  // Orders in date range
  const orders = db.prepare(`
    SELECT o.*, s.label as slot_label, a.address_line, a.city,
           d.status as delivery_status
    FROM orders o
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    WHERE o.user_id = ?
      AND date(o.created_at) >= ? AND date(o.created_at) <= ?
    ORDER BY o.created_at DESC
  `).all(userId, dateFrom, dateTo);

  // Summary stats
  const allOrders = db.prepare(`SELECT status, final_amount FROM orders WHERE user_id = ?`).all(userId);
  const totalOrders     = allOrders.length;
  const totalSpent      = allOrders.filter(o => o.status !== 'cancelled').reduce((s, o) => s + o.final_amount, 0);
  const cancelledCount  = allOrders.filter(o => o.status === 'cancelled').length;
  const deliveredCount  = allOrders.filter(o => o.status === 'delivered').length;

  // Favourite products
  const favourites = db.prepare(`
    SELECT p.name, p.unit, COUNT(*) as times_ordered, SUM(oi.estimated_qty) as total_qty
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    JOIN products p ON p.id = oi.product_id
    WHERE o.user_id = ? AND o.status != 'cancelled'
    GROUP BY oi.product_id
    ORDER BY times_ordered DESC LIMIT 5
  `).all(userId);

  res.json({
    customer,
    date_from: dateFrom,
    date_to: dateTo,
    orders,
    summary: { totalOrders, totalSpent: parseFloat(totalSpent.toFixed(2)), cancelledCount, deliveredCount },
    favourites,
  });
}

module.exports = { getAnalytics, getCustomerActivity, getCustomerBehaviour, broadcastMessage, getSalesReport, sendDueReminders };
