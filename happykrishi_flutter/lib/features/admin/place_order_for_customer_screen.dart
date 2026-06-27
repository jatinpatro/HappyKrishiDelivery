import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _customersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, search) async {
    final dio = ref.read(dioProvider);
    final user = ref.read(authStateProvider).user;
    final endpoint = user?.role == 'salesman' ? Endpoints.salesmanCustomers : Endpoints.adminUsers;
    final res = await dio.get(endpoint,
        queryParameters: search.isNotEmpty ? {'search': search} : null);
    final key = user?.role == 'salesman' ? 'customers' : 'users';
    return List<Map<String, dynamic>>.from(res.data[key]);
  },
);

final _productsForOrderProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.products);
  return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
});

final _customerAddressesProvider =
    FutureProvider.autoDispose.family<List<Address>, int>((ref, customerId) async {
  final dio = ref.read(dioProvider);
  final role = ref.read(authStateProvider).user?.role;
  final endpoint = role == 'salesman'
      ? '/api/salesman/customers/$customerId/addresses'
      : '/api/admin/customers/$customerId/addresses';
  final res = await dio.get(endpoint);
  return (res.data['addresses'] as List).map((e) => Address.fromJson(e)).toList();
});

final _deliveryChargeProvider = FutureProvider.autoDispose
    .family<double, ({int addressId, double subtotal})>((ref, args) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.deliveryCharge, queryParameters: {
    'address_id': args.addressId,
    'subtotal': args.subtotal,
  });
  return (res.data['delivery_charge'] as num).toDouble();
});

