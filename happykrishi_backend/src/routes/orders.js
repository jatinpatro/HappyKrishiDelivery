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

  // Broadcast to the order room (agent sees it on their screen)
  const wsServer = require('../websocket/server');
  wsServer.broadcast(order.id, {
    type: 'customer_location',
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    order_id: order.id,
  });

  res.json({ message: 'Location shared' });
});

module.exports = router;
