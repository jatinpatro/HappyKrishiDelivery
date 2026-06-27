const router = require('express').Router();
const c = require('../controllers/adminController');
const ac = require('../controllers/analyticsController');
const sc = require('../controllers/salesmanController');
const rc = require('../controllers/rewardsController');
const tc = require('../controllers/tiersController');
const oc = require('../controllers/orderController');
const { authenticate } = require('../middleware/auth');const { requireRole } = require('../middleware/role');
const multer = require('multer');
const path = require('path');
const db = require('../config/database');

const qrStorage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => cb(null, `upi_qr${path.extname(file.originalname).toLowerCase()}`),
});
const qrUpload = multer({
  storage: qrStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) cb(null, true);
    else cb(new Error('Only image files allowed'));
  },
});

router.use(authenticate, requireRole('admin', 'subadmin'));

router.get('/dashboard', c.getDashboard);
router.get('/orders', c.adminListOrders);
router.post('/orders/place-for-customer', oc.placeOrderForCustomer);
router.post('/orders/:id/cancel', oc.cancelOrderByStaff);
router.put('/orders/:id/status', c.updateOrderStatus);
router.post('/orders/:id/assign', c.assignAgent);
router.put('/orders/:id/items', c.updateOrderItemWeights);
router.post('/orders/:id/mark-collected', c.markPickupCollected);
router.post('/orders/:id/waive-delivery', c.waiveDeliveryCharge);
router.get('/products', c.adminListProducts);
router.get('/users', c.listUsers);
router.post('/users', requireRole('admin'), c.createCustomer);
router.put('/users/:id/toggle', requireRole('admin'), c.toggleCustomer);
router.put('/users/:id', requireRole('admin'), c.updateCustomer);
router.post('/users/:id/reset-password', requireRole('admin'), c.resetCustomerPassword);
router.get('/users/:id/wallet-history', c.getCustomerWalletHistory);
router.post('/users/:id/force-logout', requireRole('admin'), c.forceLogout);
router.get('/wallet-audit', c.getAllWalletTransactions);
router.get('/wallet-audit/summary', c.getWalletTransactionsSummary);
router.get('/customers/:id/addresses', (req, res) => {
  const db = require('../config/database');
  const addresses = db.prepare('SELECT * FROM addresses WHERE user_id = ? ORDER BY is_default DESC, id ASC').all(parseInt(req.params.id));
  res.json({ addresses });
});
router.post('/wallet/credit', requireRole('admin'), c.creditWallet);
router.post('/wallet/debit', requireRole('admin'), c.debitWallet);
router.get('/topup-requests', c.listTopupRequests);
router.get('/credit-advances', c.listCreditAdvances);
router.post('/topup-requests/:id/approve', requireRole('admin'), c.approveTopup);
router.post('/topup-requests/:id/reject', requireRole('admin'), c.rejectTopup);
router.post('/topup-requests/credit-advance', requireRole('admin'), c.creditTopupAdmin);
router.post('/topup-requests/:id/mark-paid', requireRole('admin'), c.markCreditTopupPaid);
router.get('/config', c.getConfig);
router.put('/config', requireRole('admin'), c.updateConfig);

// Salesman management
router.get('/salesmen', sc.listSalesmen);
router.post('/salesmen', requireRole('admin'), sc.createSalesman);
router.put('/salesmen/:id', requireRole('admin'), sc.updateSalesman);
router.put('/salesmen/:id/toggle', requireRole('admin'), sc.toggleSalesman);
router.put('/salesmen/:id/reset-password', requireRole('admin'), sc.resetSalesmanPassword);
router.get('/salesman-summary', sc.getSalesmanSummary);
router.post('/salesman-settle', requireRole('admin'), sc.settleSalesman);
router.post('/salesman-settlements/:id/acknowledge', requireRole('admin'), sc.acknowledgeSettlement);
router.post('/salesmen/:id/force-logout', requireRole('admin'), c.forceLogout);
router.post('/salesmen/:id/raise-settlement', requireRole('admin'), c.raiseSettlementForSalesman);

// Upload UPI QR code image
router.post('/upload-qr', requireRole('admin'), qrUpload.single('qr_image'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No image provided' });
  const imageUrl = `/uploads/${req.file.filename}`;
  // Save URL into app_config
  db.prepare("INSERT OR REPLACE INTO app_config (key, value, updated_at) VALUES (?,?,datetime('now'))")
    .run('upi_qr_image_url', imageUrl);
  res.json({ message: 'QR image uploaded', url: imageUrl });
});

