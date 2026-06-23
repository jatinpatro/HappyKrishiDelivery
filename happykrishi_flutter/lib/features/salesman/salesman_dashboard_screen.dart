import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../admin/place_order_for_customer_screen.dart';

final salesmanDashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanDashboard);
  return res.data as Map<String, dynamic>;
});

final salesmanPendingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanPendingCollections);
  return res.data as Map<String, dynamic>;
});

final salesmanCustomersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, key) async {
  // key = "search|wallet|sort"
  final parts  = key.split('|');
  final search = parts[0].isNotEmpty ? parts[0] : null;
  final wallet = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final sort   = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanCustomers, queryParameters: {
    if (search != null) 'search': search,
    if (wallet != null) 'wallet': wallet,
    if (sort   != null) 'sort':   sort,
  });
  return List<Map<String, dynamic>>.from(res.data['customers']);
});

final salesmanPendingOrdersProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, search) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanPendingOrders,
      queryParameters: search.isNotEmpty ? {'search': search} : null);
  return res.data as Map<String, dynamic>;
});

final salesmanProductsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanProducts);
  return List<Map<String, dynamic>>.from(res.data['products']);
});

// History provider — keyed by "dateFrom|dateTo|search"
final salesmanHistoryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final dateFrom = parts[0].isNotEmpty ? parts[0] : null;
  final dateTo   = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final search   = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final dio = ref.read(dioProvider);
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo != null)   params['date_to']   = dateTo;
  if (search != null)   params['search']    = search;
  final res = await dio.get(Endpoints.salesmanHistory,
      queryParameters: params.isNotEmpty ? params : null);
  return res.data as Map<String, dynamic>;
});

final salesmanApprovedCollectionsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.salesmanApprovedCollections);
  return res.data as Map<String, dynamic>;
});

class SalesmanDashboardScreen extends ConsumerStatefulWidget {
  const SalesmanDashboardScreen({super.key});
  @override
  ConsumerState<SalesmanDashboardScreen> createState() => _SalesmanDashboardScreenState();
}

class _SalesmanDashboardScreenState extends ConsumerState<SalesmanDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer? _locationTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _startLocationSharing();
    // Auto-refresh dashboard every 30s to pick up remote cancellations
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(salesmanDashboardProvider);
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ── Location sharing — active whenever salesman has an assigned/picked delivery
  Future<void> _startLocationSharing() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        !await Geolocator.isLocationServiceEnabled()) { return; }

    // Send immediately then every 10 seconds
    _sendLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendLocation());
  }

  Future<void> _sendLocation() async {
    // Always refresh dashboard to pick up remote cancellations / status changes
    ref.invalidate(salesmanDashboardProvider);

    // Only send GPS if there's an active delivery
    final dashboard = ref.read(salesmanDashboardProvider).value;
    final orders = dashboard?['assigned_orders'] as List? ?? [];
    if (orders.isEmpty) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await ref.read(dioProvider).put(
        Endpoints.deliveryLocation,
        data: {'lat': pos.latitude, 'lng': pos.longitude},
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final dashboard = ref.watch(salesmanDashboardProvider);
    final pending = ref.watch(salesmanPendingProvider);
    final pendingOrders = ref.watch(salesmanPendingOrdersProvider(''));

    final pendingCount = pending.value?['count'] as int? ?? 0;
    final pendingOrderCount = pendingOrders.value?['count'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${user?.name ?? 'Salesman'} 👋'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(salesmanDashboardProvider);
              ref.invalidate(salesmanPendingProvider);
              ref.invalidate(salesmanCustomersProvider(''));
              ref.invalidate(salesmanPendingOrdersProvider(''));
              ref.invalidate(salesmanProductsProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
              context.go('/auth/otp');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: pendingCount > 0 ? 'Collections ($pendingCount)' : 'Collections'),
            Tab(text: pendingOrderCount > 0 ? 'Approve ($pendingOrderCount)' : 'Approve'),
            const Tab(text: 'Customers'),
            const Tab(text: 'History'),
            Tab(
              text: () {
                final orders = dashboard.value?['assigned_orders'] as List? ?? [];
                return orders.isNotEmpty ? 'Deliveries (${orders.length})' : 'Deliveries';
              }(),
            ),
            const Tab(text: 'Stock'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _CollectionsTab(dashboard: dashboard),
          const _PendingOrdersTab(),
          const _CustomersTab(),
          const _HistoryTab(),
          _DeliveriesTab(dashboard: dashboard),
          const _StockTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final placed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PlaceOrderForCustomerScreen()),
          );
          if (placed == true) {
            ref.invalidate(salesmanDashboardProvider);
          }
        },
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Place Order'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }
}

// ── Tab: Pending Orders (approve & self-assign) ───────────────────────────────

class _PendingOrdersTab extends ConsumerStatefulWidget {
  const _PendingOrdersTab();
  @override
  ConsumerState<_PendingOrdersTab> createState() => _PendingOrdersTabState();
}

class _PendingOrdersTabState extends ConsumerState<_PendingOrdersTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders = ref.watch(salesmanPendingOrdersProvider(_search));
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search by order #, customer, product, category…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(child: pendingOrders.when(
        data: (d) {
          final orders = (d['orders'] as List? ?? []).cast<Map<String, dynamic>>();
          if (orders.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                const SizedBox(height: 12),
                Text(_search.isNotEmpty ? 'No orders match "$_search"'
                    : 'No pending orders',
                    style: const TextStyle(color: Colors.grey, fontSize: 16)),
                const SizedBox(height: 6),
                if (_search.isEmpty)
                  const Text('All orders are confirmed',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(salesmanPendingOrdersProvider(_search)),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (_, i) => _PendingOrderCard(
                order: orders[i],
                onRefresh: () {
                  ref.invalidate(salesmanPendingOrdersProvider(''));
                  ref.invalidate(salesmanDashboardProvider);
                },
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      )),
    ]);
  }
}

