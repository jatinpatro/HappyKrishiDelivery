import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../info/app_info_screen.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/location_picker_screen.dart';

// Lightweight all-products provider for the pincode rules banner
final _allProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/api/products', queryParameters: {'limit': 200});
  return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
});

final checkoutAddressesProvider = FutureProvider.autoDispose<List<Address>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.addresses);
  return (res.data['addresses'] as List).map((e) => Address.fromJson(e)).toList();
});

// Pincode rules for a specific pincode (null = no custom rules / not checked yet)
final pincodeRulesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, pincode) async {
  if (pincode.isEmpty) return null;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.checkPincode, queryParameters: {'pincode': pincode});
  final data = res.data as Map<String, dynamic>;
  // Only return rules if this is a custom-whitelisted pincode (was outside normal radius)
  final hasRules = data['min_order_amount'] != null ||
      data['allowed_product_ids'] != null ||
      data['custom_delivery_charge'] != null;
  return hasRules ? data : null;
});

// Fetch slots by type: 'delivery' or 'pickup'
final slotsProvider = FutureProvider.autoDispose.family<List<DeliverySlot>, String>((ref, type) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get('/api/delivery-slots', queryParameters: {'type': type});
    return (res.data['slots'] as List).map((e) => DeliverySlot.fromJson(e)).toList();
  } catch (_) {
    if (type == 'pickup') {
      return const [
        DeliverySlot(id: 4, label: 'Pickup Morning (8 AM – 12 PM)', startTime: '08:00', endTime: '12:00'),
        DeliverySlot(id: 5, label: 'Pickup Afternoon (2 PM – 6 PM)', startTime: '14:00', endTime: '18:00'),
      ];
    }
    return const [
      DeliverySlot(id: 1, label: 'Morning (7–10 AM)', startTime: '07:00', endTime: '10:00'),
      DeliverySlot(id: 2, label: 'Afternoon (12–3 PM)', startTime: '12:00', endTime: '15:00'),
      DeliverySlot(id: 3, label: 'Evening (5–8 PM)', startTime: '17:00', endTime: '20:00'),
    ];
  }
});

final salesmenListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanList);
  return List<Map<String, dynamic>>.from(res.data['salesmen']);
});

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _orderType = 'delivery';
  int? _selectedAddressId;
  String _selectedAddressPincode = '';   // for pincode rules lookup
  int? _selectedSlotId;
  String _deliveryDate = _nextDay();
  double? _deliveryCharge;
  bool _fetchingCharge = false;
  bool _deliveryBlocked = false;
  String? _blockedMessage;
  bool _loading = false;
  bool _showAddAddressForm = false;
  int? _selectedSalesmanId;

  // Promo coupon state
  final _couponCtrl   = TextEditingController();
  bool _showCouponField = false;
  String? _appliedCoupon;
  double _couponDiscount = 0;
  String? _couponLabel;
  bool _checkingCoupon = false;
  String? _couponError;
  // Per-item discount breakdown: product_id → {discount, discounted_line_total}
  Map<int, Map<String, dynamic>> _itemDiscounts = {};

  // New address form controllers
  final _labelCtrl = TextEditingController(text: 'Home');
  final _lineCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  // Pincode validation state
  bool _checkingPincode = false;
  bool? _pincodeDeliverable;   // null = unchecked, true = ok, false = out of range
  String _pincodeMsg = '';
  String? _lastCheckedPincode;
  double? _pincodeLat;
  double? _pincodeLng;
  double? _addrLat;
  double? _addrLng;

  static String _nextDay() {
    final d = DateTime.now().add(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _fetchDeliveryCharge(int addressId, double subtotal) async {
    setState(() { _fetchingCharge = true; _deliveryCharge = null; _deliveryBlocked = false; _blockedMessage = null; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(
        Endpoints.deliveryCharge,
        queryParameters: {'address_id': addressId, 'subtotal': subtotal},
      );
      if (mounted) {
        final data = res.data as Map<String, dynamic>;
        final blocked = data['blocked'] == true;
        setState(() {
          _deliveryBlocked = blocked;
          _blockedMessage = data['blocked_message'] as String?;
          _deliveryCharge = blocked ? null : (data['delivery_charge'] as num?)?.toDouble();
        });
      }
    } catch (_) {
      if (mounted) setState(() { _deliveryCharge = 30; _deliveryBlocked = false; });
    } finally {
      if (mounted) setState(() => _fetchingCharge = false);
    }
  }

  Future<void> _checkPincode(String pincode) async {
    if (pincode.length != 6) {
      setState(() { _pincodeDeliverable = null; _pincodeMsg = ''; });
      return;
    }
    if (pincode == _lastCheckedPincode) return;
    setState(() { _checkingPincode = true; _pincodeDeliverable = null; _pincodeMsg = ''; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(Endpoints.checkPincode, queryParameters: {'pincode': pincode});
      final data = res.data as Map<String, dynamic>;
      final deliverable = data['deliverable'] as bool?;
      final distKm = data['distance_km'] as num?;
      final district = data['district'] as String? ?? '';
      final pLat = (data['lat'] as num?)?.toDouble();
      final pLng = (data['lng'] as num?)?.toDouble();
      if (mounted) setState(() {
        _lastCheckedPincode = pincode;
        _checkingPincode = false;
        _pincodeDeliverable = deliverable;
        _pincodeLat = pLat;
        _pincodeLng = pLng;
        _pincodeMsg = deliverable == true
            ? '✓ Deliverable${district.isNotEmpty ? ' — $district' : ''}${distKm != null ? ' (${distKm}km)' : ''}'
            : deliverable == false
                ? '✗ Outside 20 km delivery area${distKm != null ? ' ($distKm km away)' : ''}'
                : 'Could not verify — you can still try';
      });
    } catch (_) {
      if (mounted) setState(() {
        _checkingPincode = false;
        _pincodeDeliverable = null;
        _pincodeMsg = 'Could not verify pincode';
      });
    }
  }

  Future<void> _addAddress() async {
    if (_lineCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
      _show('Address line and city are required');
      return;
    }
    final pincode = _pincodeCtrl.text.trim();
    if (pincode.length == 6 && _pincodeDeliverable == null) {
      // Not yet checked — check now before saving
      await _checkPincode(pincode);
    }
    if (_pincodeDeliverable == false) {
      _show(_pincodeMsg.isNotEmpty ? _pincodeMsg : 'This pincode is outside our 20 km delivery area');
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.addresses, data: {
        'label': _labelCtrl.text.trim(),
        'address_line': _lineCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'pincode': _pincodeCtrl.text.trim().isEmpty ? null : _pincodeCtrl.text.trim(),
        if (_addrLat != null) 'lat': _addrLat,
        if (_addrLng != null) 'lng': _addrLng,
      });
      final newAddress = Address.fromJson(res.data['address']);
      ref.invalidate(checkoutAddressesProvider);
      setState(() {
        _showAddAddressForm = false;
        _selectedAddressId = newAddress.id;
        _selectedAddressPincode = newAddress.pincode ?? '';
        _lineCtrl.clear();
        _cityCtrl.clear();
        _pincodeCtrl.clear();
        _labelCtrl.text = 'Home';
        _pincodeDeliverable = null;
        _pincodeMsg = '';
        _lastCheckedPincode = null;
        _pincodeLat = null;
        _pincodeLng = null;
        _addrLat = null;
        _addrLng = null;
      });
      _fetchDeliveryCharge(newAddress.id, ref.read(cartSubtotalProvider));
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to add address');
    }
  }

  Future<void> _openCouponSheet(BuildContext context) async {
    _couponCtrl.clear();
    setState(() => _couponError = null);

    // Load available codes with current subtotal for sorting
    List<Map<String, dynamic>> availableCodes = [];
    try {
      final subtotal = ref.read(cartSubtotalProvider);
      final res = await ref.read(dioProvider).get(Endpoints.promoAvailable,
          queryParameters: {'subtotal': subtotal});
      availableCodes = List<Map<String, dynamic>>.from(res.data['codes'] ?? []);
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          // Read from state — updated via setSt after _validateCoupon
          final String? sheetError = _couponError;
          bool applying = _checkingCoupon;

          Future<void> applyCode(String code) async {
            if (code.isEmpty) return;
            setSt(() {});
            _couponCtrl.text = code;
            await _validateCoupon();
            setSt(() {}); // refresh to show _couponError / _checkingCoupon
            if (_appliedCoupon != null && ctx.mounted) Navigator.pop(ctx);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.discount_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Promo Codes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ]),

              // ── Available codes list ────────────────────────────────────
              if (availableCodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Available for you',
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                ...availableCodes.map((c) {
                  final subtotal = ref.read(cartSubtotalProvider);
                  // Backend sends computed_discount and can_apply based on subtotal
                  final canApply = c['can_apply'] as bool? ?? (subtotal >= ((c['min_order_amount'] as num?)?.toDouble() ?? 0));
                  final minAmt = (c['min_order_amount'] as num?)?.toDouble() ?? 0;
                  final computedDiscount = (c['computed_discount'] as num?)?.toDouble() ?? 0;
                  return GestureDetector(
                    onTap: canApply && !applying ? () => applyCode(c['code'] as String) : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: canApply ? AppColors.background : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: canApply ? AppColors.primary.withValues(alpha: 0.4) : Colors.grey.shade300),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: canApply ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: canApply ? AppColors.primary : Colors.grey.shade300),
                              ),
                              child: Text(c['code'] as String,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 12,
                                      letterSpacing: 1.5,
                                      color: canApply ? AppColors.primary : Colors.grey)),
                            ),
                            if (canApply && computedDiscount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade300)),
                                child: Text('Save ₹${_amt(computedDiscount)}',
                                    style: TextStyle(fontSize: 10, color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                            if (!canApply) ...[
                              const SizedBox(width: 8),
                              Text('Min ₹${minAmt.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
                            ],
                          ]),
                          const SizedBox(height: 4),
                          Text(c['description'] as String? ?? '',
                              style: TextStyle(fontSize: 12, color: canApply ? Colors.black87 : Colors.grey)),
                          if (c['label'] != null && c['label'] != c['code'])
                            Text(c['label'] as String,
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ])),
                        if (canApply)
                          applying
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ]),
                    ),
                  );
                }),
                const Divider(height: 20),
              ],

              // ── Error message ───────────────────────────────────────────
              if (sheetError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Text(sheetError!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                  ]),
                ),

              if (availableCodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text(
                    'No promo codes available for you right now.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    textAlign: TextAlign.center,
                  )),
                ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _validateCoupon() async {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _checkingCoupon = true; _couponError = null; });
    try {
      final subtotal = ref.read(cartSubtotalProvider);
      final cart = ref.read(cartProvider);
      final res = await ref.read(dioProvider).post(Endpoints.promoValidate,
          data: {
            'code': code,
            'subtotal': subtotal,
            'product_ids': cart.map((i) => i.product.id).toList(),
            'cart_items': cart.map((i) => {
              'product_id': i.product.id,
              'qty': i.qty,
              'line_total': i.product.pricePerUnit * i.qty,
            }).toList(),
          });
      setState(() {
        _appliedCoupon  = code;
        _couponDiscount = (res.data['discount_amount'] as num).toDouble();
        _couponLabel    = res.data['label'] as String?;
        _couponError    = null;
        _showCouponField = false;
        // Build per-item discount map
        final breakdown = res.data['item_breakdown'] as List? ?? [];
        _itemDiscounts = {
          for (final item in breakdown)
            (item['product_id'] as num).toInt(): {
              'discount': (item['discount'] as num).toDouble(),
              'discounted_line_total': (item['discounted_line_total'] as num).toDouble(),
              'is_qualifying': item['is_qualifying'] as bool? ?? false,
            },
        };
      });
    } on DioException catch (e) {
      setState(() {
        _appliedCoupon  = null;
        _couponDiscount = 0;
        _couponError    = e.response?.data['error'] ?? 'Invalid coupon';
      });
    } finally {
      if (mounted) setState(() => _checkingCoupon = false);
    }
  }

  // Show decimals only when needed: 47.5 → "47.5", 50.0 → "50"
  static String _amt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');

  void _removeCoupon() {    setState(() {
      _appliedCoupon  = null;
      _couponDiscount = 0;
      _couponLabel    = null;
      _couponError    = null;
      _itemDiscounts  = {};
      _couponCtrl.clear();
    });
  }

  Future<void> _placeOrder() async {
    final cart    = ref.read(cartProvider);
    final user    = ref.read(authStateProvider).user;
    final balance = user?.walletBalance ?? 0;

    if (_orderType == 'delivery' && _selectedAddressId == null) {
      _show('Please select a delivery address'); return;
    }
    if (_orderType == 'pickup' && _selectedSalesmanId == null) {
      _show('Please select a salesman for pickup'); return;
    }
    if (_selectedSlotId == null) { _show('Please select a ${_orderType == 'pickup' ? 'pickup' : 'delivery'} slot'); return; }
    if (_orderType == 'delivery' && _deliveryCharge == null) {
      _show('Delivery charge is being calculated, please wait'); return;
    }

    // Block if wallet already negative
    if (balance < 0) {
      _show('Your wallet balance is ₹${balance.toStringAsFixed(2)}. Please top up before placing a new order.');
      return;
    }

    // Warn if this order will push balance negative
    final total = ref.read(cartSubtotalProvider) + (_deliveryCharge ?? 0) - _couponDiscount;
    if (balance < total) {
      final balanceAfter = balance - total;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Low Balance'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your current balance is ₹${balance.toStringAsFixed(2)}.'),
            const SizedBox(height: 6),
            Text('After this order (₹${total.toStringAsFixed(2)}), '
                'your balance will be ₹${balanceAfter.toStringAsFixed(2)}.',
                style: TextStyle(
                    color: balanceAfter < 0 ? Colors.red : Colors.black87)),
            const SizedBox(height: 10),
            const Text('You can still place the order — the outstanding amount '
                'will be collected by your salesman.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Place Anyway')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.orders, data: {
        if (_orderType == 'delivery') 'address_id': _selectedAddressId,
        'slot_id': _selectedSlotId,
        'delivery_date': _deliveryDate,
        'order_type': _orderType,
        if (_orderType == 'pickup' && _selectedSalesmanId != null)
          'preferred_salesman_id': _selectedSalesmanId,
        'items': cart.map((i) => {'product_id': i.product.id, 'qty': i.qty}).toList(),
        if (_appliedCoupon != null) 'coupon_code': _appliedCoupon,
      });
      ref.read(cartProvider.notifier).clear();
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_orderType == 'pickup'
              ? 'Pickup order placed! We\'ll have it ready for you 🎉'
              : 'Order placed successfully! 🎉'),
          backgroundColor: AppColors.primary,
        ));
        context.go('/orders');
      }
    } on DioException catch (e) {
      if (mounted) _show(e.response?.data['error'] ?? 'Failed to place order');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final addresses = ref.watch(checkoutAddressesProvider);
    final slots = ref.watch(slotsProvider(_orderType));
    final user = ref.watch(authStateProvider).user;
    final charge = _deliveryCharge ?? 0;
    final total = subtotal + charge - _couponDiscount;
    // Re-fetch delivery charge whenever subtotal changes (tiers depend on it)
    ref.listen<double>(cartSubtotalProvider, (prev, next) {
      if (_orderType == 'delivery' && _selectedAddressId != null && prev != next) {
        _fetchDeliveryCharge(_selectedAddressId!, next);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Order Type Toggle ────────────────────────────────────────────────
          _OrderTypeToggle(
            selected: _orderType,
            onChanged: (type) => setState(() {
              _orderType = type;
              _selectedSlotId = null;
              _selectedSalesmanId = null;
              // Pickup can be today; delivery is minimum tomorrow
              _deliveryDate = type == 'pickup' ? _today() : _nextDay();
              if (type == 'pickup') {
                _deliveryCharge = 0;
                _deliveryBlocked = false;
                _blockedMessage = null;
                _selectedAddressId = null;
              } else {
                _deliveryCharge = null;
                _deliveryBlocked = false;
                _blockedMessage = null;
              }
            }),
          ),
          const SizedBox(height: 8),

          // ── Delivery Address (only for delivery) ────────────────────────────
          if (_orderType == 'delivery') ...[
          _SectionHeader(title: 'Delivery Address'),
          addresses.when(
            data: (addrs) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...addrs.map((a) {
                final selected = _selectedAddressId == a.id;
                return Card(
                  color: selected ? const Color(0xFFEAF2EA) : null,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _selectedAddressId = a.id;
                        _selectedAddressPincode = a.pincode ?? '';
                      });
                      _fetchDeliveryCharge(a.id, subtotal);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selected ? AppColors.primary : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.label, style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selected ? AppColors.primary : null,
                          )),
                          Text('${a.addressLine}, ${a.city}${a.pincode != null ? ' - ${a.pincode}' : ''}',
                              style: const TextStyle(fontSize: 13)),
                        ])),
                        if (a.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('Default',
                                style: TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                      ]),
                    ),
                  ),
                );
              }),

              // Add new address inline
              if (_showAddAddressForm) ...[
                Card(
                  color: Colors.grey.shade50,
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      Row(children: [
                        const Text('New Address', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _showAddAddressForm = false),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: 'Label', isDense: true, border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _pincodeCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            onChanged: (v) {
                              if (v.length == 6) {
                                _checkPincode(v);
                              } else {
                                setState(() { _pincodeDeliverable = null; _pincodeMsg = ''; });
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Pincode *',
                              isDense: true,
                              counterText: '',
                              border: const OutlineInputBorder(),
                              suffixIcon: _checkingPincode
                                  ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : _pincodeDeliverable == true
                                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                      : _pincodeDeliverable == false
                                          ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                                          : null,
                            ),
                          ),
                        ),
                      ]),
                      if (_pincodeMsg.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _pincodeMsg,
                          style: TextStyle(
                            fontSize: 11,
                            color: _pincodeDeliverable == true ? Colors.green.shade700
                                : _pincodeDeliverable == false ? Colors.red
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                      if (_pincodeDeliverable == false) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => context.push(
                            '/request-delivery?pincode=${_pincodeCtrl.text.trim()}'
                            '${_pincodeMsg.contains('km') ? '&distance_km=${RegExp(r"[\d.]+km").firstMatch(_pincodeMsg)?.group(0)?.replaceAll('km', '') ?? ''}' : ''}',
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(children: [
                              Icon(Icons.local_shipping_outlined, color: Colors.orange.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                'Outside our delivery area — tap to request special delivery',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                              )),
                              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.orange.shade600),
                            ]),
                          ),
                        ),
                      ],
                      // Pin exact location after pincode verified
                      if (_pincodeDeliverable == true && _pincodeLat != null) ...[
                        const SizedBox(height: 8),
                        if (_addrLat != null && _addrLng != null)
                          Row(children: [
                            const Icon(Icons.location_pin, size: 15, color: AppColors.primary),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('Location pinned',
                                style: TextStyle(fontSize: 12, color: AppColors.primary,
                                    fontWeight: FontWeight.w500))),
                            TextButton(
                              onPressed: () async {
                                final picked = await Navigator.push<LatLng>(
                                  context,
                                  MaterialPageRoute(builder: (_) => LocationPickerScreen(
                                    initialCenter: LatLng(_pincodeLat!, _pincodeLng!),
                                    existingPin: LatLng(_addrLat!, _addrLng!),
                                  )),
                                );
                                if (picked != null && mounted) {
                                  setState(() { _addrLat = picked.latitude; _addrLng = picked.longitude; });
                                }
                              },
                              style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                              child: const Text('Change', style: TextStyle(fontSize: 12)),
                            ),
                          ])
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.pin_drop_outlined, size: 15),
                              label: const Text('Pin your exact location'),
                              onPressed: () async {
                                final picked = await Navigator.push<LatLng>(
                                  context,
                                  MaterialPageRoute(builder: (_) => LocationPickerScreen(
                                    initialCenter: LatLng(_pincodeLat!, _pincodeLng!),
                                  )),
                                );
                                if (picked != null && mounted) {
                                  setState(() { _addrLat = picked.latitude; _addrLng = picked.longitude; });
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 8),
                      TextField(controller: _lineCtrl, decoration: const InputDecoration(labelText: 'Address Line *', isDense: true, border: OutlineInputBorder())),
                      const SizedBox(height: 8),
                      TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'City *', isDense: true, border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(onPressed: _addAddress, child: const Text('Save & Use This Address')),
                      ),
                    ]),
                  ),
                ),
              ] else
                TextButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add New Address'),
                  onPressed: () => setState(() => _showAddAddressForm = true),
                ),
            ]),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              logError('checkout', e);
              return Column(children: [
                Text(friendlyError(e)),
                TextButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add Address'),
                  onPressed: () => setState(() => _showAddAddressForm = true),
                ),
              ]);
            },
          ),
          const Divider(height: 32),
          ], // end if (delivery)

          // ── Pickup Info Card (only for pickup) ─────────────────────────────
          if (_orderType == 'pickup') ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Consumer(builder: (_, ref, __) {
                final info = ref.watch(appInfoProvider);
                return info.when(
                  data: (d) {
                    final pickup = d['pickup'] as Map<String, dynamic>? ?? {};
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.store, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Pickup Location', style: TextStyle(
                            fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ]),
                      const SizedBox(height: 8),
                      Text(pickup['name'] as String? ?? 'HappyKrishi Farm',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if ((pickup['address'] as String? ?? '').isNotEmpty)
                        Text(pickup['address'] as String,
                            style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      if ((pickup['working_hours'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(pickup['working_hours'] as String,
                                style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ]),
                        ),
                      const SizedBox(height: 8),
                      const Row(children: [
                        Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 16),
                        SizedBox(width: 6),
                        Text('No delivery charge — FREE pickup!',
                            style: TextStyle(color: AppColors.primary,
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ]);
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (_, e) => const Text('Pickup at farm'),
                );
              }),
            ),
            const SizedBox(height: 16),

          // ── Pickup Salesman Picker ─────────────────────────────────────
            _SectionHeader(title: 'Select Salesman *'),
            Consumer(builder: (_, ref, __) {
              final salesmen = ref.watch(salesmenListProvider);
              return salesmen.when(
                data: (list) => list.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text(
                          'No salesmen available. Please contact admin.',
                          style: TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text(
                          'Choose the salesman who will hand over your order at the farm.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: list.map((s) {
                            final sid = s['id'] as int;
                            final selected = _selectedSalesmanId == sid;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedSalesmanId = sid),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.teal.shade600 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: selected ? Colors.teal.shade600 : Colors.grey.shade300),
                                ),
                                child: Text(
                                  s['name'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_selectedSalesmanId == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('⚠ Please select a salesman to proceed.',
                                style: TextStyle(fontSize: 12, color: Colors.red)),
                          ),
                      ]),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
              );
            }),
            const Divider(height: 24),
          ],

          // ── Delivery Date & Slot ────────────────────────────────────────────
          _SectionHeader(title: _orderType == 'pickup' ? 'Pickup Date & Time' : 'Delivery Date & Slot'),

          // Date picker row
          GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(_deliveryDate),
                firstDate: _orderType == 'pickup' ? now : now.add(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 14)),
                helpText: 'Select Delivery Date',
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(primary: AppColors.primary),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() {
                  _deliveryDate =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(12),
                color: AppColors.background,
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Delivery Date',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    _formatDisplayDate(_deliveryDate),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.primary),
                  ),
                ]),
                const Spacer(),
                const Text('Change', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                const Icon(Icons.chevron_right, color: AppColors.primary),
              ]),
            ),
          ),
          slots.when(
            data: (slts) => Column(children: slts.map((s) {
              final selected = _selectedSlotId == s.id;
              return Card(
                color: selected ? const Color(0xFFEAF2EA) : null,
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedSlotId = s.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selected ? AppColors.primary : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.label,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? AppColors.primary : null,
                          ))),
                      Text('${s.startTime} – ${s.endTime}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                  ),
                ),
              );
            }).toList()),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              logError('checkout', e);
              return Text(friendlyError(e));
            },
          ),
          const Divider(height: 32),

          // ── Custom pincode restrictions banner ──────────────────────────────
          if (_orderType == 'delivery' && _selectedAddressPincode.isNotEmpty)
            _PincodeRulesBanner(pincode: _selectedAddressPincode),

          // ── Order Summary ───────────────────────────────────────────────────
          DeliveryInfoBanner(
            subtotal: subtotal,
            fetchedCharge: (_orderType == 'delivery' && !_fetchingCharge && !_deliveryBlocked && _selectedAddressId != null)
                ? _deliveryCharge
                : null,
          ),

          // ── Promo / Coupon Code ────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _appliedCoupon == null
                ? () => _openCouponSheet(context)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _appliedCoupon != null ? Colors.green.shade50 : AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _appliedCoupon != null ? Colors.green.shade300 : Colors.grey.shade300,
                ),
              ),
              child: Row(children: [
                Icon(Icons.discount_outlined, size: 18,
                    color: _appliedCoupon != null ? Colors.green : AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _appliedCoupon != null
                        ? '${_couponLabel ?? _appliedCoupon} — saving ₹${_amt(_couponDiscount)}'
                        : 'Have a promo code? Tap to enter',
                    style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13,
                      color: _appliedCoupon != null ? Colors.green.shade700 : AppColors.primary,
                    ),
                  ),
                ),
                if (_appliedCoupon != null)
                  GestureDetector(
                    onTap: _removeCoupon,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.close, size: 14, color: Colors.green),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          _SectionHeader(title: 'Order Summary'),
          ...cart.map((i) {
            final lineTotal = i.product.pricePerUnit * i.qty;
            final itemInfo = _itemDiscounts[i.product.id];
            final itemDiscount = itemInfo?['discount'] as double? ?? 0;
            final discountedLine = itemInfo?['discounted_line_total'] as double? ?? lineTotal;
            final isQualifying = itemInfo?['is_qualifying'] as bool? ?? false;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text('${i.product.name} × ${i.qty.toStringAsFixed(2)} ${i.product.unit}',
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                if (itemDiscount > 0) ...[
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹${lineTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey,
                            decoration: TextDecoration.lineThrough)),
                    Text('₹${_amt(discountedLine)}',
                        style: const TextStyle(fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    Text('-₹${_amt(itemDiscount)}',
                        style: const TextStyle(fontSize: 10, color: Colors.green)),
                  ]),
                ] else
                  Text('₹${lineTotal.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isQualifying ? null : Colors.black54)),
              ]),
            );
          }),
          const Divider(height: 16),

          // Subtotal
          _SummaryRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),

          // Delivery charge
          if (_orderType == 'pickup')
            const _SummaryRow('Pickup Charge', 'FREE 🎉', valueColor: Colors.green)
          else if (_selectedAddressId == null)
            const _SummaryRow('Delivery Charge', 'Select address first', valueColor: Colors.grey)
          else if (_fetchingCharge)
            const _SummaryRow('Delivery Charge', 'Calculating...', valueColor: Colors.grey)
          else if (_deliveryBlocked)
            _SummaryRow('Delivery Charge', _blockedMessage ?? 'Not available', valueColor: Colors.red)
          else if (_deliveryCharge == 0)
            const _SummaryRow('Delivery Charge', 'FREE 🎉', valueColor: Colors.green)
          else
            _SummaryRow('Delivery Charge', '₹${_deliveryCharge!.toStringAsFixed(0)}'),

          // ── Promo coupon entry ────────────────────────────────────────────
          // Discount row (shown when coupon applied)
          if (_appliedCoupon != null)
            _SummaryRow('Discount (${_appliedCoupon})', '-₹${_amt(_couponDiscount)}',
                valueColor: Colors.green),

          const Divider(height: 12),
          _SummaryRow('Total', '₹${total.toStringAsFixed(2)}', bold: true),
          const SizedBox(height: 6),
          _SummaryRow(
            'Wallet Balance',
            '₹${user?.walletBalance.toStringAsFixed(2) ?? '0'}',
            valueColor: (user?.walletBalance ?? 0) < 0
                ? Colors.red
                : (user?.walletBalance ?? 0) >= total
                    ? Colors.green
                    : Colors.orange,
          ),
          if ((user?.walletBalance ?? 0) < 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Builder(builder: (ctx) {
                final isRestricted = user?.tierName == 'Restricted';
                final shortfall = user!.walletBalance.abs();
                final bgColor = isRestricted ? const Color(0xFFFFF0F0) : const Color(0xFFFFF8E1);
                final borderColor = isRestricted ? Colors.red.shade300 : Colors.orange.shade300;
                final iconColor = isRestricted ? Colors.red.shade600 : Colors.orange.shade700;

                return Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                    boxShadow: [BoxShadow(color: (isRestricted ? Colors.red : Colors.orange).withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(isRestricted ? Icons.block_rounded : Icons.warning_amber_rounded,
                              size: 20, color: iconColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            isRestricted ? 'Orders Blocked' : 'Negative Balance',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: iconColor),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isRestricted
                                ? 'Your wallet is at ₹${user!.walletBalance.toStringAsFixed(2)}. Top up ₹${shortfall.toStringAsFixed(0)} to restore ordering.'
                                : 'Balance will be ₹${(user!.walletBalance - total).toStringAsFixed(2)} after this order.',
                            style: TextStyle(fontSize: 12, color: iconColor.withValues(alpha: 0.85), height: 1.4),
                          ),
                        ])),
                      ]),
                    ),
                    if (isRestricted)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: borderColor)),
                        ),
                        child: TextButton.icon(
                          onPressed: () => context.push('/wallet/topup'),
                          icon: Icon(Icons.add_circle_outline, size: 16, color: iconColor),
                          label: Text('Top Up Wallet →',
                              style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14))),
                          ),
                        ),
                      ),
                  ]),
                );
              }),
            )
          else if ((user?.walletBalance ?? 0) < total)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Balance after order: ₹${((user?.walletBalance ?? 0) - total).toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),

          const SizedBox(height: 20),
          // Blocked delivery message banner
          if (_orderType == 'delivery' && _deliveryBlocked && _blockedMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(children: [
                const Icon(Icons.block_outlined, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_blockedMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13))),
              ]),
            ),
          ElevatedButton(
            onPressed: (_loading ||
                    (user?.tierName == 'Restricted') ||
                    (_orderType == 'delivery' && _deliveryBlocked) ||
                    (_orderType == 'pickup' && _selectedSalesmanId == null) ||
                    (_orderType == 'delivery' && (_fetchingCharge || _selectedAddressId == null)) ||
                    _selectedSlotId == null)
                ? null
                : _placeOrder,
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(_orderType == 'pickup'
                    ? 'Place Pickup Order — ₹${total.toStringAsFixed(2)}'
                    : 'Pay ₹${total.toStringAsFixed(2)} from Wallet'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  const _SummaryRow(this.label, this.value, {this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : const TextStyle(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: style),
        Text(value, style: style.copyWith(color: valueColor ?? (bold ? AppColors.primary : null))),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}

// ── Order type toggle ─────────────────────────────────────────────────────────
class _OrderTypeToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _OrderTypeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _TypeCard(
        type: 'delivery',
        selected: selected == 'delivery',
        icon: Icons.local_shipping_outlined,
        label: 'Home Delivery',
        subtitle: 'We bring it to you',
        onTap: () => onChanged('delivery'),
      )),
      const SizedBox(width: 10),
      Expanded(child: _TypeCard(
        type: 'pickup',
        selected: selected == 'pickup',
        icon: Icons.store_outlined,
        label: 'Self Pickup',
        subtitle: 'FREE — collect at farm',
        onTap: () => onChanged('pickup'),
      )),
    ]);
  }
}

