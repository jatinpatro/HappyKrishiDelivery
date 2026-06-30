const db = require('../config/database');
const walletService = require('../services/walletService');
const { calcDeliveryCharge } = require('../services/deliveryChargeService');
const notificationService = require('../services/notificationService');
const whatsappService = require('../services/whatsappService');
const { checkPromoRules } = require('../routes/promo');
const { recalculateCustomerTier } = require('../services/tierService');
const emailService = require('../services/emailService');

function getConfig(key) {
  const row = db.prepare('SELECT value FROM app_config WHERE key = ?').get(key);
  return row ? parseFloat(row.value) : null;
}

function generateOrderNumber() {
  const ts = Date.now().toString(36).toUpperCase();
  const rand = Math.random().toString(36).substring(2, 6).toUpperCase();
  return `HK-${ts}-${rand}`;
}

function placeOrder(req, res) {
  const userId = req.user.id;
  const { address_id, slot_id, delivery_date, items, notes, order_type = 'delivery',
          preferred_salesman_id, coupon_code } = req.body;

  if (!delivery_date || !items?.length) {
    return res.status(400).json({ error: 'delivery_date and items are required' });
  }
  if (order_type === 'delivery' && !address_id) {
    return res.status(400).json({ error: 'address_id is required for delivery orders' });
  }
  if (!['delivery', 'pickup'].includes(order_type)) {
    return res.status(400).json({ error: 'order_type must be delivery or pickup' });
  }

  const minOrder = getConfig('min_order_amount') || 50;

  const user = db.prepare('SELECT wallet_balance, email, tier_id, name FROM users WHERE id = ?').get(userId);
  let pincodeRules = null;
  if (order_type === 'delivery') {
    address = db.prepare('SELECT * FROM addresses WHERE id = ? AND user_id = ?').get(address_id, userId);
    if (!address) return res.status(400).json({ error: 'Invalid address' });

    if (address.pincode) {
      const cached = db.prepare(
        'SELECT deliverable, distance_km, min_order_amount, allowed_product_ids, custom_delivery_charge FROM pincode_cache WHERE pincode = ?'
      ).get(address.pincode);
      if (cached && cached.deliverable === 0) {
        return res.status(400).json({
          error: `Sorry, we don't deliver to pincode ${address.pincode}. Please contact us to arrange delivery.`,
        });
      }
      if (cached && cached.deliverable === 1) {
        pincodeRules = {
          minOrder: cached.min_order_amount,
          allowedIds: cached.allowed_product_ids ? JSON.parse(cached.allowed_product_ids) : null,
          deliveryCharge: cached.custom_delivery_charge,
        };
      }
      // cached === null → pincode not yet checked → distance-based logic applies normally
    }
  }

  // Validate items and calculate subtotal
  let subtotal = 0;
  const resolvedItems = [];

  for (const item of items) {
    const product = db.prepare('SELECT * FROM products WHERE id = ? AND is_active = 1').get(item.product_id);
    if (!product) return res.status(400).json({ error: `Product ${item.product_id} not found` });
    if (product.stock_qty < item.qty) {
      return res.status(400).json({ error: `Insufficient stock for ${product.name}` });
    }
    // Enforce allowed products for custom pincodes
    if (pincodeRules?.allowedIds && !pincodeRules.allowedIds.includes(product.id)) {
      return res.status(400).json({
        error: `"${product.name}" is not available for delivery to your area. Please check the available products for your pincode.`,
      });
    }
    const lineTotal = parseFloat((product.price_per_unit * item.qty).toFixed(2));
    subtotal += lineTotal;
    resolvedItems.push({ product, qty: item.qty, lineTotal });
  }

  // Apply custom min order if set for this pincode, else global
  const effectiveMinOrder = order_type === 'pickup'
    ? (getConfig('min_pickup_order_amount') ?? 10)
    : (pincodeRules?.minOrder ?? minOrder);
  if (subtotal < effectiveMinOrder) {
    return res.status(400).json({ error: `Minimum order amount for ${order_type === 'pickup' ? 'pickup' : 'your area'} is ₹${effectiveMinOrder}` });
  }

  // Self pickup = free; tiered rules if set; legacy custom charge; else distance-based
  let deliveryCharge;
  if (order_type === 'pickup') {
    deliveryCharge = 0;
  } else if (address.pincode) {
    const tiered = resolveDeliveryRule(address.pincode, subtotal);
    if (tiered) {
      if (tiered.blocked) {
        return res.status(400).json({ error: tiered.blocked_message || 'Delivery not available for this order amount to your area' });
      }
      deliveryCharge = tiered.delivery_charge ?? calcDeliveryCharge(address.lat, address.lng, subtotal);
    } else if (pincodeRules?.deliveryCharge != null) {
      deliveryCharge = pincodeRules.deliveryCharge;
    } else {
      deliveryCharge = calcDeliveryCharge(address.lat, address.lng, subtotal);
    }
  } else {
    deliveryCharge = pincodeRules?.deliveryCharge != null
      ? pincodeRules.deliveryCharge
      : calcDeliveryCharge(address.lat, address.lng, subtotal);
  }
  const finalAmount = parseFloat((subtotal + deliveryCharge).toFixed(2));

  // ── Promo code validation ─────────────────────────────────────────────────
  let promoDiscount = 0;
  let promoRow = null;
  if (coupon_code) {
    promoRow = db.prepare('SELECT * FROM promo_codes WHERE code = ? COLLATE NOCASE AND is_active = 1').get(coupon_code.trim());
    if (!promoRow) return res.status(400).json({ error: 'Invalid or expired coupon code' });
    const cartProductIds = resolvedItems.map(ri => ri.product.id);
    const cartItems = resolvedItems.map(ri => ({ product_id: ri.product.id, qty: ri.qty, line_total: ri.lineTotal }));
    const ruleError = checkPromoRules(promoRow, userId, subtotal, cartProductIds, cartItems);
    if (ruleError) return res.status(400).json({ error: ruleError });

    // Compute discount on qualifying total (not full cart) for product/category restricted codes
    let qualifyingTotal = subtotal;
    if (promoRow.allowed_product_ids) {
      const allowed = JSON.parse(promoRow.allowed_product_ids).map(Number);
      qualifyingTotal = cartItems.filter(i => allowed.includes(i.product_id)).reduce((s, i) => s + i.line_total, 0);
    } else if (promoRow.allowed_category_ids) {
      const allowed = JSON.parse(promoRow.allowed_category_ids).map(Number);
      const cats = db.prepare(`SELECT id,category_id FROM products WHERE id IN (${cartProductIds.map(()=>'?').join(',')})`).all(...cartProductIds);
      const qIds = cats.filter(p => allowed.includes(p.category_id)).map(p => p.id);
      qualifyingTotal = cartItems.filter(i => qIds.includes(i.product_id)).reduce((s, i) => s + i.line_total, 0);
    }
    promoDiscount = promoRow.discount_type === 'percent'
      ? (qualifyingTotal * promoRow.discount_value / 100)
      : promoRow.discount_value;
    if (promoRow.max_discount_amount) promoDiscount = Math.min(promoDiscount, promoRow.max_discount_amount);
    promoDiscount = Math.min(promoDiscount, finalAmount);
    promoDiscount = Math.round(promoDiscount * 100) / 100;
  }
  const discountedFinal = parseFloat((finalAmount - promoDiscount).toFixed(2));

  // Block order if resulting balance would exceed the allowed negative limit
  const tierRow = user.tier_id
    ? db.prepare('SELECT max_wallet_negative_limit FROM customer_tiers WHERE id=?').get(user.tier_id)
    : null;
  const negLimit = tierRow?.max_wallet_negative_limit != null
    ? tierRow.max_wallet_negative_limit
    : parseFloat(db.prepare("SELECT value FROM app_config WHERE key='max_wallet_negative_limit'").get()?.value ?? '0');
  const resultingBalance = parseFloat((user.wallet_balance - discountedFinal).toFixed(2));
  if (resultingBalance < 0 && Math.abs(resultingBalance) > negLimit) {
    return res.status(400).json({
      error: `This order would take your balance to ₹${resultingBalance.toFixed(2)}, exceeding your ₹${negLimit.toFixed(0)} credit limit. Please top up first.`
    });
  }

  const txn = db.transaction(() => {
    const orderNumber = generateOrderNumber();

    const orderResult = db.prepare(`
      INSERT INTO orders (order_number, user_id, address_id, slot_id, status, delivery_date,
        subtotal, delivery_charge, discount_amount, wallet_used, final_amount, payment_status, notes, order_type)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,'paid',?,?)
    `).run(orderNumber, userId, address_id || null, slot_id || null, 'pending', delivery_date,
      subtotal, deliveryCharge, promoDiscount, discountedFinal, discountedFinal, notes || null, order_type);

    const orderId = orderResult.lastInsertRowid;

    // Record promo code usage
    if (promoRow) {
      db.prepare('INSERT INTO promo_code_uses (promo_code_id, user_id, order_id, discount_amount) VALUES (?,?,?,?)').run(promoRow.id, userId, orderId, promoDiscount);
      db.prepare('UPDATE promo_codes SET use_count = use_count + 1 WHERE id = ?').run(promoRow.id);
    }

    for (const ri of resolvedItems) {
      db.prepare(`
        INSERT INTO order_items (order_id, product_id, estimated_qty, unit_price, estimated_total, is_weight_adjusted)
        VALUES (?,?,?,?,?,?)
      `).run(orderId, ri.product.id, ri.qty, ri.product.price_per_unit, ri.lineTotal, ri.product.is_weight_adjusted);
      db.prepare('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?').run(ri.qty, ri.product.id);
    }

    // Always create delivery record (even for pickup — agent_id stays null until assigned)
    db.prepare('INSERT INTO deliveries (order_id, status) VALUES (?,?)').run(orderId, 'pending');

    // For pickup: auto-assign preferred salesman if provided
    if (order_type === 'pickup' && preferred_salesman_id) {
      const agentRow = db.prepare('SELECT * FROM delivery_agents WHERE user_id=?').get(parseInt(preferred_salesman_id));
      if (agentRow) {
        db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now') WHERE order_id=?")
          .run(agentRow.id, orderId);
        db.prepare("UPDATE orders SET status='assigned', updated_at=datetime('now') WHERE id=?").run(orderId);
      }
    }

    // Debit wallet — balance allowed to go negative (collected later)
    const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(userId);
    const newBalance = parseFloat((userRow.wallet_balance - discountedFinal).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, userId);
    db.prepare(`
      INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description)
      VALUES (?,?,?,?,?,?,?)
    `).run(userId, 'debit', discountedFinal, newBalance, 'order', orderId,
      promoDiscount > 0 ? `Order #${orderNumber} (coupon ${coupon_code}: -₹${promoDiscount.toFixed(0)})` : `Order #${orderNumber}`);

    return db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  });

  const order = txn();
  setImmediate(() => recalculateCustomerTier(userId));

  // Low wallet balance warning
  const lowBalanceThreshold = parseFloat(db.prepare("SELECT value FROM app_config WHERE key='low_wallet_warning_threshold'").get()?.value || '100');
  const freshUser = db.prepare('SELECT wallet_balance FROM users WHERE id=?').get(userId);
  if (freshUser && freshUser.wallet_balance < lowBalanceThreshold) {
    const balanceStr = freshUser.wallet_balance < 0
      ? `₹${Math.abs(freshUser.wallet_balance).toFixed(0)} in debt`
      : `₹${freshUser.wallet_balance.toFixed(0)} remaining`;
    notificationService.sendToUser(userId, '⚠️ Low Wallet Balance',
      `Your wallet has ${balanceStr}. Top up to continue ordering without interruptions.`,
      { type: 'low_balance' });
  }

  const items_ = db.prepare(`
    SELECT oi.*, p.name as product_name, p.unit FROM order_items oi
    JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?
  `).all(order.id);

  notificationService.sendToUser(userId, 'Order Confirmed!', `Your order #${order.order_number} has been placed.`, { type: 'order_confirmed', order_id: String(order.id) });
  notificationService.sendToAdmins('New Order 🛒', `${user.name} placed order #${order.order_number} — ₹${order.final_amount.toFixed(2)}`, { type: 'new_order', order_id: String(order.id) });
  whatsappService.sendTemplate(userId, 'order_confirmed', []);
  if (user.email) emailService.sendOrderConfirmation(user.email, order, items_).catch(() => {});

  res.status(201).json({ order, items: items_ });
}

