const nodemailer = require('nodemailer');

let transporter;

function getTransporter() {
  if (transporter) return transporter;
  if (!process.env.SMTP_HOST) return null;
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '465'),
    secure: process.env.SMTP_PORT === '465' || !process.env.SMTP_PORT,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  return transporter;
}

async function sendOrderConfirmation(toEmail, order, items) {
  const t = getTransporter();
  if (!t || !toEmail) return;

  const itemRows = items
    .map(i => `<tr><td>${i.product_name}</td><td>${i.estimated_qty} ${i.unit}</td><td>₹${i.unit_price}</td><td>₹${i.estimated_total}</td></tr>`)
    .join('');

  await t.sendMail({
    from: `"${process.env.FROM_NAME || 'HappyKrishi'}" <${process.env.FROM_EMAIL}>`,
    to: toEmail,
    subject: `Order Confirmed — #${order.order_number}`,
    html: `
      <h2>Order Confirmed!</h2>
      <p>Order #: <strong>${order.order_number}</strong></p>
      <p>Delivery: ${order.delivery_date} | Slot: ${order.slot_label || ''}</p>
      <table border="1" cellpadding="6">
        <tr><th>Product</th><th>Qty</th><th>Price</th><th>Total</th></tr>
        ${itemRows}
      </table>
      <p>Subtotal: ₹${order.subtotal} | Delivery: ₹${order.delivery_charge}</p>
      <p><strong>Final Amount: ₹${order.final_amount}</strong></p>
    `,
  }).catch(e => console.error('Email error:', e.message));
}

async function sendWeightAdjustmentReceipt(toEmail, order, adjustments) {
  const t = getTransporter();
  if (!t || !toEmail) return;

  const rows = adjustments
    .map(a => `<tr><td>${a.name}</td><td>${a.estimated_qty}</td><td>${a.actual_qty}</td><td>₹${a.diff > 0 ? '-' : '+'}${Math.abs(a.diff_amount).toFixed(2)}</td></tr>`)
    .join('');

  await t.sendMail({
    from: `"${process.env.FROM_NAME || 'HappyKrishi'}" <${process.env.FROM_EMAIL}>`,
    to: toEmail,
    subject: `Weight Adjustment — Order #${order.order_number}`,
    html: `
      <h2>Weight Adjustment Receipt</h2>
      <p>Order #: <strong>${order.order_number}</strong></p>
      <table border="1" cellpadding="6">
        <tr><th>Product</th><th>Est. Qty</th><th>Actual Qty</th><th>Adjustment</th></tr>
        ${rows}
      </table>
      <p>Your wallet has been updated accordingly.</p>
    `,
  }).catch(e => console.error('Email error:', e.message));
}

async function sendOtpEmail(toEmail, code, name) {
  if (!process.env.SMTP_USER) {
    console.log(`\n[DEV EMAIL OTP] To: ${toEmail}  Code: ${code}\n`);
    return true;
  }
  const t = getTransporter();
  if (!t) return false;
  try {
    await t.sendMail({
      from: `"${process.env.FROM_NAME || 'HappyKrishi'}" <${process.env.FROM_EMAIL || process.env.SMTP_USER}>`,
      to: toEmail,
      subject: `Your HappyKrishi OTP: ${code}`,
      html: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto">
          <h2 style="color:#2E7D32">HappyKrishi OTP</h2>
          <p>Hi ${name || 'there'},</p>
          <p>Your one-time code is:</p>
          <div style="font-size:36px;font-weight:bold;letter-spacing:10px;
               background:#E8F5E9;padding:20px;border-radius:8px;
               text-align:center;color:#1B5E20">${code}</div>
          <p style="color:#888;margin-top:16px">Valid for 10 minutes. Do not share.</p>
        </div>
      `,
    });
    console.log(`[Email OTP] Sent to ${toEmail}`);
    return true;
  } catch (err) {
    console.error('[Email OTP] Failed:', err.message);
    return false;
  }
}

module.exports = { sendOrderConfirmation, sendWeightAdjustmentReceipt, sendOtpEmail };
