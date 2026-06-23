import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/pdf_service.dart';

final analyticsProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, Map<String, String>>((ref, params) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminAnalytics, queryParameters: params);
  return res.data as Map<String, dynamic>;
});

final salesReportProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, Map<String, String>>((ref, params) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminSalesReport, queryParameters: params);
  return res.data as Map<String, dynamic>;
});

final customerActivityProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, String>((ref, segment) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminCustomerActivity,
      queryParameters: segment == 'all' ? null : {'segment': segment});
  return res.data as Map<String, dynamic>;
});

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override
  ConsumerState<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _period = '30';
  String _groupBy = 'day';

  Map<String, String> get _dateParams {
    final from = DateTime.now().subtract(Duration(days: int.parse(_period)));
    return {
      'from': _fmt(from),
      'to': _fmt(DateTime.now()),
      'group_by': _groupBy,
    };
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export PDF',
            onPressed: _exportPdf,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Customers'),
            Tab(text: 'Messaging'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(dateParams: _dateParams, period: _period,
              onPeriodChange: (v) => setState(() { _period = v; })),
          const _CustomerBehaviourTab(),
          _MessagingTab(),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    final data = ref.read(analyticsProvider(_dateParams)).value;
    if (data == null) return;
    final orders = ref.read(adminOrdersFromAnalytics(data));
    PdfService.shareAdminOrdersReport(
        context: context, orders: orders, title: 'Analytics Report (Last $_period days)');
  }
}

// Helper provider to extract orders from analytics
final adminOrdersFromAnalytics = Provider.family<List<Map<String, dynamic>>, Map<String, dynamic>>((ref, data) {
  final rows = data['revenueByDay'] as List? ?? [];
  return rows.map((r) => Map<String, dynamic>.from(r)).toList();
});