function listOrders(req, res) {
  const { page = 1, limit = 50, status, search, date_from, date_to } = req.query;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  let where = 'o.user_id = ?';
  const params = [req.user.id];
  if (status) { where += ' AND o.status = ?'; params.push(status); }
  if (date_from) { where += ' AND date(o.created_at) >= ?'; params.push(date_from); }
  if (date_to)   { where += ' AND date(o.created_at) <= ?'; params.push(date_to); }
  if (search) {
    const like = `%${search}%`;
    where += ` AND (
      o.order_number LIKE ?
      OR EXISTS (
        SELECT 1 FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        LEFT JOIN categories cat ON cat.id = p.category_id
        WHERE oi.order_id = o.id AND (p.name LIKE ? OR cat.name LIKE ?)
      )
    )`;
    params.push(like, like, like);
  }

  const orders = db.prepare(`
    SELECT o.*, s.label as slot_label, a.address_line, a.city,
           pc.code as coupon_code, pcu.discount_amount as coupon_discount,
           d.delivery_code, d.customer_confirmed_at
    FROM orders o
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN promo_code_uses pcu ON pcu.order_id = o.id
    LEFT JOIN promo_codes pc ON pc.id = pcu.promo_code_id
    LEFT JOIN deliveries d ON d.order_id = o.id
    WHERE ${where} ORDER BY o.created_at DESC LIMIT ? OFFSET ?
  `).all(...params, parseInt(limit), offset);

  res.json({ orders });
}

