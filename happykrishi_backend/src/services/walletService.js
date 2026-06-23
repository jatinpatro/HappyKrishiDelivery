const db = require('../config/database');

// Atomic wallet credit
function credit(userId, amount, type, refType, refId, description) {
  const txn = db.transaction(() => {
    const user = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(userId);
    if (!user) throw new Error('User not found');

    const newBalance = parseFloat((user.wallet_balance + amount).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, userId);

    db.prepare(`
      INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description)
      VALUES (?,?,?,?,?,?,?)
    `).run(userId, type, amount, newBalance, refType, refId, description);

    return newBalance;
  });
  return txn();
}

// Atomic wallet debit — balance can go negative (no minimum enforced)
function debit(userId, amount, type, refType, refId, description) {
  const txn = db.transaction(() => {
    const user = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(userId);
    if (!user) throw new Error('User not found');

    const newBalance = parseFloat((user.wallet_balance - amount).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, userId);

    db.prepare(`
      INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description)
      VALUES (?,?,?,?,?,?,?)
    `).run(userId, type, amount, newBalance, refType, refId, description);

    return newBalance;
  });
  return txn();
}

// Weight-adjust: calculates diff and credits/debits accordingly — allows negative balance
function adjustForActualWeight(userId, orderId, adjustments) {
  const txn = db.transaction(() => {
    let totalDiff = 0;
    for (const adj of adjustments) {
      totalDiff += adj.actual_total - adj.estimated_total;
    }

    const user = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(userId);
    if (!user) throw new Error('User not found');

    let newBalance;
    if (totalDiff > 0) {
      // Customer owes more — debit (balance may go negative)
      newBalance = parseFloat((user.wallet_balance - totalDiff).toFixed(2));
      db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, userId);
      db.prepare(`
        INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description)
        VALUES (?,?,?,?,?,?,?)
      `).run(userId, 'adjustment', totalDiff, newBalance, 'order', orderId,
        'Weight adjustment — actual weight exceeded estimate');
    } else if (totalDiff < 0) {
      newBalance = parseFloat((user.wallet_balance + Math.abs(totalDiff)).toFixed(2));
      db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, userId);
      db.prepare(`
        INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description)
        VALUES (?,?,?,?,?,?,?)
      `).run(userId, 'refund', Math.abs(totalDiff), newBalance, 'order', orderId,
        'Weight adjustment — actual weight less than estimate');
    } else {
      newBalance = user.wallet_balance;
    }

    return { diff_amount: totalDiff, newBalance };
  });
  return txn();
}

module.exports = { credit, debit, adjustForActualWeight };
