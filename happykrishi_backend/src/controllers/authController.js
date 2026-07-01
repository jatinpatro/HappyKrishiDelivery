const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const otpService = require('../services/otpService');
const notificationService = require('../services/notificationService');

function issueToken(user) {
  return jwt.sign(
    { id: user.id, role: user.role, tv: user.token_version ?? 0 },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
  );
}

function getConfig(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? row.value : null;
}

// ── Send OTP ──────────────────────────────────────────────────────────────────
async function sendOtp(req, res) {
  const { phone, email } = req.body;

  // Helper: get rate limit config
  function getRateLimits() {
    const perHour = parseInt(db.prepare("SELECT value FROM app_config WHERE key='otp_rate_limit_per_hour'").get()?.value || '5');
    const perDay  = parseInt(db.prepare("SELECT value FROM app_config WHERE key='otp_rate_limit_per_day'").get()?.value  || '10');
    return { perHour, perDay };
  }

  function checkRateLimit(phoneNum) {
    const { perHour, perDay } = getRateLimits();
    const hourCount = db.prepare("SELECT COUNT(*) as c FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 hour')").get(phoneNum).c;
    const dayCount  = db.prepare("SELECT COUNT(*) as c FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 day')").get(phoneNum).c;

    if (hourCount >= perHour) {
      // Find when the oldest OTP in this hour was created so we can tell when slot opens
      const oldest = db.prepare("SELECT created_at FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 hour') ORDER BY created_at ASC LIMIT 1").get(phoneNum);
      const resetMs = oldest ? Math.max(0, 3600000 - (Date.now() - new Date(oldest.created_at + ' UTC').getTime())) : 60000;
      const resetMins = Math.ceil(resetMs / 60000);
      return {
        error: `Hourly OTP limit reached (${perHour} per hour). Try again in ${resetMins} minute${resetMins !== 1 ? 's' : ''}.`,
        remaining_this_hour: 0,
        remaining_today: Math.max(0, perDay - dayCount),
        reset_in_seconds: Math.ceil(resetMs / 1000),
        limit_type: 'hour',
      };
    }
    if (dayCount >= perDay) {
      return {
        error: `Daily OTP limit reached (${perDay} per day). Try again tomorrow or use password login.`,
        remaining_this_hour: Math.max(0, perHour - hourCount),
        remaining_today: 0,
        reset_in_seconds: null,
        limit_type: 'day',
      };
    }
    return null;
  }

  // Allow OTP request via email — look up the user and send to their email
  if (email && !phone) {
    const normalized = email.trim().toLowerCase();
    const user = db.prepare("SELECT phone, name, email FROM users WHERE email = ?").get(normalized);
    if (!user) return res.status(404).json({ error: 'No account found with this email' });

    const rateLimitErr = checkRateLimit(user.phone);
    if (rateLimitErr) return res.status(429).json(rateLimitErr);

    const recent = db.prepare('SELECT created_at FROM otp_codes WHERE phone = ? ORDER BY id DESC LIMIT 1').get(user.phone);
    if (recent) {
      const secondsAgo = (Date.now() - new Date(recent.created_at + ' UTC').getTime()) / 1000;
      if (secondsAgo < 60) {
        return res.status(429).json({ error: `Please wait ${Math.ceil(60 - secondsAgo)}s before requesting a new OTP` });
      }
    }

    const code = otpService.generateOtp();
    otpService.saveOtp(user.phone, code);
    await otpService.sendEmailOtp(normalized, code, user.name, 'login');
    return res.json({
      message: `OTP sent to ${normalized}`,
      phone: user.phone,
      hint: normalized,
    });
  }

  if (!phone || !/^[0-9]{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Invalid phone number (10 digits required)' });
  }

  const rateLimitErr = checkRateLimit(phone);
  if (rateLimitErr) return res.status(429).json(rateLimitErr);

  const recent = db.prepare(
    'SELECT created_at FROM otp_codes WHERE phone = ? ORDER BY id DESC LIMIT 1'
  ).get(phone);
  if (recent) {
    const secondsAgo = (Date.now() - new Date(recent.created_at + ' UTC').getTime()) / 1000;
    if (secondsAgo < 60) {
      const wait = Math.ceil(60 - secondsAgo);
      return res.status(429).json({ error: `Please wait ${wait} seconds before requesting a new OTP` });
    }
  }

  const code = otpService.generateOtp();
  otpService.saveOtp(phone, code);

  // Route OTP:
  // 1. Verified email → email (free, preferred for login)
  // 2. First phone verify → SMS preferred (proves the number); email only if SMS fails
  // 3. No verified email → SMS (charged, except first phone verify)
  const user = db.prepare('SELECT id, email, email_verified, phone_verified, wallet_balance, password_hash, role FROM users WHERE phone = ?').get(phone);

  const isFirstPhoneVerify = user && !user.phone_verified;
  const isAdmin = user && (user.role === 'admin' || user.role === 'subadmin');

  // Admins always get OTP via email — free, no wallet charge, no email_verified check
  if (isAdmin && user.email) {
    const sent = await otpService.sendEmailOtp(user.email, code, user.name, 'login');
    if (!sent) return res.status(503).json({ error: 'Email delivery failed.', channel_failed: 'email' });
    return res.json({ message: 'OTP sent to your email', channel: 'email', hint: user.email.replace(/(.{2}).*(@.*)/, '$1***$2') });
  }

  // For verified email login (not first phone verify) → email is free and reliable
  if (user?.email && user.email_verified && !isFirstPhoneVerify) {
    const sent = await otpService.sendEmailOtp(user.email, code, user.name, 'login');
    if (!sent) return res.status(503).json({
      error: 'Email delivery failed. Please use password login.',
      can_use_password: !!user.password_hash,
      channel_failed: 'email',
    });
    return res.json({ message: 'OTP sent to your email', channel: 'email', hint: user.email.replace(/(.{2}).*(@.*)/, '$1***$2') });
  }
  const smsCost = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='sms_otp_cost'").get()?.value || '2');
  const balance = user?.wallet_balance ?? 0;
  if (!isFirstPhoneVerify && balance < smsCost) {
    return res.status(402).json({
      error: `Insufficient wallet balance for SMS OTP (₹${smsCost} required). Please top up or verify your email for free OTPs.`,
      wallet_balance: balance,
      sms_cost: smsCost,
      can_use_password: !!(user?.password_hash),
      needs_email_verify: !!(user?.email && !user.email_verified),
    });
  }

  // Deduct wallet (skip for first-time phone verification)
  const walletService = require('../services/walletService');
  if (!isFirstPhoneVerify) {
    try {
      walletService.debit(user.id, smsCost, 'debit', 'otp_sms', null, `SMS OTP charge`);
    } catch (e) {
      return res.status(402).json({ error: 'Could not deduct wallet balance. Please top up.' });
    }
  }

  const smsSent = await otpService.sendSmsOtp(phone, code);
  if (!smsSent) {
    if (!isFirstPhoneVerify) {
      // Refund wallet if SMS failed on a paid request
      const walletService2 = require('../services/walletService');
      walletService2.credit(user.id, smsCost, 'credit', 'otp_sms_refund', null, 'SMS OTP refund — delivery failed');
      return res.status(503).json({
        error: 'SMS service unavailable. ₹' + smsCost + ' refunded. Please use password login or verify your email.',
        can_use_password: !!user.password_hash,
        channel_failed: 'sms',
      });
    }
    // First phone verify — SMS failed, fall back to email
    if (user?.email) {
      const emailSent = await otpService.sendEmailOtp(user.email, code, user.name, 'login');
      if (emailSent) {
        return res.json({ message: 'OTP sent to your email (SMS unavailable)', channel: 'email', hint: user.email.replace(/(.{2}).*(@.*)/, '$1***$2') });
      }
    }
    return res.status(503).json({ error: 'Could not send OTP. Please try again later.' });
  }

  res.json({ message: 'OTP sent to your phone', channel: 'sms', sms_cost: isFirstPhoneVerify ? 0 : smsCost });
}

// ── Verify OTP ────────────────────────────────────────────────────────────────
function verifyOtp(req, res) {
  const { phone, code } = req.body;
  if (!phone || !code) return res.status(400).json({ error: 'phone and code required' });

  const valid = otpService.verifyOtp(phone, code);
  if (!valid) return res.status(400).json({ error: 'Invalid or expired OTP' });

  let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  const isNew = !user;

  if (!user) {
    const result = db.prepare('INSERT INTO users (name, phone, role, tier_id) VALUES (?,?,?,?)')
      .run('User', phone, 'customer', db.prepare("SELECT id FROM customer_tiers WHERE name='Normal' LIMIT 1").get()?.id ?? null);
    user = db.prepare('SELECT * FROM users WHERE id = ?').get(result.lastInsertRowid);
    // Flush WAL immediately so walletService (separate connection) can see the new user
    db.pragma('wal_checkpoint(PASSIVE)');
  }

  // ── Auto-credit referral if this phone was invited ───────────────────────────
  // Runs on NEW signup AND on every subsequent login until credited — self-healing
  // in case the server was down during first signup.
  try {
    const alreadyHasReferral = db.prepare('SELECT id FROM referral_coupons WHERE used_by_user_id = ?').get(user.id);
    if (!alreadyHasReferral) {
      const coupon = db.prepare(`
        SELECT rc.*, u.name as owner_name
        FROM referral_coupons rc
        JOIN users u ON u.id = rc.owner_user_id
        WHERE rc.invited_phone = ? AND rc.used_by_user_id IS NULL AND (rc.is_generic = 0 OR rc.is_generic IS NULL)
        ORDER BY rc.created_at DESC LIMIT 1
      `).get(phone);
      if (coupon) {
        const signupCredit = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='referral_signup_credit'").get()?.value || '0');
        db.prepare(`
          UPDATE referral_coupons
          SET used_by_user_id=?, used_at=datetime('now'), signup_credit_amount=?
          WHERE id=?
        `).run(user.id, signupCredit > 0 ? signupCredit : null, coupon.id);
        if (signupCredit > 0) {
          const walletService = require('../services/walletService');
          const notificationService = require('../services/notificationService');
          walletService.credit(user.id, signupCredit, 'credit', 'referral_signup', coupon.id,
            `Referral sign-up bonus from ${coupon.owner_name}'s invite`);
          notificationService.sendToUser(user.id, 'Welcome Bonus! 🎉',
            `₹${signupCredit} added to your wallet as a welcome gift from ${coupon.owner_name}.`);
          notificationService.sendToUser(coupon.owner_user_id, 'Your Friend Joined! 🎉',
            `A new customer just signed up using your invite code. You'll earn ₹${parseFloat(db.prepare("SELECT value FROM app_config WHERE key='referral_first_order_bonus'").get()?.value || '0')} when they place their first order.`);
          // Refresh user to include updated wallet balance
          user = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id);
        }
      }
    }
  } catch (e) { console.error('[Referral auto-credit]', e); }
  // ────────────────────────────────────────────────────────────────────────────

  db.prepare("UPDATE users SET last_login_at=datetime('now', '+5 hours', '+30 minutes'), phone_verified=1 WHERE id=?").run(user.id);
  const token = issueToken(user);

  // Refresh user to get updated fields
  const updatedUser = db.prepare('SELECT * FROM users WHERE id=?').get(user.id);

  // Notify admins of new customer signup
  if (isNew) {
    notificationService.sendToAdmins('🆕 New Customer Joined',
      `${updatedUser.name || 'A new customer'} (${phone}) just signed up.`,
      { type: 'new_customer' });
  }

  // Check if referral was auto-credited on this signup
  const referralCredited = isNew && (() => {
    const c = db.prepare(`SELECT signup_credit_amount FROM referral_coupons
      WHERE used_by_user_id = ? AND signup_credit_amount IS NOT NULL
      ORDER BY used_at DESC LIMIT 1`).get(user.id);
    return c ? (c.signup_credit_amount) : null;
  })();

  // If user has email but not verified, prompt them to verify
  const needsEmailVerify = !!(updatedUser.email && !updatedUser.email_verified);

  res.json({
    token,
    user: safeUser(updatedUser),
    is_new: isNew,
    needs_password: !updatedUser.password_set,
    role: updatedUser.role,
    referral_credited: referralCredited,
    needs_email_verify: needsEmailVerify,
    email_hint: needsEmailVerify ? updatedUser.email.replace(/(.{2}).*(@.*)/, '$1***$2') : null,
  });
}

