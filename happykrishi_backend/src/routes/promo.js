const router = require('express').Router();
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/role');

router.use(authenticate);

// Helper — run all rule checks, return error string or null
// cartItems: [{product_id, qty, line_total}]  (optional, for min_product_amount check)
function checkPromoRules(promo, userId, subtotal, cartProductIds, cartItems) {
  const now = new Date().toISOString().slice(0, 19);
  if (!promo.is_active) return 'Invalid or expired coupon code';
  if (promo.valid_from && now < promo.valid_from) return 'This coupon is not active yet';
  if (promo.valid_until && now > promo.valid_until) return 'This coupon has expired';
  if (promo.max_uses && promo.use_count >= promo.max_uses) return 'This coupon has reached its usage limit';
  if (subtotal < promo.min_order_amount) return `Minimum cart total ₹${promo.min_order_amount.toFixed(0)} required for this coupon`;

  const userUses = db.prepare('SELECT COUNT(*) as c FROM promo_code_uses WHERE promo_code_id=? AND user_id=?').get(promo.id, userId).c;
  if (userUses >= promo.per_user_limit) return 'You have already used this coupon';

  // First order only
  if (promo.first_order_only) {
    const priorOrders = db.prepare("SELECT COUNT(*) as c FROM orders WHERE user_id=? AND status NOT IN ('cancelled')").get(userId).c;
    if (priorOrders > 0) return 'This coupon is only valid for your first order';
  }

  // Phone whitelist
  if (promo.allowed_phones) {
    const phones = JSON.parse(promo.allowed_phones);
    if (phones.length > 0) {
      const user = db.prepare('SELECT phone FROM users WHERE id=?').get(userId);
      if (!phones.includes(user.phone)) return 'This coupon is not valid for your account';
    }
  }

  // Tier restriction
  if (promo.allowed_tier_ids) {
    const tiers = JSON.parse(promo.allowed_tier_ids);
    if (tiers.length > 0) {
      const user = db.prepare('SELECT tier_id FROM users WHERE id=?').get(userId);
      if (!tiers.includes(user.tier_id)) {
        const tierNames = db.prepare(`SELECT name FROM customer_tiers WHERE id IN (${tiers.map(()=>'?').join(',')})`).all(...tiers).map(t=>t.name).join(', ');
        return `This coupon is only valid for ${tierNames} customers`;
      }
    }
  }

  const hasProductRestriction = promo.allowed_product_ids && JSON.parse(promo.allowed_product_ids).length > 0;
  const hasCategoryRestriction = promo.allowed_category_ids && JSON.parse(promo.allowed_category_ids).length > 0;

  // Specific products — cart must contain at least one
  if (hasProductRestriction && cartProductIds) {
    const allowed = JSON.parse(promo.allowed_product_ids);
    const hasAllowed = cartProductIds.some(id => allowed.includes(id));
    if (!hasAllowed) {
      const names = db.prepare(`SELECT name FROM products WHERE id IN (${allowed.map(()=>'?').join(',')})`).all(...allowed).map(p=>p.name).join(', ');
      return `This coupon requires ${names} in your cart`;
    }
  }

  // Specific categories — cart must contain at least one
  if (hasCategoryRestriction && cartProductIds && cartProductIds.length > 0) {
    const allowed = JSON.parse(promo.allowed_category_ids);
    const productCats = db.prepare(`SELECT DISTINCT category_id FROM products WHERE id IN (${cartProductIds.map(()=>'?').join(',')})`).all(...cartProductIds).map(r=>r.category_id);
    const hasAllowed = productCats.some(id => allowed.includes(id));
    if (!hasAllowed) {
      const names = db.prepare(`SELECT name FROM categories WHERE id IN (${allowed.map(()=>'?').join(',')})`).all(...allowed).map(c=>c.name).join(', ');
      return `This coupon requires products from ${names} in your cart`;
    }
  }

  // Minimum spend on specific products/categories (min_product_amount)
  if (promo.min_product_amount && promo.min_product_amount > 0 && cartItems && cartItems.length > 0) {
    let qualifyingTotal = 0;
    const minAmt = parseFloat(promo.min_product_amount);

    if (hasProductRestriction) {
      const allowed = JSON.parse(promo.allowed_product_ids);
      qualifyingTotal = cartItems.filter(i => allowed.includes(i.product_id)).reduce((s, i) => s + i.line_total, 0);
      if (qualifyingTotal < minAmt) {
        const names = db.prepare(`SELECT name FROM products WHERE id IN (${allowed.map(()=>'?').join(',')})`).all(...allowed).map(p=>p.name).join(', ');
        return `Minimum ₹${minAmt.toFixed(0)} worth of ${names} required (you have ₹${qualifyingTotal.toFixed(0)})`;
      }
    } else if (hasCategoryRestriction) {
      const allowed = JSON.parse(promo.allowed_category_ids);
      const catIds = cartItems.map(i => i.product_id);
      const catMap = {};
      if (catIds.length > 0) db.prepare(`SELECT id, category_id FROM products WHERE id IN (${catIds.map(()=>'?').join(',')})`).all(...catIds).forEach(p => { catMap[p.id] = p.category_id; });
      qualifyingTotal = cartItems.filter(i => allowed.includes(catMap[i.product_id])).reduce((s, i) => s + i.line_total, 0);
      if (qualifyingTotal < minAmt) {
        const names = db.prepare(`SELECT name FROM categories WHERE id IN (${allowed.map(()=>'?').join(',')})`).all(...allowed).map(c=>c.name).join(', ');
        return `Minimum ₹${minAmt.toFixed(0)} from ${names} required (you have ₹${qualifyingTotal.toFixed(0)})`;
      }
    } else {
      // No product/category restriction — check overall cart total
      if (subtotal < minAmt) return `Minimum cart total ₹${minAmt.toFixed(0)} required (you have ₹${subtotal.toFixed(0)})`;
    }
  }

  return null; // all checks passed
}

