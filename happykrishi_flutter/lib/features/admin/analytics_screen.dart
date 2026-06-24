import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/pdf_service.dart';
import '../../core/utils/error_handler.dart';

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

const _kGreen  = Color(0xFF2E7D32);
const _kGreenL = Color(0xFFE8F5E9);

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override
  ConsumerState<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _period = '30';

  Map<String, String> get _dateParams {
    final from = DateTime.now().subtract(Duration(days: int.parse(_period)));
    return {
      'from': _fmt(from),
      'to': _fmt(DateTime.now()),
      'group_by': int.parse(_period) <= 14 ? 'day' : 'day',
    };
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export PDF',
            onPressed: _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Customers'),
            Tab(text: 'Messaging'),
            Tab(text: 'Wallet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(dateParams: _dateParams, period: _period,
              onPeriodChange: (v) => setState(() => _period = v)),
          const _CustomerBehaviourTab(),
          _MessagingTab(),
          const _WalletAuditTab(),
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
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        // Period selector
        _PeriodSelector(period: period, onChanged: onPeriodChange),
        const SizedBox(height: 16),

        analytics.when(
          data: (data) => _OverviewBody(data: data),
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: _kGreen)),
          ),
          error: (e, _) {
            logError('analytics', e);
            return _ErrorCard(error: friendlyError(e), onRetry: () => ref.invalidate(analyticsProvider(dateParams)));
          },
        ),
      ]),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;
  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final d in [('7', '7 Days'), ('30', '30 Days'), ('90', '90 Days')])
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(d.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: period == d.$1 ? _kGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(d.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: period == d.$1 ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OverviewBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final a = data['activity'] as Map<String, dynamic>? ?? {};
    final rows = (data['revenueByDay'] as List? ?? []).cast<Map<String, dynamic>>();
    final statuses = (data['statusBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    final products = (data['topProducts'] as List? ?? []).cast<Map<String, dynamic>>();
    final f = data['financialSummary'] as Map<String, dynamic>? ?? {};

    final totalRevenue = rows.fold<double>(0, (s, r) => s + (r['revenue'] as num).toDouble());
    final totalOrders = statuses.fold<int>(0, (s, r) => s + (r['count'] as int));
    final delivered = statuses.firstWhere((s) => s['status'] == 'delivered', orElse: () => {'count': 0})['count'] as int;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── KPI strip ───────────────────────────────────────────────────────
      Row(children: [
        _KpiCard('Revenue', '₹${_compactNum(totalRevenue)}', Icons.trending_up, _kGreen),
        const SizedBox(width: 10),
        _KpiCard('Orders', '$totalOrders', Icons.receipt_long_outlined, Colors.blue.shade600),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _KpiCard('Delivered', '$delivered', Icons.done_all, Colors.teal),
        const SizedBox(width: 10),
        _KpiCard('Customers', '${a['total_customers'] ?? 0}', Icons.people_outline, Colors.purple.shade400),
      ]),
      const SizedBox(height: 20),

      // ── Revenue chart ────────────────────────────────────────────────────
      if (rows.isNotEmpty) ...[
        _SectionLabel('Revenue Trend'),
        const SizedBox(height: 8),
        _RevenueChart(rows: rows),
        const SizedBox(height: 20),
      ],

      // ── Customer activity ────────────────────────────────────────────────
      _SectionLabel('Customer Activity'),
      const SizedBox(height: 8),
      _ActivityGrid(a: a),
      const SizedBox(height: 20),

      // ── Order status ─────────────────────────────────────────────────────
      if (statuses.isNotEmpty) ...[
        _SectionLabel('Order Status'),
        const SizedBox(height: 8),
        _StatusDonut(statuses: statuses),
        const SizedBox(height: 20),
      ],

      // ── Top products ──────────────────────────────────────────────────────
      if (products.isNotEmpty) ...[
        _SectionLabel('Top Products'),
        const SizedBox(height: 8),
        _TopProductsCard(products: products),
        const SizedBox(height: 20),
      ],

      // ── Financial summary ─────────────────────────────────────────────────
      _SectionLabel('Financial Summary'),
      const SizedBox(height: 8),
      _FinancialCard(f: f),
    ]);
  }

  static String _compactNum(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
        ])),
      ]),
    ),
  );
}

