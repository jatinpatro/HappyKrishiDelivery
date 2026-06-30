import '../theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared order summary card used across customer, salesman and admin order lists.
///
/// Pass either a [Map<String,dynamic>] (raw API response) or individual fields.
/// Shows: order number, status badge, customer name+phone, delivery date/slot,
/// address, coupon discount (original ~~price~~ → discounted), items preview.
class OrderSummaryCard extends StatelessWidget {
  // Required
  final int orderId;
  final String orderNumber;
  final String status;
  final double finalAmount;
  final double discountAmount;
  final String? couponCode;

  // Optional context
  final String? customerName;
  final String? customerPhone;
  final double? customerWalletBalance;
  final String? deliveryDate;
  final String? slotLabel;
  final String? addressLine;
  final String? city;
  final String? orderType;
  final String? salesmanName;
  final String? salesmanPhone;
  final List<Map<String, dynamic>>? items;
  final String? deliveryCode;
  final bool deliveryConfirmed; // for salesman view item preview

  // Behaviour
  final VoidCallback? onTap;
  final List<Widget>? actions;     // buttons at the bottom (e.g. Track, Confirm)
  final bool showCustomerContact;  // show call/WA buttons
  final Color? borderColor;

  const OrderSummaryCard({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.finalAmount,
    this.discountAmount = 0,
    this.couponCode,
    this.customerName,
    this.customerPhone,
    this.customerWalletBalance,
    this.deliveryDate,
    this.slotLabel,
    this.addressLine,
    this.city,
    this.orderType,
    this.salesmanName,
    this.salesmanPhone,
    this.items,
    this.onTap,
    this.actions,
    this.showCustomerContact = false,
    this.borderColor,
    this.deliveryCode,
    this.deliveryConfirmed = false,
  });

  // Smart amount formatter — shows decimals only when needed
  static String _amt(double v) => v == v.truncateToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');

  static Color _statusColor(String s) => switch (s) {
    'pending'   => Colors.orange,
    'confirmed' => Colors.teal,
    'assigned'  || 'dispatched' => Colors.blue,
    'delivered' => AppColors.primary,
    'cancelled' => Colors.red,
    _ => Colors.grey,
  };

  static IconData _statusIcon(String s) => switch (s) {
    'pending'   => Icons.hourglass_empty,
    'confirmed' => Icons.check_circle_outline,
    'assigned'  => Icons.person_pin_outlined,
    'dispatched'=> Icons.local_shipping_outlined,
    'delivered' => Icons.done_all,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final isPickup     = orderType == 'pickup';
    final statusColor  = _statusColor(status);
    final originalAmt  = finalAmount + discountAmount;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor ?? statusColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(children: [
          // ── Coloured status bar ──────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(children: [
              Icon(_statusIcon(status), size: 14, color: statusColor),
              const SizedBox(width: 6),
              Text(status.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: statusColor, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isPickup ? Colors.teal.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isPickup ? Colors.teal.shade200 : Colors.blue.shade200),
                ),
                child: Text(isPickup ? '🏪 Pickup' : '🚚 Delivery',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                        color: isPickup ? Colors.teal.shade700 : Colors.blue.shade700)),
              ),
              const Spacer(),
              // Amount — strikethrough original if coupon applied
              if (discountAmount > 0) ...[
                Text('₹${_amt(originalAmt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 4),
              ],
              Text('₹${_amt(finalAmount)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: statusColor)),
            ]),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Order # + customer name
              Row(children: [
                const Icon(Icons.receipt_long_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 5),
                Text('#$orderNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (customerWalletBalance != null && customerWalletBalance! < 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50, borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.account_balance_wallet, size: 11, color: Colors.red.shade700),
                      const SizedBox(width: 3),
                      Text('₹${customerWalletBalance!.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                              color: Colors.red.shade700)),
                    ]),
                  ),
                if (customerName != null) ...[
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(customerName!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ]),
              const SizedBox(height: 5),

              // Phone + date + call/WA
              Row(children: [
                if (customerPhone != null) ...[
                  const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text('+91 $customerPhone',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (showCustomerContact) ...[
                    const SizedBox(width: 4),
                    _ContactBtn(phone: customerPhone!, isWhatsApp: false),
                    _ContactBtn(phone: customerPhone!, isWhatsApp: true),
                  ],
                ],
                const Spacer(),
                if (deliveryDate != null) ...[
                  const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(deliveryDate!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ]),

              // Slot
              if (slotLabel != null) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.schedule_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(slotLabel!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ],

              // Address
              if (!isPickup && addressLine != null) ...[
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Expanded(child: Text('$addressLine, ${city ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],

              // Coupon
              if (couponCode != null && discountAmount > 0) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.discount_outlined, size: 13, color: Colors.green),
                  const SizedBox(width: 5),
                  Text(couponCode!,
                      style: const TextStyle(fontSize: 12, color: Colors.green,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(width: 6),
                  Text('-₹${_amt(discountAmount)} off',
                      style: const TextStyle(fontSize: 11, color: Colors.green)),
                ]),
              ],

              // Salesman
              if (salesmanName != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.badge_outlined, size: 13, color: Colors.indigo),
                  const SizedBox(width: 5),
                  Text(salesmanName!,
                      style: const TextStyle(fontSize: 12, color: Colors.indigo,
                          fontWeight: FontWeight.w500)),
                  if (salesmanPhone != null) ...[
                    const SizedBox(width: 4),
                    Text('+91 $salesmanPhone',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ]),
              ],

              // Items preview (salesman view)
              if (items != null && items!.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...items!.take(3).map((i) => Text(
                  '• ${i['product_name']}  ${(i['estimated_qty'] as num).toStringAsFixed(2)} ${i['unit'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                )),
                if (items!.length > 3)
                  Text('+${items!.length - 3} more',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],

              // Delivery code — shown to customer for active orders
              if (deliveryCode != null &&
                  !['delivered', 'cancelled', 'pending', 'confirmed'].contains(status)) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: deliveryConfirmed ? Colors.green.shade50 : const Color(0xFFEAF2EA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: deliveryConfirmed
                          ? Colors.green.shade400
                          : AppColors.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      deliveryConfirmed ? Icons.verified_outlined : Icons.lock_outline,
                      color: AppColors.primary, size: 16,
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        deliveryConfirmed ? 'Delivery Confirmed' : 'Your Delivery Code',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark),
                      ),
                      Text(
                        deliveryCode!,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                            letterSpacing: 5, color: AppColors.primary),
                      ),
                    ]),
                    const Spacer(),
                    if (deliveryConfirmed)
                      const Icon(Icons.check_circle, color: Colors.green, size: 24),
                  ]),
                ),
                if (!deliveryConfirmed)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Share this code with your salesman on arrival',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
              ],

              // Actions
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...actions!,
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Inline contact button ─────────────────────────────────────────────────────

class _ContactBtn extends StatelessWidget {
  final String phone;
  final bool isWhatsApp;
  const _ContactBtn({required this.phone, required this.isWhatsApp});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      final uri = isWhatsApp
          ? Uri.parse('https://wa.me/91$phone')
          : Uri.parse('tel:+91$phone');
      launchUrl(uri, mode: LaunchMode.externalApplication);
    },
    child: Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isWhatsApp ? const Color(0xFF25D366).withValues(alpha: 0.1)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        isWhatsApp ? Icons.message_outlined : Icons.phone_outlined,
        size: 14,
        color: isWhatsApp ? const Color(0xFF25D366) : Colors.blue,
      ),
    ),
  );
}