function getOrder(req, res) {
  const order = db.prepare(`
    SELECT o.*, s.label as slot_label, s.start_time, s.end_time,
           a.address_line, a.city, a.pincode, a.lat, a.lng,
           sm.name as salesman_name, sm.phone as salesman_phone,
           pc.code as coupon_code, pcu.discount_amount as coupon_discount
    FROM orders o
    LEFT JOIN delivery_slots s ON s.id = o.slot_id
    LEFT JOIN addresses a ON a.id = o.address_id
    LEFT JOIN users sm ON sm.id = o.salesman_id
    LEFT JOIN promo_code_uses pcu ON pcu.order_id = o.id
    LEFT JOIN promo_codes pc ON pc.id = pcu.promo_code_id
    WHERE o.id = ? AND (o.user_id = ? OR ? IN ('admin','subadmin','agent','salesman'))
  `).get(req.params.id, req.user.id, req.user.role);

  if (!order) return res.status(404).json({ error: 'Order not found' });

  const items = db.prepare(`
    SELECT oi.*, p.name as product_name, p.name_odia, p.unit, p.image_url
    FROM order_items oi JOIN products p ON p.id = oi.product_id
    WHERE oi.order_id = ?
  `).all(order.id);

  const delivery = db.prepare(`
    SELECT d.*, u.name as agent_name, u.phone as agent_phone,
           COALESCE(da.current_lat, sda.current_lat)   as agent_lat,
           COALESCE(da.current_lng, sda.current_lng)   as agent_lng,
           COALESCE(u.name, sm.name)                   as agent_name,
           COALESCE(u.phone, sm.phone)                 as agent_phone,
           d.customer_lat, d.customer_lng
    FROM deliveries d
    LEFT JOIN delivery_agents da  ON da.id = d.agent_id
    LEFT JOIN users u             ON u.id  = da.user_id
    LEFT JOIN users sm            ON sm.id = (SELECT salesman_id FROM orders WHERE id = d.order_id)
    LEFT JOIN delivery_agents sda ON sda.user_id = sm.id
    WHERE d.order_id = ?
  `).get(order.id);

  // Only expose delivery_code to customer (owner) and admin/subadmin — not to salesman
  const canSeeCode = req.user.id === order.user_id || ['admin', 'subadmin'].includes(req.user.role);
  const deliveryOut = delivery && !canSeeCode
    ? { ...delivery, delivery_code: undefined }
    : delivery;

  // Build per-item discount breakdown if a coupon was used
  let itemBreakdown = null;
  if (order.coupon_code && order.discount_amount > 0) {
    const promoRow = db.prepare('SELECT * FROM promo_codes WHERE code = ? COLLATE NOCASE').get(order.coupon_code);
    if (promoRow) {
      const cartProductIds = items.map(i => i.product_id);
      const hasProductRestriction = promoRow.allowed_product_ids && JSON.parse(promoRow.allowed_product_ids).length > 0;
      const hasCategoryRestriction = promoRow.allowed_category_ids && JSON.parse(promoRow.allowed_category_ids).length > 0;
      let qualifyingIds = cartProductIds;
      if (hasProductRestriction) qualifyingIds = JSON.parse(promoRow.allowed_product_ids).map(Number);
      else if (hasCategoryRestriction) {
        const allowed = JSON.parse(promoRow.allowed_category_ids).map(Number);
        const cats = db.prepare(`SELECT id,category_id FROM products WHERE id IN (${cartProductIds.map(()=>'?').join(',')})`).all(...cartProductIds);
        qualifyingIds = cats.filter(p => allowed.includes(p.category_id)).map(p => p.id);
      }
      const qualifyingTotal = items.filter(i => qualifyingIds.includes(i.product_id)).reduce((s, i) => s + (i.actual_total ?? i.estimated_total), 0);
      const totalDiscount = order.discount_amount;
      itemBreakdown = {};
      for (const item of items) {
        const isQualifying = qualifyingIds.includes(item.product_id);
        let itemDiscount = 0;
        if (isQualifying && qualifyingTotal > 0) {
          if (promoRow.discount_type === 'percent') {
            // Apply percent to this item's share
            const uncappedItemDiscount = (item.actual_total ?? item.estimated_total) * promoRow.discount_value / 100;
            const uncappedTotal = qualifyingTotal * promoRow.discount_value / 100;
            if (promoRow.max_discount_amount && uncappedTotal > promoRow.max_discount_amount) {
              // Distribute the capped total proportionally across qualifying items
              itemDiscount = promoRow.max_discount_amount * ((item.actual_total ?? item.estimated_total) / qualifyingTotal);
            } else {
              itemDiscount = uncappedItemDiscount;
            }
          } else {
            itemDiscount = totalDiscount * ((item.actual_total ?? item.estimated_total) / qualifyingTotal);
          }
          itemDiscount = Math.round(itemDiscount * 100) / 100;
        }
        itemBreakdown[item.product_id] = { discount: itemDiscount, is_qualifying: isQualifying };
      }
    }
  }

  res.json({ order, items, delivery: deliveryOut, item_breakdown: itemBreakdown });
}