class _ActivityGrid extends StatelessWidget {
  final Map<String, dynamic> a;
  const _ActivityGrid({required this.a});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Active 30d', '${a['active_30d'] ?? 0}', Icons.local_fire_department, Colors.orange),
      ('Active 7d', '${a['active_7d'] ?? 0}', Icons.flash_on, Colors.amber.shade700),
      ('No Orders', '${a['no_orders'] ?? 0}', Icons.person_off_outlined, Colors.red.shade400),
      ('Total', '${a['total_customers'] ?? 0}', Icons.groups_outlined, Colors.blue.shade600),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: items.map((item) {
        final (label, value, icon, color) = item;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ]),
        );
      }).toList(),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _RevenueChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final recent = rows.length > 14 ? rows.sublist(rows.length - 14) : rows;
    final maxRev = recent.fold<double>(0, (m, r) => math.max(m, (r['revenue'] as num).toDouble()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bar chart
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: recent.map((r) {
              final rev = (r['revenue'] as num).toDouble();
              final pct = maxRev > 0 ? rev / maxRev : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message: '₹${rev.toStringAsFixed(0)}',
                    child: Container(
                      height: math.max(4, 96 * pct),
                      decoration: BoxDecoration(
                        color: rev > 0 ? _kGreen : Colors.grey.shade200,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // X-axis labels (first, middle, last)
        Row(children: [
          Text(recent.first['day'].toString().substring(5),
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const Spacer(),
          if (recent.length > 2)
            Text(recent[recent.length ~/ 2]['day'].toString().substring(5),
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const Spacer(),
          Text(recent.last['day'].toString().substring(5),
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ]),
      ]),
    );
  }
}

class _StatusDonut extends StatelessWidget {
  final List<Map<String, dynamic>> statuses;
  const _StatusDonut({required this.statuses});

  static const _colors = {
    'delivered': Color(0xFF2E7D32),
    'pending': Color(0xFFFF9800),
    'confirmed': Color(0xFF1976D2),
    'dispatched': Color(0xFF7B1FA2),
    'assigned': Color(0xFF00897B),
    'cancelled': Color(0xFFE53935),
  };

  @override
  Widget build(BuildContext context) {
    final total = statuses.fold<int>(0, (s, r) => s + (r['count'] as int));
    if (total == 0) return const _EmptyCard('No orders in this period');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(children: statuses.map((s) {
        final status = s['status'] as String;
        final count  = s['count'] as int;
        final pct    = total > 0 ? count / total : 0.0;
        final color  = _colors[status] ?? Colors.grey;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Text('$count',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right),
            ),
            SizedBox(
              width: 36,
              child: Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  textAlign: TextAlign.right),
            ),
          ]),
        );
      }).toList()),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  const _TopProductsCard({required this.products});

  @override
  Widget build(BuildContext context) {
    final top = products.take(5).toList();
    final maxRev = top.fold<double>(0, (m, p) => math.max(m, (p['total_revenue'] as num).toDouble()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: top.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final rev = (p['total_revenue'] as num).toDouble();
          final pct = maxRev > 0 ? rev / maxRev : 0.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, i == 0 ? 14 : 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: i == 0 ? _kGreen : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: i == 0 ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p['name'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text('₹${rev.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kGreen)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const SizedBox(width: 34),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct, minHeight: 5,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation(
                          i == 0 ? _kGreen : Colors.grey.shade400),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${p['order_count']} orders',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
              if (i < top.length - 1)
                const Padding(padding: EdgeInsets.only(top: 10), child: Divider(height: 1)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

class _FinancialCard extends StatelessWidget {
  final Map<String, dynamic> f;
  const _FinancialCard({required this.f});

  @override
  Widget build(BuildContext context) {
    num g(String k) => (f[k] as num?) ?? 0;

    final totalOut = g('total_cashback_rewards') + g('total_admin_credits') +
        g('total_refunds') + g('total_topups_credited');

    final items = [
      ('Cashback Rewards',   g('total_cashback_rewards'),   const Color(0xFF6A1B9A), Icons.card_giftcard_outlined),
      ('Admin Credits',      g('total_admin_credits'),      Colors.blue.shade700,   Icons.admin_panel_settings_outlined),
      ('Order Refunds',      g('total_refunds'),            Colors.teal,            Icons.undo),
      ('Topups Credited',    g('total_topups_credited'),    Colors.orange.shade700, Icons.payments_outlined),
      ('Admin Deductions',   g('total_admin_deductions'),   Colors.red.shade700,    Icons.remove_circle_outline),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Total out header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFEBEE), Color(0xFFFFF3E0)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: Colors.deepOrange, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Total Credits Out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text('₹${totalOut.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 14),
        ...items.where((item) => item.$2.toDouble() > 0).map((item) {
          final (label, amount, color, icon) = item;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87))),
              Text('₹${amount.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Tab 2: Customer Behaviour ─────────────────────────────────────────────────

final _customerBehaviourProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final id = int.parse(parts[0]);
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
            colorScheme: const ColorScheme.light(primary: _kGreen)),
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
      // Search bar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() { _search = v.trim(); _page = 1; }),
          decoration: InputDecoration(
            hintText: 'Search customer by name or phone…',
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

      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Customer list
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.38,
            child: searchAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen)),
              error: (e, _) => Center(child: Text(friendlyError(e), style: const TextStyle(color: Colors.red, fontSize: 12))),
              data: (data) {
                final customers = (data['users'] as List).cast<Map<String, dynamic>>();
                final total     = data['total'] as int? ?? 0;
                final hasMore   = customers.length < total;
                if (customers.isEmpty) {
                  return Center(child: Text(
                    _search.isEmpty ? 'No customers' : 'No results',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: customers.length + (hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == customers.length) {
                      return TextButton(
                        onPressed: () => setState(() => _page++),
                        child: Text('${total - customers.length} more',
                            style: const TextStyle(fontSize: 11)),
                      );
                    }
                    final c = customers[i];
                    final sel = _selectedCustomer?['id'] == c['id'];
                    return InkWell(
                      onTap: () => setState(() {
                        _selectedCustomer = c;
                        _search = ''; _searchCtrl.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? _kGreenL : Colors.transparent,
                          border: Border(left: BorderSide(
                            color: sel ? _kGreen : Colors.transparent, width: 3)),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: sel ? _kGreen : Colors.grey.shade200,
                            child: Text(
                              (c['name'] as String).substring(0, 1).toUpperCase(),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                  color: sel ? Colors.white : Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c['name'] as String,
                                style: TextStyle(fontSize: 12,
                                    fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                                    color: sel ? _kGreen : Colors.black87),
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

          Expanded(
            child: behaviourAsync == null
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_search_outlined, size: 52, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text('Select a customer', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                  ]))
                : Column(children: [
                    // Date range picker bar
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                        child: Row(children: [
                          const Icon(Icons.date_range, size: 15, color: _kGreen),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('${_fmt(_dateFrom)} → ${_fmt(_dateTo)}',
                              style: const TextStyle(fontSize: 11, color: _kGreen, fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.edit_calendar_outlined, size: 13, color: Colors.grey),
                        ]),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: behaviourAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator(color: _kGreen)),
                        error: (e, _) => Center(child: Text(friendlyError(e), style: const TextStyle(color: Colors.red))),
                        data: (d) => _CustomerBehaviourView(data: d),
                      ),
                    ),
                  ]),
          ),
        ]),
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

    final totalOrders = summary['totalOrders'] as int? ?? 0;
    final totalSpent  = (summary['totalSpent'] as num?)?.toDouble() ?? 0;
    final cancelled   = summary['cancelledCount'] as int? ?? 0;
    final delivered   = summary['deliveredCount'] as int? ?? 0;
    final wallet      = (customer['wallet_balance'] as num?)?.toDouble() ?? 0;

    return ListView(padding: const EdgeInsets.all(12), children: [
      // Customer name header
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 20, backgroundColor: _kGreen,
            child: Text(
              (customer['name'] as String).substring(0, 1).toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text('+91 ${customer['phone']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: wallet < 0 ? Colors.red.shade50 : _kGreenL,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('₹${wallet.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13,
                color: wallet < 0 ? Colors.red : _kGreen,
              ),
            ),
          ),
        ]),
      ),

      // Stats row
      Row(children: [
        _StatPill('Orders', '$totalOrders', Colors.blue.shade600),
        const SizedBox(width: 8),
        _StatPill('Delivered', '$delivered', Colors.teal),
        const SizedBox(width: 8),
        _StatPill('Cancelled', '$cancelled', Colors.red.shade400),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
        ),
        child: Row(children: [
          const Icon(Icons.currency_rupee, color: _kGreen, size: 18),
          const SizedBox(width: 6),
          const Text('Total Spent', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const Spacer(),
          Text('₹${totalSpent.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kGreen)),
        ]),
      ),
      const SizedBox(height: 16),

      // Favourites
      if (favourites.isNotEmpty) ...[
        const Text('Favourite Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
          ),
          child: Column(children: favourites.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Padding(
              padding: EdgeInsets.fromLTRB(14, i == 0 ? 12 : 0, 14, 12),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: i == 0 ? _kGreen : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(child: Text('${i+1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                          color: i == 0 ? Colors.white : Colors.grey))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p['name'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  Text('${p['times_ordered']}x',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                if (i < favourites.length - 1)
                  const Padding(padding: EdgeInsets.only(top: 10), child: Divider(height: 1)),
              ]),
            );
          }).toList()),
        ),
        const SizedBox(height: 16),
      ],

      // Orders
      Row(children: [
        Text('Orders (${orders.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
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
            'delivered'  => Colors.teal,
            'cancelled'  => Colors.red.shade400,
            'dispatched' => Colors.blue.shade600,
            _ => Colors.orange,
          };
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
            ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 4,
                decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(4)),
              ),
              contentPadding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
              title: Text('#${o['order_number']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('₹${amount.toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: sc, fontSize: 13)),
                Text(status, style: TextStyle(fontSize: 10, color: sc)),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatPill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
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
  // Broadcast
  final _msgCtrl = TextEditingController();
  final List<String> _channels = ['push'];
  String _targetSegment = 'all';
  bool _sending = false;
  int? _lastSentCount;

  // Select & send
  final _selectMsgCtrl    = TextEditingController();
  final _selectSearchCtrl = TextEditingController();
  String _selectSearch    = '';
  final List<Map<String, dynamic>> _selectedCustomers = [];
  bool _selectSending     = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _selectMsgCtrl.dispose();
    _selectSearchCtrl.dispose();
    super.dispose();
  }

  static const _segments = [
    ('all',       'All Customers',  Icons.groups_outlined,       Colors.blue),
    ('active',    'Active (30d)',   Icons.local_fire_department,  Colors.orange),
    ('inactive',  'Inactive',       Icons.person_off_outlined,    Colors.grey),
    ('no_orders', 'No Orders Yet',  Icons.shopping_cart_outlined, Colors.red),
  ];

  Future<void> _sendBroadcast() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      final usersRes = await dio.get(Endpoints.adminCustomerActivity,
          queryParameters: _targetSegment == 'all' ? null : {'segment': _targetSegment});
      final users = usersRes.data['customers'] as List? ?? [];
      final ids = users.map((u) => (u as Map)['id'] as int).toList();
      if (ids.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No customers in this segment')));
        return;
      }
      final res = await dio.post(Endpoints.adminBroadcast, data: {
        'user_ids': ids, 'message': _msgCtrl.text.trim(), 'channels': _channels,
      });
      setState(() { _lastSentCount = res.data['sent'] as int; _msgCtrl.clear(); });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sent to $_lastSentCount customers ✅'),
          backgroundColor: _kGreen,
        ));
      }
    } catch (e, st) {
      logError('analytics', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendToSelected() async {
    if (_selectedCustomers.isEmpty || _selectMsgCtrl.text.trim().isEmpty) return;
    setState(() => _selectSending = true);
    try {
      final dio = ref.read(dioProvider);
      final ids = _selectedCustomers.map((c) => c['id'] as int).toList();
      final res = await dio.post(Endpoints.adminBroadcast, data: {
        'user_ids': ids,
        'message': _selectMsgCtrl.text.trim(),
        'channels': ['push'],
      });
      final sent = res.data['sent'] as int;
      setState(() { _selectedCustomers.clear(); _selectMsgCtrl.clear(); _selectSearch = ''; _selectSearchCtrl.clear(); });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sent to $sent customer${sent == 1 ? '' : 's'} ✅'),
          backgroundColor: _kGreen,
        ));
      }
    } catch (e, st) {
      logError('messaging-select', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _selectSending = false);
    }
  }

  Future<void> _sendDueReminders() async {
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.adminDueReminders, data: {});
      final sent = res.data['sent'] as int;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Due reminders sent to $sent customers ✅'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e, st) {
      logError('analytics', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ── Select customers & send ───────────────────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.people_alt_outlined, color: Colors.blue.shade700, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Send to Selected Customers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Search, select one or more, then send', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ])),
            if (_selectedCustomers.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _selectedCustomers.clear()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text('Clear all', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
          const SizedBox(height: 16),

          // Search field
          TextField(
            controller: _selectSearchCtrl,
            onChanged: (v) => setState(() => _selectSearch = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _selectSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _selectSearchCtrl.clear(); setState(() => _selectSearch = ''); })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),

          // Search results with checkboxes
          if (_selectSearch.isNotEmpty)
            Consumer(builder: (ctx, ref, _) {
              final res = ref.watch(_customerSearchProvider('$_selectSearch|1'));
              return res.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen))),
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (data) {
                  final list = (data['users'] as List)
                      .cast<Map<String, dynamic>>()
                      .where((c) => c['role'] == 'customer' || c['role'] == null)
                      .take(8)
                      .toList();
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('No customers found', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    );
                  }
                  return Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: list.asMap().entries.map((e) {
                      final i = e.key;
                      final c = e.value;
                      final isSelected = _selectedCustomers.any((s) => s['id'] == c['id']);
                      return InkWell(
                        borderRadius: BorderRadius.only(
                          topLeft: i == 0 ? const Radius.circular(10) : Radius.zero,
                          topRight: i == 0 ? const Radius.circular(10) : Radius.zero,
                          bottomLeft: i == list.length - 1 ? const Radius.circular(10) : Radius.zero,
                          bottomRight: i == list.length - 1 ? const Radius.circular(10) : Radius.zero,
                        ),
                        onTap: () => setState(() {
                          if (isSelected) {
                            _selectedCustomers.removeWhere((s) => s['id'] == c['id']);
                          } else {
                            _selectedCustomers.add(c);
                          }
                        }),
                        child: Container(
                          color: isSelected ? _kGreenL : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: isSelected ? _kGreen : Colors.transparent,
                                border: Border.all(color: isSelected ? _kGreen : Colors.grey.shade400, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isSelected ? _kGreen : Colors.grey.shade100,
                              child: Text((c['name'] as String)[0].toUpperCase(),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : Colors.grey.shade600)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['name'] as String,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: isSelected ? _kGreen : Colors.black87)),
                              Text('+91 ${c['phone']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ])),
                          ]),
                        ),
                      );
                    }).toList()),
                  );
                },
              );
            }),

          // Selected chips
          if (_selectedCustomers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kGreenL,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle, size: 14, color: _kGreen),
                  const SizedBox(width: 6),
                  Text('${_selectedCustomers.length} selected',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kGreen)),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedCustomers.map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(c['name'] as String,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _kGreen)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _selectedCustomers.removeWhere((s) => s['id'] == c['id'])),
                        child: const Icon(Icons.close, size: 13, color: Colors.grey),
                      ),
                    ]),
                  )).toList(),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 14),

          // Message field
          TextField(
            controller: _selectMsgCtrl,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Type your message…',
              labelText: 'Message',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: _selectSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_selectSending
                  ? 'Sending…'
                  : _selectedCustomers.isEmpty
                      ? 'Select customers first'
                      : 'Send to ${_selectedCustomers.length} customer${_selectedCustomers.length == 1 ? '' : 's'}'),
              onPressed: (_selectSending || _selectedCustomers.isEmpty) ? null : _sendToSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 16),

      // Broadcast card
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: _kGreenL, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.campaign_outlined, color: _kGreen, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Broadcast Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Send to a group of customers', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 20),

          // Target segment
          const Text('Send To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 3.2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: _segments.map((s) {
              final sel = _targetSegment == s.$1;
              return GestureDetector(
                onTap: () => setState(() => _targetSegment = s.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: sel ? s.$4.withValues(alpha: 0.1) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? s.$4 : Colors.grey.shade200, width: sel ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(s.$3, size: 15, color: sel ? s.$4 : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s.$2, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: sel ? s.$4 : Colors.black87,
                    ), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Channels
          const Text('Via', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          Row(children: [
            for (final c in [('push', 'Push', Icons.notifications_outlined), ('whatsapp', 'WhatsApp', Icons.chat_outlined)])
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (_channels.contains(c.$1)) {
                      _channels.remove(c.$1);
                    } else {
                      _channels.add(c.$1);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _channels.contains(c.$1) ? _kGreenL : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _channels.contains(c.$1) ? _kGreen : Colors.grey.shade200,
                        width: _channels.contains(c.$1) ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c.$3, size: 15, color: _channels.contains(c.$1) ? _kGreen : Colors.grey),
                      const SizedBox(width: 6),
                      Text(c.$2, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: _channels.contains(c.$1) ? _kGreen : Colors.black87,
                      )),
                      if (_channels.contains(c.$1)) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check, size: 12, color: _kGreen),
                      ],
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),

          // Message field
          TextField(
            controller: _msgCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Type your message…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              labelText: 'Message',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_sending ? 'Sending…' : 'Send Broadcast'),
              onPressed: (_sending || _channels.isEmpty) ? null : _sendBroadcast,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_lastSentCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 14, color: _kGreen),
                const SizedBox(width: 6),
                Text('Last sent to $_lastSentCount customers',
                    style: const TextStyle(color: _kGreen, fontSize: 12)),
              ]),
            ),
        ]),
      ),

      const SizedBox(height: 16),

      // Due reminders card
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.notifications_active_outlined, color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Due Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Notify customers with pending dues', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sends push + WhatsApp to customers with:',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
              SizedBox(height: 4),
              Text('• Wallet balance < ₹100',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              Text('• Pending top-up requests',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.alarm_outlined, size: 18),
              label: const Text('Send Due Reminders'),
              onPressed: _sending ? null : _sendDueReminders,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ── Tab 4: Wallet Audit ───────────────────────────────────────────────────────

class _WalletAuditTab extends ConsumerStatefulWidget {
  const _WalletAuditTab();
  @override
  ConsumerState<_WalletAuditTab> createState() => _WalletAuditTabState();
}

class _WalletAuditTabState extends ConsumerState<_WalletAuditTab> {
  final _customerCtrl = TextEditingController();
  String _customerSearch = '';
  String _typeFilter = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  List<Map<String, dynamic>> _txns = [];
  Map<String, dynamic>? _summary;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int _total = 0;
  int _page = 1;

  static const _types = [
    ('', 'All'),
    ('credit', 'Credits'),
    ('debit', 'Debits'),
    ('topup', 'Top-ups'),
    ('order', 'Orders'),
    ('cashback', 'Cashback'),
    ('refund', 'Refunds'),
    ('admin', 'Admin'),
    ('adjust', 'Adjust'),
  ];

  @override
  void initState() { super.initState(); _fetch(); }

  @override
  void dispose() { _customerCtrl.dispose(); super.dispose(); }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch({bool reset = true}) async {
    if (reset) setState(() { _page = 1; _txns = []; });
    setState(() { _loading = true; _error = null; });
    try {
      final params = <String, String>{'limit': '100', 'page': '$_page'};
      if (_typeFilter.isNotEmpty) params['type'] = _typeFilter;
      if (_dateFrom != null) params['date_from'] = _fmt(_dateFrom!);
      if (_dateTo   != null) params['date_to']   = _fmt(_dateTo!);
      if (_customerSearch.isNotEmpty) params['customer_search'] = _customerSearch;

      final res = await ref.read(dioProvider).get(Endpoints.adminWalletAudit, queryParameters: params);
      final newTxns = List<Map<String, dynamic>>.from(res.data['transactions'] as List);
      setState(() {
        _txns    = reset ? newTxns : [..._txns, ...newTxns];
        _total   = res.data['total'] as int;
        _summary = res.data['summary'] as Map<String, dynamic>?;
        _loaded  = true;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _kGreen)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
      _fetch();
    }
  }

  Color _txnColor(Map<String, dynamic> t) {
    final type = t['type'] as String;
    final refT = t['reference_type'] as String? ?? '';
    if (type == 'debit') return Colors.red.shade600;
    if (type == 'discount' && refT == 'reward') return const Color(0xFF6A1B9A);
    if (type == 'adjustment') return Colors.orange;
    return _kGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Filter area
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: [
          // Search
          TextField(
            controller: _customerCtrl,
            onChanged: (v) => setState(() => _customerSearch = v.trim()),
            onSubmitted: (_) => _fetch(),
            decoration: InputDecoration(
              hintText: 'Search customer…',
              prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
              suffixIcon: _customerSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () { _customerCtrl.clear(); setState(() => _customerSearch = ''); _fetch(); })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          const SizedBox(height: 8),
          // Type chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _types.map((t) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () { setState(() => _typeFilter = t.$1); _fetch(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _typeFilter == t.$1 ? _kGreen : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _typeFilter == t.$1 ? _kGreen : Colors.grey.shade300),
                  ),
                  child: Text(t.$2, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: _typeFilter == t.$1 ? Colors.white : Colors.black87,
                  )),
                ),
              ),
            )).toList()),
          ),
          const SizedBox(height: 8),
          // Date range
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _dateFrom != null ? _kGreenL : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _dateFrom != null ? _kGreen : Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range, size: 15, color: _dateFrom != null ? _kGreen : Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      _dateFrom != null
                          ? '${_fmt(_dateFrom!)} → ${_dateTo != null ? _fmt(_dateTo!) : '…'}'
                          : 'Filter by date range',
                      style: TextStyle(fontSize: 12,
                          color: _dateFrom != null ? _kGreen : Colors.grey.shade600),
                    ),
                  ]),
                ),
              ),
            ),
            if (_dateFrom != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { setState(() { _dateFrom = null; _dateTo = null; }); _fetch(); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Icon(Icons.close, size: 14, color: Colors.red.shade700),
                ),
              ),
            ],
          ]),
        ]),
      ),
      const Divider(height: 1),

      // Summary
      if (_summary != null)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            _AuditCard('Transactions', '$_total', Colors.blueGrey),
            const SizedBox(width: 8),
            _AuditCard('Credited', '₹${(_summary!['total_credited'] as num).toStringAsFixed(0)}', _kGreen),
            const SizedBox(width: 8),
            _AuditCard('Debited', '₹${(_summary!['total_debited'] as num).toStringAsFixed(0)}', Colors.red.shade600),
          ]),
        ),

      if (_summary != null) const Divider(height: 1),

      // Transaction list
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => _fetch(),
          child: _loading && !_loaded
              ? const Center(child: CircularProgressIndicator(color: _kGreen))
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                      TextButton(onPressed: _fetch, child: const Text('Retry')),
                    ]))
                  : _txns.isEmpty && _loaded
                      ? const Center(child: Text('No transactions found', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _txns.length + (_txns.length < _total ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _txns.length) {
                              return TextButton(
                                onPressed: () { _page++; _fetch(reset: false); },
                                child: Text(_loading ? 'Loading…' : 'Load more (${_total - _txns.length} remaining)'),
                              );
                            }
                            final t = _txns[i];
                            final amount = (t['amount'] as num).toDouble();
                            final isCredit = ['credit', 'refund', 'discount'].contains(t['type']);
                            final color = _txnColor(t);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: color.withValues(alpha: 0.1),
                                    child: Text(
                                      (t['customer_name'] as String? ?? '?')[0].toUpperCase(),
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Expanded(child: Text(t['customer_name'] as String? ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                        Text(
                                          '${isCredit ? '+' : '−'}₹${amount.abs().toStringAsFixed(2)}',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                                        ),
                                      ]),
                                      const SizedBox(height: 3),
                                      Text(
                                        t['description'] as String? ?? t['type'] as String,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (t['created_at'] as String).substring(0, 10),
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ]),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ),
    ]);
  }
}

class _AuditCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AuditCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87));
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard(this.message);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(child: Text(message, style: const TextStyle(color: Colors.grey))),
  );
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorCard({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: [
      Text(error, style: TextStyle(color: Colors.red.shade700)),
      const SizedBox(height: 8),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ]),
  );
}
