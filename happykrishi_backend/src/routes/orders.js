const router = require('express').Router();
const c = require('../controllers/orderController');
const { authenticate } = require('../middleware/auth');

router.use(authenticate);
router.post('/', c.placeOrder);
router.get('/', c.listOrders);
router.get('/delivery-charge', c.getDeliveryCharge);
router.get('/:id', c.getOrder);
router.post('/:id/cancel', c.cancelOrder);
router.post('/:id/reorder', c.reorder);

// Customer shares their live location for an active order
router.post('/:id/customer-location', (req, res) => {
  const { lat, lng } = req.body;
  if (!lat || !lng) return res.status(400).json({ error: 'lat and lng required' });

  const db = require('../config/database');
  const order = db.prepare('SELECT id, status FROM orders WHERE id = ? AND user_id = ?')
    .get(req.params.id, req.user.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (['delivered', 'cancelled'].includes(order.status)) {
    return res.status(400).json({ error: 'Order is no longer active' });
  }

  // Save to deliveries table so admin/salesman see it on page load
  const delivery = db.prepare('SELECT id FROM deliveries WHERE order_id = ?').get(order.id);
  if (delivery) {
    db.prepare("UPDATE deliveries SET customer_lat=?, customer_lng=? WHERE id=?")
      .run(parseFloat(lat), parseFloat(lng), delivery.id);
  }

  // Broadcast to the order room (salesman/admin see it on their screen)
  const wsServer = require('../websocket/server');
  wsServer.broadcast(order.id, {
    type: 'customer_location',
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    order_id: order.id,
  });

  res.json({ message: 'Location shared' });
});

// Customer confirms they received the delivery (in-app confirmation)
router.post('/:id/confirm-delivery', (req, res) => {
  const db = require('../config/database');
  const order = db.prepare('SELECT id, user_id, status FROM orders WHERE id = ? AND user_id = ?')
    .get(req.params.id, req.user.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (!['assigned', 'dispatched', 'picked'].includes(order.status)) {
    return res.status(400).json({ error: 'Order is not in a deliverable state' });
  }
  const delivery = db.prepare("SELECT id FROM deliveries WHERE order_id = ? AND status IN ('assigned','picked')").get(order.id);
  if (!delivery) return res.status(404).json({ error: 'No active delivery found' });

  db.prepare("UPDATE deliveries SET customer_confirmed_at=datetime('now') WHERE id=?").run(delivery.id);
  const wsServer = require('../websocket/server');
  wsServer.broadcast(order.id, { type: 'customer_confirmed', order_id: order.id });
  res.json({ message: 'Delivery confirmed' });
});

module.exports = router;
