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

// Check OTP channel without sending — returns { channel, cost, needs_email_verify, wallet_balance }
router.get('/otp-channel', (req, res) => {
  const { phone } = req.query;
  if (!phone) return res.status(400).json({ error: 'phone required' });
  const user = db.prepare('SELECT id, email, email_verified, phone_verified, wallet_balance, role FROM users WHERE phone = ?').get(phone);
  if (!user) return res.json({ channel: 'sms', cost: 0, is_new: true });
  const isAdmin = user.role === 'admin' || user.role === 'subadmin';
  const isSalesman = user.role === 'salesman';
  const isFirstPhoneVerify = !user.phone_verified;
  if (isAdmin || isSalesman || (user.email && user.email_verified) || isFirstPhoneVerify) {
    return res.json({ channel: 'email', cost: 0, needs_email_verify: !!(user.email && !user.email_verified) });
  }
  const smsCost = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='sms_otp_cost'").get()?.value || '2');
  res.json({
    channel: 'sms',
    cost: smsCost,
    wallet_balance: user.wallet_balance,
    needs_email_verify: !!(user.email && !user.email_verified),
    can_use_password: true,
  });
});
router.post('/verify-otp', c.verifyOtp);
router.post('/phone-login', c.phoneLogin);
router.post('/admin-login', c.adminLogin);
router.post('/email-signup', c.emailSignup);
router.post('/email-login', c.emailLogin);

// Authenticated routes
router.post('/register', authenticate, c.register);
router.get('/me', authenticate, c.getMe);
router.patch('/profile', authenticate, c.updateProfile);
router.post('/set-password', authenticate, c.setPassword);
router.post('/change-password/request-otp', authenticate, c.requestChangePasswordOtp);
router.post('/change-password', authenticate, c.changePassword);
router.post('/fcm-token', authenticate, c.saveFcmToken);
router.post('/send-email-verification', authenticate, c.sendEmailVerification);
router.post('/verify-email', authenticate, c.verifyEmailOtp);
router.post('/change-phone/request-otp', authenticate, c.requestPhoneChange);
router.post('/change-phone/confirm', authenticate, c.confirmPhoneChange);
router.post('/change-phone/firebase-confirm', authenticate, c.changePhoneFirebaseConfirm);
router.post('/verify-firebase-phone', c.verifyFirebasePhone);

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