// GET /api/promo/available — list active codes the current customer can potentially use
// Pass ?subtotal=XXX to get sorted by max discount
router.get('/available', (req, res) => {
  const now = new Date().toISOString().slice(0, 19);
  const subtotal = parseFloat(req.query.subtotal || 0);

  const codes = db.prepare(`
    SELECT id, code, label, discount_type, discount_value, max_discount_amount,
           min_order_amount, min_product_amount, first_order_only, allowed_phones, allowed_tier_ids,
           per_user_limit, valid_until, use_count, max_uses
    FROM promo_codes
    WHERE is_active = 1
      AND (valid_from IS NULL OR valid_from <= ?)
      AND (valid_until IS NULL OR valid_until >= ?)
      AND (max_uses IS NULL OR use_count < max_uses)
  `).all(now, now);

  const user = db.prepare('SELECT phone, tier_id FROM users WHERE id=?').get(req.user.id);
  const priorOrders = db.prepare("SELECT COUNT(*) as c FROM orders WHERE user_id=? AND status!='cancelled'").get(req.user.id).c;

  const available = codes.filter(c => {
    const uses = db.prepare('SELECT COUNT(*) as n FROM promo_code_uses WHERE promo_code_id=? AND user_id=?').get(c.id, req.user.id).n;
    if (uses >= (c.per_user_limit || 1)) return false;  // hide only when customer has hit their personal limit
    if (c.allowed_phones) {
      const phones = JSON.parse(c.allowed_phones);
      if (phones.length > 0 && !phones.includes(user.phone)) return false;
    }
    if (c.allowed_tier_ids) {
      const tiers = JSON.parse(c.allowed_tier_ids);
      if (tiers.length > 0 && !tiers.includes(user.tier_id)) return false;
    }
    if (c.first_order_only && priorOrders > 0) return false;
    return true;
  }).map(c => {
    // Compute actual discount for current cart
    const canApply = subtotal >= c.min_order_amount;
    let computedDiscount = 0;
    if (canApply && subtotal > 0) {
      computedDiscount = c.discount_type === 'percent'
        ? (subtotal * c.discount_value / 100)
        : c.discount_value;
      if (c.max_discount_amount) computedDiscount = Math.min(computedDiscount, c.max_discount_amount);
      computedDiscount = Math.min(computedDiscount, subtotal);
      computedDiscount = Math.round(computedDiscount * 100) / 100;
    }

    return {
      id: c.id,
      code: c.code,
      label: c.label || c.code,
      discount_type: c.discount_type,
      discount_value: c.discount_value,
      max_discount_amount: c.max_discount_amount,
      min_order_amount: c.min_order_amount,
      min_product_amount: c.min_product_amount,
      first_order_only: c.first_order_only,
      valid_until: c.valid_until,
      computed_discount: computedDiscount,
      can_apply: canApply,
      description: c.discount_type === 'percent'
        ? `${c.discount_value}% off${c.max_discount_amount ? ` (max ₹${c.max_discount_amount})` : ''}${c.min_order_amount > 0 ? ` on orders ₹${c.min_order_amount}+` : ''}`
        : `₹${c.discount_value} off${c.min_order_amount > 0 ? ` on orders ₹${c.min_order_amount}+` : ''}`,
    };
  });

  // Sort: applicable codes first (by computed_discount desc), then non-applicable (by potential desc)
  available.sort((a, b) => {
    if (a.can_apply !== b.can_apply) return a.can_apply ? -1 : 1;
    return b.computed_discount - a.computed_discount;
  });

  res.json({ codes: available });
});