class _PendingOrderCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  const _PendingOrderCard({required this.order, required this.onRefresh});
  @override
  ConsumerState<_PendingOrderCard> createState() => _PendingOrderCardState();
}

class _PendingOrderCardState extends ConsumerState<_PendingOrderCard> {
  bool _loading = false;

  Future<void> _confirmAndAssign() async {
    final orderId = widget.order['id'] as int;
    final orderNum = widget.order['order_number'] as String;
    final customerName = widget.order['customer_name'] as String? ?? 'customer';
    final selfUser = ref.read(authStateProvider).user;
    final items = (widget.order['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final weightItems = items.where((i) => i['is_weight_adjusted'] == 1 || i['is_weight_adjusted'] == true).toList();

    // Build weight controllers for weight-adjusted items
    final weightCtrls = {
      for (final i in weightItems)
        i['id'] as int: TextEditingController(
          text: (i['estimated_qty'] as num).toStringAsFixed(2))
    };

    // Load salesmen list
    List<Map<String, dynamic>> salesmen = [];
    try {
      final res = await ref.read(dioProvider).get(Endpoints.salesmanList);
      salesmen = List<Map<String, dynamic>>.from(res.data['salesmen']);
    } catch (_) {}

    if (!mounted) return;

    int? selectedSalesmanId = selfUser?.id;
    String selectedName = selfUser?.name ?? 'Me';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: Text('Confirm Order #$orderNum'),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Customer: $customerName', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 14),

              // Weight-adjusted items
              if (weightItems.isNotEmpty) ...[
                const Text('Gross Weight (actual)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('Update actual weights for weight-adjusted products:',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                ...weightItems.map((i) {
                  final id = i['id'] as int;
                  final name = i['product_name'] as String;
                  final unit = i['unit'] as String? ?? 'kg';
                  final est = (i['estimated_qty'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('Est: ${est.toStringAsFixed(2)} $unit',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ])),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: weightCtrls[id],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            suffixText: unit,
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
                const Divider(height: 20),
              ],

              const Text('Assign to:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              if (salesmen.isEmpty)
                const Text('Only self-assignment available', style: TextStyle(color: Colors.grey, fontSize: 12))
              else
                DropdownButtonFormField<int>(
                  initialValue: selectedSalesmanId,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: salesmen.map((s) => DropdownMenuItem<int>(
                    value: s['id'] as int,
                    child: Text('${s['name']}  •  +91 ${s['phone']}'),
                  )).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final s = salesmen.firstWhere((x) => x['id'] == v);
                    setDs(() {
                      selectedSalesmanId = v;
                      selectedName = s['name'] as String;
                    });
                  },
                ),
              const SizedBox(height: 16),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: Text('Confirm & Assign to $selectedName'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final data = <String, dynamic>{};
      if (selectedSalesmanId != null && selectedSalesmanId != selfUser?.id) {
        data['salesman_id'] = selectedSalesmanId;
      }
      // Include actual weights for weight-adjusted items
      if (weightItems.isNotEmpty) {
        data['actual_weights'] = weightCtrls.entries.map((e) => {
          'order_item_id': e.key,
          'actual_qty': double.tryParse(e.value.text) ?? 0,
        }).toList();
      }
      await ref.read(dioProvider).post(Endpoints.salesmanConfirmOrder(orderId), data: data);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Confirmed & assigned to $selectedName ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      // Clean up controllers
      for (final c in weightCtrls.values) { c.dispose(); }
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final amount = (o['final_amount'] as num).toDouble();
    final isPickup = o['order_type'] == 'pickup';
    final items = (o['items'] as List? ?? []).cast<Map<String, dynamic>>();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/${o['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: const Text('PENDING', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
              ),
              const SizedBox(width: 8),
              if (isPickup) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.teal.shade200)),
                  child: Text('🏪 Pickup', style: TextStyle(fontSize: 10, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
              ],
              Text('#${o['order_number']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text('₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text('${o['customer_name']}  •  +91 ${o['customer_phone']}',
                    style: const TextStyle(fontSize: 13)),
              ),
              if ((o['customer_wallet_balance'] as num?)?.toDouble() != null &&
                  (o['customer_wallet_balance'] as num).toDouble() < 0)
                _NegativeWalletBadge(balance: (o['customer_wallet_balance'] as num).toDouble()),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Text('${o['delivery_date']}  ${o['slot_label'] != null ? '• ${o['slot_label']}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
            if (!isPickup && o['address_line'] != null) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(child: Text('${o['address_line']}, ${o['city'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...items.take(3).map((i) => Text(
                '• ${i['product_name']}  ${(i['estimated_qty'] as num).toStringAsFixed(2)} ${i['unit']}',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              )),
              if (items.length > 3)
                Text('+${items.length - 3} more items', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Confirm & Assign to Me'),
                onPressed: _loading ? null : _confirmAndAssign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Tab 1: Collections (pending approval + summary) ───────────────────────────

class _CollectionsTab extends ConsumerWidget {
  final AsyncValue<Map<String, dynamic>> dashboard;
  const _CollectionsTab({required this.dashboard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending  = ref.watch(salesmanPendingProvider);
    final approved = ref.watch(salesmanApprovedCollectionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(salesmanPendingProvider);
        ref.invalidate(salesmanApprovedCollectionsProvider);
        ref.invalidate(salesmanDashboardProvider);
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Summary cards ────────────────────────────────────────────────
        dashboard.when(
          data: (d) {
            final p = d['pending_collections'] as Map<String, dynamic>;
            final a = d['approved_collections'] as Map<String, dynamic>;
            return Row(children: [
              Expanded(child: _StatCard(
                  label: 'Pending\n(awaiting your approval)', icon: Icons.hourglass_empty,
                  value: '₹${(p['total'] as num).toStringAsFixed(0)}',
                  count: p['count'] as int, color: Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                  label: 'Approved\n(credited to wallets)', icon: Icons.check_circle_outline,
                  value: '₹${(a['total'] as num).toStringAsFixed(0)}',
                  count: a['count'] as int, color: const Color(0xFF2E7D32))),
            ]);
          },
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (_, st) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),

        // ── Raise settlement to admin ────────────────────────────────────
        approved.when(
          data: (d) {
            final unsettled = (d['unsettled'] as List? ?? []).cast<Map<String, dynamic>>();
            final unsettledTotal = (d['unsettled_total'] as num?)?.toDouble() ?? 0;
            final settlements = (d['settlements'] as List? ?? []).cast<Map<String, dynamic>>();

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Unsettled section
              if (unsettled.isNotEmpty) ...[
                const Text('Cash Ready to Settle',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('₹${unsettledTotal.toStringAsFixed(0)} collected from ${unsettled.length} customers — not yet handed to admin.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                // Approved collections list
                ...unsettled.map((r) => _ApprovedCollectionCard(request: r)),
                const SizedBox(height: 12),
                // Raise settlement button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send_to_mobile),
                    label: Text('Raise Settlement Request — ₹${unsettledTotal.toStringAsFixed(0)}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _confirmRaiseSettlement(context, ref, unsettledTotal, unsettled.length),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This notifies admin that you have physical cash ready to hand over.',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                    SizedBox(width: 10),
                    Text('All collections settled ✅',
                        style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // Settlement history
              if (settlements.isNotEmpty) ...[
                const Text('Settlement History',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                ...settlements.map((s) => _SettlementRequestCard(s: s)),
              ],
            ]);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
        const SizedBox(height: 24),

        // ── Pending collections to approve ───────────────────────────────
        const Text('Pending — Tap to Approve',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Once you approve, the amount is credited to the customer\'s wallet immediately.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 12),

        pending.when(
          data: (d) {
            final items = d['pending'] as List? ?? [];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                  SizedBox(height: 8),
                  Text('No pending collections', style: TextStyle(color: Colors.grey)),
                ])),
              );
            }
            return Column(children: items.map((r) => _PendingCollectionCard(
              request: r,
              onApprove: () async {
                final id = r['id'] as int;
                final amount = (r['amount'] as num).toDouble();
                final customerName = r['customer_name'] as String? ?? 'customer';

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Approve Collection?'),
                    content: Text(
                        'Credit ₹${amount.toStringAsFixed(0)} to $customerName\'s wallet immediately?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Cancel')),
                      ElevatedButton(onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('Approve & Credit')),
                    ],
                  ),
                );
                if (confirm != true) return;
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(Endpoints.salesmanApproveCollection(id));
                  ref.invalidate(salesmanPendingProvider);
                  ref.invalidate(salesmanApprovedCollectionsProvider);
                  ref.invalidate(salesmanDashboardProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('₹${amount.toStringAsFixed(0)} credited to $customerName ✅'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
            )).toList());
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ]),
    );
  }

  Future<void> _confirmRaiseSettlement(
      BuildContext context, WidgetRef ref, double total, int count) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.send_to_mobile, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text('Raise Settlement'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You are about to notify admin that you have ₹${total.toStringAsFixed(0)} '
              'physical cash from $count collection${count == 1 ? '' : 's'} ready to hand over.'),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. Will hand over tomorrow morning',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            child: const Text('Send to Admin'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.salesmanRaiseSettlement,
          data: noteCtrl.text.isNotEmpty ? {'note': noteCtrl.text.trim()} : {});
      ref.invalidate(salesmanApprovedCollectionsProvider);
      ref.invalidate(salesmanDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Settlement request of ₹${total.toStringAsFixed(0)} sent to admin ✅'),
          backgroundColor: const Color(0xFF1565C0),
        ));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to raise settlement')));
      }
    }
  }
}

// ── Approved collection card (credited, pending settlement) ───────────────────

class _ApprovedCollectionCard extends StatelessWidget {
  final Map<String, dynamic> request;
  const _ApprovedCollectionCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final amount   = (request['amount'] as num).toDouble();
    final customer = request['customer_name'] as String? ?? '';
    final date     = ((request['resolved_at'] ?? request['created_at']) as String).substring(0, 10);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.blue.shade50,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Text(customer.isNotEmpty ? customer[0].toUpperCase() : 'C',
              style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
        ),
        title: Text(customer, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: Text('₹${amount.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 15)),
      ),
    );
  }
}

// ── Settlement request card (raised by salesman, waiting admin ack) ────────────

class _SettlementRequestCard extends StatelessWidget {
  final Map<String, dynamic> s;
  const _SettlementRequestCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final amount      = (s['amount'] as num).toDouble();
    final date        = (s['created_at'] as String).substring(0, 10);
    final note        = s['note'] as String?;
    final ackedBy     = s['acknowledged_by_name'] as String?;
    final isAcked     = ackedBy != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isAcked ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(isAcked ? Icons.check_circle : Icons.hourglass_top,
              color: isAcked ? Colors.green : Colors.orange, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(isAcked ? 'Acknowledged by $ackedBy' : 'Pending admin acknowledgement',
                style: TextStyle(
                    fontSize: 12,
                    color: isAcked ? Colors.green.shade700 : Colors.orange.shade800)),
            if (note != null && note.isNotEmpty)
              Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        ]),
      ),
    );
  }
}

