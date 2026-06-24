const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const otpService = require('../services/otpService');
const notificationService = require('../services/notificationService');

function issueToken(user) {
  return jwt.sign({ id: user.id, role: user.role }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '30d',
  });
}

function getConfig(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? row.value : null;
}

// ── Send OTP ──────────────────────────────────────────────────────────────────
async function sendOtp(req, res) {
  const { phone, email } = req.body;

  // Allow OTP request via email — look up the user and send to their email
  if (email && !phone) {
    const normalized = email.trim().toLowerCase();
    const user = db.prepare("SELECT phone, name, email FROM users WHERE email = ?").get(normalized);
    if (!user) return res.status(404).json({ error: 'No account found with this email' });

    const recent = db.prepare('SELECT created_at FROM otp_codes WHERE phone = ? ORDER BY id DESC LIMIT 1').get(user.phone);
    if (recent) {
      const secondsAgo = (Date.now() - new Date(recent.created_at + ' UTC').getTime()) / 1000;
      if (secondsAgo < 60) {
        return res.status(429).json({ error: `Please wait ${Math.ceil(60 - secondsAgo)}s before requesting a new OTP` });
      }
    }

    const code = otpService.generateOtp();
    otpService.saveOtp(user.phone, code);
    await otpService.sendEmailOtp(normalized, code, user.name);
    return res.json({
      message: `OTP sent to ${normalized}`,
      phone: user.phone,       // Flutter needs this for /auth/verify
      hint: normalized,
    });
  }

  if (!phone || !/^[0-9]{10}$/.test(phone)) {
    return res.status(400).json({ error: 'Invalid phone number (10 digits required)' });
  }

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
  await otpService.sendSmsOtp(phone, code);   // sends to email too if user.email is set
  res.json({ message: 'OTP sent' });
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
  }

  const token = issueToken(user);
  res.json({
    token,
    user: safeUser(user),
    is_new: isNew,
    needs_password: !user.password_set,
    // Let Flutter route correctly without checking role separately
    role: user.role,
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
function emailSignup(req, res) {
  const { name, email, phone, password, gender, birthdate } = req.body;
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
  const token = issueToken(user);
  res.status(201).json({ token, user: safeUser(user), is_new: true });
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

  const token = issueToken(user);
  res.json({ token, user: safeUser(user) });
}

function saveFcmToken(req, res) {
  const { fcm_token } = req.body;
  if (!fcm_token) return res.status(400).json({ error: 'fcm_token required' });
  db.prepare('UPDATE users SET fcm_token=? WHERE id=?').run(fcm_token, req.user.id);
  res.json({ message: 'FCM token saved' });
}

module.exports = {
  sendOtp, verifyOtp, phoneLogin, setPassword,
  requestChangePasswordOtp, changePassword,
  saveFcmToken,
  register, adminLogin, getMe, updateProfile,
  emailSignup, emailLogin,
};
