const router = require('express').Router();
const c = require('../controllers/deliveryController');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/role');

router.use(authenticate);
router.get('/my-order', requireRole('agent', 'salesman'), c.getMyOrder);
router.post('/location', requireRole('agent', 'salesman'), c.updateLocation);
router.put('/:id/picked', requireRole('agent', 'salesman'), c.markPicked);
router.put('/:id/delivered', requireRole('agent', 'salesman'), c.markDelivered);

module.exports = router;