class _TypeCard extends StatelessWidget {
  final String type;
  final bool selected;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _TypeCard({required this.type, required this.selected, required this.icon,
      required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = type == 'pickup' ? Colors.teal : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? color : Colors.grey, size: 28),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: selected ? color : Colors.black87,
          )),
          Text(subtitle, style: TextStyle(
            fontSize: 10,
            color: selected ? color.withValues(alpha: 0.8) : Colors.grey,
          ), textAlign: TextAlign.center),
          if (selected) ...[
            const SizedBox(height: 4),
            Icon(Icons.check_circle, color: color, size: 16),
          ],
        ]),
      ),
    );
  }
}

// ── Pincode rules banner (shown in checkout when custom rules apply) ───────────

class _PincodeRulesBanner extends ConsumerWidget {
  final String pincode;
  const _PincodeRulesBanner({required this.pincode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(pincodeRulesProvider(pincode));
    return rulesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (rules) {
        if (rules == null) return const SizedBox.shrink();

        final minOrder   = rules['min_order_amount'] as num?;
        final charge     = rules['custom_delivery_charge'] as num?;
        final allowedIds = rules['allowed_product_ids'] as List?;

        // Check cart items against allowed products
        final cart = ref.watch(cartProvider);
        final blockedItems = allowedIds != null
            ? cart.where((i) => !allowedIds.contains(i.product.id)).toList()
            : <CartItem>[];

        // Get allowed product names for display
        final allProducts = ref.watch(_allProductsProvider).value ?? [];
        final allowedProducts = allowedIds != null
            ? allProducts.where((p) => allowedIds.contains(p.id)).toList()
            : <Product>[];

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: blockedItems.isNotEmpty ? Colors.red.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: blockedItems.isNotEmpty ? Colors.red.shade200 : Colors.orange.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                blockedItems.isNotEmpty ? Icons.error_outline : Icons.info_outline,
                color: blockedItems.isNotEmpty ? Colors.red.shade700 : Colors.orange.shade700,
                size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Special delivery rules for pincode $pincode',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: blockedItems.isNotEmpty
                            ? Colors.red.shade800 : Colors.orange.shade800)),
              ),
            ]),
            const SizedBox(height: 8),
            if (minOrder != null)
              _RuleRow(Icons.shopping_bag_outlined,
                  'Minimum order: ₹${minOrder.toStringAsFixed(0)}'),
            if (charge != null)
              _RuleRow(Icons.local_shipping_outlined,
                  'Delivery charge: ₹${charge.toStringAsFixed(0)}'),

            // Show available products list
            if (allowedIds != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text('Available for your area:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                            color: Colors.green.shade700)),
                  ]),
                  const SizedBox(height: 4),
                  if (allowedProducts.isNotEmpty)
                    ...allowedProducts.map((p) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• ${p.name}',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                    ))
                  else
                    Text('${allowedIds.length} product${allowedIds.length == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                ]),
              ),
            ],

            // Blocked items in cart
            if (blockedItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.remove_shopping_cart, size: 14, color: Colors.red.shade800),
                    const SizedBox(width: 6),
                    Text('Not available for this area (remove to proceed):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                            color: Colors.red.shade800)),
                  ]),
                  const SizedBox(height: 4),
                  ...blockedItems.map((i) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• ${i.product.name}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  )),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RuleRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.orange.shade600),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
    ]),
  );
}