// Upload product image — overwrites previous file so no orphans accumulate
const productUpload = multer({
  storage: multer.diskStorage({
    destination: 'uploads/',
    filename: (req, file, cb) => cb(null, `product_${req.params.id}${path.extname(file.originalname).toLowerCase()}`),
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => file.mimetype.startsWith('image/') ? cb(null, true) : cb(new Error('Only image files allowed')),
});
router.post('/products/:id/image', requireRole('admin'), productUpload.single('image'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No image provided' });
  const id = parseInt(req.params.id);
  // Delete old file if it exists and has a different name (e.g. different extension)
  const existing = db.prepare('SELECT image_url FROM products WHERE id=?').get(id);
  if (existing?.image_url) {
    const oldPath = path.join(__dirname, '../../../uploads', path.basename(existing.image_url));
    if (oldPath !== path.join(__dirname, '../../../', req.file.path)) {
      try { require('fs').unlinkSync(oldPath); } catch (_) {}
    }
  }
  const imageUrl = `/uploads/${req.file.filename}`;
  db.prepare('UPDATE products SET image_url=? WHERE id=?').run(imageUrl, id);
  res.json({ message: 'Product image uploaded', url: imageUrl,
    product: db.prepare('SELECT id, name, image_url FROM products WHERE id=?').get(id) });
});

// Upload category image — overwrites previous file so no orphans accumulate
const categoryUpload = multer({
  storage: multer.diskStorage({
    destination: 'uploads/',
    filename: (req, file, cb) => cb(null, `category_${req.params.id}${path.extname(file.originalname).toLowerCase()}`),
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => file.mimetype.startsWith('image/') ? cb(null, true) : cb(new Error('Only image files allowed')),
});
router.post('/categories/:id/image', requireRole('admin'), categoryUpload.single('image'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No image provided' });
  const id = parseInt(req.params.id);
  // Delete old file if it has a different name
  const existing = db.prepare('SELECT image_url FROM categories WHERE id=?').get(id);
  if (existing?.image_url) {
    const oldPath = path.join(__dirname, '../../../uploads', path.basename(existing.image_url));
    if (oldPath !== path.join(__dirname, '../../../', req.file.path)) {
      try { require('fs').unlinkSync(oldPath); } catch (_) {}
    }
  }
  const imageUrl = `/uploads/${req.file.filename}`;
  db.prepare('UPDATE categories SET image_url=? WHERE id=?').run(imageUrl, id);
  res.json({ message: 'Category image uploaded', url: imageUrl,
    category: db.prepare('SELECT id, name, image_url FROM categories WHERE id=?').get(id) });
});

// Analytics & messaging
router.get('/analytics', ac.getAnalytics);
router.get('/analytics/customer/:id', ac.getCustomerBehaviour);
router.get('/customer-activity', ac.getCustomerActivity);
router.get('/sales-report', ac.getSalesReport);
router.post('/broadcast', requireRole('admin'), ac.broadcastMessage);
router.post('/due-reminders', requireRole('admin'), ac.sendDueReminders);

// Rewards
router.get('/rewards/rules', rc.listRules);
router.post('/rewards/rules', requireRole('admin'), rc.createRule);
router.put('/rewards/rules/:id', requireRole('admin'), rc.updateRule);
router.delete('/rewards/rules/:id', requireRole('admin'), rc.deleteRule);
router.post('/rewards/calculate', requireRole('admin'), rc.calculateRewards);
router.post('/rewards/approve', requireRole('admin'), rc.approvePayouts);
router.post('/rewards/reject', requireRole('admin'), rc.rejectPayouts);
router.get('/rewards/payouts', rc.listPayouts);
router.get('/rewards/products-and-categories', rc.getProductsForRules);

// Referrals
router.get('/referrals', c.listReferrals);
router.post('/referrals/generate', requireRole('admin', 'subadmin'), c.adminGenerateReferral);
router.post('/referrals/generic', requireRole('admin', 'subadmin'), c.adminCreateGenericCode);
router.put('/referrals/generic/:id', requireRole('admin', 'subadmin'), c.adminUpdateGenericCode);
router.delete('/referrals/generic/:id', requireRole('admin', 'subadmin'), c.adminDeleteGenericCode);

// Customer tiers
router.get('/tiers', tc.listTiers);
router.post('/tiers', requireRole('admin'), tc.createTier);
router.put('/tiers/:id', requireRole('admin'), tc.updateTier);
router.delete('/tiers/:id', requireRole('admin'), tc.deleteTier);
router.patch('/customers/:id/tier', requireRole('admin'), tc.assignTier);

router.get('/agents/locations', c.getAgentLocations);

module.exports = router;
