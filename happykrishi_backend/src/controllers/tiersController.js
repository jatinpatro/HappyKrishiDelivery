const db = require('../config/database');

function listTiers(req, res) {
  const tiers = db.prepare('SELECT * FROM customer_tiers ORDER BY sort_order ASC, name ASC').all();
  res.json({ tiers });
}

function createTier(req, res) {
  const { name, color = '#607D8B', min_wallet_balance = 0, max_wallet_negative_limit = 0, cashback_multiplier = 1.0, sort_order = 0 } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'name is required' });
  if (parseFloat(cashback_multiplier) < 0) return res.status(400).json({ error: 'cashback_multiplier must be >= 0' });
  if (parseFloat(max_wallet_negative_limit) < 0) return res.status(400).json({ error: 'max_wallet_negative_limit must be >= 0' });
  if (parseFloat(min_wallet_balance) < 0) return res.status(400).json({ error: 'min_wallet_balance must be >= 0' });
  const existing = db.prepare('SELECT id FROM customer_tiers WHERE name = ?').get(name.trim());
  if (existing) return res.status(409).json({ error: 'A tier with this name already exists' });

  const result = db.prepare(
    'INSERT INTO customer_tiers (name, color, min_wallet_balance, max_wallet_negative_limit, cashback_multiplier, sort_order) VALUES (?,?,?,?,?,?)'
  ).run(name.trim(), color || '#607D8B', parseFloat(min_wallet_balance), parseFloat(max_wallet_negative_limit), parseFloat(cashback_multiplier), parseInt(sort_order));

  res.status(201).json({ tier: db.prepare('SELECT * FROM customer_tiers WHERE id=?').get(result.lastInsertRowid) });
}

function updateTier(req, res) {
  const tier = db.prepare('SELECT * FROM customer_tiers WHERE id=?').get(req.params.id);
  if (!tier) return res.status(404).json({ error: 'Tier not found' });

  const { name, color, min_wallet_balance, max_wallet_negative_limit, cashback_multiplier, sort_order, is_active } = req.body;

  if (name && name.trim() !== tier.name) {
    const dup = db.prepare('SELECT id FROM customer_tiers WHERE name=? AND id!=?').get(name.trim(), tier.id);
    if (dup) return res.status(409).json({ error: 'A tier with this name already exists' });
  }

  db.prepare(`UPDATE customer_tiers SET name=?, color=?, min_wallet_balance=?, max_wallet_negative_limit=?, cashback_multiplier=?,
    sort_order=?, is_active=? WHERE id=?`).run(
    name != null ? name.trim() : tier.name,
    color != null ? color : (tier.color || '#607D8B'),
    min_wallet_balance != null ? parseFloat(min_wallet_balance) : (tier.min_wallet_balance ?? 0),
    max_wallet_negative_limit != null ? parseFloat(max_wallet_negative_limit) : tier.max_wallet_negative_limit,
    cashback_multiplier != null ? parseFloat(cashback_multiplier) : tier.cashback_multiplier,
    sort_order != null ? parseInt(sort_order) : tier.sort_order,
    is_active != null ? (is_active ? 1 : 0) : tier.is_active,
    tier.id
  );

  res.json({ tier: db.prepare('SELECT * FROM customer_tiers WHERE id=?').get(tier.id) });
}

function deleteTier(req, res) {
  const tier = db.prepare('SELECT * FROM customer_tiers WHERE id=?').get(req.params.id);
  if (!tier) return res.status(404).json({ error: 'Tier not found' });

  const count = db.prepare('SELECT COUNT(*) as c FROM users WHERE tier_id=?').get(tier.id).c;
  if (count > 0) {
    return res.status(400).json({
      error: `Cannot delete: ${count} customer(s) are assigned this tier. Reassign them first.`
    });
  }

  db.prepare('DELETE FROM customer_tiers WHERE id=?').run(tier.id);
  res.json({ message: 'Tier deleted' });
}

function assignTier(req, res) {
  const customerId = parseInt(req.params.id);
  const { tier_id } = req.body;

  const customer = db.prepare("SELECT id, name FROM users WHERE id=? AND role='customer'").get(customerId);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  if (tier_id != null) {
    const tier = db.prepare('SELECT * FROM customer_tiers WHERE id=? AND is_active=1').get(tier_id);
    if (!tier) return res.status(404).json({ error: 'Tier not found or inactive' });
  }

  db.prepare('UPDATE users SET tier_id=? WHERE id=?').run(tier_id ?? null, customerId);

  const tier = tier_id != null ? db.prepare('SELECT * FROM customer_tiers WHERE id=?').get(tier_id) : null;
  res.json({
    message: `Tier ${tier ? `"${tier.name}"` : 'cleared'} assigned to ${customer.name}`,
    tier,
  });
}

module.exports = { listTiers, createTier, updateTier, deleteTier, assignTier };
