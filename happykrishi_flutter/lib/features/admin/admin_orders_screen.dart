import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/pdf_service.dart';
import '../orders/order_detail_screen.dart' show orderDetailProvider;
import 'place_order_for_customer_screen.dart';
import '../../core/widgets/active_filter.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/utils/error_handler.dart';

final adminOrdersProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, key) async {
  // key = "status|orderType|filterKey|page"
  final parts     = key.split('|||');
  final mainKey   = parts[0];
  final page      = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;

  final firstPipe  = mainKey.indexOf('|');
  final secondPipe = mainKey.indexOf('|', firstPipe + 1);
  final status    = firstPipe < 0 ? null : mainKey.substring(0, firstPipe);
  final orderType = secondPipe < 0 ? null : mainKey.substring(firstPipe + 1, secondPipe);
  final filterKey = secondPipe < 0 ? '' : mainKey.substring(secondPipe + 1);

  final filterParts = filterKey.split('|');
  final params = <String, dynamic>{};
  if (status    != null && status.isNotEmpty)          params['status']     = status;
  if (orderType != null && orderType.isNotEmpty)        params['order_type'] = orderType;
  if (filterParts.isNotEmpty && filterParts[0].isNotEmpty) params['date_from']  = filterParts[0];
  if (filterParts.length > 1 && filterParts[1].isNotEmpty) params['date_to']    = filterParts[1];
  if (filterParts.length > 2 && filterParts[2].isNotEmpty) params['search']     = filterParts[2];
  for (int i = 3; i < filterParts.length; i++) {
    final seg = filterParts[i].split(':');
    if (seg.length >= 2 && seg[0] == 'salesman_id') params['salesman_id'] = seg[1];
  }
  params['page']  = page;
  params['limit'] = 50;

  final res = await ref.read(dioProvider).get(Endpoints.adminOrders, queryParameters: params);
  return res.data as Map<String, dynamic>;
});

// Status metadata: label, color, icon
const _statusMeta = {
  'pending':    ('Pending',    Color(0xFFE65100), Icons.hourglass_empty),
  'confirmed':  ('Confirmed',  Color(0xFF0277BD), Icons.check_circle_outline),
  'assigned':   ('Assigned',   Color(0xFF6A1B9A), Icons.person_pin),
  'dispatched': ('Dispatched', Color(0xFF00838F), Icons.local_shipping),
  'delivered':  ('Delivered',  AppColors.primary, Icons.done_all),
  'cancelled':  ('Cancelled',  Color(0xFFC62828), Icons.cancel_outlined),
};

