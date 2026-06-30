// Load better-sqlite3 — prefer global install so npm install never affects it.
// Global paths: Mac → /opt/homebrew/lib/node_modules
//               Server → /root/.npm-global/lib/node_modules (Node 22 global)
// Falls back to project node_modules if global not found.
// Never falls back to node:sqlite — it has a WAL corruption bug in Node 24.
const GLOBAL_PATHS = [
  '/opt/homebrew/lib/node_modules/better-sqlite3',      // Mac (Homebrew)
  '/root/.npm-global/lib/node_modules/better-sqlite3',  // Server (Node 22 global)
  '/usr/local/lib/node_modules/better-sqlite3',         // Linux fallback
  '/usr/lib/node_modules/better-sqlite3',               // Linux fallback
];

let Database;
for (const p of GLOBAL_PATHS) {
  try { Database = require(p); break; } catch (_) {}
}
if (!Database) {
  try {
    Database = require('better-sqlite3');  // project node_modules
  } catch (_) {
    throw new Error(
      'better-sqlite3 not found. Run: npm install -g better-sqlite3\n' +
      'DO NOT use node:sqlite — it corrupts WAL databases on Node 24.'
    );
  }
}

const path = require('path');
const fs = require('fs');

const dbPath = process.env.DB_PATH || './data/happykrishi.db';
const dbDir = path.dirname(dbPath);

if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

const db = new Database(dbPath);

// Enable WAL mode and foreign keys
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');
// Checkpoint any pending WAL data from previous sessions so all data is visible
try { db.pragma('wal_checkpoint(TRUNCATE)'); } catch (_) {}

// better-sqlite3 natively provides:
//   db.prepare(sql).run(...params)  → { lastInsertRowid, changes }
//   db.prepare(sql).get(...params)  → first row or undefined
//   db.prepare(sql).all(...params)  → array of rows
//   db.transaction(fn)()            → atomic transaction


