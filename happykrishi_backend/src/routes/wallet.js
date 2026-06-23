const router = require('express').Router();
const c = require('../controllers/walletController');
const { authenticate } = require('../middleware/auth');

router.use(authenticate);
router.get('/', c.getWallet);
router.get('/transactions', c.getTransactions);
router.post('/topup-request', c.requestTopup);
router.get('/topup-requests', c.getMyTopupRequests);

module.exports = router;