// POST /api/promo/validate — validate a code and return discount preview
router.post('/validate', (req, res) => {
  const { code, subtotal, product_ids, cart_items } = req.body;
  if (!code) return res.status(400).json({ error: 'code is required' });

  const promo = db.prepare('SELECT * FROM promo_codes WHERE code = ? COLLATE NOCASE').get(code.trim());
  if (!promo) return res.status(404).json({ error: 'Invalid or expired coupon code' });

  const orderAmt = parseFloat(subtotal || 0);
  const cartProductIds = Array.isArray(product_ids) ? product_ids.map(Number) : [];
  const cartItemsArr = Array.isArray(cart_items) ? cart_items : [];
  const error = checkPromoRules(promo, req.user.id, orderAmt, cartProductIds, cartItemsArr);
  if (error) return res.status(400).json({ error });

  // Build per-item discount breakdown for UI display
  const itemBreakdown = [];
  let discount = 0;

  const hasProductRestriction = promo.allowed_product_ids && JSON.parse(promo.allowed_product_ids).length > 0;
  const hasCategoryRestriction = promo.allowed_category_ids && JSON.parse(promo.allowed_category_ids).length > 0;

  let qualifyingIds = cartProductIds.length > 0 ? cartProductIds : [];
  if (hasProductRestriction) {
    qualifyingIds = JSON.parse(promo.allowed_product_ids).map(Number);
  } else if (hasCategoryRestriction) {
    const allowed = JSON.parse(promo.allowed_category_ids).map(Number);
    if (cartProductIds.length > 0) {
      const cats = db.prepare(`SELECT id,category_id FROM products WHERE id IN (${cartProductIds.map(()=>'?').join(',')})`).all(...cartProductIds);
      qualifyingIds = cats.filter(p => allowed.includes(p.category_id)).map(p => p.id);
    }
  }

  // Compute qualifying total (items the discount actually applies to)
  const qualifyingItems = cartItemsArr.filter(i => qualifyingIds.includes(Number(i.product_id)));
  const qualifyingTotal = qualifyingItems.length > 0
    ? qualifyingItems.reduce((s, i) => s + i.line_total, 0)
    : orderAmt; // fall back to full cart if no item details

  // Compute total discount based on qualifying total
  if (promo.discount_type === 'percent') {
    discount = qualifyingTotal * promo.discount_value / 100;
  } else {
    discount = promo.discount_value;
  }
  if (promo.max_discount_amount) discount = Math.min(discount, promo.max_discount_amount);
  discount = Math.min(discount, orderAmt);
  discount = Math.round(discount * 100) / 100;

  if (cartItemsArr.length > 0) {
    for (const item of cartItemsArr) {
      const isQualifying = qualifyingIds.includes(Number(item.product_id));
      let itemDiscount = 0;
      if (isQualifying && qualifyingTotal > 0) {
        if (promo.discount_type === 'percent') {
          const uncappedItem = item.line_total * promo.discount_value / 100;
          const uncappedTotal = qualifyingTotal * promo.discount_value / 100;
          if (promo.max_discount_amount && uncappedTotal > promo.max_discount_amount) {
            // Distribute the capped total proportionally across qualifying items
            itemDiscount = promo.max_discount_amount * (item.line_total / qualifyingTotal);
          } else {
            itemDiscount = uncappedItem;
          }
        } else {
          // Flat — distribute proportionally across qualifying items
          itemDiscount = discount * (item.line_total / qualifyingTotal);
        }
        itemDiscount = Math.round(itemDiscount * 100) / 100;
      }
      itemBreakdown.push({
        product_id: item.product_id,
        original_line_total: item.line_total,
        discount: itemDiscount,
        discounted_line_total: Math.round((item.line_total - itemDiscount) * 100) / 100,
        is_qualifying: isQualifying,
      });
    }
  }

  res.json({
    valid: true,
    code: promo.code,
    label: promo.label || promo.code,
    discount_type: promo.discount_type,
    discount_value: promo.discount_value,
    discount_amount: discount,
    item_breakdown: itemBreakdown,
  });
});