class _PendingCollectionCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  const _PendingCollectionCard({required this.request, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final amount = (request['amount'] as num).toDouble();
    final customer = request['customer_name'] as String? ?? '';
    final phone = request['customer_phone'] as String? ?? '';
    final date = (request['created_at'] as String).substring(0, 16);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Text(customer.isNotEmpty ? customer.substring(0, 1).toUpperCase() : 'C',
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(phone, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ])),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: Text('Approve & Credit ₹${amount.toStringAsFixed(0)} to Wallet'),
              onPressed: onApprove,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Tab 2: Customers ──────────────────────────────────────────────────────────

class _CustomersTab extends ConsumerStatefulWidget {
  const _CustomersTab();
  @override
  ConsumerState<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends ConsumerState<_CustomersTab> {
  final _searchCtrl = TextEditingController();
  String _search       = '';
  String _walletFilter = '';   // '' | negative | zero | positive | low
  String _sortFilter   = 'name'; // name | recent | wallet_asc | wallet_desc

  String get _providerKey => '$_search|$_walletFilter|$_sortFilter';

  static const _walletOptions = [
    (key: '',         label: 'All',        color: Color(0xFF2E7D32)),
    (key: 'negative', label: '🔴 Negative', color: Color(0xFFC62828)),
    (key: 'zero',     label: '⚪ Zero',     color: Color(0xFF757575)),
    (key: 'positive', label: '🟢 Positive', color: Color(0xFF2E7D32)),
    (key: 'low',      label: '🟡 Low',      color: Color(0xFFE65100)),
  ];

  static const _sortOptions = [
    (key: 'name',        label: 'Name A-Z'),
    (key: 'recent',      label: 'Newest'),
    (key: 'wallet_desc', label: 'Wallet ↓'),
    (key: 'wallet_asc',  label: 'Wallet ↑'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(salesmanCustomersProvider(_providerKey));

    return Column(children: [
      // Header
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by name, phone or email...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              onPressed: () => _showAddCustomerDialog(context),
            ),
          ]),
          const SizedBox(height: 10),
          // Wallet chips
          Row(children: [
            const Text('Wallet:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _walletOptions.map((o) => Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: _SmallChip(
                      label: o.label,
                      selected: _walletFilter == o.key,
                      color: o.color,
                      onTap: () => setState(() => _walletFilter = o.key),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Sort chips
          Row(children: [
            const Text('Sort:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _sortOptions.map((o) => Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: _SmallChip(
                      label: o.label,
                      selected: _sortFilter == o.key,
                      color: const Color(0xFF1565C0),
                      onTap: () => setState(() => _sortFilter = o.key),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ]),
        ]),
      ),
      const Divider(height: 1),

      Expanded(
        child: customers.when(
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.people_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    _search.isNotEmpty || _walletFilter.isNotEmpty
                        ? 'No customers match this filter'
                        : 'Search for a customer above',
                    style: const TextStyle(color: Colors.grey, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('or tap Add to register a new one',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(salesmanCustomersProvider(_providerKey)),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) => _CustomerTile(
                  customer: list[i],
                  onRefresh: () => ref.invalidate(salesmanCustomersProvider(_providerKey)),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    ]);
  }

  void _showAddCustomerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: const Text('Add Customer'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Name *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (10 digits) *',
                    prefixText: '+91 ', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password (optional, min 6)',
                    border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (nameCtrl.text.isEmpty || phoneCtrl.text.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Name and valid phone required')));
                  return;
                }
                setDs(() => saving = true);
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(Endpoints.salesmanCustomers, data: {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    if (passCtrl.text.length >= 6) 'password': passCtrl.text,
                  });
                  ref.invalidate(salesmanCustomersProvider(_providerKey));
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Customer added ✅'),
                            backgroundColor: Color(0xFF2E7D32)));
                  }
                } on DioException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.response?.data['error'] ?? 'Error')));
                  }
                } finally {
                  if (dialogCtx.mounted) setDs(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Add Customer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onRefresh;
  const _CustomerTile({required this.customer, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id      = customer['id'] as int;
    final name    = customer['name'] as String;
    final phone   = customer['phone'] as String;
    final balance = (customer['wallet_balance'] as num).toDouble();
    final email   = customer['email'] as String?;
    final isLow = balance < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar
          CircleAvatar(
            backgroundColor: const Color(0xFF2E7D32),
            radius: 20,
            child: Text(name.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('+91 $phone',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (email != null)
              Text(email, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLow ? Colors.red.shade50 : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isLow ? Colors.red.shade200 : const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 12, color: isLow ? Colors.red : const Color(0xFF2E7D32)),
                  const SizedBox(width: 4),
                  Text('₹${balance.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLow ? Colors.red : const Color(0xFF2E7D32))),
                ]),
              ),
              if (isLow) ...[
                const SizedBox(width: 6),
                Text('Low balance', style: TextStyle(fontSize: 10, color: Colors.red.shade600)),
              ],
            ]),
          ])),

          // Actions
          Column(mainAxisSize: MainAxisSize.min, children: [
            // Place order
            IconButton(
              icon: const Icon(Icons.add_shopping_cart_outlined,
                  color: Color(0xFF2E7D32), size: 20),
              tooltip: 'Place Order',
              onPressed: () async {
                final placed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const PlaceOrderForCustomerScreen(),
                  ),
                );
                if (placed == true) onRefresh();
              },
            ),
            // Reset password
            IconButton(
              icon: const Icon(Icons.lock_reset, color: Colors.orange, size: 20),
              tooltip: 'Reset Password',
              onPressed: () => _showResetPasswordDialog(context, ref, id, name),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext ctx, WidgetRef ref, int id, String name) {
    final passCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Reset: $name'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'New Password (min 6)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (passCtrl.text.length < 6) return;
              final dio = ref.read(dioProvider);
              await dio.put(Endpoints.salesmanResetCustomerPassword(id),
                  data: {'new_password': passCtrl.text});
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Password reset for $name ✅')));
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ── Tab 3: History ────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();
  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _section = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static DateTime get _defaultFrom {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }
  static DateTime get _defaultTo {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String get _providerKey =>
      '${_fmt(_dateFrom ?? _defaultFrom)}|${_fmt(_dateTo ?? _defaultTo)}|$_search';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final effectiveTo = (_dateTo ?? _defaultTo).isAfter(now) ? now : (_dateTo ?? _defaultTo);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 60)),
      initialDateRange: DateTimeRange(
          start: _dateFrom ?? _defaultFrom,
          end:   effectiveTo),
      helpText: 'Filter by Date',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32))),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(salesmanHistoryProvider(_providerKey));
    final from = _dateFrom ?? _defaultFrom;
    final to   = _dateTo   ?? _defaultTo;

    // Extract data outside when() so filter strip never loses state
    final d = historyAsync.value;
    final completed   = (d?['completed_orders']   as List?)?.cast<Map<String, dynamic>>() ?? [];
    final cancelled   = (d?['cancelled_orders']   as List?)?.cast<Map<String, dynamic>>() ?? [];
    final collections = (d?['approved_collections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final approvedOrders = (d?['approved_orders']    as List?)?.cast<Map<String, dynamic>>() ?? [];
    final settlements = (d?['settlements'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalDelivered = completed.fold<double>(0, (s, o) => s + (o['final_amount'] as num).toDouble());
    final totalCollected = collections.fold<double>(0, (s, o) => s + (o['amount'] as num).toDouble());

    return Column(children: [
      // ── Filter strip — outside when() so TextField never loses focus ──────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search by order #, customer, product, category…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _SummaryPill('✅ ${completed.length}', '₹${totalDelivered.toStringAsFixed(0)}', const Color(0xFF2E7D32)),
            const SizedBox(width: 6),
            _SummaryPill('📋 ${approvedOrders.length}', 'approved', Colors.indigo),
            const SizedBox(width: 6),
            _SummaryPill('❌ ${cancelled.length}', 'cancelled', Colors.red),
            const SizedBox(width: 6),
            _SummaryPill('💵 ${collections.length}', '₹${totalCollected.toStringAsFixed(0)}', Colors.orange.shade700),
            const SizedBox(width: 6),
            _SummaryPill('🏦 ${settlements.length}', 'settled', Colors.blueGrey),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _HChip('All', _section == 'all', () => setState(() => _section = 'all')),
              const SizedBox(width: 6),
              _HChip('✅ Delivered', _section == 'delivered', () => setState(() => _section = 'delivered'), color: const Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              _HChip('📋 Approved', _section == 'approved', () => setState(() => _section = 'approved'), color: Colors.indigo),
              const SizedBox(width: 6),
              _HChip('❌ Cancelled', _section == 'cancelled', () => setState(() => _section = 'cancelled'), color: Colors.red),
              const SizedBox(width: 6),
              _HChip('💵 Collections', _section == 'collections', () => setState(() => _section = 'collections'), color: Colors.orange.shade700),
              const SizedBox(width: 6),
              _HChip('🏦 Settlements', _section == 'settlements', () => setState(() => _section = 'settlements'), color: Colors.blueGrey),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _dateFrom != null ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _dateFrom != null ? const Color(0xFF2E7D32) : Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range, size: 16, color: _dateFrom != null ? const Color(0xFF2E7D32) : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '${_fmt(from)} → ${_fmt(to)}',
                      style: TextStyle(fontSize: 12,
                        color: _dateFrom != null ? const Color(0xFF2E7D32) : Colors.grey.shade700,
                        fontWeight: _dateFrom != null ? FontWeight.w600 : FontWeight.normal),
                    )),
                    const Icon(Icons.edit_calendar_outlined, size: 14, color: Colors.grey),
                  ]),
                ),
              ),
            ),
            if (_dateFrom != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200)),
                  child: Icon(Icons.close, size: 16, color: Colors.red.shade700),
                ),
              ),
            ],
          ]),
        ]),
      ),
      const Divider(height: 1),

      // ── Content — only this rebuilds on provider change ───────────────────
      Expanded(
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (_) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(salesmanHistoryProvider(_providerKey)),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              if (_section == 'all' || _section == 'approved') ...[
                _SectionHeader('Approved Orders', approvedOrders.length, Colors.indigo),
                const SizedBox(height: 8),
                approvedOrders.isEmpty
                    ? _Empty('No approved orders in this period')
                    : Column(children: approvedOrders.map((o) => _ApprovedOrderTile(order: o)).toList()),
                const SizedBox(height: 20),
              ],
              if (_section == 'all' || _section == 'delivered') ...[
                _SectionHeader('Deliveries Completed', completed.length, const Color(0xFF2E7D32)),
                const SizedBox(height: 8),
                completed.isEmpty ? _Empty('No deliveries in this period')
                    : Column(children: completed.map((o) => _DeliveryHistoryTile(order: o)).toList()),
                const SizedBox(height: 20),
              ],
              if (_section == 'all' || _section == 'cancelled') ...[
                _SectionHeader('Cancelled Orders', cancelled.length, Colors.red),
                const SizedBox(height: 8),
                cancelled.isEmpty ? _Empty('No cancellations in this period')
                    : Column(children: cancelled.map((o) => _CancelledOrderTile(order: o)).toList()),
                const SizedBox(height: 20),
              ],
              if (_section == 'all' || _section == 'collections') ...[
                _SectionHeader('Approved Collections', collections.length, Colors.orange.shade700),
                const SizedBox(height: 8),
                collections.isEmpty ? _Empty('No collections in this period')
                    : Column(children: collections.map((r) => _HistoryCollectionTile(r: r)).toList()),
                const SizedBox(height: 20),
              ],
              if (_section == 'all' || _section == 'settlements') ...[
                _SectionHeader('Settlement History', settlements.length, Colors.blueGrey),
                const SizedBox(height: 8),
                settlements.isEmpty ? _Empty('No settlements yet')
                    : Column(children: settlements.map((s) => _SettlementTile(s: s)).toList()),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ── Shared history widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader(this.title, this.count, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    const SizedBox(width: 8),
    if (count > 0)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Text('$count',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
  ]);
}

class _SummaryPill extends StatelessWidget {
  final String label, sub;
  final Color color;
  const _SummaryPill(this.label, this.sub, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(sub, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
      ]),
    ),
  );
}

