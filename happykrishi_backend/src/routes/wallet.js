const router = require('express').Router();
const c = require('../controllers/walletController');
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');

router.use(authenticate);
router.get('/', c.getWallet);
router.get('/transactions', c.getTransactions);
router.post('/topup-request', c.requestTopup);
router.get('/topup-requests', c.getMyTopupRequests);

// Customer: see credit advances received
router.get('/credit-advances', (req, res) => {
  const { date_from, date_to } = req.query;
  const now = new Date();
  const defaultFrom = `${now.getFullYear()}-01-01`;
  const defaultTo   = `${now.getFullYear()}-12-31`;
  const from = date_from || defaultFrom;
  const to   = date_to   || defaultTo;

  const advances = db.prepare(`
    SELECT tr.id, tr.amount, tr.payment_received, tr.payment_received_at,
           tr.admin_note, tr.created_at, tr.credited_by_role, tr.credited_by_id,
           cb.name as credited_by_name
    FROM topup_requests tr
    LEFT JOIN users cb ON cb.id = CAST(tr.credited_by_id AS INTEGER)
    WHERE tr.user_id = ? AND tr.payment_method = 'credit_advance'
      AND date(tr.created_at) >= ? AND date(tr.created_at) <= ?
    ORDER BY tr.created_at DESC
    LIMIT 100
  `).all(req.user.id, from, to);

  res.json({ advances, date_from: from, date_to: to });
});

module.exports = router;
