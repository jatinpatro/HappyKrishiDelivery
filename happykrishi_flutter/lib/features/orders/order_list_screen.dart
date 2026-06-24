import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/services/pdf_service.dart';
import '../../core/widgets/active_filter.dart';
import '../../core/widgets/filter_chip_bar.dart';
import '../../core/utils/error_handler.dart';

final ordersProvider = FutureProvider.autoDispose.family<List<Order>, String>((ref, key) async {
  // key = "search|status|dateFrom|dateTo"
  final parts    = key.split('|');
  final search   = parts[0];
  final status   = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final dateFrom = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final dateTo   = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
  final dio = ref.read(dioProvider);
  final params = <String, String>{'limit': '200'};
  if (search.isNotEmpty) params['search']    = search;
  if (status   != null)  params['status']    = status;
  if (dateFrom != null)  params['date_from'] = dateFrom;
  if (dateTo   != null)  params['date_to']   = dateTo;
  final res = await dio.get(Endpoints.orders, queryParameters: params);
  return (res.data['orders'] as List).map((e) => Order.fromJson(e)).toList();
});

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});
  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  String? _statusFilter;
  String _search = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _searchCtrl = TextEditingController();
  List<ActiveFilter> _activeFilters = [];

  static const _filterDefs = [
    FilterDefinition(field: 'finalAmount', label: 'Amount', type: FilterType.number),
    FilterDefinition(field: 'city', label: 'City', type: FilterType.text),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _hasDate => _dateFrom != null || _dateTo != null;

  String get _providerKey =>
      '$_search|${_statusFilter ?? ''}|${_dateFrom != null ? _fmt(_dateFrom!) : ''}|${_dateTo != null ? _fmt(_dateTo!) : ''}';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
    );
    if (picked != null) setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
  }

  static const _statuses = [
    (key: 'pending',    label: '⏳ Pending',    color: Color(0xFFE65100)),
    (key: 'confirmed',  label: '✅ Confirmed',   color: Color(0xFF0277BD)),
    (key: 'assigned',   label: '🚴 Assigned',    color: Color(0xFF6A1B9A)),
    (key: 'dispatched', label: '🚚 Dispatched',  color: Color(0xFF00838F)),
    (key: 'delivered',  label: '📦 Delivered',   color: Color(0xFF2E7D32)),
    (key: 'cancelled',  label: '❌ Cancelled',   color: Color(0xFFC62828)),
  ];

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider(_providerKey));
    final user = ref.watch(authStateProvider).user;
    final walletBalance = user?.walletBalance ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download Order History',
            onPressed: () {
              final list = orders.value ?? [];
              if (user == null || list.isEmpty) return;
              PdfService.shareOrderHistory(context: context, user: user, orders: list);
            },
          ),
        ],
      ),
      body: Column(children: [

        // ── Negative balance banner ────────────────────────────────────────
        if (walletBalance < 0)
          GestureDetector(
            onTap: () => context.go('/wallet'),
            child: Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Wallet balance is ₹${walletBalance.toStringAsFixed(2)}. Top up to place new orders.',
                    style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 13),
              ]),
            ),
          ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Search bar
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by order #, product, category…',
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
            // Date range filter
            GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _hasDate ? const Color(0xFF2E7D32).withValues(alpha: 0.08) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.date_range_outlined,
                      size: 16, color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasDate
                          ? '${_dateFrom != null ? _fmt(_dateFrom!) : '…'}  →  ${_dateTo != null ? _fmt(_dateTo!) : '…'}'
                          : 'Filter by date',
                      style: TextStyle(
                        fontSize: 13,
                        color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey,
                      ),
                    ),
                  ),
                  if (_hasDate)
                    GestureDetector(
                      onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            FilterChipBar(
              availableFilters: _filterDefs,
              activeFilters: _activeFilters,
              onAdd: (f) => setState(() => _activeFilters = [..._activeFilters.where((e) => e.field != f.field), f]),
              onRemove: (f) => setState(() => _activeFilters = _activeFilters.where((e) => e.field != f.field).toList()),
            ),
            const SizedBox(height: 10),
            // Order count
            orders.when(
              data: (list) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${list.length} order${list.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(
                    label: 'All',
                    selected: _statusFilter == null,
                    color: const Color(0xFF2E7D32),
                    onTap: () => setState(() => _statusFilter = null),
                  ),
                  ..._statuses.map((s) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _Chip(
                      label: s.label,
                      selected: _statusFilter == s.key,
                      color: s.color,
                      onTap: () => setState(() =>
                          _statusFilter = _statusFilter == s.key ? null : s.key),
                    ),
                  )),
                ],
              ),
            ),
          ]),
        ),
        const Divider(height: 1),

        // ── Order list ─────────────────────────────────────────────────────
        Expanded(
          child: orders.when(
            data: (list) {
              if (list.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _statusFilter != null ? 'No $_statusFilter orders' : 'No orders yet',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    if (_statusFilter != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() => _statusFilter = null),
                        child: const Text('Show all orders'),
                      ),
                    ],
                  ],
                ));
              }
              final filtered = _filtered(list);
              if (filtered.isEmpty) {
                return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.filter_list_off, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('No ${_statusFilter ?? ''} orders',
                        style: const TextStyle(color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _statusFilter = null),
                      child: const Text('Show all orders'),
                    ),
                  ],
                ));
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(ordersProvider(_providerKey)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _OrderTile(order: filtered[i]),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              logError('orders', e);
              return Center(child: Text(friendlyError(e)));
            },
          ),
        ),
      ]),
    );
  }

  List<Order> _filtered(List<Order> all) {
    if (_activeFilters.isEmpty) return all;
    return all.where((o) {
      for (final f in _activeFilters) {
        switch (f.field) {
          case 'finalAmount':
            final n = o.finalAmount;
            if (f.op == FilterOp.gte && n < (f.value as num)) return false;
            if (f.op == FilterOp.lte && n > (f.value as num)) return false;
            if (f.op == FilterOp.equals && n != (f.value as num)) return false;
          case 'city':
            if (!(o.city?.toLowerCase().contains((f.value as String).toLowerCase()) ?? false)) return false;
        }
      }
      return true;
    }).toList();
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected,
      required this.color, required this.onTap});

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
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          )),
    ),
  );
}

// ── Order tile ────────────────────────────────────────────────────────────────

class _OrderTile extends StatelessWidget {
  final Order order;
  const _OrderTile({required this.order});

  Color _statusColor(String s) => switch (s) {
    'delivered'                  => Colors.green,
    'cancelled'                  => Colors.red,
    'dispatched' || 'assigned'   => Colors.blue,
    _                            => Colors.orange,
  };

  IconData _statusIcon(String s) => switch (s) {
    'delivered'  => Icons.check_circle,
    'cancelled'  => Icons.cancel,
    'dispatched' => Icons.local_shipping,
    'assigned'   => Icons.person_pin,
    'confirmed'  => Icons.thumb_up,
    _            => Icons.hourglass_empty,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('#${order.orderNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_statusIcon(order.status), size: 14,
                      color: _statusColor(order.status)),
                  const SizedBox(width: 4),
                  Text(order.status.toUpperCase(),
                      style: TextStyle(fontSize: 12,
                          color: _statusColor(order.status),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${order.city ?? ''}  •  ${order.slotLabel ?? ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text('Delivery: ${order.deliveryDate}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Text('₹${order.finalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: Color(0xFF2E7D32))),
              const Spacer(),
              if (order.status == 'dispatched' || order.status == 'assigned')
                TextButton.icon(
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('Track'),
                  onPressed: () => context.push('/track/${order.id}'),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