class _HChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _HChip(this.label, this.selected, this.onTap,
      {this.color = const Color(0xFF2E7D32)});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87)),
    ),
  );
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty(this.msg);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 13)),
  );
}

class _DeliveryHistoryTile extends StatelessWidget {
  final Map<String, dynamic> order;
  const _DeliveryHistoryTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final customerName = order['customer_name'] as String? ?? '';
    final city = order['city'] as String? ?? '';
    final raw = order['delivered_at'] as String? ?? order['delivery_date'] as String? ?? '';
    final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final amount = (order['final_amount'] as num).toDouble();
    final items = (order['items'] as List? ?? []).cast<Map<String, dynamic>>();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(radius: 14, backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.check, color: Color(0xFF2E7D32), size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${order['order_number']}  •  $customerName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('$city  •  $date',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          ]),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...items.map((i) {
              final isAdj = i['is_weight_adjusted'] == 1;
              final est = (i['estimated_qty'] as num).toDouble();
              final act = i['actual_qty'] != null ? (i['actual_qty'] as num).toDouble() : null;
              final unit = i['unit'] as String? ?? '';
              return Row(children: [
                const SizedBox(width: 4),
                Expanded(child: Text(i['product_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 12))),
                if (isAdj && act != null) ...[
                  Text('${act.toStringAsFixed(2)} $unit',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32))),
                  if ((act - est).abs() > 0.01)
                    Text('  (est ${est.toStringAsFixed(2)})',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  const Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.scale, size: 12, color: Colors.orange)),
                ] else
                  Text('${est.toStringAsFixed(2)} $unit',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]);
            }),
          ],
        ]),
      ),
    );
  }
}