// ── Phone + Password Login (customers and salesmen only) ─────────────────────
function phoneLogin(req, res) {
  const { phone, password } = req.body;
  if (!phone || !password) return res.status(400).json({ error: 'phone and password required' });

  const user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  if (!user) return res.status(401).json({ error: 'Phone number not registered' });

  // Admin must use OTP via email — password login blocked for security
  if (user.role === 'admin' || user.role === 'subadmin') {
    return res.status(403).json({
      error: 'Admin accounts must login with OTP. Please use the Admin tab.',
      use_otp: true,
    });
  }
  if (!user) return res.status(401).json({ error: 'Phone number not registered' });

  if (!user.password_set || !user.password_hash) {
    return res.status(401).json({
      error: 'Password not set yet. Please login with OTP first.',
      needs_otp: true,
    });
  }
  if (!user.is_active) return res.status(401).json({ error: 'Account inactive' });
  if (!bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'Incorrect password' });
  }

  db.prepare("UPDATE users SET last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?").run(user.id);
  const token = issueToken(user);
  res.json({ token, user: safeUser(user) });
}

// ── Set Password (first time after OTP) ───────────────────────────────────────
function setPassword(req, res) {
  const { password } = req.body;
  if (!password || password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  if (req.user.password_set) {
    return res.status(400).json({ error: 'Password already set. Use change-password.' });
  }

  const hash = bcrypt.hashSync(password, 10);
  db.prepare(
    "UPDATE users SET password_hash=?, password_set=1, password_changed_at=datetime('now') WHERE id=?"
  ).run(hash, req.user.id);

  notificationService.sendToUser(req.user.id, 'Password Set ✅', 'Your account password has been set.');
  res.json({ message: 'Password set successfully' });
}

// ── Request OTP to change password (free — no charge) ────────────────────────
async function requestChangePasswordOtp(req, res) {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);

  const code = otpService.generateOtp();
  otpService.saveOtp(user.phone, code);

  // Send OTP via email if user has one, otherwise phone (WhatsApp/SMS)
  let sentTo = 'phone';
  if (user.email) {
    const emailService = require('../services/emailService');
    const emailSent = await emailService.sendOtpEmail(user.email, code, user.name);
    if (emailSent) sentTo = 'email';
  }
  if (sentTo === 'phone') {
    await otpService.sendSmsOtp(user.phone, code);
  }

  res.json({
    message: sentTo === 'email'
      ? `OTP sent to your email (${user.email})`
      : 'OTP sent to your phone',
    sent_to: sentTo,
    hint: sentTo === 'email' ? user.email : user.phone.slice(-4),
  });
}

