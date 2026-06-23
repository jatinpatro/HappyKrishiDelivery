const router = require('express').Router();
const c = require('../controllers/authController');
const { authenticate } = require('../middleware/auth');
const db = require('../config/database');

// Public routes
router.post('/send-otp', c.sendOtp);
router.post('/verify-otp', c.verifyOtp);
router.post('/phone-login', c.phoneLogin);
router.post('/admin-login', c.adminLogin);
router.post('/email-signup', c.emailSignup);
router.post('/email-login', c.emailLogin);

// Authenticated routes
router.post('/register', authenticate, c.register);
router.get('/me', authenticate, c.getMe);
router.patch('/profile', authenticate, c.updateProfile);
router.post('/set-password', authenticate, c.setPassword);           // first-time set
router.post('/change-password/request-otp', authenticate, c.requestChangePasswordOtp);  // step 1
router.post('/change-password', authenticate, c.changePassword);     // step 2

// Dev-only: see latest OTP (only when MSG91_AUTH_KEY is not set)
router.get('/dev-otp/:phone', (req, res) => {
  if (process.env.MSG91_AUTH_KEY) return res.status(403).json({ error: 'Not available in production' });
  const row = db.prepare(
    'SELECT code, expires_at, is_used FROM otp_codes WHERE phone = ? ORDER BY id DESC LIMIT 1'
  ).get(req.params.phone);
  if (!row) return res.status(404).json({ error: 'No OTP found for this number' });
  res.json({ phone: req.params.phone, otp: row.code, expires_at: row.expires_at, is_used: row.is_used });
});

module.exports = router;