final _deliverySlotsForPlacingProvider =
    FutureProvider.autoDispose.family<List<DeliverySlot>, String>((ref, type) async {
  final dio = ref.read(dioProvider);
  try {
    final res = await dio.get('/api/delivery-slots', queryParameters: {'type': type});
    return (res.data['slots'] as List).map((e) => DeliverySlot.fromJson(e)).toList();
  } catch (_) {
    if (type == 'pickup') {
      return const [
        DeliverySlot(id: 4, label: 'Pickup Morning (8–12 AM)', startTime: '08:00', endTime: '12:00'),
        DeliverySlot(id: 5, label: 'Pickup Afternoon (2–6 PM)', startTime: '14:00', endTime: '18:00'),
      ];
    }
    return const [
      DeliverySlot(id: 1, label: 'Morning (7–10 AM)', startTime: '07:00', endTime: '10:00'),
      DeliverySlot(id: 2, label: 'Afternoon (12–3 PM)', startTime: '12:00', endTime: '15:00'),
      DeliverySlot(id: 3, label: 'Evening (5–8 PM)', startTime: '17:00', endTime: '20:00'),
    ];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class PlaceOrderForCustomerScreen extends ConsumerStatefulWidget {
  const PlaceOrderForCustomerScreen({super.key});
  @override
  ConsumerState<PlaceOrderForCustomerScreen> createState() =>
      _PlaceOrderForCustomerScreenState();
}

class _PlaceOrderForCustomerScreenState
    extends ConsumerState<PlaceOrderForCustomerScreen> {
  // Step tracking
  int _step = 0; // 0=customer, 1=products, 2=checkout

  // Step 0 — customer
  String _customerSearch = '';
  Map<String, dynamic>? _selectedCustomer;

  // Step 1 — products
  final Map<int, double> _cart = {}; // product_id → qty
  List<Product> _products = [];

  // Step 2 — checkout
  String _orderType = 'delivery';
  int? _selectedAddressId;
  int? _selectedSlotId;
  String _deliveryDate = _defaultDate(false);
  final _notesCtrl = TextEditingController();
  bool _placing = false;
  bool _freeDelivery = false; // admin/salesman override: waive delivery charge

  static String _defaultDate(bool isPickup) {
    final d = isPickup ? DateTime.now() : DateTime.now().add(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  double get _subtotal {
    double s = 0;
    for (final p in _products) {
      final qty = _cart[p.id] ?? 0;
      s += p.pricePerUnit * qty;
    }
    return s;
  }

  List<Product> get _cartProducts =>
      _products.where((p) => (_cart[p.id] ?? 0) > 0).toList();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).user?.role ?? 'admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0
            ? 'Select Customer'
            : _step == 1
                ? 'Add Products'
                : 'Review & Place Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go(role == 'salesman' ? '/salesman' : '/admin/dashboard'),
          ),
        ],
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--),
              ),
      ),
      body: IndexedStack(
        index: _step,
        children: [
          _CustomerStep(
            search: _customerSearch,
            selected: _selectedCustomer,
            onSearchChanged: (v) => setState(() => _customerSearch = v),
            onSelect: (c) => setState(() {
              _selectedCustomer = c;
              _selectedAddressId = null;
            }),
            onNext: () => setState(() => _step = 1),
          ),
          _ProductsStep(
            cart: _cart,
            onProductsLoaded: (p) => _products = p,
            onNext: () => setState(() => _step = 2),
          ),
          _CheckoutStep(
            customer: _selectedCustomer,
            cartProducts: _cartProducts,
            cart: _cart,
            subtotal: _subtotal,
            orderType: _orderType,
            selectedAddressId: _selectedAddressId,
            selectedSlotId: _selectedSlotId,
            deliveryDate: _deliveryDate,
            notesCtrl: _notesCtrl,
            placing: _placing,
            freeDelivery: _freeDelivery,
            role: role,
            onTypeChanged: (t) => setState(() {
              _orderType = t;
              _selectedSlotId = null;
              _deliveryDate = _defaultDate(t == 'pickup');
              if (t == 'pickup') _selectedAddressId = null;
            }),
            onAddressChanged: (id) => setState(() => _selectedAddressId = id),
            onSlotChanged: (id) => setState(() => _selectedSlotId = id),
            onDateChanged: (d) => setState(() => _deliveryDate = d),
            onFreeDeliveryChanged: (v) => setState(() => _freeDelivery = v),
            onPlace: _placeOrder,
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder() async {
    if (_selectedCustomer == null || _selectedSlotId == null) return;
    if (_orderType == 'delivery' && _selectedAddressId == null) {
      _snack('Select a delivery address');
      return;
    }
    if (_cartProducts.isEmpty) {
      _snack('Add at least one product');
      return;
    }

    setState(() => _placing = true);
    try {
      final dio = ref.read(dioProvider);
      final role = ref.read(authStateProvider).user?.role;
      final endpoint = role == 'salesman'
          ? Endpoints.salesmanPlaceOrderForCustomer
          : Endpoints.adminPlaceOrderForCustomer;

      final items = _cartProducts
          .map((p) => {'product_id': p.id, 'qty': _cart[p.id]})
          .toList();

      await dio.post(endpoint, data: {
        'customer_id': _selectedCustomer!['id'],
        'order_type': _orderType,
        if (_orderType == 'delivery') 'address_id': _selectedAddressId,
        'slot_id': _selectedSlotId,
        'delivery_date': _deliveryDate,
        if (_freeDelivery && _orderType == 'delivery') 'delivery_charge_override': 0,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'items': items,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order placed for ${_selectedCustomer!['name']} ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
        Navigator.of(context).pop(true);
      }
    } on DioException catch (e) {
      if (mounted) _snack(e.response?.data['error'] ?? 'Failed to place order');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ── Step 0: Customer selection ─────────────────────────────────────────────────

class _CustomerStep extends ConsumerWidget {
  final String search;
  final Map<String, dynamic>? selected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onNext;
  const _CustomerStep({
    required this.search, required this.selected,
    required this.onSearchChanged, required this.onSelect, required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(_customersProvider(search));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (selected != null)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E7D32)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF2E7D32),
                child: Text(
                  (selected!['name'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(selected!['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('+91 ${selected!['phone']}  •  Wallet: ₹${((selected!['wallet_balance'] as num?) ?? 0).toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
            ]),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Next — Select Products →'),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Search customers by name or phone...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: customers.when(
          data: (list) {
            final filtered = list.where((c) => c['role'] == 'customer' || c['role'] == null).toList();
            if (filtered.isEmpty) {
              return const Center(child: Text('No customers found', style: TextStyle(color: Colors.grey)));
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                final isSelected = selected != null && selected!['id'] == c['id'];
                return Card(
                  color: isSelected ? const Color(0xFFE8F5E9) : null,
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                      child: Text(
                        (c['name'] as String).substring(0, 1).toUpperCase(),
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(c['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '+91 ${c['phone']}  •  ₹${((c['wallet_balance'] as num?) ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                        : null,
                    onTap: () => onSelect(c),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) { logError('admin-place-order', e); return Center(child: Text(friendlyError(e))); },
        ),
      ),
    ]);
  }
}

// ── Step 1: Product picker ────────────────────────────────────────────────────

class _ProductsStep extends ConsumerStatefulWidget {
  final Map<int, double> cart;
  final ValueChanged<List<Product>> onProductsLoaded;
  final VoidCallback onNext;
  const _ProductsStep({required this.cart, required this.onProductsLoaded, required this.onNext});

  @override
  ConsumerState<_ProductsStep> createState() => _ProductsStepState();
}

class _ProductsStepState extends ConsumerState<_ProductsStep> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _categoryFilter;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(_productsForOrderProvider);
    final cartCount = widget.cart.values.fold(0.0, (s, v) => s + v);

    return Column(children: [
      // ── Search + category filter ─────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search products…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          products.whenOrNull(data: (list) {
            final cats = ({} ..addAll({for (final p in list) if (p.categoryName != null) p.categoryName!: true})).keys.toList()..sort();
            if (cats.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _CatChip('All', _categoryFilter == null, () => setState(() => _categoryFilter = null)),
                  ...cats.map((c) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _CatChip(c, _categoryFilter == c,
                        () => setState(() => _categoryFilter = _categoryFilter == c ? null : c)),
                  )),
                ]),
              ),
            );
          }) ?? const SizedBox.shrink(),
        ]),
      ),
      const Divider(height: 1),

      Expanded(
        child: products.when(
          data: (list) {
            widget.onProductsLoaded(list);
            final active = list.where((p) {
              if (!p.isActive || p.stockQty <= 0) return false;
              if (_categoryFilter != null && p.categoryName != _categoryFilter) return false;
              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                return p.name.toLowerCase().contains(q) ||
                    (p.categoryName?.toLowerCase().contains(q) ?? false);
              }
              return true;
            }).toList();

            if (active.isEmpty) {
              return const Center(child: Text('No products match', style: TextStyle(color: Colors.grey)));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: active.length,
              itemBuilder: (_, i) {
                final p = active[i];
                final qty = widget.cart[p.id] ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('₹${p.pricePerUnit}/${p.unit}  •  Stock: ${p.stockQty.toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        if (p.categoryName != null)
                          Text(p.categoryName!, style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32))),
                      ])),
                      _QtyControl(
                        qty: qty,
                        unit: p.unit,
                        maxQty: p.stockQty,
                        onChanged: (v) {
                          setState(() {
                            if (v <= 0) {
                              widget.cart.remove(p.id);
                            } else {
                              widget.cart[p.id] = v;
                            }
                          });
                        },
                      ),
                    ]),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) { logError('admin-place-order', e); return Center(child: Text(friendlyError(e))); },
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.cart.isEmpty ? null : widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(widget.cart.isEmpty
                  ? 'Add products to continue'
                  : 'Review Order (${cartCount.toStringAsFixed(1)} items) →'),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _QtyControl extends StatefulWidget {
  final double qty, maxQty;
  final String unit;
  final ValueChanged<double> onChanged;
  const _QtyControl({required this.qty, required this.maxQty,
      required this.unit, required this.onChanged});

  @override
  State<_QtyControl> createState() => _QtyControlState();
}

class _QtyControlState extends State<_QtyControl> {
  late final _ctrl = TextEditingController(
      text: widget.qty > 0 ? widget.qty.toStringAsFixed(2) : '');

  @override
  void didUpdateWidget(_QtyControl old) {
    super.didUpdateWidget(old);
    if (old.qty != widget.qty) {
      final newText = widget.qty > 0 ? widget.qty.toStringAsFixed(2) : '';
      if (_ctrl.text != newText) _ctrl.text = newText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.qty > 0) ...[
        GestureDetector(
          onTap: () {
            final v = (widget.qty - 0.5).clamp(0.0, widget.maxQty);
            widget.onChanged(v);
          },
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.remove, size: 16),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              suffixText: widget.unit,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            ),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null) widget.onChanged(d.clamp(0, widget.maxQty));
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
      GestureDetector(
        onTap: () {
          final v = (widget.qty + (widget.qty == 0 ? 1.0 : 0.5)).clamp(0.0, widget.maxQty);
          widget.onChanged(v);
        },
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.add, size: 16, color: Colors.white),
        ),
      ),
    ]);
  }
}