// ── Change Password (OTP + new password — no fee) ─────────────────────────────
function changePassword(req, res) {
  const { otp, new_password } = req.body;
  if (!otp || !new_password) return res.status(400).json({ error: 'otp and new_password required' });
  if (new_password.length < 6) return res.status(400).json({ error: 'Password must be at least 6 characters' });

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!otpService.verifyOtp(user.phone, otp)) {
    return res.status(400).json({ error: 'Invalid or expired OTP' });
  }

  const hash = bcrypt.hashSync(new_password, 10);
  db.prepare(
    "UPDATE users SET password_hash=?, password_set=1, password_changed_at=datetime('now') WHERE id=?"
  ).run(hash, user.id);

  notificationService.sendToUser(user.id, 'Password Changed 🔒', 'Your password was changed successfully.');
  res.json({ message: 'Password changed successfully' });
}

// ── Admin login ────────────────────────────────────────────────────────────────
function adminLogin(req, res) {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const user = db.prepare("SELECT * FROM users WHERE email = ? AND role IN ('admin','subadmin')").get(email);
  if (!user || !bcrypt.compareSync(password, user.password_hash || '')) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  if (!user.is_active) return res.status(401).json({ error: 'Account inactive' });
  const token = issueToken(user);
  res.json({ token, user: safeUser(user) });
}