class _CancelledOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  const _CancelledOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final customerName  = order['customer_name'] as String? ?? '';
    final customerPhone = order['customer_phone'] as String? ?? '';
    final city          = order['city'] as String? ?? '';
    final addrLine      = order['address_line'] as String? ?? '';
    final deliveryDate  = order['delivery_date'] as String? ?? '';
    final amount        = (order['final_amount'] as num).toDouble();
    final orderNum      = order['order_number'] as String? ?? '#${order['id']}';
    final reason        = order['cancelled_reason'] as String?;
    final isPickup      = order['order_type'] == 'pickup';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cancel_outlined, size: 13, color: Colors.red),
                SizedBox(width: 4),
                Text('CANCELLED', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(orderNum, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('₹${amount.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: Colors.red.shade600)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text('$customerName  •  +91 $customerPhone',
                style: const TextStyle(fontSize: 13))),
            if ((order['customer_wallet_balance'] as num?)?.toDouble() != null &&
                (order['customer_wallet_balance'] as num).toDouble() < 0)
              _NegativeWalletBadge(
                  balance: (order['customer_wallet_balance'] as num).toDouble()),
          ]),
          if (addrLine.isNotEmpty || city.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              Icon(isPickup ? Icons.store_outlined : Icons.location_on_outlined,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(
                isPickup ? 'Pickup at farm' : '$addrLine${city.isNotEmpty ? ', $city' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
            ]),
          ],
          if (deliveryDate.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 6),
              Text(deliveryDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ],
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 13, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(child: Text(reason,
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ApprovedOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  const _ApprovedOrderTile({required this.order});

  Color _statusColor(String s) => switch (s) {
    'delivered'  => const Color(0xFF2E7D32),
    'cancelled'  => Colors.red,
    'dispatched' => Colors.blue,
    'assigned'   => Colors.indigo,
    'confirmed'  => const Color(0xFF0277BD),
    _ => Colors.orange,
  };

  IconData _statusIcon(String s) => switch (s) {
    'delivered'  => Icons.done_all,
    'cancelled'  => Icons.cancel_outlined,
    'dispatched' => Icons.local_shipping_outlined,
    'assigned'   => Icons.person_pin,
    'confirmed'  => Icons.check_circle_outline,
    _ => Icons.hourglass_empty,
  };

  @override
  Widget build(BuildContext context) {
    final orderNum      = order['order_number'] as String? ?? '';
    final customerName  = order['customer_name'] as String? ?? '';
    final customerPhone = order['customer_phone'] as String? ?? '';
    final city          = order['city'] as String? ?? '';
    final addrLine      = order['address_line'] as String? ?? '';
    final deliveryDate  = order['delivery_date'] as String? ?? '';
    final amount        = (order['final_amount'] as num).toDouble();
    final status        = order['status'] as String? ?? '';
    final isPickup      = order['order_type'] == 'pickup';
    final assignedAt    = order['assigned_at'] as String?;

    final color = _statusColor(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_statusIcon(status), size: 13, color: color),
                const SizedBox(width: 4),
                Text(status.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
              ]),
            ),
            const SizedBox(width: 8),
            Text('#$orderNum', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('₹${amount.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text('$customerName  •  +91 $customerPhone',
                style: const TextStyle(fontSize: 13))),
            if ((order['customer_wallet_balance'] as num?)?.toDouble() != null &&
                (order['customer_wallet_balance'] as num).toDouble() < 0)
              _NegativeWalletBadge(
                  balance: (order['customer_wallet_balance'] as num).toDouble()),
          ]),
          if (!isPickup && (addrLine.isNotEmpty || city.isNotEmpty)) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(
                '$addrLine${city.isNotEmpty ? ', $city' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
            ]),
          ],
          if (isPickup) ...[
            const SizedBox(height: 3),
            const Row(children: [
              Icon(Icons.store_outlined, size: 13, color: Colors.teal),
              SizedBox(width: 6),
              Text('Pickup at farm', style: TextStyle(fontSize: 12, color: Colors.teal)),
            ]),
          ],
          if (deliveryDate.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
              const SizedBox(width: 6),
              Text(deliveryDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (assignedAt != null) ...[
                const Text('  •  Approved: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(assignedAt.substring(0, 10),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

class _HistoryCollectionTile extends StatelessWidget {
  final Map<String, dynamic> r;
  const _HistoryCollectionTile({required this.r});
  @override
  Widget build(BuildContext context) {
    final amount = (r['amount'] as num).toDouble();
    final customer = r['customer_name'] as String? ?? '';
    final date = (r['created_at'] as String).substring(0, 10);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.check, color: Color(0xFF2E7D32), size: 18)),
        title: Text('₹${amount.toStringAsFixed(0)} — $customer',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  final Map<String, dynamic> s;
  const _SettlementTile({required this.s});
  @override
  Widget build(BuildContext context) {
    final amount = (s['amount'] as num).toDouble();
    final date = (s['created_at'] as String).substring(0, 10);
    final note = s['note'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.account_balance, color: Color(0xFF2E7D32), size: 18)),
        title: Text('₹${amount.toStringAsFixed(0)} settled to central account',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('$date${note != null ? '  •  $note' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }
}

// ── Tab 4: Deliveries ─────────────────────────────────────────────────────────

class _DeliveriesTab extends ConsumerWidget {
  final AsyncValue<Map<String, dynamic>> dashboard;
  const _DeliveriesTab({required this.dashboard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return dashboard.when(
      data: (d) {
        final orders = (d['assigned_orders'] as List? ?? []).cast<Map<String, dynamic>>();
        final completedToday = d['completed_today'] as int? ?? 0;

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(salesmanDashboardProvider),
          child: orders.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.local_shipping_outlined, size: 72, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('No deliveries assigned', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    if (completedToday > 0) ...[
                      const SizedBox(height: 6),
                      Text('$completedToday delivered today ✅',
                          style: const TextStyle(color: Colors.green, fontSize: 13)),
                    ],
                  ]),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (completedToday > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Text('$completedToday delivered today',
                            style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  const Text('Assigned Deliveries',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  ...orders.map((o) => _DeliveryOrderCard(order: o,
                      onRefresh: () => ref.invalidate(salesmanDashboardProvider))),
                ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _DeliveryOrderCard extends ConsumerWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  const _DeliveryOrderCard({required this.order, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = order['delivery_status'] as String? ?? 'pending';
    final deliveryId = order['delivery_id'] as int;
    final orderId = order['id'] as int;
    final amount = (order['final_amount'] as num).toDouble();
    final isPickup = order['order_type'] == 'pickup';

    Color statusColor = status == 'picked' ? Colors.blue : Colors.orange;
    String statusLabel = status == 'picked' ? 'Picked Up' : 'Assigned';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/$orderId'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long, color: Color(0xFF2E7D32), size: 18),
            const SizedBox(width: 8),
            Text('Order #${order['order_number']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (isPickup) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal.shade200)),
                child: Text('🏪 Pickup',
                    style: TextStyle(fontSize: 10, color: Colors.teal.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
            ),
          ]),
          const Divider(height: 14),
          Row(children: [
            const Icon(Icons.person_outline, size: 15, color: Colors.grey),
            const SizedBox(width: 6),
            Text('${order['customer_name']}  •  +91 ${order['customer_phone']}',
                style: const TextStyle(fontSize: 13)),
          ]),
          if (isPickup) ...[
            const SizedBox(height: 4),
            const Row(children: [
              Icon(Icons.store_outlined, size: 15, color: Colors.teal),
              SizedBox(width: 6),
              Text('Customer picks up at farm', style: TextStyle(fontSize: 13, color: Colors.teal)),
            ]),
          ] else if (order['address_line'] != null) ...[
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_outlined, size: 15, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text('${order['address_line']}, ${order['city'] ?? ''}',
                  style: const TextStyle(fontSize: 13))),
            ]),
          ],
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.schedule_outlined, size: 15, color: Colors.grey),
            const SizedBox(width: 6),
            Text('${order['delivery_date']}  •  ${order['slot_label'] ?? 'Any time'}',
                style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32), fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          // Show items
          ...(order['items'] as List? ?? []).map((i) {
            final isWeightAdj = i['is_weight_adjusted'] == 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                const Icon(Icons.circle, size: 6, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text('${i['product_name']}', style: const TextStyle(fontSize: 12))),
                Text('${(i['estimated_qty'] as num).toStringAsFixed(2)} ${i['unit']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (isWeightAdj) const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.scale, size: 12, color: Colors.orange),
                ),
              ]),
            );
          }),
          const SizedBox(height: 12),
          Row(children: [
            if (isPickup && status == 'assigned') ...[
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open & Mark Collected'),
                  onPressed: () => context.push('/orders/$orderId'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ),
            ] else if (!isPickup && status == 'assigned') ...[
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Mark Picked Up'),
                  onPressed: () => _markPicked(context, ref, deliveryId),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ),
            ],
            if (!isPickup && status == 'picked') ...[
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open & Mark Delivered'),
                  onPressed: () => context.push('/orders/$orderId'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
                ),
              ),
            ],
          ]),
        ]),
      ),
      ),
    );
  }

  Future<void> _markPicked(BuildContext context, WidgetRef ref, int deliveryId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put(Endpoints.salesmanMarkPicked(deliveryId));
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Marked as picked up ✅'),
          backgroundColor: Colors.blue,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final int count;
  final Color color;
  final IconData icon;
  const _StatCard({required this.label, required this.value,
      required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text('$count item(s)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    )),
  );
}

// ── Tab 5: Stock Management ───────────────────────────────────────────────────

class _StockTab extends ConsumerWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(salesmanProductsProvider);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (products) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(salesmanProductsProvider),
        child: products.isEmpty
            ? const Center(child: Text('No products', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: products.length,
                itemBuilder: (_, i) => _StockProductTile(
                  product: products[i],
                  onChanged: () => ref.invalidate(salesmanProductsProvider),
                ),
              ),
      ),
    );
  }
}