const _ordersFilterConfig = FilterFormConfig(
  title: 'Filter Orders',
  showDateRange: true,
  showTextSearch: true,
  textSearchHint: 'Order #, customer, salesman, product…',
  dynamicFields: [
    FilterDefinition(field: 'customer_name', label: 'Customer', type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'salesman_name', label: 'Salesman', type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'final_amount',  label: 'Amount',   type: FilterType.number, serverSide: false),
    FilterDefinition(field: 'city',          label: 'City',     type: FilterType.text,   serverSide: false),
  ],
);

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  String? _statusFilter;
  String? _typeFilter;
  FilterFormState _filter = FilterFormState.empty;

  static const _limit = 50;
  static const _statuses = [null, 'pending', 'confirmed', 'assigned', 'dispatched', 'delivered', 'cancelled'];

  List<Map<String, dynamic>> _allOrders = [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    final nextPage = reset ? 1 : _page + 1;
    if (reset) {
      setState(() { _allOrders = []; _page = 1; _total = 0; _loading = true; });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final params = <String, dynamic>{'page': nextPage, 'limit': _limit};
      if (_statusFilter != null && _statusFilter!.isNotEmpty) params['status'] = _statusFilter;
      if (_typeFilter   != null && _typeFilter!.isNotEmpty)   params['order_type'] = _typeFilter;
      final qp = _filter.toQueryParams();
      params.addAll(qp);
      final res  = await ref.read(dioProvider).get(Endpoints.adminOrders, queryParameters: params);
      final data = res.data as Map<String, dynamic>;
      final orders = List<Map<String, dynamic>>.from(data['orders'] as List);
      final total  = (data['total'] as num?)?.toInt() ?? orders.length;
      setState(() {
        if (reset) {
          _allOrders = orders;
          _page = 1;
        } else {
          _allOrders = [..._allOrders, ...orders];
          _page++;
        }
        _total = total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      logError('admin-orders', e);
      setState(() { _loading = false; _loadingMore = false; });
    }
  }

  bool get _hasMore => _allOrders.length < _total;

  @override
  Widget build(BuildContext context) {
    final localFilters = _filter.toLocalFilters();
    final filtered = localFilters.isEmpty
        ? _allOrders
        : _allOrders.where((o) => matchesAllFilters(o, localFilters)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Orders'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download Report',
            onPressed: () {
              if (_allOrders.isEmpty) return;
              final label = _statusFilter == null && _typeFilter == null
                  ? 'All Orders'
                  : '${_typeFilter?.toUpperCase() ?? ''} ${_statusFilter?.toUpperCase() ?? 'ALL'}'.trim();
              PdfService.shareAdminOrdersReport(context: context, orders: _allOrders, title: label);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(reset: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final placed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PlaceOrderForCustomerScreen()),
          );
          if (placed == true) _load(reset: true);
        },
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Place Order'),
        backgroundColor: AppColors.primary,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(children: [
        // ── Filter header ─────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  _TypeBtn(label: 'All',         value: null,       selected: _typeFilter, onTap: (v) { setState(() => _typeFilter = v); _load(reset: true); }),
                  _TypeBtn(label: '🚚 Delivery', value: 'delivery', selected: _typeFilter, onTap: (v) { setState(() => _typeFilter = v); _load(reset: true); }),
                  _TypeBtn(label: '🏪 Pickup',   value: 'pickup',   selected: _typeFilter, onTap: (v) { setState(() => _typeFilter = v); _load(reset: true); }),
                ]),
              ),
              if (_total > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAF2EA),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('$_total',
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatusChip(label: 'All', value: null, selected: _statusFilter,
                    onTap: () { setState(() => _statusFilter = null); _load(reset: true); }),
                ..._statuses.where((s) => s != null).map((s) {
                  final meta = _statusMeta[s]!;
                  return _StatusChip(
                    label: meta.$1, value: s, selected: _statusFilter,
                    color: meta.$2, icon: meta.$3,
                    onTap: () { setState(() => _statusFilter = _statusFilter == s ? null : s); _load(reset: true); },
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
          ]),
        ),
        // ── FilterBar ────────────────────────────────────────────────────────
        FilterBar(
          config: _ordersFilterConfig,
          state: _filter,
          onChanged: (f) { setState(() => _filter = f); _load(reset: true); },
          onLoad: () => _load(reset: true),
        ),
        const Divider(height: 1),

        // ── Order list ───────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? _EmptyState(statusFilter: _statusFilter)
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: filtered.length + 1,
                        itemBuilder: (_, i) {
                          if (i < filtered.length) {
                            return _AdminOrderTile(
                              order: filtered[i],
                              onRefresh: () => _load(reset: true),
                            );
                          }
                          if (_hasMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : ElevatedButton.icon(
                                        icon: const Icon(Icons.expand_more),
                                        label: Text('Load More (${_allOrders.length} of $_total)'),
                                        onPressed: () => _load(),
                                      ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ── Type button ───────────────────────────────────────────────────────────────

class _TypeBtn extends StatelessWidget {
  final String label;
  final String? value, selected;
  final ValueChanged<String?> onTap;
  const _TypeBtn({required this.label, required this.value,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    const color = AppColors.primary;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.black87,
            )),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final String? value, selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label, required this.value,
    required this.selected, required this.onTap,
    this.color = Colors.grey, this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black87,
              )),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String? statusFilter;
  const _EmptyState({this.statusFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          statusFilter == null ? 'No orders yet' : 'No ${statusFilter!} orders',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text('Pull down to refresh', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ]),
    );
  }
}

// ── Order Tile ────────────────────────────────────────────────────────────────

class _AdminOrderTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  const _AdminOrderTile({required this.order, required this.onRefresh});
  @override
  ConsumerState<_AdminOrderTile> createState() => _AdminOrderTileState();
}

class _AdminOrderTileState extends ConsumerState<_AdminOrderTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final order     = widget.order;
    final onRefresh = widget.onRefresh;
    final status          = order['status'] as String;
    final orderId         = order['id'] as int;
    final amount          = (order['final_amount'] as num).toDouble();
    final isPickup        = order['order_type'] == 'pickup';
    final salesmanName    = order['salesman_name'] as String?;
    final salesmanPhone   = order['salesman_phone'] as String?;
    final customerPhone   = order['customer_phone'] as String? ?? '';
    final cancelledReason = order['cancelled_reason'] as String?;
    final couponCode      = order['coupon_code'] as String?;
    final couponDiscount  = (order['coupon_discount'] as num?)?.toDouble() ?? 0;

    // Smart amount formatter — shows decimals only when needed
    String amt(double v) => v == v.truncateToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');

    final meta        = _statusMeta[status];
    final statusColor = meta?.$2 ?? Colors.grey;
    final statusIcon  = meta?.$3 ?? Icons.circle;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/orders/$orderId'),
        child: Column(children: [
          // ── Colored status bar ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(children: [
              Icon(statusIcon, size: 14, color: statusColor),
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
              if (couponDiscount > 0) ...[
                Text(
                  '₹${amt(amount + couponDiscount)}',
                  style: TextStyle(
                    fontSize: 11, color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text('₹${amt(amount)}',
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
                Text('#${order['order_number']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if ((order['customer_wallet_balance'] as num?)?.toDouble() != null &&
                    (order['customer_wallet_balance'] as num).toDouble() < 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.account_balance_wallet, size: 11, color: Colors.red.shade700),
                      const SizedBox(width: 3),
                      Text('₹${(order['customer_wallet_balance'] as num).toDouble().toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                              color: Colors.red.shade700)),
                    ]),
                  ),
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${order['customer_name']}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ]),
              const SizedBox(height: 5),

              // Customer phone + date + call/WhatsApp
              Row(children: [
                const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Text('+91 $customerPhone',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 6),
                _ContactBtn(phone: customerPhone, isWhatsApp: false),
                _ContactBtn(phone: customerPhone, isWhatsApp: true),
                const Spacer(),
                const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Text('${order['delivery_date'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),

              // Address
              if (!isPickup && order['address_line'] != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 5),
                  Expanded(child: Text(
                    '${order['address_line']}, ${order['city'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ],

              // Coupon discount
              if (couponCode != null && couponDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.discount_outlined, size: 13, color: Colors.green),
                  const SizedBox(width: 5),
                  Text(couponCode,
                      style: const TextStyle(fontSize: 12, color: Colors.green,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(width: 6),
                  Text('-₹${amt(couponDiscount)} off',
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
                  const SizedBox(width: 4),
                  if (salesmanPhone != null) ...[
                    Text('+91 $salesmanPhone',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 4),
                    _ContactBtn(phone: salesmanPhone!, isWhatsApp: false),
                    _ContactBtn(phone: salesmanPhone!, isWhatsApp: true),
                  ],
                ]),
              ],

              // Cancellation reason
              if (status == 'cancelled' && cancelledReason != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 13, color: Colors.red.shade600),
                    const SizedBox(width: 6),
                    Expanded(child: Text(cancelledReason,
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],

              // Action buttons
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _ActionButtons(
                status: status,
                isPickup: isPickup,
                order: order,
                onRefresh: onRefresh,
                onDetails: () => context.push('/orders/$orderId'),
              ),

              // ── Expand/collapse items ─────────────────────────────────
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_expanded ? 'Hide details' : 'Show items & timeline',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: Colors.grey.shade600),
                ]),
              ),

              if (_expanded) ...[
                const SizedBox(height: 8),
                _OrderExpandedDetail(orderId: orderId),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Expanded order detail (items + delivery info) ─────────────────────────────

class _OrderExpandedDetail extends ConsumerWidget {
  final int orderId;
  const _OrderExpandedDetail({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(orderDetailProvider(orderId));

    return detailAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) { logError('admin-order-detail', e); return Text(friendlyError(e),
          style: const TextStyle(color: Colors.red, fontSize: 12)); },
      data: (d) {
        final items    = (d['items'] as List).cast<Map<String, dynamic>>();
        final delivery = d['delivery'] as Map<String, dynamic>?;
        final staffName   = delivery?['agent_name'] as String?;
        final staffPhone  = delivery?['agent_phone'] as String?;
        final assignedAt  = delivery?['assigned_at'] as String?;
        final pickedAt    = delivery?['picked_at'] as String?;
        final deliveredAt = delivery?['delivered_at'] as String?;

        return Container(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Items list
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            ...items.map((i) {
              final est  = (i['estimated_qty'] as num).toDouble();
              final act  = i['actual_qty'] != null ? (i['actual_qty'] as num).toDouble() : null;
              final unit = i['unit'] as String? ?? '';
              final isWt = i['is_weight_adjusted'] == 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(i['product_name'] as String,
                      style: const TextStyle(fontSize: 12))),
                  Text(
                    isWt && act != null
                        ? '${act.toStringAsFixed(2)} $unit${(act - est).abs() > 0.01 ? ' (est ${est.toStringAsFixed(2)})' : ''}'
                        : '${est.toStringAsFixed(2)} $unit',
                    style: TextStyle(fontSize: 12, color: isWt ? Colors.orange : Colors.grey),
                  ),
                  if (isWt) const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.scale, size: 12, color: Colors.orange),
                  ),
                ]),
              );
            }),

            // Delivery timeline
            if (staffName != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text('Delivery Timeline',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              _TimelineRow(Icons.badge_outlined, Colors.indigo,
                  '$staffName  •  +91 ${staffPhone ?? ''}', null),
              if (assignedAt != null)
                _TimelineRow(Icons.assignment_turned_in_outlined, Colors.blue,
                    'Assigned', assignedAt.substring(0, 16)),
              if (pickedAt != null)
                _TimelineRow(Icons.inventory_2_outlined, Colors.orange,
                    'Picked up', pickedAt.substring(0, 16)),
              if (deliveredAt != null)
                _TimelineRow(Icons.done_all, Colors.green,
                    'Delivered', deliveredAt.substring(0, 16)),
            ],
          ]),
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? time;
  const _TimelineRow(this.icon, this.color, this.label, this.time);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
      if (time != null)
        Text(time!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]),
  );
}

// ── Contact button (call or WhatsApp) ────────────────────────────────────────

class _ContactBtn extends StatelessWidget {
  final String phone;
  final bool isWhatsApp;
  const _ContactBtn({required this.phone, required this.isWhatsApp});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = isWhatsApp
            ? Uri.parse('https://wa.me/91$phone')
            : Uri.parse('tel:+91$phone');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isWhatsApp ? Colors.green.shade50 : Colors.blue.shade50,
          shape: BoxShape.circle,
          border: Border.all(
              color: isWhatsApp ? Colors.green.shade200 : Colors.blue.shade200),
        ),
        child: Icon(
          isWhatsApp ? Icons.chat_outlined : Icons.call_outlined,
          size: 13,
          color: isWhatsApp ? Colors.green.shade700 : Colors.blue.shade700,
        ),
      ),
    );
  }
}