function register(req, res) {
  const { name, name_odia, email } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  db.prepare('UPDATE users SET name=?, name_odia=?, email=? WHERE id=?').run(
    name, name_odia || null, email || null, req.user.id
  );
  const updated = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  res.json({ user: safeUser(updated) });
}

function getMe(req, res) {
  res.json({ user: safeUser(req.user) });
}

function safeUser(u) {
  const { password_hash, fcm_token, ...safe } = u;
  const tier = u.tier_id
    ? db.prepare('SELECT name, color FROM customer_tiers WHERE id=?').get(u.tier_id)
    : null;
  return { ...safe, tier_name: tier?.name ?? null, tier_color: tier?.color ?? null };
}
function updateProfile(req, res) {
  const { name, email } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required' });

  const trimmedEmail = email ? email.trim().toLowerCase() : null;

  // Validate email format if provided
  if (trimmedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
    return res.status(400).json({ error: 'Invalid email address' });
  }

  // Ensure email is unique (ignore current user)
  if (trimmedEmail) {
    const conflict = db.prepare(
      'SELECT id FROM users WHERE email = ? AND id != ?'
    ).get(trimmedEmail, req.user.id);
    if (conflict) return res.status(409).json({ error: 'This email is already in use by another account' });
  }

  db.prepare('UPDATE users SET name=?, email=? WHERE id=?')
    .run(name.trim(), trimmedEmail, req.user.id);

  const updated = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  res.json({ user: safeUser(updated), message: 'Profile updated successfully' });
}

