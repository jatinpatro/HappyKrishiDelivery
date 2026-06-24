require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const path = require('path');
const cron = require('node-cron');

// Init DB (runs migrations)
require('./src/config/database');
// Init Firebase (lazy)
require('./src/config/firebase');

const app = express();
const server = http.createServer(app);

// Init WebSocket
const wsServer = require('./src/websocket/server');
wsServer.init(server);

// Middleware
app.use(cors({
  origin: (origin, callback) => {
    // Allow: no-origin (mobile/Postman), localhost, and production domains
    if (
      !origin ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin) ||
      /^https?:\/\/88\.222\.212\.244(:\d+)?$/.test(origin) ||
      /^https?:\/\/delivery\.happykrishi\.com$/.test(origin) ||
      /^https?:\/\/accounting\.happykrishi\.com$/.test(origin)
    ) {
      callback(null, true);
    } else {
      callback(new Error('CORS: origin not allowed'));
    }
  },
  credentials: true,
}));
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Routes
app.use('/api/auth', require('./src/routes/auth'));
app.use('/api/products', require('./src/routes/products'));
app.use('/api/categories', (req, res, next) => {
  req.url = '/categories' + req.url;
  require('./src/routes/products')(req, res, next);
});
app.use('/api/orders', require('./src/routes/orders'));
app.use('/api/custom-delivery', require('./src/routes/customDelivery'));
app.use('/api/wallet', require('./src/routes/wallet'));
app.use('/api/delivery', require('./src/routes/delivery'));
app.use('/api/notifications', require('./src/routes/notifications'));
app.use('/api/admin', require('./src/routes/admin'));
app.use('/api/salesman', require('./src/routes/salesman'));

// Public app info — delivery rules, contact details (no auth required)
app.get('/api/app-info', (req, res) => {
  const rows = db.prepare('SELECT key, value FROM app_config').all();
  const config = {};
  rows.forEach(r => { config[r.key] = r.value; });
  res.json({
    delivery: {
      free_above: parseFloat(config.free_delivery_above || '500'),
      base_charge: parseFloat(config.base_delivery_charge || '30'),
      charge_per_km: parseFloat(config.delivery_charge_per_km || '5'),
      min_order: parseFloat(config.min_order_amount || '50'),
      min_wallet: parseFloat(config.min_wallet_balance || '100'),
    },
    contact: {
      phone: config.contact_phone || '',
      whatsapp: config.contact_whatsapp || '',
      email: config.contact_email || '',
      working_hours: config.working_hours || '',
    },
    farm: {
      name: config.farm_name || 'HappyKrishi',
      address: config.farm_address || '',
    },
    pickup: {
      enabled: config.pickup_enabled !== '0',
      name: config.farm_name || 'HappyKrishi Farm',
      address: config.farm_address || '',
      working_hours: config.working_hours || '',
    },
    payment: {
      upi_id: config.upi_id || '',
      upi_name: config.upi_name || 'HappyKrishi Farm',
      upi_qr_image_url: config.upi_qr_image_url || '',
      cash_payment_address: config.cash_payment_address || '',
      salesmen: db.prepare(
        "SELECT name FROM users WHERE role='salesman' AND is_active=1 ORDER BY name"
      ).all().map(s => s.name),
    },
  });
});

// Public delivery slots endpoint — filtered by type
app.get('/api/delivery-slots', (req, res) => {
  const { type } = req.query;
  let slots;
  if (type) {
    slots = db.prepare('SELECT * FROM delivery_slots WHERE is_active=1 AND slot_type=? ORDER BY start_time').all(type);
  } else {
    slots = db.prepare('SELECT * FROM delivery_slots WHERE is_active=1 ORDER BY slot_type, start_time').all();
  }
  res.json({ slots });
});

// Public: list all active tiers (for customer info screen)
app.get('/api/tiers', (req, res) => {
  const tiers = db.prepare(
    'SELECT id, name, color, min_wallet_balance, max_wallet_negative_limit, cashback_multiplier, sort_order FROM customer_tiers WHERE is_active=1 ORDER BY sort_order ASC'
  ).all();
  res.json({ tiers });
});

// Public pincode deliverability check
app.get('/api/delivery/check-pincode', async (req, res) => {
  const { pincode } = req.query;
  if (!pincode) return res.status(400).json({ error: 'pincode required' });
  try {
    const { checkPincode, MAX_RADIUS_KM } = require('./src/services/pincodeService');
    const result = await checkPincode(pincode.trim());
    // Include custom rules if whitelisted
    const cached = db.prepare('SELECT min_order_amount, allowed_product_ids, custom_delivery_charge FROM pincode_cache WHERE pincode = ?').get(pincode.trim());
    res.json({
      ...result,
      max_radius_km: MAX_RADIUS_KM,
      min_order_amount: cached?.min_order_amount ?? null,
      allowed_product_ids: cached?.allowed_product_ids ? JSON.parse(cached.allowed_product_ids) : null,
      custom_delivery_charge: cached?.custom_delivery_charge ?? null,
    });
  } catch (e) {
    console.error('[check-pincode]', e);
    res.status(500).json({ error: 'Could not check pincode', deliverable: null });
  }
});