class _StockProductTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onChanged;
  const _StockProductTile({required this.product, required this.onChanged});

  @override
  ConsumerState<_StockProductTile> createState() => _StockProductTileState();
}

class _StockProductTileState extends ConsumerState<_StockProductTile> {
  bool _updating = false;

  Future<void> _editStock() async {
    final id = widget.product['id'] as int;
    final name = widget.product['name'] as String;
    final unit = widget.product['unit'] as String? ?? '';
    final currentStock = (widget.product['stock_qty'] as num).toDouble();
    final ctrl = TextEditingController(text: currentStock.toStringAsFixed(2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Update Stock: $name'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Stock quantity ($unit)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final newQty = double.tryParse(ctrl.text);
    if (newQty == null) return;

    setState(() => _updating = true);
    try {
      await ref.read(dioProvider).patch(
        Endpoints.salesmanProductStock(id),
        data: {'stock_qty': newQty},
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _toggleActive(bool value) async {
    final id = widget.product['id'] as int;
    setState(() => _updating = true);
    try {
      await ref.read(dioProvider).patch(
        Endpoints.salesmanProductStock(id),
        data: {'is_active': value},
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final name = p['name'] as String;
    final unit = p['unit'] as String? ?? '';
    final stock = (p['stock_qty'] as num).toDouble();
    final isActive = (p['is_active'] as int? ?? 1) == 1;
    final lowThreshold = (p['low_stock_threshold'] as num?)?.toDouble() ?? 5;
    final category = p['category_name'] as String?;
    final isLow = stock <= lowThreshold;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
          child: Text(
            name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: isActive ? const Color(0xFF2E7D32) : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Stock: '),
            Text(
              '${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 2)} $unit',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isLow ? Colors.red : const Color(0xFF2E7D32),
              ),
            ),
            if (isLow) ...[
              const SizedBox(width: 6),
              const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
              const Text(' Low', style: TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ]),
          if (category != null)
            Text(category, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        trailing: _updating
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(
                  value: isActive,
                  activeThumbColor: const Color(0xFF2E7D32),
                  onChanged: _updating ? null : _toggleActive,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Update stock',
                  onPressed: _updating ? null : _editStock,
                ),
              ]),
      ),
    );
  }
}

// ── Small filter chip (used in salesman customers tab) ────────────────────────

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _SmallChip({required this.label, required this.selected,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? color : Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          )),
    ),
  );
}

// ── Negative wallet badge — shared across order tiles ─────────────────────────

class _NegativeWalletBadge extends StatelessWidget {
  final double balance;
  const _NegativeWalletBadge({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.red.shade300),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.account_balance_wallet, size: 11, color: Colors.red.shade700),
      const SizedBox(width: 3),
      Text('₹${balance.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: Colors.red.shade700)),
    ]),
  );
}