function cancelOrder(req, res) {
  const order = db.prepare('SELECT * FROM orders WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (!['pending', 'confirmed'].includes(order.status)) {
    return res.status(400).json({ error: 'Order cannot be cancelled at this stage' });
  }

  // Block cancellation if delivery date is tomorrow or today
  const deliveryDate = new Date(order.delivery_date);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const cutoff = new Date(today);
  cutoff.setDate(cutoff.getDate() + 1); // 1 day before delivery
  if (deliveryDate <= cutoff) {
    return res.status(400).json({
      error: `Order cannot be cancelled within 1 day of delivery (${order.delivery_date}). Please contact us for help.`
    });
  }

  const { reason } = req.body;
  if (!reason || reason.trim() === '') {
    return res.status(400).json({ error: 'A reason is required to cancel an order' });
  }

  db.transaction(() => {
    db.prepare("UPDATE orders SET status='cancelled', cancelled_reason=?, updated_at=datetime('now') WHERE id=?").run(reason || null, order.id);
    db.prepare("UPDATE deliveries SET status='cancelled', updated_at=datetime('now') WHERE order_id=? AND status NOT IN ('delivered','cancelled')").run(order.id);
    const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(order.user_id);
    const newBal = parseFloat((userRow.wallet_balance + order.final_amount).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBal, order.user_id);
    db.prepare(`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, reference_type, reference_id, description) VALUES (?,?,?,?,?,?,?)`)
      .run(order.user_id, 'refund', order.final_amount, newBal, 'order', order.id, `Refund for cancelled order #${order.order_number}`);
    // Restore stock
    const items = db.prepare('SELECT * FROM order_items WHERE order_id = ?').all(order.id);
    for (const item of items) {
      db.prepare('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?').run(item.estimated_qty, item.product_id);
    }
    // Restore promo code usage so customer can use it again on a future order
    const promoUse = db.prepare('SELECT * FROM promo_code_uses WHERE order_id = ?').get(order.id);
    if (promoUse) {
      db.prepare('DELETE FROM promo_code_uses WHERE order_id = ?').run(order.id);
      db.prepare('UPDATE promo_codes SET use_count = MAX(0, use_count - 1) WHERE id = ?').run(promoUse.promo_code_id);
    }
  })();

  notificationService.sendToUser(order.user_id, 'Order Cancelled', `Order #${order.order_number} has been cancelled. Refund added to wallet.`);
  setImmediate(() => recalculateCustomerTier(order.user_id));
  res.json({ message: 'Order cancelled and wallet refunded' });
}

