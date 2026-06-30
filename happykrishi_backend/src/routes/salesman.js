const router = require('express').Router();
const c = require('../controllers/salesmanController');
const ops = require('../controllers/salesmanOpsController');
const deliveryCtrl = require('../controllers/deliveryController');
const oc = require('../controllers/orderController');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/role');

// Public: salesman login
router.post('/login', c.salesmanLogin);

// Public: list active salesmen (for customer pickup salesman selection)
router.get('/list', c.listActiveSalesmen);

// All routes below require salesman auth
router.use(authenticate, requireRole('salesman'));

// Dashboard
router.get('/dashboard', c.salesmanDashboard);
router.get('/history', c.salesmanHistory);

// Pending orders — salesman can see and approve
router.get('/pending-orders', c.getSalesmanPendingOrders);
router.post('/pending-orders/:id/confirm', c.confirmAndAssignOrder);

// Customer management
router.get('/customers', ops.listMyCustomers);
router.post('/customers', ops.addCustomer);
router.put('/customers/:id/reset-password', ops.resetCustomerPasswordBySalesman);
router.get('/customers/:id/addresses', (req, res) => {
  const db = require('../config/database');
  const addresses = db.prepare('SELECT * FROM addresses WHERE user_id = ? ORDER BY is_default DESC, id ASC').all(parseInt(req.params.id));
  res.json({ addresses });
});

// Place order on behalf of a customer
router.post('/orders/place-for-customer', oc.placeOrderForCustomer);

// Cancel order (any status, reason required)
router.post('/orders/:id/cancel', oc.cancelOrderByStaff);

// Cash collection management
router.get('/pending-collections', ops.myPendingCollections);
router.post('/collections/:id/approve', ops.approveMyCollection);
router.get('/approved-collections', ops.myApprovedCollections);
router.post('/settlements/raise', ops.raiseSettlementRequest);

// Credit advance (give wallet credit before payment)
router.post('/credit-advance', ops.creditTopupSalesman);
router.post('/credit-advances/:id/mark-paid', ops.markCreditTopupPaidSalesman);
// List my credit advances with optional date range filter
router.get('/credit-advances', (req, res) => {
  const db = require('../config/database');
  const { date_from, date_to } = req.query;
  const now = new Date();
  const defaultFrom = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-01`;
  const defaultTo   = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(new Date(now.getFullYear(), now.getMonth()+1, 0).getDate()).padStart(2,'0')}`;
  const from = date_from || defaultFrom;
  const to   = date_to   || defaultTo;

  const advances = db.prepare(`
    SELECT tr.*, u.name as user_name, u.phone as user_phone
    FROM topup_requests tr
    JOIN users u ON u.id = tr.user_id
    WHERE tr.payment_method = 'credit_advance'
      AND tr.credited_by_role = 'salesman'
      AND CAST(tr.credited_by_id AS INTEGER) = ?
      AND date(tr.created_at) >= ? AND date(tr.created_at) <= ?
    ORDER BY tr.created_at DESC
    LIMIT 200
  `).all(req.user.id, from, to);

  const totalGiven       = advances.reduce((s, a) => s + a.amount, 0);
  const totalOutstanding = advances.filter(a => !a.payment_received).reduce((s, a) => s + a.amount, 0);
  const totalReceived    = advances.filter(a => a.payment_received).reduce((s, a) => s + a.amount, 0);

  res.json({ advances, date_from: from, date_to: to, totalGiven, totalOutstanding, totalReceived });
});

// Delivery management (salesman as delivery agent)
router.put('/delivery/:id/pick', deliveryCtrl.markPicked);
router.put('/delivery/:id/deliver', deliveryCtrl.markDelivered);
router.put('/delivery/location', deliveryCtrl.updateLocation);

// Weight update for delivery items
router.put('/orders/:id/items', require('../controllers/adminController').updateOrderItemWeights);
// Waive delivery charge
router.post('/orders/:id/waive-delivery', require('../controllers/adminController').waiveDeliveryCharge);

// Stock management (salesman can update stock_qty and toggle is_active)
router.get('/products', (req, res) => {
  const db = require('../config/database');
  const products = db.prepare(`
    SELECT p.id, p.name, p.unit, p.price_per_unit, p.stock_qty, p.low_stock_threshold,
           p.is_active, p.is_weight_adjusted, p.image_url, c.name as category_name
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    ORDER BY p.name
  `).all();
  res.json({ products });
});

router.patch('/products/:id/stock', (req, res) => {
  const db = require('../config/database');
  const id = parseInt(req.params.id);
  const { stock_qty, is_active } = req.body;

  const existing = db.prepare('SELECT id FROM products WHERE id = ?').get(id);
  if (!existing) return res.status(404).json({ error: 'Product not found' });

  if (stock_qty != null) {
    db.prepare('UPDATE products SET stock_qty = ? WHERE id = ?').run(parseFloat(stock_qty), id);
  }
  if (is_active != null) {
    db.prepare('UPDATE products SET is_active = ? WHERE id = ?').run(is_active ? 1 : 0, id);
  }

  const product = db.prepare('SELECT id, name, unit, stock_qty, is_active FROM products WHERE id = ?').get(id);
  res.json({ product });
});

module.exports = router;