// ── Action Buttons — separate widget so state is isolated ─────────────────────

class _ActionButtons extends ConsumerStatefulWidget {
  final String status;
  final bool isPickup;
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  final VoidCallback onDetails;
  const _ActionButtons({
    required this.status, required this.isPickup, required this.order,
    required this.onRefresh, required this.onDetails,
  });
  @override
  ConsumerState<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends ConsumerState<_ActionButtons> {
  bool _loading = false;

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).put(
        Endpoints.adminOrderStatus(widget.order['id'] as int),
        data: {'status': newStatus},
      );
      widget.onRefresh();
    } catch (e, st) {
      logError('admin-orders', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessageDialog(BuildContext context) {
    final order       = widget.order;
    final orderNum    = order['order_number'] as String? ?? '';
    final customer    = order['customer_name'] as String? ?? '';
    final status      = order['status'] as String? ?? '';
    final delivDate   = order['delivery_date'] as String? ?? '';
    final userId      = order['user_id'] as int;

    // Pre-build a context-aware draft message
    final draft = _buildDraft(orderNum, customer, status, delivDate);

    final msgCtrl = TextEditingController(text: draft);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.message_outlined, color: Colors.indigo, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Message to $customer',
              style: const TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.receipt_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 6),
              Text('Order #$orderNum  •  $delivDate',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: msgCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
              hintText: 'Edit message before sending…',
            ),
          ),
          const SizedBox(height: 8),
          const Text('Sent as push notification + WhatsApp',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Send'),
            onPressed: () async {
              if (msgCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref.read(dioProvider).post(Endpoints.adminBroadcast, data: {
                  'user_ids': [userId],
                  'message': msgCtrl.text.trim(),
                  'channels': ['push', 'whatsapp'],
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Message sent to $customer ✅'),
                    backgroundColor: AppColors.primary,
                  ));
                }
              } catch (e, st) {
                logError('admin-orders', e, st);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  String _buildDraft(String orderNum, String customer, String status, String date) {
    switch (status) {
      case 'pending':
        return 'Hi $customer, we\'ve received your order #$orderNum scheduled for $date. We\'re confirming it now — you\'ll hear from us shortly!';
      case 'confirmed':
        return 'Hi $customer, your order #$orderNum is confirmed and being prepared for delivery on $date. 🌿';
      case 'assigned':
        return 'Hi $customer, your order #$orderNum has been assigned to a delivery person and will be delivered on $date.';
      case 'dispatched':
        return 'Hi $customer, your order #$orderNum is on the way! Expect delivery today ($date). 🚚';
      case 'delivered':
        return 'Hi $customer, your order #$orderNum has been delivered. Hope you enjoy your fresh produce! 🌿 Thank you for choosing HappyKrishi.';
      case 'cancelled':
        return 'Hi $customer, regarding your order #$orderNum — please contact us if you have any questions about the cancellation.';
      default:
        return 'Hi $customer, update on your order #$orderNum ($date): ';
    }
  }

  Future<void> _cancelWithReason() async {
    final reasonCtrl = TextEditingController();
    final orderId = widget.order['id'] as int;
    final orderNum = widget.order['order_number'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDs) => AlertDialog(
        title: Text('Cancel Order #$orderNum?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'The full amount will be refunded to the customer\'s wallet immediately.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: reasonCtrl,
            autofocus: true,
            maxLines: 3,
            onChanged: (_) => setDs(() {}),
            decoration: const InputDecoration(
              labelText: 'Reason for cancellation *',
              hintText: 'e.g. Customer requested, stock issue...',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          ElevatedButton(
            onPressed: reasonCtrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Cancel Order'),
          ),
        ],
      )),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(
        Endpoints.staffCancelOrder(orderId, 'admin'),
        data: {'reason': reasonCtrl.text.trim()},
      );
      widget.onRefresh();
      if (mounted) _snack('Order cancelled. Refund sent to wallet.', color: AppColors.primary);
    } catch (e, st) {
      logError('admin-orders', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markCollected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Collected?'),
        content: const Text('Confirm the customer has collected this pickup order.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Yes, Collected'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminMarkCollected(widget.order['id'] as int));
      widget.onRefresh();
      if (mounted) _snack('Pickup marked as collected ✅', color: AppColors.primary);
    } catch (e, st) {
      logError('admin-orders', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assignAgent() async {
    final dio = ref.read(dioProvider);
    final res = await dio.get(Endpoints.adminSalesmen);
    final salesmen = List<Map<String, dynamic>>.from(res.data['salesmen'] ?? res.data['agents'] ?? []);
    if (!mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Assign Salesman'),
        children: salesmen.map((s) {
          final active = (s['is_active'] as int? ?? 1) == 1;
          return SimpleDialogOption(
            onPressed: active ? () => Navigator.pop(ctx, s['id'] as int) : null,
            child: ListTile(
              dense: true,
              enabled: active,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: active ? AppColors.primary : Colors.grey.shade400,
                child: Text((s['name'] as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text(s['name'] as String,
                  style: TextStyle(color: active ? null : Colors.grey)),
              subtitle: Text(
                active ? '🟢 Active' : '🔴 Disabled',
                style: TextStyle(fontSize: 11, color: active ? Colors.green.shade700 : Colors.red.shade400),
              ),
              trailing: active ? null : const Icon(Icons.block, size: 16, color: Colors.grey),
            ),
          );
        }).toList(),
      ),
    );
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      await dio.post(Endpoints.adminAssignAgent(widget.order['id'] as int), data: {'agent_id': picked});
      widget.onRefresh();
    } catch (e, st) {
      logError('admin-orders', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _waiveDelivery(BuildContext ctx, double currentCharge) async {
    final amtCtrl = TextEditingController(text: currentCharge.toStringAsFixed(0));
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Waive Delivery Charge?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current delivery charge: ₹${currentCharge.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount to waive (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'This amount will be credited to customer wallet',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text('Waive & Credit Wallet'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(amtCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Enter a valid amount');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(
        Endpoints.adminWaiveDelivery(widget.order['id'] as int),
        data: {
          'amount': amount,
          if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
        },
      );
      widget.onRefresh();
      if (mounted) _snack('₹${amount.toStringAsFixed(0)} waived — credited to customer wallet ✅', color: Colors.teal);
    } catch (e, st) {
      logError('admin-waive-delivery', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final isPickup = widget.isPickup;

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    // Build the relevant action buttons for this status
    final List<Widget> primary = [];
    final List<Widget> secondary = [];

    switch (status) {
      case 'pending':
        primary.add(_btn('Confirm Order', Icons.check_circle_outline, Colors.teal,
            () => _updateStatus('confirmed')));
        secondary.add(_outlineBtn('Cancel', Icons.close, Colors.red, _cancelWithReason));

      case 'confirmed':
        primary.add(_btn('Assign Salesman', Icons.person_add_outlined, Colors.indigo, _assignAgent));
        secondary.add(_outlineBtn('Cancel', Icons.close, Colors.red, _cancelWithReason));

      case 'assigned':
        if (isPickup) {
          primary.add(_btn('Mark Collected', Icons.store_outlined, AppColors.primary, _markCollected));
        } else {
          primary.add(_btn('Mark Dispatched', Icons.local_shipping_outlined, Colors.blue,
              () => _updateStatus('dispatched')));
        }
        secondary.add(_outlineBtn('Cancel', Icons.close, Colors.red, _cancelWithReason));

      case 'dispatched':
        primary.add(_btn('Mark Delivered', Icons.done_all, AppColors.primary,
            () => _updateStatus('delivered')));
        secondary.add(_outlineBtn('Cancel', Icons.close, Colors.red, _cancelWithReason));
    }

    // Message + Details always shown
    final deliveryCharge = (widget.order['delivery_charge'] as num?)?.toDouble() ?? 0;
    if (!isPickup && deliveryCharge > 0 && !['delivered', 'cancelled'].contains(status)) {
      secondary.add(
        TextButton.icon(
          icon: Icon(Icons.money_off_outlined, size: 14, color: Colors.teal.shade600),
          label: Text('Waive Delivery', style: TextStyle(color: Colors.teal.shade600)),
          onPressed: () => _waiveDelivery(context, deliveryCharge),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }
    if (['assigned', 'dispatched'].contains(status) && !isPickup) {
      secondary.add(
        TextButton.icon(
          icon: const Icon(Icons.map_outlined, size: 14),
          label: const Text('Track'),
          onPressed: () => context.push('/admin/track/${widget.order['id']}'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }
    secondary.add(
      TextButton.icon(
        icon: const Icon(Icons.message_outlined, size: 14),
        label: const Text('Message'),
        onPressed: () => _showMessageDialog(context),
        style: TextButton.styleFrom(
          foregroundColor: Colors.indigo.shade600,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
    secondary.add(
      TextButton.icon(
        icon: const Icon(Icons.open_in_new, size: 14),
        label: const Text('Full Details'),
        onPressed: widget.onDetails,
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade600,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );

    // Split secondary into cancel (outlined) vs text actions
    final cancelBtns    = secondary.whereType<OutlinedButton>().cast<Widget>().toList();
    final textActionBtns = secondary.where((w) => w is! OutlinedButton).toList();

    if (primary.isEmpty && secondary.length == 1) {
      // delivered / cancelled — just show the details link aligned right
      return Align(alignment: Alignment.centerRight, child: secondary.first);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Primary action (full-width)
      if (primary.isNotEmpty) ...[
        ...primary,
        const SizedBox(height: 6),
      ],
      // Cancel button — full width, its own row
      if (cancelBtns.isNotEmpty) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Cancel Order'),
            onPressed: _cancelWithReason,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
      // Text action buttons — wrapping row
      if (textActionBtns.isNotEmpty)
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: textActionBtns,
        ),
    ]);
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback onPressed) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(icon, size: 16),
          label: Text(label),
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      );

  Widget _outlineBtn(String label, IconData icon, Color color, VoidCallback onPressed) =>
      OutlinedButton.icon(
        icon: Icon(icon, size: 14),
        label: Text(label),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}