// ── Email signup (new customer) — collects full profile ───────────────────────
async function emailSignup(req, res) {  const { name, email, phone, password, gender, birthdate } = req.body;
  if (!name || !email || !phone || !password) {
    return res.status(400).json({ error: 'name, email, phone and password are required' });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    return res.status(400).json({ error: 'Invalid email address' });
  }
  if (!/^[0-9]{10}$/.test(phone.trim())) {
    return res.status(400).json({ error: 'Phone must be 10 digits' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }

  const normalizedEmail = email.trim().toLowerCase();

  // Check email uniqueness
  if (db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail)) {
    return res.status(409).json({ error: 'Email already registered. Please log in.' });
  }
  // Check phone uniqueness if provided
  if (phone) {
    const cleanPhone = phone.trim();
    if (db.prepare('SELECT id FROM users WHERE phone = ?').get(cleanPhone)) {
      return res.status(409).json({ error: 'Phone number already registered.' });
    }
  }

  const hash = bcrypt.hashSync(password, 10);
  // Use real phone if given, else a unique placeholder
  const finalPhone = phone ? phone.trim() : `email_${Date.now()}`;

  const result = db.prepare(
    `INSERT INTO users (name, phone, email, password_hash, password_set, role, gender, birthdate, tier_id)
     VALUES (?,?,?,?,1,'customer',?,?,?)`
  ).run(name.trim(), finalPhone, normalizedEmail, hash,
        gender || null, birthdate || null,
        db.prepare("SELECT id FROM customer_tiers WHERE name='Normal' LIMIT 1").get()?.id ?? null);

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(result.lastInsertRowid);

  // Account created — verify screen will send OTP on load
  res.status(201).json({ phone: finalPhone, needs_verification: true });
}

// ── Email / phone login (customers) ──────────────────────────────────────────
function emailLogin(req, res) {
  const { email, phone, password } = req.body;
  if (!password) return res.status(400).json({ error: 'password is required' });
  if (!email && !phone) return res.status(400).json({ error: 'email or phone is required' });

  let user;
  if (email) {
    user = db.prepare("SELECT * FROM users WHERE email = ? AND role = 'customer'")
              .get(email.trim().toLowerCase());
    if (!user) return res.status(401).json({ error: 'No account found with this email' });
  } else {
    user = db.prepare("SELECT * FROM users WHERE phone = ? AND role = 'customer'")
              .get(phone.trim());
    if (!user) return res.status(401).json({ error: 'No account found with this phone number' });
  }

  if (!user.password_hash) return res.status(401).json({ error: 'No password set. Please use OTP to log in.' });
  if (!bcrypt.compareSync(password, user.password_hash)) return res.status(401).json({ error: 'Incorrect password' });
  if (!user.is_active) return res.status(401).json({ error: 'Account inactive' });

  db.prepare("UPDATE users SET last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?").run(user.id);
  const token = issueToken(user);
  res.json({ token, user: safeUser(user) });
}

function saveFcmToken(req, res) {
  const { fcm_token } = req.body;
  if (!fcm_token) return res.status(400).json({ error: 'fcm_token required' });
  db.prepare('UPDATE users SET fcm_token=? WHERE id=?').run(fcm_token, req.user.id);
  res.json({ message: 'FCM token saved' });
}

// ── Email verification (step 1: send OTP to email) ────────────────────────────
async function sendEmailVerification(req, res) {
  const { email } = req.body;

  // Use provided email or fall back to the user's existing email
  const rawEmail = email || req.user.email;
  if (!rawEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail.trim())) {
    return res.status(400).json({ error: 'Valid email address is required' });
  }
  const normalized = rawEmail.trim().toLowerCase();

  // Check not already taken by another account
  const conflict = db.prepare('SELECT id FROM users WHERE email = ? AND id != ?').get(normalized, req.user.id);
  if (conflict) return res.status(409).json({ error: 'This email is already linked to another account' });

  // Rate-limit: 1 per 60s — reuse otp_codes keyed on "email:{address}"
  const key = `email:${normalized}`;
  const recent = db.prepare('SELECT created_at FROM otp_codes WHERE phone = ? ORDER BY id DESC LIMIT 1').get(key);
  if (recent) {
    const secondsAgo = (Date.now() - new Date(recent.created_at + ' UTC').getTime()) / 1000;
    if (secondsAgo < 60) {
      return res.status(429).json({ error: `Please wait ${Math.ceil(60 - secondsAgo)}s before requesting again` });
    }
  }

  const code = otpService.generateOtp();
  otpService.saveOtp(key, code);
  await otpService.sendEmailOtp(normalized, code, req.user.name || 'Customer', 'verify_email');
  res.json({ message: `Verification code sent to ${normalized}` });
}

