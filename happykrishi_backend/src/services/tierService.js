const db = require('../config/database');
const notificationService = require('./notificationService');

function recalculateCustomerTier(userId) {
  try {
    const user = db.prepare('SELECT wallet_balance, tier_id FROM users WHERE id=?').get(userId);
    if (!user) return;

    const balance = user.wallet_balance;

    // All active tiers sorted highest→lowest by sort_order
    const tiers = db.prepare(
      'SELECT * FROM customer_tiers WHERE is_active=1 ORDER BY sort_order DESC'
    ).all();
    if (!tiers.length) return;

    let newTierId;

    if (balance < 0) {
      // Negative balance → Restricted tier (sort_order < 0)
      const restricted = tiers.find(t => t.sort_order < 0) || tiers[tiers.length - 1];
      newTierId = restricted.id;
    } else {
      // Find highest tier where balance >= min_wallet_balance (skip Restricted)
      const eligible = tiers.find(t => t.sort_order >= 0 && balance >= t.min_wallet_balance);
      newTierId = eligible
        ? eligible.id
        : (tiers.find(t => t.sort_order < 0) || tiers[tiers.length - 1]).id;
    }

    if (newTierId === user.tier_id) return;

    const oldOrder = user.tier_id
      ? (db.prepare('SELECT sort_order FROM customer_tiers WHERE id=?').get(user.tier_id)?.sort_order ?? 0)
      : 0;
    const newTier = db.prepare('SELECT sort_order, name, cashback_multiplier FROM customer_tiers WHERE id=?').get(newTierId);
    if (!newTier) return;

    db.prepare('UPDATE users SET tier_id=? WHERE id=?').run(newTierId, userId);

    const upgraded = newTier.sort_order > oldOrder;
    if (upgraded) {
      notificationService.sendToUser(userId, '🎉 Tier Upgraded!',
        `You've been upgraded to ${newTier.name} tier! Enjoy ${newTier.cashback_multiplier}x cashback.`,
        { type: 'tier_change' });
    } else {
      notificationService.sendToUser(userId, 'Tier Updated',
        newTier.name === 'Restricted'
          ? 'Your wallet balance is negative. Please top up to place orders.'
          : `Your tier has changed to ${newTier.name}. Top up to upgrade.`,
        { type: 'tier_change' });
    }
  } catch (err) {
    console.error('tierService.recalculateCustomerTier error:', err.message);
  }
}

module.exports = { recalculateCustomerTier };