// ── Tab 1: Overview ───────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final Map<String, String> dateParams;
  final String period;
  final ValueChanged<String> onPeriodChange;
  const _OverviewTab({required this.dateParams, required this.period, required this.onPeriodChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider(dateParams));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(analyticsProvider(dateParams)),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Period selector
        Row(children: [
          const Text('Period:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          ...['7', '30', '90'].map((d) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('${d}d'),
              selected: period == d,
              selectedColor: const Color(0xFFE8F5E9),
              onSelected: (_) => onPeriodChange(d),
            ),
          )),
        ]),
        const SizedBox(height: 16),

        analytics.when(
          data: (data) => Column(children: [
            // Activity cards
            _buildActivityCards(context, data),
            const SizedBox(height: 16),

            // Revenue by day
            _SectionHeader('Revenue by Day'),
            _buildRevenueChart(context, data),
            const SizedBox(height: 16),

            // Status breakdown
            _SectionHeader('Order Status'),
            _buildStatusBreakdown(context, data),
            const SizedBox(height: 16),

            // Top products
            _SectionHeader('Top Products'),
            _buildTopProducts(context, data),
            const SizedBox(height: 16),

            // Financial summary
            _SectionHeader('Financial Summary (Expenses)'),
            _buildFinancialSummary(context, data),
            const SizedBox(height: 16),
          ]),
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
          error: (e, _) => _ErrorCard(error: '$e', onRetry: () => ref.invalidate(analyticsProvider(dateParams))),
        ),
      ]),
    );
  }

  Widget _buildActivityCards(BuildContext context, Map<String, dynamic> data) {
    final a = data['activity'] as Map<String, dynamic>? ?? {};
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        _MiniCard('Total Customers', '${a['total_customers'] ?? 0}', Icons.people, Colors.blue),
        _MiniCard('Active (30d)', '${a['active_30d'] ?? 0}', Icons.trending_up, Colors.green),
        _MiniCard('Active (7d)', '${a['active_7d'] ?? 0}', Icons.flash_on, Colors.orange),
        _MiniCard('No Orders Yet', '${a['no_orders'] ?? 0}', Icons.person_add_disabled, Colors.red),
      ],
    );
  }

  Widget _buildRevenueChart(BuildContext context, Map<String, dynamic> data) {
    final rows = data['revenueByDay'] as List? ?? [];
    if (rows.isEmpty) return const _EmptyCard('No revenue data in this period');

    final maxRevenue = rows.fold<double>(0, (m, r) => (r['revenue'] as num).toDouble() > m ? (r['revenue'] as num).toDouble() : m);
    if (maxRevenue == 0) return const _EmptyCard('No revenue in this period');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...rows.take(14).map((r) {
              final rev = (r['revenue'] as num).toDouble();
              final pct = maxRevenue > 0 ? rev / maxRevenue : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 75, child: Text(r['day'].toString().substring(5), style: const TextStyle(fontSize: 11, color: Colors.grey))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 16,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF2E7D32)),
                    ),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: Text('₹${rev.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBreakdown(BuildContext context, Map<String, dynamic> data) {
    final statuses = data['statusBreakdown'] as List? ?? [];
    if (statuses.isEmpty) return const _EmptyCard('No orders in this period');

    final total = statuses.fold<int>(0, (s, r) => s + (r['count'] as int));
    final colors = {
      'delivered': Colors.green, 'pending': Colors.orange,
      'cancelled': Colors.red, 'confirmed': Colors.blue,
      'dispatched': Colors.purple, 'assigned': Colors.teal,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: statuses.map((s) {
          final status = s['status'] as String;
          final count = s['count'] as int;
          final pct = total > 0 ? count / total : 0.0;
          final color = colors[status] ?? Colors.grey;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              SizedBox(width: 80, child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11))),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct, minHeight: 12, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation(color)),
              )),
              const SizedBox(width: 8),
              Text('$count', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
          );
        }).toList()),
      ),
    );
  }

  Widget _buildTopProducts(BuildContext context, Map<String, dynamic> data) {
    final products = data['topProducts'] as List? ?? [];
    if (products.isEmpty) return const _EmptyCard('No product sales in this period');

    return Card(
      child: Column(
        children: products.take(5).toList().asMap().entries.map((e) {
          final i = e.key;
          final p = e.value as Map<String, dynamic>;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE8F5E9),
              radius: 16,
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
            ),
            title: Text(p['name'] as String, style: const TextStyle(fontSize: 13)),
            subtitle: Text('${p['order_count']} orders • ${p['total_qty'].toStringAsFixed(1)} ${p['unit']}',
                style: const TextStyle(fontSize: 11)),
            trailing: Text('₹${(p['total_revenue'] as num).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFinancialSummary(BuildContext context, Map<String, dynamic> data) {
    final f = data['financialSummary'] as Map<String, dynamic>? ?? {};

    num g(String k) => (f[k] as num?) ?? 0;

    final items = [
      ('Cashback Rewards', g('total_cashback_rewards'), Colors.purple, Icons.card_giftcard),
      ('Admin Credits', g('total_admin_credits'), Colors.blue.shade700, Icons.admin_panel_settings),
      ('Admin Deductions', g('total_admin_deductions'), Colors.red.shade700, Icons.remove_circle),
      ('Order Refunds', g('total_refunds'), Colors.teal, Icons.undo),
      ('Topups Credited', g('total_topups_credited'), Colors.orange.shade700, Icons.payments),
      ('Service Fees', g('total_service_fees'), Colors.grey.shade600, Icons.lock_outline),
    ];

    final totalExpenses = g('total_cashback_rewards') + g('total_admin_credits') +
        g('total_refunds') + g('total_topups_credited');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Total expenses row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.trending_down, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Total Expenses / Credits Out',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('₹${totalExpenses.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.red, fontSize: 16)),
            ]),
          ),
          const Divider(height: 16),
          ...items.map((item) {
            final (label, amount, color, icon) = item;
            if (amount.toDouble() == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                Text('₹${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13)),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}

// ── Tab 2: Customer Behaviour ─────────────────────────────────────────────────

final _customerBehaviourProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final id       = int.parse(parts[0]);
  final dateFrom = parts.length > 1 ? parts[1] : null;
  final dateTo   = parts.length > 2 ? parts[2] : null;
  final dio = ref.read(dioProvider);
  final params = <String, String>{};
  if (dateFrom != null) params['date_from'] = dateFrom;
  if (dateTo   != null) params['date_to']   = dateTo;
  final res = await dio.get(Endpoints.adminCustomerBehaviour(id),
      queryParameters: params.isNotEmpty ? params : null);
  return res.data as Map<String, dynamic>;
});

final _customerSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  // key = "search|page"
  final parts  = key.split('|');
  final search = parts[0];
  final page   = parts.length > 1 ? parts[1] : '1';
  final dio    = ref.read(dioProvider);
  final res    = await dio.get(Endpoints.adminUsers, queryParameters: {
    if (search.isNotEmpty) 'search': search,
    'page': page,
    'limit': '50',
  });
  return res.data as Map<String, dynamic>;
});

class _CustomerBehaviourTab extends ConsumerStatefulWidget {
  const _CustomerBehaviourTab();
  @override
  ConsumerState<_CustomerBehaviourTab> createState() => _CustomerBehaviourTabState();
}