// ── Email verification (step 2: confirm OTP and save email) ──────────────────
function verifyEmailOtp(req, res) {
  const { code } = req.body;
  const email = req.body.email || req.user.email;
  if (!email || !code) return res.status(400).json({ error: 'email and code are required' });

  const normalized = email.trim().toLowerCase();
  const key = `email:${normalized}`;
  const valid = otpService.verifyOtp(key, code);
  if (!valid) return res.status(400).json({ error: 'Invalid or expired verification code' });

  // Check not taken by another account (race-condition guard)
  const conflict = db.prepare('SELECT id FROM users WHERE email = ? AND id != ?').get(normalized, req.user.id);
  if (conflict) return res.status(409).json({ error: 'This email is already linked to another account' });

  db.prepare('UPDATE users SET email=?, email_verified=1 WHERE id=?').run(normalized, req.user.id);
  const updated = db.prepare('SELECT * FROM users WHERE id=?').get(req.user.id);
  res.json({ message: 'Email verified and saved', user: safeUser(updated) });
}

// ── Change Phone — step 1: send OTP to new number ────────────────────────────
async function requestPhoneChange(req, res) {
  const { phone } = req.body;
  if (!phone || !/^[0-9]{10}$/.test(phone.trim())) {
    return res.status(400).json({ error: 'Valid 10-digit phone number required' });
  }
  const newPhone = phone.trim();

  // Can't use a number already registered to another account
  const conflict = db.prepare('SELECT id FROM users WHERE phone = ? AND id != ?').get(newPhone, req.user.id);
  if (conflict) return res.status(409).json({ error: 'This phone number is already registered to another account' });

  // Rate limit — return rich response with timing info
  const rateLimitErr = (() => {
    const perHour = parseInt(db.prepare("SELECT value FROM app_config WHERE key='otp_rate_limit_per_hour'").get()?.value || '5');
    const perDay  = parseInt(db.prepare("SELECT value FROM app_config WHERE key='otp_rate_limit_per_day'").get()?.value  || '10');
    const hourCount = db.prepare("SELECT COUNT(*) as c FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 hour')").get(newPhone).c;
    const dayCount  = db.prepare("SELECT COUNT(*) as c FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 day')").get(newPhone).c;
    if (hourCount >= perHour) {
      const oldest = db.prepare("SELECT created_at FROM otp_codes WHERE phone=? AND created_at > datetime('now','-1 hour') ORDER BY created_at ASC LIMIT 1").get(newPhone);
      const resetMs = oldest ? Math.max(0, 3600000 - (Date.now() - new Date(oldest.created_at + ' UTC').getTime())) : 60000;
      const resetMins = Math.ceil(resetMs / 60000);
      return {
        error: `Too many OTP requests for this number (${perHour} per hour). Try again in ${resetMins} minute${resetMins !== 1 ? 's' : ''}.`,
        remaining_today: Math.max(0, perDay - dayCount),
        reset_in_seconds: Math.ceil(resetMs / 1000),
        limit_type: 'hour',
      };
    }
    if (dayCount >= perDay) {
      return {
        error: `Daily OTP limit reached for this number (${perDay} per day). Try a different number or try again tomorrow.`,
        remaining_today: 0,
        reset_in_seconds: null,
        limit_type: 'day',
      };
    }
    return null;
  })();
  if (rateLimitErr) return res.status(429).json(rateLimitErr);

  const code = otpService.generateOtp();
  otpService.saveOtp(newPhone, code);

  // Try SMS to new number; if no SMS service, fall back to current user's email
  let sent = await otpService.sendSmsOtp(newPhone, code);
  if (!sent && req.user.email) {
    // Fall back to sending OTP via the user's existing email
    sent = await otpService.sendEmailOtp(req.user.email, code, req.user.name, 'login');
    if (sent) {
      return res.json({ message: `OTP sent to your email (${req.user.email.replace(/(.{2}).*(@.*)/, '$1***$2')})`, phone: newPhone, channel: 'email' });
    }
  }
  if (!sent) return res.status(503).json({ error: 'Could not send OTP. Please try again later.' });

  res.json({ message: `OTP sent to +91 ${newPhone}`, phone: newPhone, channel: 'sms' });
}