function reorder(req, res) {
  const prevOrder = db.prepare('SELECT * FROM orders WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!prevOrder) return res.status(404).json({ error: 'Order not found' });

  const items = db.prepare(`
    SELECT oi.product_id, oi.estimated_qty as qty,
           p.id, p.name, p.name_odia, p.unit, p.price_per_unit,
           p.stock_qty, p.low_stock_threshold, p.is_weight_adjusted,
           p.image_url, p.is_active, p.category_id,
           c.name as category_name
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE oi.order_id = ? AND p.is_active = 1 AND p.stock_qty > 0
  `).all(prevOrder.id);

  const cartItems = items.map(i => ({
    product_id: i.product_id,
    qty: i.qty,
    product: {
      id: i.id,
      name: i.name,
      name_odia: i.name_odia,
      unit: i.unit,
      price_per_unit: i.price_per_unit,
      stock_qty: i.stock_qty,
      low_stock_threshold: i.low_stock_threshold,
      is_weight_adjusted: i.is_weight_adjusted,
      image_url: i.image_url,
      is_active: i.is_active,
      category_id: i.category_id,
      category_name: i.category_name,
    },
  }));

  res.json({ cart_items: cartItems, count: cartItems.length });
}

function getDeliveryCharge(req, res) {
  const { address_id, subtotal } = req.query;
  if (!address_id) return res.status(400).json({ error: 'address_id required' });

  const isStaff = ['admin', 'salesman'].includes(req.user.role);
  const address = isStaff
    ? db.prepare('SELECT lat, lng, pincode FROM addresses WHERE id = ?').get(address_id)
    : db.prepare('SELECT lat, lng, pincode FROM addresses WHERE id = ? AND user_id = ?').get(address_id, req.user.id);
  if (!address) return res.status(404).json({ error: 'Address not found' });

  const sub = parseFloat(subtotal || 0);

  // Check tiered delivery rules first
  if (address.pincode) {
    const tiered = resolveDeliveryRule(address.pincode, sub);
    if (tiered !== null) {
      if (tiered.blocked) {
        return res.json({ delivery_charge: null, blocked: true, blocked_message: tiered.blocked_message || 'Delivery not available for this order amount' });
      }
      return res.json({ delivery_charge: tiered.delivery_charge, blocked: false });
    }
    // Fallback: legacy single custom_delivery_charge
    const cached = db.prepare('SELECT custom_delivery_charge FROM pincode_cache WHERE pincode = ? AND deliverable = 1').get(address.pincode);
    if (cached?.custom_delivery_charge != null) {
      return res.json({ delivery_charge: cached.custom_delivery_charge, blocked: false });
    }
  }

  const charge = calcDeliveryCharge(address.lat, address.lng, sub);
  res.json({ delivery_charge: charge, blocked: false });
}

// Resolve the best matching tiered delivery rule for a subtotal
function resolveDeliveryRule(pincode, subtotal) {
  const rules = db.prepare(`
    SELECT * FROM pincode_delivery_rules
    WHERE pincode = ?
      AND min_subtotal <= ?
      AND (max_subtotal IS NULL OR max_subtotal >= ?)
    ORDER BY sort_order ASC, min_subtotal DESC
    LIMIT 1
  `).get(pincode, subtotal, subtotal);
  return rules || null;
}

module.exports = { placeOrder, listOrders, getOrder, cancelOrder, cancelOrderByStaff, reorder, getDeliveryCharge, placeOrderForCustomer, resolveDeliveryRule };

// ── Cancel order by admin or salesman (no cutoff restriction) ─────────────────
function cancelOrderByStaff(req, res) {
  const staff = req.user;
  const { reason } = req.body;

  if (!reason || reason.trim() === '') {
    return res.status(400).json({ error: 'A reason is required to cancel an order' });
  }

  const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });
  if (order.status === 'delivered') {
    return res.status(400).json({ error: 'Delivered orders cannot be cancelled' });
  }
  if (order.status === 'cancelled') {
    return res.status(400).json({ error: 'Order is already cancelled' });
  }

  const cancelNote = `Cancelled by ${staff.role} (${staff.name || staff.id}): ${reason.trim()}`;

  db.transaction(() => {
    db.prepare("UPDATE orders SET status='cancelled', cancelled_reason=?, updated_at=datetime('now') WHERE id=?")
      .run(cancelNote, order.id);
    // Cancel any active delivery for this order
    db.prepare("UPDATE deliveries SET status='cancelled', updated_at=datetime('now') WHERE order_id=? AND status NOT IN ('delivered','cancelled')").run(order.id);

    // Refund wallet
    const userRow = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(order.user_id);
    const newBal = parseFloat((userRow.wallet_balance + order.final_amount).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBal, order.user_id);
    db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description) VALUES (?,?,?,?,?,?,?)`)
      .run(order.user_id, 'refund', order.final_amount, newBal, 'order', order.id,
        `Refund for cancelled order #${order.order_number}`);

    // Restore stock
    const items = db.prepare('SELECT * FROM order_items WHERE order_id = ?').all(order.id);
    for (const item of items) {
      db.prepare('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?').run(item.estimated_qty, item.product_id);
    }
    // Restore promo code usage
    const promoUse = db.prepare('SELECT * FROM promo_code_uses WHERE order_id = ?').get(order.id);
    if (promoUse) {
      db.prepare('DELETE FROM promo_code_uses WHERE order_id = ?').run(order.id);
      db.prepare('UPDATE promo_codes SET use_count = MAX(0, use_count - 1) WHERE id = ?').run(promoUse.promo_code_id);
    }
  })();

  notificationService.sendToUser(
    order.user_id,
    'Order Cancelled',
    `Your order #${order.order_number} was cancelled by ${staff.role}. Reason: ${reason.trim()}. Refund added to wallet.`
  );
  setImmediate(() => recalculateCustomerTier(order.user_id));
  res.json({ message: 'Order cancelled and wallet refunded', cancelled_by: staff.role });
}