class _CustomerBehaviourTabState extends ConsumerState<_CustomerBehaviourTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  int    _page   = 1;
  Map<String, dynamic>? _selectedCustomer;
  late DateTime _dateFrom;
  late DateTime _dateTo;

  String get _searchKey => '$_search|$_page';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo   = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String get _providerKey =>
      '${_selectedCustomer!['id']}|${_fmt(_dateFrom)}|${_fmt(_dateTo)}';

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 30)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      helpText: 'Filter orders by date',
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
    final searchAsync    = ref.watch(_customerSearchProvider(_searchKey));
    final behaviourAsync = _selectedCustomer != null
        ? ref.watch(_customerBehaviourProvider(_providerKey))
        : null;

    return Column(children: [
      // ── Search bar — never rebuilt ────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() { _search = v.trim(); _page = 1; }),
          decoration: InputDecoration(
            hintText: 'Search by name or phone…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() { _search = ''; });
                    })
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
        ),
      ),

      // ── Split view: customer list (top) + behaviour (bottom) ──────────
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: customer list — always visible
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.38,
              child: searchAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: Colors.red, fontSize: 12))),
                data: (data) {
                  final customers = (data['users'] as List).cast<Map<String, dynamic>>();
                  final total     = data['total'] as int? ?? 0;
                  final hasMore   = customers.length < total;
                  if (customers.isEmpty) {
                    return Center(child: Text(
                        _search.isEmpty ? 'No customers' : 'No results for "$_search"',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: customers.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == customers.length) {
                        return TextButton(
                          onPressed: () => setState(() => _page++),
                          child: Text('Load more (${total - customers.length} more)',
                              style: const TextStyle(fontSize: 12)),
                        );
                      }
                      final c = customers[i];
                      final selected = _selectedCustomer?['id'] == c['id'];
                      return InkWell(
                        onTap: () => setState(() {
                          _selectedCustomer = c;
                          _search = '';
                          _searchCtrl.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFE8F5E9) : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: selected ? const Color(0xFF2E7D32) : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: selected
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade200,
                              child: Text(
                                (c['name'] as String).substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selected ? Colors.white : Colors.grey.shade700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['name'] as String,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                                      color: selected ? const Color(0xFF2E7D32) : Colors.black87),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('+91 ${c['phone']}',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ])),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const VerticalDivider(width: 1),

            // Right: behaviour data or prompt
            Expanded(
              child: behaviourAsync == null
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text('Tap a customer', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                      ]),
                    )
                  : Column(children: [
                      // Date picker bar
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: GestureDetector(
                          onTap: _pickDateRange,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.4)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.date_range, size: 14, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(
                                '${_fmt(_dateFrom)} → ${_fmt(_dateTo)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                              )),
                              const Icon(Icons.edit_calendar_outlined, size: 13, color: Colors.grey),
                            ]),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: behaviourAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: Colors.red))),
                          data: (d) => _CustomerBehaviourView(data: d),
                        ),
                      ),
                    ]),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _CustomerBehaviourView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CustomerBehaviourView({required this.data});

  @override
  Widget build(BuildContext context) {
    final summary    = data['summary'] as Map<String, dynamic>;
    final orders     = (data['orders'] as List).cast<Map<String, dynamic>>();
    final favourites = (data['favourites'] as List).cast<Map<String, dynamic>>();
    final customer   = data['customer'] as Map<String, dynamic>;

    final totalOrders    = summary['totalOrders'] as int? ?? 0;
    final totalSpent     = (summary['totalSpent'] as num?)?.toDouble() ?? 0;
    final cancelled      = summary['cancelledCount'] as int? ?? 0;
    final delivered      = summary['deliveredCount'] as int? ?? 0;
    final wallet         = (customer['wallet_balance'] as num?)?.toDouble() ?? 0;

    return ListView(padding: const EdgeInsets.all(14), children: [
      // ── Summary cards ────────────────────────────────────────────────
      Row(children: [
        _BCard('Total Orders', '$totalOrders', Icons.shopping_bag_outlined, Colors.blue),
        const SizedBox(width: 8),
        _BCard('Total Spent', '₹${totalSpent.toStringAsFixed(0)}', Icons.currency_rupee, const Color(0xFF2E7D32)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _BCard('Delivered', '$delivered', Icons.done_all, Colors.green),
        const SizedBox(width: 8),
        _BCard('Cancelled', '$cancelled', Icons.cancel_outlined, Colors.red),
        const SizedBox(width: 8),
        _BCard('Wallet', '₹${wallet.toStringAsFixed(0)}',
            Icons.account_balance_wallet_outlined,
            wallet < 0 ? Colors.orange : Colors.teal),
      ]),
      const SizedBox(height: 20),

      // ── Favourite products ───────────────────────────────────────────
      if (favourites.isNotEmpty) ...[
        const Text('Favourite Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Card(
          child: Column(children: favourites.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE8F5E9),
                child: Text('${i+1}', style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
              ),
              title: Text(p['name'] as String, style: const TextStyle(fontSize: 13)),
              subtitle: Text('${p['times_ordered']}x ordered • ${(p['total_qty'] as num).toStringAsFixed(1)} ${p['unit']}',
                  style: const TextStyle(fontSize: 11)),
            );
          }).toList()),
        ),
        const SizedBox(height: 20),
      ],

      // ── Orders in date range ─────────────────────────────────────────
      Text('Orders (${orders.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 8),
      if (orders.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No orders in this period', style: TextStyle(color: Colors.grey)),
        ))
      else
        ...orders.map((o) {
          final status = o['status'] as String;
          final amount = (o['final_amount'] as num).toDouble();
          final date   = (o['created_at'] as String).substring(0, 10);
          final Color sc = switch (status) {
            'delivered'  => Colors.green,
            'cancelled'  => Colors.red,
            'dispatched' => Colors.blue,
            _ => Colors.orange,
          };
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: sc.withValues(alpha: 0.3)),
            ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 8, decoration: BoxDecoration(
                    color: sc, borderRadius: BorderRadius.circular(4)),
              ),
              title: Text('#${o['order_number']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('$date  •  ${o['city'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('₹${amount.toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: sc)),
                Text(status, style: TextStyle(fontSize: 10, color: sc)),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _BCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _BCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ),
  );
}

// ── Tab 3: Messaging ──────────────────────────────────────────────────────────

class _MessagingTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MessagingTab> createState() => _MessagingTabState();
}