// Addresses route (inline — simple enough)
const { authenticate } = require('./src/middleware/auth');
const db = require('./src/config/database');

app.get('/api/addresses', authenticate, (req, res) => {
  const addresses = db.prepare('SELECT * FROM addresses WHERE user_id = ? ORDER BY is_default DESC').all(req.user.id);
  res.json({ addresses });
});

app.post('/api/addresses', authenticate, async (req, res) => {
  const { label, address_line, city, pincode, lat, lng, is_default } = req.body;
  if (!address_line || !city) return res.status(400).json({ error: 'address_line and city required' });

  // Validate pincode deliverability if provided
  let resolvedLat = lat || null;
  let resolvedLng = lng || null;
  if (pincode && /^\d{6}$/.test(pincode.trim())) {
    try {
      const { checkPincode } = require('./src/services/pincodeService');
      const check = await checkPincode(pincode.trim());
      if (check.deliverable === false) {
        return res.status(400).json({
          error: `Sorry, we don't deliver to pincode ${pincode} — outside our 20 km delivery radius.`,
          deliverable: false,
          distance_km: check.distance_km,
        });
      }
      // Use geocoded lat/lng if none supplied by client
      if (!resolvedLat && check.lat) resolvedLat = check.lat;
      if (!resolvedLng && check.lng) resolvedLng = check.lng;
    } catch (_) {
      // Geocoder unavailable — allow save without blocking
    }
  }

  if (is_default) {
    db.prepare('UPDATE addresses SET is_default = 0 WHERE user_id = ?').run(req.user.id);
  }
  const result = db.prepare(
    'INSERT INTO addresses (user_id, label, address_line, city, pincode, lat, lng, is_default) VALUES (?,?,?,?,?,?,?,?)'
  ).run(req.user.id, label || 'Home', address_line, city, pincode || null, resolvedLat, resolvedLng, is_default ? 1 : 0);

  res.status(201).json({ address: db.prepare('SELECT * FROM addresses WHERE id = ?').get(result.lastInsertRowid) });
});

app.put('/api/addresses/:id', authenticate, (req, res) => {
  const { label, address_line, city, pincode, lat, lng, is_default } = req.body;
  const existing = db.prepare('SELECT * FROM addresses WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!existing) return res.status(404).json({ error: 'Address not found' });

  if (is_default) db.prepare('UPDATE addresses SET is_default = 0 WHERE user_id = ?').run(req.user.id);
  db.prepare('UPDATE addresses SET label=?, address_line=?, city=?, pincode=?, lat=?, lng=?, is_default=? WHERE id=?').run(
    label ?? existing.label, address_line ?? existing.address_line,
    city ?? existing.city, pincode ?? existing.pincode,
    lat ?? existing.lat, lng ?? existing.lng,
    is_default != null ? (is_default ? 1 : 0) : existing.is_default,
    req.params.id
  );
  res.json({ address: db.prepare('SELECT * FROM addresses WHERE id = ?').get(req.params.id) });
});

app.delete('/api/addresses/:id', authenticate, (req, res) => {
  db.prepare('DELETE FROM addresses WHERE id = ? AND user_id = ?').run(req.params.id, req.user.id);
  res.json({ message: 'Deleted' });
});

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));

// 404
app.use((req, res) => res.status(404).json({ error: 'Route not found' }));

// Error handler — never expose stack traces or internal messages in production
app.use((err, req, res, next) => {
  console.error(`[${new Date().toISOString()}] ${req.method} ${req.path}:`, err);
  const status = err.status || err.statusCode || 500;
  // Only send internal details in dev; production gets a generic message
  const message = process.env.NODE_ENV === 'development'
    ? (err.message || 'Internal server error')
    : 'An unexpected error occurred. Please try again.';
  res.status(status).json({ error: message });
});

const PORT = process.env.PORT || 3000;

// Auto-calculate rewards on the LAST day of every month at 11:00 PM
// Cron: 0 23 28-31 * * — fires on days 28-31, but only when it's the last day
cron.schedule('0 23 28-31 * *', () => {
  const now = new Date();
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  if (tomorrow.getMonth() !== now.getMonth()) {
    // It is the last day of the month
    const rc = require('./src/controllers/rewardsController');
    const targetMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    console.log(`[Rewards Cron] Auto-calculating rewards for ${targetMonth} (last day of month)`);
    const fakeReq = { body: { month: targetMonth } };
    const fakeRes = { json: (d) => console.log(`[Rewards Cron] Done: ${d.customersFound} customers, ₹${d.totalCalculated} pending`) };
    rc.calculateRewards(fakeReq, fakeRes);
  }
});

server.listen(PORT, () => {
  console.log(`HappyKrishi API running on port ${PORT}`);
  console.log(`WebSocket server ready`);
});