// ── Step 2: Checkout ──────────────────────────────────────────────────────────

class _CheckoutStep extends ConsumerWidget {
  final Map<String, dynamic>? customer;
  final List<Product> cartProducts;
  final Map<int, double> cart;
  final double subtotal;
  final String orderType, deliveryDate;
  final int? selectedAddressId, selectedSlotId;
  final TextEditingController notesCtrl;
  final bool placing;
  final bool freeDelivery;
  final String role;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int?> onAddressChanged;
  final ValueChanged<int?> onSlotChanged;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<bool> onFreeDeliveryChanged;
  final VoidCallback onPlace;

  const _CheckoutStep({
    required this.customer, required this.cartProducts, required this.cart,
    required this.subtotal, required this.orderType, required this.deliveryDate,
    required this.selectedAddressId, required this.selectedSlotId,
    required this.notesCtrl, required this.placing, required this.freeDelivery,
    required this.role,
    required this.onTypeChanged, required this.onAddressChanged,
    required this.onSlotChanged, required this.onDateChanged,
    required this.onFreeDeliveryChanged, required this.onPlace,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customer == null) return const SizedBox.shrink();

    final customerId = customer!['id'] as int;
    final walletBalance = ((customer!['wallet_balance'] as num?) ?? 0).toDouble();
    final addresses = ref.watch(_customerAddressesProvider(customerId));
    final slots = ref.watch(_deliverySlotsForPlacingProvider(orderType));

    // Fetch actual delivery charge when address is selected
    final deliveryChargeAsync = (orderType == 'delivery' && selectedAddressId != null && !freeDelivery)
        ? ref.watch(_deliveryChargeProvider((addressId: selectedAddressId!, subtotal: subtotal)))
        : null;
    final fetchedCharge = deliveryChargeAsync?.valueOrNull;
    final effectiveDeliveryCharge = (orderType == 'pickup' || freeDelivery)
        ? 0.0
        : (fetchedCharge ?? 0.0);
    final totalForWalletCheck = subtotal + effectiveDeliveryCharge;
    final walletAlreadyNegative = walletBalance < 0;
    final canPlace = !placing &&
        selectedSlotId != null &&
        (orderType == 'pickup' || selectedAddressId != null) &&
        cartProducts.isNotEmpty &&
        !walletAlreadyNegative;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Customer info
      Card(
        color: const Color(0xFFE8F5E9),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.person, color: Color(0xFF2E7D32)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer!['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('Wallet: ₹${walletBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: walletBalance >= subtotal ? const Color(0xFF2E7D32) : Colors.red,
                      fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      // Order type toggle
      Row(children: [
        Expanded(child: _typeCard('delivery', '🚚 Delivery', orderType, onTypeChanged)),
        const SizedBox(width: 10),
        Expanded(child: _typeCard('pickup', '🏪 Pickup (FREE)', orderType, onTypeChanged)),
      ]),
      const SizedBox(height: 14),

      // Address (delivery only)
      if (orderType == 'delivery') ...[
        const Text('Delivery Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        addresses.when(
          data: (list) => list.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: const Text('No addresses saved for this customer.',
                      style: TextStyle(color: Colors.orange, fontSize: 13)),
                )
              : Column(children: list.map((a) {
                  final sel = selectedAddressId == a.id;
                  return Card(
                    color: sel ? const Color(0xFFE8F5E9) : null,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onAddressChanged(a.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: sel ? const Color(0xFF2E7D32) : Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(child: Text('${a.label}: ${a.addressLine}, ${a.city}',
                              style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                    ),
                  );
                }).toList()),
          loading: () => const LinearProgressIndicator(),
          error: (_, e) => Text('Could not load addresses: $e'),
        ),
        const SizedBox(height: 14),
      ],

      // Date
      const Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.parse(deliveryDate),
            firstDate: orderType == 'pickup' ? now : now.add(const Duration(days: 1)),
            lastDate: now.add(const Duration(days: 14)),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                  colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32))),
              child: child!,
            ),
          );
          if (picked != null) {
            onDateChanged(
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF2E7D32)),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.calendar_today, color: Color(0xFF2E7D32), size: 18),
            const SizedBox(width: 10),
            Text(deliveryDate,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
            const Spacer(),
            const Text('Change', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 14),

      // Slot
      const Text('Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 6),
      slots.when(
        data: (list) => Column(children: list.map((s) {
          final sel = selectedSlotId == s.id;
          return Card(
            color: sel ? const Color(0xFFE8F5E9) : null,
            margin: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => onSlotChanged(s.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: sel ? const Color(0xFF2E7D32) : Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13))),
                  Text('${s.startTime} – ${s.endTime}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ),
            ),
          );
        }).toList()),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) { logError('admin-place-order', e); return Text(friendlyError(e)); },
      ),
      const SizedBox(height: 14),

      // Items summary
      const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 6),
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ...cartProducts.map((p) {
            final qty = cart[p.id] ?? 0;
            final total = p.pricePerUnit * qty;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${p.name} × ${qty.toStringAsFixed(2)} ${p.unit}',
                    style: const TextStyle(fontSize: 13))),
                Text('₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            );
          }),
          const Divider(height: 16),
          // Delivery charge row (delivery orders only)
          if (orderType == 'delivery') ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Delivery Charge', style: TextStyle(fontSize: 13)),
              freeDelivery
                  ? const Text('FREE ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13))
                  : selectedAddressId == null
                      ? const Text('Select address to calculate', style: TextStyle(color: Colors.grey, fontSize: 12))
                      : deliveryChargeAsync == null
                          ? const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12))
                          : deliveryChargeAsync.when(
                              data: (charge) => Text(
                                charge == 0 ? 'FREE ✅' : '₹${charge.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13,
                                  color: charge == 0 ? Colors.green : Colors.black87,
                                ),
                              ),
                              loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              error: (_, _) => const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ),
            ]),
            const SizedBox(height: 6),
            // Free delivery toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: freeDelivery ? Colors.green.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: freeDelivery ? Colors.green.shade300 : Colors.grey.shade300),
              ),
              child: Row(children: [
                Icon(Icons.local_shipping_outlined,
                    size: 16, color: freeDelivery ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    freeDelivery ? 'Delivery charge waived (FREE)' : 'Waive delivery charge',
                    style: TextStyle(
                      fontSize: 13,
                      color: freeDelivery ? Colors.green.shade700 : Colors.black87,
                      fontWeight: freeDelivery ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Switch(
                  value: freeDelivery,
                  activeThumbColor: Colors.green,
                  onChanged: onFreeDeliveryChanged,
                ),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(
              orderType == 'delivery' && !freeDelivery && selectedAddressId != null && fetchedCharge == null
                  ? '₹${subtotal.toStringAsFixed(2)} + delivery'
                  : '₹${(subtotal + effectiveDeliveryCharge).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32)),
            ),
          ]),
          if (walletAlreadyNegative)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
                  Text(
                    'Cannot place order — wallet balance is negative. Top up first.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ]),
              ),
            )
          else if (walletBalance < totalForWalletCheck)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Balance short by ₹${(totalForWalletCheck - walletBalance).toStringAsFixed(2)} — will go negative',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ]),
      )),
      const SizedBox(height: 10),

      // Notes
      TextField(
        controller: notesCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Notes (optional)',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: placing
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(placing ? 'Placing...' : 'Place Order for Customer'),
          onPressed: canPlace ? onPlace : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _typeCard(String value, String label, String selected, ValueChanged<String> onTap) {
    final sel = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFE8F5E9) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? const Color(0xFF2E7D32) : Colors.grey.shade300, width: sel ? 2 : 1),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 13,
            color: sel ? const Color(0xFF2E7D32) : Colors.black87,
          ), textAlign: TextAlign.center),
          if (sel) const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 16),
        ]),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2E7D32) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black87,
              )),
        ),
      );
}
