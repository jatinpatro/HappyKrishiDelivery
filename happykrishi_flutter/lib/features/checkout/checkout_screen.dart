import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../info/app_info_screen.dart';

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
  bool _loading = false;
  bool _showAddAddressForm = false;
  int? _selectedSalesmanId; // for pickup orders

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
    setState(() { _fetchingCharge = true; _deliveryCharge = null; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get(
        Endpoints.deliveryCharge,
        queryParameters: {'address_id': addressId, 'subtotal': subtotal},
      );
      if (mounted) {
        setState(() => _deliveryCharge = (res.data['delivery_charge'] as num).toDouble());
      }
    } catch (_) {
      if (mounted) setState(() => _deliveryCharge = 30); // fallback base charge
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
      if (mounted) setState(() {
        _lastCheckedPincode = pincode;
        _checkingPincode = false;
        _pincodeDeliverable = deliverable;
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
      });
      _fetchDeliveryCharge(newAddress.id, ref.read(cartSubtotalProvider));
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to add address');
    }
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
    final total = ref.read(cartSubtotalProvider) + (_deliveryCharge ?? 0);
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
                    backgroundColor: const Color(0xFF2E7D32)),
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
      });
      ref.read(cartProvider.notifier).clear();
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_orderType == 'pickup'
              ? 'Pickup order placed! We\'ll have it ready for you 🎉'
              : 'Order placed successfully! 🎉'),
          backgroundColor: const Color(0xFF2E7D32),
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
    final total = subtotal + charge;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
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
                _selectedAddressId = null;
              } else {
                _deliveryCharge = null;
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
                  color: selected ? const Color(0xFFE8F5E9) : null,
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
                          color: selected ? const Color(0xFF2E7D32) : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.label, style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selected ? const Color(0xFF2E7D32) : null,
                          )),
                          Text('${a.addressLine}, ${a.city}${a.pincode != null ? ' - ${a.pincode}' : ''}',
                              style: const TextStyle(fontSize: 13)),
                        ])),
                        if (a.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
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
            error: (e, _) => Column(children: [
              Text('Error loading addresses: $e'),
              TextButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add Address'),
                onPressed: () => setState(() => _showAddAddressForm = true),
              ),
            ]),
          ),
          const Divider(height: 32),
          ], // end if (delivery)

          // ── Pickup Info Card (only for pickup) ─────────────────────────────
          if (_orderType == 'pickup') ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.4)),
              ),
              child: Consumer(builder: (_, ref, __) {
                final info = ref.watch(appInfoProvider);
                return info.when(
                  data: (d) {
                    final pickup = d['pickup'] as Map<String, dynamic>? ?? {};
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.store, color: Color(0xFF2E7D32)),
                        SizedBox(width: 8),
                        Text('Pickup Location', style: TextStyle(
                            fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
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
                        Icon(Icons.local_shipping_outlined, color: Color(0xFF2E7D32), size: 16),
                        SizedBox(width: 6),
                        Text('No delivery charge — FREE pickup!',
                            style: TextStyle(color: Color(0xFF2E7D32),
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
                    colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32)),
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
                border: Border.all(color: const Color(0xFF2E7D32)),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF9FBF9),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, color: Color(0xFF2E7D32), size: 20),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Delivery Date',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(
                    _formatDisplayDate(_deliveryDate),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF2E7D32)),
                  ),
                ]),
                const Spacer(),
                const Text('Change', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                const Icon(Icons.chevron_right, color: Color(0xFF2E7D32)),
              ]),
            ),
          ),
          slots.when(
            data: (slts) => Column(children: slts.map((s) {
              final selected = _selectedSlotId == s.id;
              return Card(
                color: selected ? const Color(0xFFE8F5E9) : null,
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedSlotId = s.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selected ? const Color(0xFF2E7D32) : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.label,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? const Color(0xFF2E7D32) : null,
                          ))),
                      Text('${s.startTime} – ${s.endTime}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                  ),
                ),
              );
            }).toList()),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
          const Divider(height: 32),

          // ── Custom pincode restrictions banner ──────────────────────────────
          if (_orderType == 'delivery' && _selectedAddressPincode.isNotEmpty)
            _PincodeRulesBanner(pincode: _selectedAddressPincode),

          // ── Order Summary ───────────────────────────────────────────────────
          DeliveryInfoBanner(subtotal: subtotal),
          _SectionHeader(title: 'Order Summary'),
          ...cart.map((i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text('${i.product.name} × ${i.qty.toStringAsFixed(2)} ${i.product.unit}', overflow: TextOverflow.ellipsis)),
              Text('₹${(i.product.pricePerUnit * i.qty).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
            ]),
          )).toList(),
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
          else if (_deliveryCharge == 0)
            const _SummaryRow('Delivery Charge', 'FREE 🎉', valueColor: Colors.green)
          else
            _SummaryRow('Delivery Charge', '₹${_deliveryCharge!.toStringAsFixed(0)}'),

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
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.block, size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cannot place order — wallet balance is negative. Please top up first.',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ),
                ]),
              ),
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
          ElevatedButton(
            onPressed: (_loading ||
                    (user?.walletBalance ?? 0) < 0 ||
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
        Text(value, style: style.copyWith(color: valueColor ?? (bold ? const Color(0xFF2E7D32) : null))),
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
    final color = type == 'pickup' ? Colors.teal : const Color(0xFF2E7D32);
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