// ── Admin: CRUD for promo codes ───────────────────────────────────────────────

router.get('/', requireRole('admin', 'subadmin'), (req, res) => {
  const codes = db.prepare(`
    SELECT pc.*, u.name as created_by_name,
           (SELECT COUNT(*) FROM promo_code_uses pcu WHERE pcu.promo_code_id = pc.id) as total_uses,
           (SELECT COALESCE(SUM(pcu.discount_amount),0) FROM promo_code_uses pcu WHERE pcu.promo_code_id = pc.id) as total_discounted
    FROM promo_codes pc
    LEFT JOIN users u ON u.id = pc.created_by
    ORDER BY pc.created_at DESC
  `).all();
  res.json({ codes });
});

router.post('/', requireRole('admin', 'subadmin'), (req, res) => {
  const { code, label, discount_type, discount_value, min_order_amount, min_product_amount,
          max_discount_amount, max_uses, per_user_limit, valid_from, valid_until,
          first_order_only, allowed_phones, allowed_product_ids, allowed_category_ids, allowed_tier_ids } = req.body;
  if (!code || !discount_value) return res.status(400).json({ error: 'code and discount_value required' });
  const existing = db.prepare('SELECT id FROM promo_codes WHERE code = ? COLLATE NOCASE').get(code.trim());
  if (existing) return res.status(400).json({ error: 'Code already exists' });
  const result = db.prepare(`
    INSERT INTO promo_codes (code, label, discount_type, discount_value, min_order_amount, min_product_amount,
      max_discount_amount, max_uses, per_user_limit, valid_from, valid_until, created_by,
      first_order_only, allowed_phones, allowed_product_ids, allowed_category_ids, allowed_tier_ids)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
  `).run(
    code.trim().toUpperCase(), label||null,
    discount_type||'flat', parseFloat(discount_value),
    parseFloat(min_order_amount||0), min_product_amount ? parseFloat(min_product_amount) : null,
    max_discount_amount ? parseFloat(max_discount_amount) : null,
    max_uses ? parseInt(max_uses) : null,
    parseInt(per_user_limit||1),
    valid_from||null, valid_until||null, req.user.id,
    first_order_only ? 1 : 0,
    allowed_phones?.length ? JSON.stringify(allowed_phones) : null,
    allowed_product_ids?.length ? JSON.stringify(allowed_product_ids.map(Number)) : null,
    allowed_category_ids?.length ? JSON.stringify(allowed_category_ids.map(Number)) : null,
    allowed_tier_ids?.length ? JSON.stringify(allowed_tier_ids.map(Number)) : null
  );
  res.status(201).json({ id: result.lastInsertRowid });
});