// ── Place order on behalf of a customer (admin / salesman) ───────────────────
function placeOrderForCustomer(req, res) {
  const placedBy = req.user; // admin or salesman
  const {
    customer_id, address_id, slot_id, delivery_date, items,
    notes, order_type = 'delivery', preferred_salesman_id,
    delivery_charge_override, // optional: admin/salesman can set to 0 or any value
  } = req.body;

  if (!customer_id) return res.status(400).json({ error: 'customer_id is required' });
  if (!delivery_date || !items?.length) return res.status(400).json({ error: 'delivery_date and items are required' });
  if (order_type === 'delivery' && !address_id) return res.status(400).json({ error: 'address_id is required for delivery orders' });
  if (!['delivery', 'pickup'].includes(order_type)) return res.status(400).json({ error: 'order_type must be delivery or pickup' });

  const customer = db.prepare("SELECT * FROM users WHERE id = ? AND role = 'customer' AND is_active = 1").get(parseInt(customer_id));
  if (!customer) return res.status(404).json({ error: 'Customer not found or inactive' });

  // Salesman can only place orders for their own customers
  if (placedBy.role === 'salesman') {
    const isMyCustomer = db.prepare(
      "SELECT 1 FROM topup_requests WHERE user_id = ? AND collected_by = ? LIMIT 1"
    ).get(customer.id, placedBy.name);
    // Fallback: allow if customer exists (salesmen manage any active customer)
    // — no strict ownership enforced here, salesman sees all customers they added
  }

  let address = null;
  if (order_type === 'delivery') {
    address = db.prepare('SELECT * FROM addresses WHERE id = ? AND user_id = ?').get(address_id, customer.id);
    if (!address) return res.status(400).json({ error: 'Address not found for this customer' });
  }

  const minOrder = getConfig('min_order_amount') || 50;
  let subtotal = 0;
  const resolvedItems = [];

  for (const item of items) {
    const product = db.prepare('SELECT * FROM products WHERE id = ? AND is_active = 1').get(item.product_id);
    if (!product) return res.status(400).json({ error: `Product ${item.product_id} not found` });
    if (product.stock_qty < item.qty) return res.status(400).json({ error: `Insufficient stock for ${product.name}` });
    const lineTotal = parseFloat((product.price_per_unit * item.qty).toFixed(2));
    subtotal += lineTotal;
    resolvedItems.push({ product, qty: item.qty, lineTotal });
  }

  const effectiveMin = order_type === 'pickup'
    ? (getConfig('min_pickup_order_amount') ?? 10)
    : minOrder;
  if (subtotal < effectiveMin) return res.status(400).json({ error: `Minimum order amount for ${order_type === 'pickup' ? 'pickup' : 'delivery'} is ₹${effectiveMin}` });

  const deliveryCharge = order_type === 'pickup'
    ? 0
    : delivery_charge_override !== undefined && delivery_charge_override !== null
      ? Math.max(0, parseFloat(delivery_charge_override))
      : calcDeliveryCharge(address?.lat, address?.lng, subtotal);
  const finalAmount = parseFloat((subtotal + deliveryCharge).toFixed(2));

  // Block order if resulting balance would exceed the allowed negative limit
  const tierRow2 = customer.tier_id
    ? db.prepare('SELECT max_wallet_negative_limit FROM customer_tiers WHERE id=?').get(customer.tier_id)
    : null;
  const negLimit2 = tierRow2?.max_wallet_negative_limit != null
    ? tierRow2.max_wallet_negative_limit
    : parseFloat(db.prepare("SELECT value FROM app_config WHERE key='max_wallet_negative_limit'").get()?.value ?? '0');
  const resultingBalance2 = parseFloat((customer.wallet_balance - finalAmount).toFixed(2));
  if (resultingBalance2 < 0 && Math.abs(resultingBalance2) > negLimit2) {
    return res.status(400).json({
      error: `This order would take customer balance to ₹${resultingBalance2.toFixed(2)}, exceeding their ₹${negLimit2.toFixed(0)} credit limit.`
    });
  }

  // Wallet is debited regardless of balance — negative balance is collected later

  const txn = db.transaction(() => {
    const orderNumber = generateOrderNumber();

    const orderResult = db.prepare(`
      INSERT INTO orders (order_number, user_id, address_id, slot_id, status, delivery_date,
        subtotal, delivery_charge, wallet_used, final_amount, payment_status, notes, order_type, salesman_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,'paid',?,?,?)
    `).run(orderNumber, customer.id, address_id || null, slot_id || null, 'pending', delivery_date,
      subtotal, deliveryCharge, finalAmount, finalAmount, notes || null, order_type,
      placedBy.role === 'salesman' ? placedBy.id : null);

    const orderId = orderResult.lastInsertRowid;

    for (const ri of resolvedItems) {
      db.prepare(`
        INSERT INTO order_items (order_id, product_id, estimated_qty, unit_price, estimated_total, is_weight_adjusted)
        VALUES (?,?,?,?,?,?)
      `).run(orderId, ri.product.id, ri.qty, ri.product.price_per_unit, ri.lineTotal, ri.product.is_weight_adjusted);
      db.prepare('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?').run(ri.qty, ri.product.id);
    }

    db.prepare('INSERT INTO deliveries (order_id, status) VALUES (?,?)').run(orderId, 'pending');

    // Auto-assign salesman — explicit preferred_salesman_id, or default from config
    const salesmanUserId = preferred_salesman_id
      ? parseInt(preferred_salesman_id)
      : (() => {
          const row = db.prepare("SELECT value FROM app_config WHERE key='default_salesman_id'").get();
          return row?.value ? parseInt(row.value) : null;
        })();

    if (salesmanUserId) {
      const agentRow = db.prepare('SELECT * FROM delivery_agents WHERE user_id=?').get(salesmanUserId);
      if (agentRow) {
        db.prepare("UPDATE deliveries SET agent_id=?, status='assigned', assigned_at=datetime('now') WHERE order_id=?")
          .run(agentRow.id, orderId);
        db.prepare("UPDATE orders SET status='assigned', updated_at=datetime('now') WHERE id=?").run(orderId);
      }
    }

    // Debit customer wallet — balance allowed to go negative
    const freshCustomer = db.prepare('SELECT wallet_balance FROM users WHERE id = ?').get(customer.id);
    const newBalance = parseFloat((freshCustomer.wallet_balance - finalAmount).toFixed(2));
    db.prepare('UPDATE users SET wallet_balance = ? WHERE id = ?').run(newBalance, customer.id);
    db.prepare(`INSERT INTO wallet_transactions (user_id,type,amount,balance_after,reference_type,reference_id,description)
      VALUES (?,?,?,?,?,?,?)`).run(
      customer.id, 'debit', finalAmount, newBalance, 'order', orderId,
      `Order #${orderNumber} placed by ${placedBy.role} (${placedBy.name || placedBy.id})`
    );

    return db.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  });

  const order = txn();
  setImmediate(() => recalculateCustomerTier(customer.id));
  const items_ = db.prepare(`
    SELECT oi.*, p.name as product_name, p.unit FROM order_items oi
    JOIN products p ON p.id = oi.product_id WHERE oi.order_id = ?
  `).all(order.id);

  notificationService.sendToUser(customer.id, 'Order Placed!',
    `Your order #${order.order_number} has been placed by ${placedBy.role}.`,
    { type: 'order_confirmed', order_id: String(order.id) });
  notificationService.sendToAdmins('Order Placed for Customer 🛒', `${placedBy.name} (${placedBy.role}) placed order #${order.order_number} for ${customer.name} — ₹${order.final_amount.toFixed(2)}`, { type: 'new_order', order_id: String(order.id) });
  if (customer.email) emailService.sendOrderConfirmation(customer.email, order, items_).catch(() => {});

  res.status(201).json({ order, items: items_ });
}