class _MessagingTabState extends ConsumerState<_MessagingTab> {
  final _msgCtrl = TextEditingController();
  List<String> _channels = ['push'];
  String _targetSegment = 'all';
  bool _sending = false;
  int? _lastSentCount;

  Future<void> _sendBroadcast() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      // Get user IDs for segment first
      final usersRes = await dio.get(Endpoints.adminCustomerActivity,
          queryParameters: _targetSegment == 'all' ? null : {'segment': _targetSegment});
      final users = usersRes.data['customers'] as List? ?? [];
      final ids = users.map((u) => (u as Map)['id'] as int).toList();

      if (ids.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No customers in this segment')));
        return;
      }

      final res = await dio.post(Endpoints.adminBroadcast, data: {
        'user_ids': ids,
        'message': _msgCtrl.text.trim(),
        'channels': _channels,
      });
      setState(() { _lastSentCount = res.data['sent'] as int; _msgCtrl.clear(); });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Broadcast sent to ${_lastSentCount} customers ✅'), backgroundColor: const Color(0xFF2E7D32)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendDueReminders() async {
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.adminDueReminders, data: {});
      final sent = res.data['sent'] as int;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Due reminders sent to $sent customers ✅'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Broadcast section
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Broadcast Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Send a message to a group of customers', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),

            // Target segment
            const Text('Send to:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ('all', 'All Customers'),
              ('active', 'Active (30d)'),
              ('inactive', 'Inactive'),
              ('no_orders', 'No Orders Yet'),
            ].map((s) => ChoiceChip(
              label: Text(s.$2),
              selected: _targetSegment == s.$1,
              selectedColor: const Color(0xFFE8F5E9),
              onSelected: (_) => setState(() => _targetSegment = s.$1),
            )).toList()),
            const SizedBox(height: 16),

            // Channels
            const Text('Via:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ('push', 'Push Notification', Icons.notifications),
              ('whatsapp', 'WhatsApp', Icons.chat),
            ].map((c) => FilterChip(
              avatar: Icon(c.$3, size: 14),
              label: Text(c.$2),
              selected: _channels.contains(c.$1),
              selectedColor: const Color(0xFFE8F5E9),
              onSelected: (sel) => setState(() {
                if (sel) _channels.add(c.$1);
                else _channels.remove(c.$1);
              }),
            )).toList()),
            const SizedBox(height: 16),

            // Message
            TextField(
              controller: _msgCtrl,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Type your message to customers...',
                border: OutlineInputBorder(),
                labelText: 'Message',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: _sending
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Send Broadcast'),
                onPressed: (_sending || _channels.isEmpty) ? null : _sendBroadcast,
              ),
            ),
            if (_lastSentCount != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Last sent to $_lastSentCount customers',
                    style: const TextStyle(color: Colors.green, fontSize: 12)),
              ),
          ]),
        ),
      ),

      const SizedBox(height: 16),

      // Due reminders
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.notifications_active, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('Due Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Automatically sends push + WhatsApp to customers with:\n• Wallet balance < ₹100\n• Pending top-up requests',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: _sending ? const CircularProgressIndicator(color: Colors.white) : const Text('Send Due Reminders Now'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: _sending ? null : _sendDueReminders,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  );
}

class _MiniCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniCard(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: color, size: 22),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    )),
  );
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard(this.message);
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(message, style: const TextStyle(color: Colors.grey))),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorCard({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.red.shade50,
    child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Text('Error: $error', style: const TextStyle(color: Colors.red)),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ])),
  );
}