router.put('/:id', requireRole('admin', 'subadmin'), (req, res) => {
  const id = parseInt(req.params.id);
  const { label, code: newCode, discount_type, discount_value, min_order_amount, min_product_amount,
          max_discount_amount, max_uses, per_user_limit, valid_from, valid_until, is_active,
          first_order_only, allowed_phones, allowed_product_ids, allowed_category_ids, allowed_tier_ids } = req.body;
  const existing = db.prepare('SELECT * FROM promo_codes WHERE id=?').get(id);
  if (!existing) return res.status(404).json({ error: 'Not found' });
  // Check new code uniqueness if being changed
  if (newCode && newCode.toUpperCase() !== existing.code) {
    const clash = db.prepare('SELECT id FROM promo_codes WHERE code = ? COLLATE NOCASE AND id != ?').get(newCode.trim(), id);
    if (clash) return res.status(400).json({ error: 'Code already exists' });
  }
  db.prepare(`
    UPDATE promo_codes SET code=?,label=?,discount_type=?,discount_value=?,min_order_amount=?,min_product_amount=?,
      max_discount_amount=?,max_uses=?,per_user_limit=?,valid_from=?,valid_until=?,is_active=?,
      first_order_only=?,allowed_phones=?,allowed_product_ids=?,allowed_category_ids=?,allowed_tier_ids=?
    WHERE id=?
  `).run(
    newCode ? newCode.trim().toUpperCase() : existing.code,
    label ?? existing.label,
    discount_type ?? existing.discount_type,
    discount_value != null ? parseFloat(discount_value) : existing.discount_value,
    min_order_amount != null ? parseFloat(min_order_amount) : existing.min_order_amount,
    min_product_amount !== undefined ? (min_product_amount ? parseFloat(min_product_amount) : null) : existing.min_product_amount,
    max_discount_amount != null ? parseFloat(max_discount_amount) : existing.max_discount_amount,
    max_uses != null ? (max_uses ? parseInt(max_uses) : null) : existing.max_uses,
    per_user_limit != null ? parseInt(per_user_limit) : existing.per_user_limit,
    valid_from !== undefined ? (valid_from||null) : existing.valid_from,
    valid_until !== undefined ? (valid_until||null) : existing.valid_until,
    is_active != null ? (is_active ? 1 : 0) : existing.is_active,
    first_order_only !== undefined ? (first_order_only ? 1 : 0) : existing.first_order_only,
    allowed_phones !== undefined ? (allowed_phones?.length ? JSON.stringify(allowed_phones) : null) : existing.allowed_phones,
    allowed_product_ids !== undefined ? (allowed_product_ids?.length ? JSON.stringify(allowed_product_ids.map(Number)) : null) : existing.allowed_product_ids,
    allowed_category_ids !== undefined ? (allowed_category_ids?.length ? JSON.stringify(allowed_category_ids.map(Number)) : null) : existing.allowed_category_ids,
    allowed_tier_ids !== undefined ? (allowed_tier_ids?.length ? JSON.stringify(allowed_tier_ids.map(Number)) : null) : existing.allowed_tier_ids,
    id
  );
  res.json({ message: 'Updated' });
});

router.delete('/:id', requireRole('admin', 'subadmin'), (req, res) => {
  const id = parseInt(req.params.id);
  if (!db.prepare('SELECT id FROM promo_codes WHERE id=?').get(id)) return res.status(404).json({ error: 'Not found' });
  db.prepare('DELETE FROM promo_codes WHERE id=?').run(id);
  res.json({ message: 'Deleted' });
});

module.exports = router;
module.exports.checkPromoRules = checkPromoRules;