function runMigrations() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      name_odia TEXT,
      phone TEXT UNIQUE NOT NULL,
      email TEXT,
      password_hash TEXT,
      password_set INTEGER NOT NULL DEFAULT 0,
      password_changed_at TEXT,
      role TEXT NOT NULL DEFAULT 'customer' CHECK(role IN ('customer','admin','agent','subadmin','salesman')),
      fcm_token TEXT,
      wallet_balance REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      birthdate TEXT,
      gender TEXT
    );

    CREATE TABLE IF NOT EXISTS otp_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL,
      code TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      is_used INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS addresses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      label TEXT NOT NULL DEFAULT 'Home',
      address_line TEXT NOT NULL,
      city TEXT NOT NULL,
      pincode TEXT,
      lat REAL,
      lng REAL,
      is_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      name_odia TEXT,
      icon TEXT,
      image_url TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id INTEGER REFERENCES categories(id),
      name TEXT NOT NULL,
      name_odia TEXT,
      description TEXT,
      unit TEXT NOT NULL DEFAULT 'kg',
      price_per_unit REAL NOT NULL,
      stock_qty REAL NOT NULL DEFAULT 0,
      low_stock_threshold REAL NOT NULL DEFAULT 5,
      min_qty REAL NOT NULL DEFAULT 0.5,
      qty_step REAL NOT NULL DEFAULT 0.5,
      is_weight_adjusted INTEGER NOT NULL DEFAULT 0,
      image_url TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS delivery_slots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL,
      label_odia TEXT,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      slot_type TEXT NOT NULL DEFAULT 'delivery',
      is_active INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_number TEXT UNIQUE NOT NULL,
      user_id INTEGER NOT NULL REFERENCES users(id),
      address_id INTEGER REFERENCES addresses(id),
      slot_id INTEGER REFERENCES delivery_slots(id),
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','confirmed','assigned','dispatched','delivered','cancelled')),
      delivery_date TEXT NOT NULL,
      subtotal REAL NOT NULL DEFAULT 0,
      delivery_charge REAL NOT NULL DEFAULT 0,
      discount_amount REAL NOT NULL DEFAULT 0,
      wallet_used REAL NOT NULL DEFAULT 0,
      final_amount REAL NOT NULL DEFAULT 0,
      payment_status TEXT NOT NULL DEFAULT 'pending'
        CHECK(payment_status IN ('pending','paid','adjusted','refunded')),
      notes TEXT,
      cancelled_reason TEXT,
      order_type TEXT NOT NULL DEFAULT 'delivery' CHECK(order_type IN ('delivery','pickup')),
      salesman_id INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id),
      estimated_qty REAL NOT NULL,
      actual_qty REAL,
      unit_price REAL NOT NULL,
      estimated_total REAL NOT NULL,
      actual_total REAL,
      is_weight_adjusted INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS delivery_agents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER UNIQUE NOT NULL REFERENCES users(id),
      is_available INTEGER NOT NULL DEFAULT 1,
      current_lat REAL,
      current_lng REAL,
      last_seen_at TEXT
    );

    CREATE TABLE IF NOT EXISTS deliveries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER UNIQUE NOT NULL REFERENCES orders(id),
      agent_id INTEGER REFERENCES delivery_agents(id),
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','assigned','picked','delivered','cancelled')),
      assigned_at TEXT,
      picked_at TEXT,
      delivered_at TEXT,
      actual_weight_recorded_at TEXT,
      updated_at TEXT
    );

    CREATE TABLE IF NOT EXISTS wallet_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      type TEXT NOT NULL CHECK(type IN ('credit','debit','discount','adjustment','refund')),
      amount REAL NOT NULL,
      balance_after REAL NOT NULL,
      reference_type TEXT,
      reference_id INTEGER,
      description TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      type TEXT,
      data_json TEXT,
      is_read INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS topup_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      amount REAL NOT NULL,
      payment_method TEXT NOT NULL DEFAULT 'cash',
      transaction_ref TEXT,
      collected_by TEXT,
      settled_at TEXT,
      settlement_id INTEGER,
      status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
      admin_note TEXT,
      resolved_at TEXT,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS salesman_settlements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      salesman_name TEXT NOT NULL,
      amount REAL NOT NULL,
      topup_request_ids TEXT NOT NULL,
      note TEXT,
      settled_by INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS reward_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('product_cashback','category_cashback')),
      target_id INTEGER,
      target_name TEXT NOT NULL,
      cashback_percent REAL NOT NULL,
      min_qty REAL NOT NULL DEFAULT 0,
      min_spend REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS reward_payouts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      rule_id INTEGER NOT NULL REFERENCES reward_rules(id),
      order_id INTEGER REFERENCES orders(id),
      month TEXT NOT NULL,
      spend_amount REAL NOT NULL,
      qty_purchased REAL NOT NULL,
      cashback_amount REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
      wallet_txn_id INTEGER REFERENCES wallet_transactions(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS app_config (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS referral_coupons (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT UNIQUE NOT NULL,
      owner_user_id INTEGER NOT NULL REFERENCES users(id),
      used_by_user_id INTEGER REFERENCES users(id),
      used_at TEXT,
      signup_credit_amount REAL,
      bonus_credit_amount REAL,
      bonus_credited_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS customer_tiers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      color TEXT NOT NULL DEFAULT '#607D8B',
      min_wallet_balance REAL NOT NULL DEFAULT 0,
      max_wallet_negative_limit REAL NOT NULL DEFAULT 0,
      cashback_multiplier REAL NOT NULL DEFAULT 1.0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS pincode_delivery_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pincode TEXT NOT NULL,
      min_subtotal REAL NOT NULL DEFAULT 0,
      max_subtotal REAL,
      delivery_charge REAL,
      blocked INTEGER NOT NULL DEFAULT 0,
      blocked_message TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS pincode_cache (
      pincode TEXT PRIMARY KEY,
      lat REAL, lng REAL,
      district TEXT, state TEXT,
      deliverable INTEGER NOT NULL DEFAULT 0,
      distance_km REAL,
      checked_at TEXT NOT NULL DEFAULT (datetime('now')),
      min_order_amount REAL,
      allowed_product_ids TEXT,
      custom_delivery_charge REAL
    );

    CREATE TABLE IF NOT EXISTS custom_delivery_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      pincode TEXT NOT NULL,
      address TEXT NOT NULL,
      note TEXT,
      distance_km REAL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
      admin_note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // Negative wallet balance is allowed — drop the old blocking trigger if it exists
  db.exec(`DROP TRIGGER IF EXISTS prevent_negative_wallet;`);

  // Seed default delivery slots (only if empty)
  const slotCount = db.prepare('SELECT COUNT(*) as c FROM delivery_slots').get();
  if (slotCount.c === 0) {
    const ins = db.prepare('INSERT INTO delivery_slots (label, label_odia, start_time, end_time, slot_type) VALUES (?,?,?,?,?)');
    ins.run('Morning (7–10 AM)', 'ସକାଳ (7–10)', '07:00', '10:00', 'delivery');
    ins.run('Afternoon (12–3 PM)', 'ଅପରାହ୍ନ (12–3)', '12:00', '15:00', 'delivery');
    ins.run('Evening (5–8 PM)', 'ସନ୍ଧ୍ୟା (5–8)', '17:00', '20:00', 'delivery');
    ins.run('Pickup Morning (8 AM – 12 PM)', 'ସ୍ୱ-ସଂଗ୍ରହ ସକାଳ', '08:00', '12:00', 'pickup');
    ins.run('Pickup Afternoon (2 PM – 6 PM)', 'ସ୍ୱ-ସଂଗ୍ରହ ଅପରାହ୍ନ', '14:00', '18:00', 'pickup');
  }

  // Seed default app config
  const configCount = db.prepare('SELECT COUNT(*) as c FROM app_config').get();
  if (configCount.c === 0) {
    const ic = db.prepare('INSERT OR IGNORE INTO app_config (key, value) VALUES (?,?)');
    ic.run('min_wallet_balance', '100');
    ic.run('min_order_amount', '50');
    ic.run('min_pickup_order_amount', '10');
    ic.run('free_delivery_above', '500');
    ic.run('base_delivery_charge', '30');
    ic.run('delivery_charge_per_km', '5');
    ic.run('geofence_radius_m', '500');
    ic.run('password_change_fee', '29');
    ic.run('password_change_interval_days', '30');
    ic.run('max_wallet_negative_limit', '0');
    ic.run('upi_id', 'happykrishi@upi');
    ic.run('upi_name', 'HappyKrishi Farm');
    ic.run('upi_qr_image_url', '');
    ic.run('cash_payment_address', 'Visit our farm or pay to our agent');
    ic.run('salesmen_list', 'Tarini,Abhi,Jatin,Sunil');
    ic.run('default_salesman_id', ''); // user ID of default salesman — empty = none
    ic.run('referral_enabled', '1');
    ic.run('referral_signup_credit', '50');
    ic.run('referral_first_order_bonus', '100');
    ic.run('require_delivery_code', '1');
  }

  // Seed default customer tiers (only if empty)
  const tierCount = db.prepare('SELECT COUNT(*) as c FROM customer_tiers').get();
  if (tierCount.c === 0) {
    const it = db.prepare(
      'INSERT INTO customer_tiers (name, color, min_wallet_balance, max_wallet_negative_limit, cashback_multiplier, sort_order) VALUES (?,?,?,?,?,?)'
    );
    it.run('Restricted', '#DC2626', 0,    0,    1.0, -1);
    it.run('Normal',     '#78909C', 0,    100,  1.0,  0);
    it.run('Silver',     '#546E7A', 200,  200,  1.2,  1);
    it.run('Gold',       '#F9A825', 500,  500,  1.5,  2);
    it.run('Platinum',   '#6A1B9A', 1000, 1000, 2.0,  3);
  }

  // Seed admin user (only once)
  const adminPhone = process.env.ADMIN_SEED_PHONE;
  const adminEmail = process.env.ADMIN_SEED_EMAIL;
  const adminPassword = process.env.ADMIN_SEED_PASSWORD;
  if (adminPhone && adminEmail && adminPassword) {
    const existing = db.prepare('SELECT id FROM users WHERE phone = ?').get(adminPhone);
    if (!existing) {
      const bcrypt = require('bcryptjs');
      const hash = bcrypt.hashSync(adminPassword, 10);
      db.prepare(
        'INSERT INTO users (name, phone, email, password_hash, role) VALUES (?,?,?,?,?)'
      ).run('Admin', adminPhone, adminEmail, hash, 'admin');
      console.log('✅ Admin user seeded:', adminEmail);
    }
  }
}

runMigrations();

// ── Incremental migrations — kept for existing DBs that predate the CREATE TABLE updates ──
// These are safe no-ops on fresh installs (ADD COLUMN throws if column exists, caught silently).
try { db.exec('ALTER TABLE topup_requests ADD COLUMN settlement_id INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN settled_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN updated_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN collected_by TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN resolved_at TEXT'); } catch (_) {}
try { db.exec("ALTER TABLE topup_requests ADD COLUMN payment_received INTEGER NOT NULL DEFAULT 1"); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN payment_received_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN credited_by_role TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN credited_by_id INTEGER'); } catch (_) {}
try { db.exec("ALTER TABLE topup_requests ADD COLUMN paid_by_role TEXT"); } catch (_) {}
try { db.exec("ALTER TABLE salesman_settlements ADD COLUMN settlement_type TEXT NOT NULL DEFAULT 'cash'"); } catch (_) {}
try { db.exec('ALTER TABLE products ADD COLUMN min_qty REAL NOT NULL DEFAULT 0.5'); } catch (_) {}
try { db.exec('ALTER TABLE products ADD COLUMN qty_step REAL NOT NULL DEFAULT 0.5'); } catch (_) {}
try { db.exec('ALTER TABLE products ADD COLUMN description TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE orders ADD COLUMN salesman_id INTEGER REFERENCES users(id)'); } catch (_) {}
try { db.exec('ALTER TABLE orders ADD COLUMN cancelled_reason TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE orders ADD COLUMN discount_amount REAL NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE orders ADD COLUMN wallet_used REAL NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN birthdate TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN gender TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE categories ADD COLUMN image_url TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE reward_payouts ADD COLUMN wallet_txn_id INTEGER REFERENCES wallet_transactions(id)'); } catch (_) {}
try { db.exec('ALTER TABLE reward_payouts ADD COLUMN order_id INTEGER REFERENCES orders(id)'); } catch (_) {}
try { db.exec('ALTER TABLE pincode_cache ADD COLUMN min_order_amount REAL'); } catch (_) {}
try { db.exec('ALTER TABLE pincode_cache ADD COLUMN allowed_product_ids TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE pincode_cache ADD COLUMN custom_delivery_charge REAL'); } catch (_) {}
try { db.exec('ALTER TABLE deliveries ADD COLUMN updated_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN tier_id INTEGER REFERENCES customer_tiers(id)'); } catch (_) {}
try { db.exec("ALTER TABLE customer_tiers ADD COLUMN color TEXT NOT NULL DEFAULT '#607D8B'"); } catch (_) {}
try { db.exec("ALTER TABLE customer_tiers ADD COLUMN min_wallet_balance REAL NOT NULL DEFAULT 0"); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN referral_code TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN approved_by_id INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE topup_requests ADD COLUMN approved_by_role TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE deliveries ADD COLUMN delivery_code TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE deliveries ADD COLUMN customer_confirmed_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE deliveries ADD COLUMN customer_lat REAL'); } catch (_) {}
try { db.exec('ALTER TABLE deliveries ADD COLUMN customer_lng REAL'); } catch (_) {}
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN invited_phone TEXT'); } catch (_) {}

// One-time: migrate existing tiers to have min_wallet_balance + update Normal limit + add Restricted
try {
  const allZero = db.prepare('SELECT COUNT(*) as c FROM customer_tiers WHERE min_wallet_balance > 0').get().c === 0;
  if (allZero) {
    db.prepare("UPDATE customer_tiers SET min_wallet_balance=0,    max_wallet_negative_limit=100  WHERE name='Normal'").run();
    db.prepare("UPDATE customer_tiers SET min_wallet_balance=200,  max_wallet_negative_limit=200  WHERE name='Silver'").run();
    db.prepare("UPDATE customer_tiers SET min_wallet_balance=500,  max_wallet_negative_limit=500  WHERE name='Gold'").run();
    db.prepare("UPDATE customer_tiers SET min_wallet_balance=1000, max_wallet_negative_limit=1000 WHERE name='Platinum'").run();
  }
  const hasRestricted = db.prepare("SELECT id FROM customer_tiers WHERE name='Restricted'").get();
  if (!hasRestricted) {
    db.prepare("INSERT OR IGNORE INTO customer_tiers (name,color,min_wallet_balance,max_wallet_negative_limit,cashback_multiplier,sort_order) VALUES (?,?,?,?,?,?)")
      .run('Restricted', '#DC2626', 0, 0, 1.0, -1);
  }
} catch (_) {}
try { db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email) WHERE email IS NOT NULL'); } catch (_) {}

// ── Boot-time schema integrity check ─────────────────────────────────────────
// Detects and fixes broken FK references left by table-rename migrations.
// Safe: only fires when there is an actual problem.
(function checkAndHealSchema() {
  try {
    db.pragma('foreign_keys = ON');

    // 1. Fix any broken FK references (e.g. pointing to *_old or *_new stale tables)
    const tables = db.prepare("SELECT name, sql FROM sqlite_master WHERE type='table'").all();
    const tableNames = new Set(tables.map(t => t.name));
    const broken = tables.filter(t => {
      const refs = (t.sql || '').match(/REFERENCES\s+["']?([\w_]+)["']?/g) || [];
      return refs.some(ref => {
        const target = ref.replace(/REFERENCES\s+["']?/, '').replace(/["']/g, '');
        return !tableNames.has(target);
      });
    });

    if (broken.length > 0) {
      console.log('[DB] Found broken FK references in:', broken.map(t => t.name).join(', '));
      db.pragma('foreign_keys = OFF');
      db.exec('BEGIN');
      try {
        for (const t of broken) {
          const cols = db.prepare(`PRAGMA table_info(${t.name})`).all();
          const rows = db.prepare(`SELECT * FROM ${t.name}`).all();
          const fixedSql = t.sql
            .replace(/REFERENCES\s+["']?[\w_]+_old["']?/g, 'REFERENCES users')
            .replace(/REFERENCES\s+["']?[\w_]+_new["']?/g, r => {
              const base = r.replace(/REFERENCES\s+["']?/, '').replace(/["'_new]/g, '');
              return `REFERENCES ${base}`;
            });
          db.exec(`DROP TABLE IF EXISTS ${t.name}_heal_tmp`);
          db.exec(fixedSql.replace(new RegExp(`CREATE TABLE ${t.name}`), `CREATE TABLE ${t.name}_heal_tmp`));
          if (rows.length > 0) {
            const colNames = cols.map(c => c.name).join(',');
            const placeholders = cols.map(() => '?').join(',');
            const ins = db.prepare(`INSERT INTO ${t.name}_heal_tmp (${colNames}) VALUES (${placeholders})`);
            for (const r of rows) ins.run(...cols.map(c => r[c.name]));
          }
          db.exec(`DROP TABLE ${t.name}`);
          db.exec(`ALTER TABLE ${t.name}_heal_tmp RENAME TO ${t.name}`);
          console.log(`[DB] ✅ Fixed FK in ${t.name}`);
        }
        db.exec('COMMIT');
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
      db.pragma('foreign_keys = ON');
    }

    // 2. Fix users.id if it was created as INT instead of INTEGER PRIMARY KEY
    const usersSchema = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'").get();
    if (usersSchema && !usersSchema.sql.includes('INTEGER PRIMARY KEY')) {
      console.log('[DB] Healing users table schema...');
      const good = db.prepare('SELECT rowid,name,name_odia,phone,email,password_hash,password_set,password_changed_at,role,fcm_token,wallet_balance,is_active,created_at,birthdate,gender FROM users').all().filter(r => r.rowid != null);
      db.pragma('foreign_keys = OFF');
      db.exec('BEGIN');
      try {
        db.exec('DROP TABLE IF EXISTS users_heal_tmp');
        db.exec(`CREATE TABLE users_heal_tmp (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, name_odia TEXT, phone TEXT UNIQUE NOT NULL,
          email TEXT, password_hash TEXT, password_set INTEGER NOT NULL DEFAULT 0,
          password_changed_at TEXT,
          role TEXT NOT NULL DEFAULT 'customer' CHECK(role IN ('customer','admin','agent','subadmin','salesman')),
          fcm_token TEXT, wallet_balance REAL NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          birthdate TEXT, gender TEXT
        )`);
        const ins = db.prepare('INSERT INTO users_heal_tmp (name,name_odia,phone,email,password_hash,password_set,password_changed_at,role,fcm_token,wallet_balance,is_active,created_at,birthdate,gender) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
        for (const r of good) ins.run(r.name,r.name_odia,r.phone,r.email,r.password_hash,r.password_set,r.password_changed_at,r.role,r.fcm_token,r.wallet_balance,r.is_active,r.created_at,r.birthdate,r.gender);
        db.exec('DROP TABLE users');
        db.exec('ALTER TABLE users_heal_tmp RENAME TO users');
        db.exec('COMMIT');
        db.pragma('foreign_keys = ON');
        console.log(`[DB] ✅ Users table healed — ${good.length} rows preserved`);
      } catch (e) {
        db.exec('ROLLBACK');
        db.pragma('foreign_keys = ON');
        console.error('[DB] Users heal failed (non-fatal):', e.message);
      }
    }

  } catch (e) {
    console.error('[DB] Schema check failed (non-fatal):', e.message);
  }
})();

// Add updated_at to salesman_settlements for acknowledgement timestamp
try { db.exec('ALTER TABLE salesman_settlements ADD COLUMN updated_at TEXT'); } catch (_) {}

// Generic referral codes — reusable admin-created codes with custom cashback
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN is_generic INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN max_uses INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN custom_signup_credit REAL'); } catch (_) {}
try { db.exec('ALTER TABLE referral_coupons ADD COLUMN label TEXT'); } catch (_) {}

// Promo code rule extensions
try { db.exec("ALTER TABLE promo_codes ADD COLUMN first_order_only INTEGER NOT NULL DEFAULT 0"); } catch (_) {}
try { db.exec("ALTER TABLE promo_codes ADD COLUMN allowed_phones TEXT"); } catch (_) {}      // JSON array of phone strings
try { db.exec("ALTER TABLE promo_codes ADD COLUMN allowed_product_ids TEXT"); } catch (_) {} // JSON array of product ids
try { db.exec("ALTER TABLE promo_codes ADD COLUMN allowed_category_ids TEXT"); } catch (_) {}// JSON array of category ids
try { db.exec("ALTER TABLE promo_codes ADD COLUMN allowed_tier_ids TEXT"); } catch (_) {}    // JSON array of tier ids
try { db.exec("ALTER TABLE promo_codes ADD COLUMN min_product_amount REAL"); } catch (_) {}  // min spend on restricted products/categories
try { db.exec(`
  CREATE TABLE IF NOT EXISTS promo_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    label TEXT,
    discount_type TEXT NOT NULL DEFAULT 'flat' CHECK(discount_type IN ('flat','percent')),
    discount_value REAL NOT NULL,
    min_order_amount REAL NOT NULL DEFAULT 0,
    max_discount_amount REAL,
    max_uses INTEGER,
    use_count INTEGER NOT NULL DEFAULT 0,
    per_user_limit INTEGER NOT NULL DEFAULT 1,
    valid_from TEXT,
    valid_until TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`); } catch (_) {}
try { db.exec(`
  CREATE TABLE IF NOT EXISTS promo_code_uses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    promo_code_id INTEGER NOT NULL REFERENCES promo_codes(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    order_id INTEGER REFERENCES orders(id),
    discount_amount REAL NOT NULL,
    used_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`); } catch (_) {}

try { db.exec('ALTER TABLE users ADD COLUMN last_login_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN last_active_at TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN phone_verified INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
try { db.exec('ALTER TABLE otp_codes ADD COLUMN sent_via TEXT'); } catch (_) {}

// Mark existing active customers as phone_verified (they're already using the app)
try { db.exec("UPDATE users SET phone_verified=1 WHERE role='customer' AND is_active=1 AND phone NOT LIKE 'email_%' AND phone_verified=0"); } catch (_) {}

// App config: rate limits and SMS cost
try { db.exec("INSERT OR IGNORE INTO app_config (key, value) VALUES ('sms_otp_cost', '2')"); } catch (_) {}
try { db.exec("INSERT OR IGNORE INTO app_config (key, value) VALUES ('otp_rate_limit_per_hour', '5')"); } catch (_) {}
try { db.exec("INSERT OR IGNORE INTO app_config (key, value) VALUES ('otp_rate_limit_per_day', '10')"); } catch (_) {}
try { db.exec("INSERT OR IGNORE INTO app_config (key, value) VALUES ('low_wallet_warning_threshold', '100')"); } catch (_) {}

module.exports = db;