// ── Change Phone — step 2: verify OTP and update phone ───────────────────────
function confirmPhoneChange(req, res) {
  const { phone, code } = req.body;
  if (!phone || !code) return res.status(400).json({ error: 'phone and code required' });
  const newPhone = phone.trim();

  // Ensure not taken (race-condition guard)
  const conflict = db.prepare('SELECT id FROM users WHERE phone = ? AND id != ?').get(newPhone, req.user.id);
  if (conflict) return res.status(409).json({ error: 'This phone number is already registered to another account' });

  const valid = otpService.verifyOtp(newPhone, code);
  if (!valid) return res.status(400).json({ error: 'Invalid or expired OTP' });

  db.prepare("UPDATE users SET phone=?, phone_verified=1, last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?")
    .run(newPhone, req.user.id);

  const updated = db.prepare('SELECT * FROM users WHERE id=?').get(req.user.id);
  res.json({ message: 'Phone number updated successfully', user: safeUser(updated) });
}

// ── Change Phone via Firebase — verify new phone with Firebase token ──────────
async function changePhoneFirebaseConfirm(req, res) {
  const { firebase_token, phone } = req.body;
  if (!firebase_token || !phone) {
    return res.status(400).json({ error: 'firebase_token and phone required' });
  }
  const newPhone = phone.trim();

  // Verify Firebase token
  const { getFirebaseAdmin } = require('../config/firebase');
  const admin = getFirebaseAdmin();
  if (!admin) return res.status(503).json({ error: 'Firebase not configured' });

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(firebase_token);
  } catch (e) {
    return res.status(401).json({ error: 'Invalid or expired Firebase token' });
  }

  const expectedPhone = '+91' + newPhone.replace(/^91/, '');
  if (decoded.phone_number !== expectedPhone) {
    return res.status(401).json({ error: 'Phone number mismatch' });
  }

  // Check not taken by another account
  const conflict = db.prepare('SELECT id FROM users WHERE phone = ? AND id != ?').get(newPhone, req.user.id);
  if (conflict) return res.status(409).json({ error: 'This phone number is already registered to another account' });

  db.prepare("UPDATE users SET phone=?, phone_verified=1, last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?")
    .run(newPhone, req.user.id);

  const updated = db.prepare('SELECT * FROM users WHERE id=?').get(req.user.id);
  res.json({ message: 'Phone number updated successfully', user: safeUser(updated) });
}
async function verifyFirebasePhone(req, res) {
  const { firebase_token, phone } = req.body;
  if (!firebase_token || !phone) {
    return res.status(400).json({ error: 'firebase_token and phone are required' });
  }

  // Verify Firebase ID token
  const { getFirebaseAdmin } = require('../config/firebase');
  const admin = getFirebaseAdmin();
  if (!admin) return res.status(503).json({ error: 'Firebase not configured' });

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(firebase_token);
  } catch (e) {
    return res.status(401).json({ error: 'Invalid or expired Firebase token' });
  }

  // Confirm phone matches
  const expectedPhone = '+91' + phone.replace(/^91/, '');
  if (decoded.phone_number !== expectedPhone) {
    return res.status(401).json({ error: 'Phone number mismatch' });
  }

  // Find or handle user
  let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  const isNew = !user;

  if (!user) {
    const result = db.prepare('INSERT INTO users (name, phone, role, phone_verified, tier_id) VALUES (?,?,?,1,?)')
      .run('User', phone, 'customer', db.prepare("SELECT id FROM customer_tiers WHERE name='Normal' LIMIT 1").get()?.id ?? null);
    user = db.prepare('SELECT * FROM users WHERE id = ?').get(result.lastInsertRowid);
    db.pragma('wal_checkpoint(PASSIVE)');
  } else {
    // Mark phone as verified
    db.prepare("UPDATE users SET phone_verified=1, last_login_at=datetime('now', '+5 hours', '+30 minutes') WHERE id=?").run(user.id);
    user = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id);
  }

  // Referral auto-credit (same as verifyOtp)
  try {
    const alreadyHasReferral = db.prepare('SELECT id FROM referral_coupons WHERE used_by_user_id = ?').get(user.id);
    if (!alreadyHasReferral) {
      const coupon = db.prepare(`
        SELECT rc.*, u.name as owner_name FROM referral_coupons rc
        JOIN users u ON u.id = rc.owner_user_id
        WHERE rc.invited_phone = ? AND rc.used_by_user_id IS NULL AND (rc.is_generic = 0 OR rc.is_generic IS NULL)
        ORDER BY rc.created_at DESC LIMIT 1
      `).get(phone);
      if (coupon) {
        const signupCredit = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='referral_signup_credit'").get()?.value || '0');
        db.prepare(`UPDATE referral_coupons SET used_by_user_id=?, used_at=datetime('now'), signup_credit_amount=? WHERE id=?`)
          .run(user.id, signupCredit > 0 ? signupCredit : null, coupon.id);
        if (signupCredit > 0) {
          const walletService = require('../services/walletService');
          walletService.credit(user.id, signupCredit, 'credit', 'referral_signup', coupon.id,
            `Referral sign-up bonus from ${coupon.owner_name}'s invite`);
          notificationService.sendToUser(user.id, 'Welcome Bonus! 🎉',
            `₹${signupCredit} added to your wallet from ${coupon.owner_name}'s invite.`);
        }
      }
    }
  } catch (e) { console.error('[Referral firebase]', e); }

  const token = issueToken(user);
  res.json({
    token,
    user: safeUser(user),
    is_new: isNew,
    needs_password: !user.password_set,
    role: user.role,
  });
}

module.exports = {
  sendOtp, verifyOtp, phoneLogin, setPassword,
  requestChangePasswordOtp, changePassword,
  saveFcmToken,
  register, adminLogin, getMe, updateProfile,
  emailSignup, emailLogin,
  sendEmailVerification, verifyEmailOtp,
  requestPhoneChange, confirmPhoneChange, changePhoneFirebaseConfirm,
  verifyFirebasePhone,
};
