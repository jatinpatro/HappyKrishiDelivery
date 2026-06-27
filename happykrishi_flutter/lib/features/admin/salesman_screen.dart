import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/widgets/active_filter.dart';
import '../../core/widgets/filter_chip_bar.dart';
import '../../core/utils/error_handler.dart';

final salesmanListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminSalesmen);
  return List<Map<String, dynamic>>.from(res.data['salesmen']);
});

final salesmanSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminSalesmanSummary);
  return res.data as Map<String, dynamic>;
});

class SalesmanScreen extends ConsumerStatefulWidget {
  const SalesmanScreen({super.key});
  @override
  ConsumerState<SalesmanScreen> createState() => _SalesmanScreenState();
}

class _SalesmanScreenState extends ConsumerState<SalesmanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesmenCount = ref.watch(salesmanListProvider).value?.length;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Salesman Management'),
          if (salesmenCount != null && salesmenCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$salesmenCount',
                  style: const TextStyle(
                      color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Salesman',
            onPressed: () => _showAddSalesmanDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(salesmanListProvider);
              ref.invalidate(salesmanSummaryProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Salesmen'),
            Tab(text: 'Cash Collections'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SalesmenTab(),
          _CashCollectionsTab(),
        ],
      ),
    );
  }

  void _showAddSalesmanDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: const Text('Add Salesman'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (10 digits) *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (min 6) *', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (nameCtrl.text.isEmpty || phoneCtrl.text.length != 10 || passCtrl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fill all fields correctly')));
                  return;
                }
                setDs(() => saving = true);
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post(Endpoints.adminSalesmen, data: {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'password': passCtrl.text,
                  });
                  ref.invalidate(salesmanListProvider);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Salesman created ✅'),
                            backgroundColor: Color(0xFF2E7D32)));
                  }
                } catch (e, st) {
                  logError('admin-salesman', e, st);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                  }
                } finally {
                  if (dialogCtx.mounted) setDs(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1: Salesmen list ──────────────────────────────────────────────────────

class _SalesmenTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesmen = ref.watch(salesmanListProvider);

    return salesmen.when(
      data: (list) => list.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.people_outline, size: 72, color: Colors.grey),
              SizedBox(height: 12),
              Text('No salesmen yet. Tap + to add.', style: TextStyle(color: Colors.grey)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) => _SalesmanTile(salesman: list[i],
                  onRefresh: () => ref.invalidate(salesmanListProvider)),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-salesman', e); return Center(child: Text(friendlyError(e))); },
    );
  }
}

class _SalesmanTile extends ConsumerWidget {
  final Map<String, dynamic> salesman;
  final VoidCallback onRefresh;
  const _SalesmanTile({required this.salesman, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = salesman['id'] as int;
    final name = salesman['name'] as String;
    final phone = salesman['phone'] as String;
    final isActive = salesman['is_active'] == 1;
    final pendingCount = salesman['pending_count'] as int? ?? 0;
    final unsettledTotal = (salesman['unsettled_total'] as num? ?? 0).toDouble();
    final lastLoginRaw = salesman['last_login_at'] as String?;
    final lastActiveRaw = salesman['last_active_at'] as String?;

    String timeAgo(String raw) {
      try {
        final dt = DateTime.parse(raw.replaceFirst(' ', 'T'));
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 1) return 'Just now';
        if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
        if (diff.inHours < 24) return '${diff.inHours}h ago';
        if (diff.inDays < 7) return '${diff.inDays}d ago';
        return '${diff.inDays}d ago';
      } catch (_) { return ''; }
    }

    final lastLogin = lastLoginRaw != null
        ? '${lastLoginRaw.substring(0, 16)} (${timeAgo(lastLoginRaw)})'
        : 'Never';
    final lastActive = lastActiveRaw != null
        ? '${lastActiveRaw.substring(0, 16)} (${timeAgo(lastActiveRaw)})'
        : 'Never';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: isActive ? const Color(0xFF2E7D32) : Colors.grey,
              child: Text(name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('+91 $phone', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 2),
              Text('Last login: $lastLogin', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text('Last active: $lastActive', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (pendingCount > 0 || unsettledTotal > 0)
                Text('$pendingCount pending  •  ₹${unsettledTotal.toStringAsFixed(0)} unsettled',
                    style: TextStyle(fontSize: 11, color: unsettledTotal > 0 ? Colors.orange : Colors.grey)),
            ])),
            Switch(
              value: isActive,
              activeTrackColor: const Color(0xFF2E7D32),
              onChanged: (_) async {
                final dio = ref.read(dioProvider);
                await dio.put(Endpoints.adminSalesmanToggle(id));
                onRefresh();
              },
            ),
          ]),
          const Divider(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              onPressed: () => _showEditDialog(context, ref, id, name, phone),
            ),
            TextButton.icon(
              icon: const Icon(Icons.lock_reset, size: 16),
              label: const Text('Reset Password'),
              onPressed: () => _showResetPasswordDialog(context, ref, id, name),
            ),
            TextButton.icon(
              icon: Icon(Icons.logout, size: 16, color: Colors.red.shade400),
              label: Text('Force Logout', style: TextStyle(color: Colors.red.shade400)),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Force Logout?'),
                    content: Text('This will immediately log out $name. They will need to log in again.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        child: const Text('Force Logout'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                try {
                  await ref.read(dioProvider).post(Endpoints.adminSalesmanForceLogout(id));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$name logged out'),
                      backgroundColor: Colors.orange,
                    ));
                  }
                } catch (_) {}
              },
            ),
          ]),
        ]),
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, WidgetRef ref, int id, String name) {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Reset Password: $name'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'New Password (min 6)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (passCtrl.text.length < 6) return;
              final dio = ref.read(dioProvider);
              await dio.put(Endpoints.adminSalesmanResetPassword(id),
                  data: {'new_password': passCtrl.text});
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Password reset for $name ✅')));
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, int id, String currentName, String currentPhone) {
    final nameCtrl = TextEditingController(text: currentName);
    final phoneCtrl = TextEditingController(text: currentPhone);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Salesman'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
                labelText: 'Phone (10 digits)',
                prefixText: '+91 ',
                counterText: '',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              if (phoneCtrl.text.trim().length != 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid 10-digit phone number')));
                return;
              }
              try {
                final dio = ref.read(dioProvider);
                await dio.put(Endpoints.adminSalesmanUpdate(id), data: {
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                });
                onRefresh();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Salesman updated ✅'),
                          backgroundColor: Color(0xFF2E7D32)));
                }
              } catch (e, st) {
                logError('admin-salesman', e, st);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Cash collections ───────────────────────────────────────────────────

class _CashCollectionsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CashCollectionsTab> createState() => _CashCollectionsTabState();
}

class _CashCollectionsTabState extends ConsumerState<_CashCollectionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _innerTabs;
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  List<ActiveFilter> _activeFilters = [];

  static const _filterDefs = [
    FilterDefinition(field: 'payment_method', label: 'Method', type: FilterType.select, options: ['cash', 'upi']),
    FilterDefinition(field: 'amount', label: 'Amount', type: FilterType.number),
    FilterDefinition(field: 'note', label: 'Note', type: FilterType.text),
  ];

  @override
  void initState() {
    super.initState();
    _innerTabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _innerTabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  bool get _hasDate => _dateFrom != null || _dateTo != null;

  bool _inDateRange(String? dateStr) {
    if (!_hasDate || dateStr == null) return true;
    try {
      final d = DateTime.parse(dateStr.substring(0, 10));
      if (_dateFrom != null && d.isBefore(_dateFrom!)) return false;
      if (_dateTo   != null && d.isAfter(_dateTo!)) return false;
    } catch (_) {}
    return true;
  }

  bool _matches(Map<String, dynamic> r) {
    if (!_inDateRange(r['created_at'] as String? ?? r['resolved_at'] as String?)) return false;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      final fields = [
        r['customer_name'], r['user_name'], r['salesman_name'],
        r['collector_name'], r['collected_by']?.toString(),
        r['amount']?.toString(), r['transaction_ref'],
      ].whereType<String>();
      if (!fields.any((f) => f.toLowerCase().contains(q))) return false;
    }
    if (!matchesAllFilters(r, _activeFilters)) return false;
    return true;
  }

  bool _matchesSettlement(Map<String, dynamic> s) {
    if (!_inDateRange(s['created_at'] as String?)) return false;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      if (![s['salesman_name'], s['note'], s['amount']?.toString()]
          .whereType<String>().any((f) => f.toLowerCase().contains(q))) return false;
    }
    if (!matchesAllFilters(s, _activeFilters)) return false;
    return true;
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
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32))),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(salesmanSummaryProvider);

    return data.when(
      data: (d) {
        final collected         = d['collected'] as List? ?? [];
        final pending           = d['pending'] as List? ?? [];
        final raisedSettlements = (d['raised_settlements'] as List? ?? []).cast<Map<String, dynamic>>();
        final settlements       = d['settlements'] as List? ?? [];

        // Apply search filter
        final filteredPending     = pending.cast<Map<String,dynamic>>().where(_matches).toList();
        final filteredRaised      = raisedSettlements.where(_matchesSettlement).toList();
        final filteredNotRaised   = collected.cast<Map<String,dynamic>>().where(_matches).toList();
        final filteredSettlements = settlements.cast<Map<String,dynamic>>().where(_matchesSettlement).toList();

        final totalNotRaised = filteredNotRaised.fold<double>(0, (s, c) => s + ((c['amount'] ?? c['total_collected'] ?? 0) as num).toDouble());
        final totalRaisedPendingAdmin = filteredRaised.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());

        return Column(children: [
          // Search bar — shared across all tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name, amount, salesman…',
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
          FilterChipBar(
            availableFilters: _filterDefs,
            activeFilters: _activeFilters,
            onAdd: (f) => setState(() => _activeFilters = [..._activeFilters.where((e) => e.field != f.field), f]),
            onRemove: (f) => setState(() => _activeFilters = _activeFilters.where((e) => e.field != f.field).toList()),
          ),
          // Date range row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _hasDate ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey.shade300),
                    ),
                    child: Row(children: [
                      Icon(Icons.date_range, size: 15,
                          color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        _hasDate
                            ? '${_fmt(_dateFrom!)} → ${_fmt(_dateTo!)}'
                            : 'Filter by date range',
                        style: TextStyle(
                          fontSize: 12,
                          color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey.shade600,
                          fontWeight: _hasDate ? FontWeight.w600 : FontWeight.normal,
                        ),
                      )),
                      Icon(Icons.edit_calendar_outlined, size: 13,
                          color: _hasDate ? const Color(0xFF2E7D32) : Colors.grey),
                    ]),
                  ),
                ),
              ),
              if (_hasDate) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
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
          ),
          // Inner tab bar — 4 tabs
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _innerTabs,
              labelColor: const Color(0xFF2E7D32),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF2E7D32),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                // Tab 1: Customer requests pending admin
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Cust. Pending', style: TextStyle(fontSize: 12)),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                      child: Text('${pending.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
                // Tab 2: Salesman raised settlement — waiting admin to acknowledge
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Raised by Salesman', style: TextStyle(fontSize: 12)),
                  if (raisedSettlements.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF1565C0), borderRadius: BorderRadius.circular(10)),
                      child: Text('${raisedSettlements.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
                // Tab 3: Salesman has cash but NOT raised yet
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Not Raised Yet', style: TextStyle(fontSize: 12)),
                  if (collected.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                      child: Text('${collected.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
                // Tab 4: Acknowledged/settled history
                const Tab(child: Text('Approved', style: TextStyle(fontSize: 12))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _innerTabs,
              children: [

                // ── TAB 1: Customer topup requests ─────────────────────────
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(salesmanSummaryProvider),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (filteredPending.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                          SizedBox(height: 12),
                          Text('No pending customer requests ✅',
                              style: TextStyle(color: Colors.grey, fontSize: 15)),
                          SizedBox(height: 6),
                          Text('All customer top-up requests have been processed.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                              textAlign: TextAlign.center),
                        ]),
                      ))
                    else ...[
                      _SecHeader('Customer Top-up Requests',
                          Icons.hourglass_empty, Colors.orange,
                          badge: '${pending.length}'),
                      const SizedBox(height: 4),
                      const Text('Approve or reject customer cash top-up requests.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 10),
                      ...filteredPending.map((r) => _PendingRequestTile(request: r,
                          onAction: () => ref.invalidate(salesmanSummaryProvider))),
                    ],
                  ]),
                ),

                // ── TAB 2: Raised by Salesman — admin to acknowledge ────────
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(salesmanSummaryProvider),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (filteredRaised.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                          SizedBox(height: 12),
                          Text('No raised settlement requests ✅',
                              style: TextStyle(color: Colors.grey, fontSize: 15)),
                          SizedBox(height: 6),
                          Text('No salesman has raised a settlement request yet.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                              textAlign: TextAlign.center),
                        ]),
                      ))
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.send_to_mobile, color: Color(0xFF1565C0), size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '${raisedSettlements.length} salesman${raisedSettlements.length == 1 ? '' : 's'} raised settlement — ₹${totalRaisedPendingAdmin.toStringAsFixed(0)} total. Acknowledge once you receive the cash.',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          )),
                        ]),
                      ),
                      ...filteredRaised.map((s) => _RaisedSettlementCard(
                        settlement: s,
                        onAcknowledge: () => _acknowledgeSettlement(context, ref, s),
                      )),
                    ],
                  ]),
                ),

                // ── TAB 3: Not Raised Yet — admin can settle directly ───────
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(salesmanSummaryProvider),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (filteredNotRaised.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                          SizedBox(height: 12),
                          Text('All collections settled ✅',
                              style: TextStyle(color: Colors.grey, fontSize: 15)),
                        ]),
                      ))
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '${collected.length} request${collected.length == 1 ? '' : 's'} — ₹${totalNotRaised.toStringAsFixed(0)} total. Salesman has NOT raised settlement yet.',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          )),
                        ]),
                      ),
                      ...filteredNotRaised.map((r) => _PendingRequestTile(
                          request: r,
                          onAction: () => ref.invalidate(salesmanSummaryProvider),
                          onSettle: () => _settleRequest(context, ref, r))),
                    ],
                  ]),
                ),

                // ── TAB 4: Approved / Settlement History ────────────────────
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(salesmanSummaryProvider),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (filteredSettlements.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.history, size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('No settlements acknowledged yet',
                              style: TextStyle(color: Colors.grey, fontSize: 15)),
                        ]),
                      ))
                    else ...[
                      _SecHeader('Acknowledged Settlements', Icons.check_circle,
                          const Color(0xFF2E7D32)),
                      const SizedBox(height: 8),
                      ...filteredSettlements.map((s) => _HistoryTile(s: s)),
                    ],
                  ]),
                ),

              ],
            ),
          ),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-salesman', e); return Center(child: Text(friendlyError(e))); },
    );
  }

  Future<void> _acknowledgeSettlement(
      BuildContext context, WidgetRef ref, Map<String, dynamic> s) async {
    final id     = s['id'] as int;
    final name   = s['salesman_name'] as String;
    final amount = (s['amount'] as num).toDouble();
    final note   = s['note'] as String?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          Text('Acknowledge: $name'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.payments, color: Color(0xFF2E7D32)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cash to receive from salesman',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('₹${amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32))),
              ]),
            ]),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note: $note', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Acknowledge & Mark Received'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.adminAcknowledgeSettlement(id));
      ref.invalidate(salesmanSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} from $name acknowledged ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to acknowledge')));
      }
    }
  }

  Future<void> _settleRequest(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    final amount      = (r['amount'] as num).toDouble();
    final salesman    = (r['salesman_name'] ?? r['collector_name'] ?? 'Unknown').toString();
    final customer    = (r['customer_name'] ?? r['user_name'] ?? '').toString();
    final requestId   = r['id'] as int;
    final noteCtrl    = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Settled'),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              Text('from $customer via $salesman',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('Mark this cash collection as settled. Cash may still be with salesman.',
              style: TextStyle(fontSize: 12, color: Colors.black87)),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(
              labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dioProvider).post(Endpoints.adminSalesmanSettle, data: {
        'salesman_name': salesman,
        'request_ids': [requestId],
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });
      ref.invalidate(salesmanSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} settled ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to settle')));
      }
    }
  }

}

class _SecHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? badge;
  const _SecHeader(this.title, this.icon, this.color, {this.badge});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
      if (badge != null) Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
        child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ]),
  );
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty(this.msg);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(child: Text(msg, style: const TextStyle(color: Colors.grey))),
  );
}

// ── Raised settlement card (salesman requested → admin acknowledges) ──────────

class _RaisedSettlementCard extends StatelessWidget {
  final Map<String, dynamic> settlement;
  final VoidCallback onAcknowledge;
  const _RaisedSettlementCard({required this.settlement, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final name   = settlement['salesman_name'] as String;
    final amount = (settlement['amount'] as num).toDouble();
    final date   = (settlement['created_at'] as String).length >= 16
        ? (settlement['created_at'] as String).substring(0, 16).replaceAll('T', ' ')
        : (settlement['created_at'] as String).substring(0, 10);
    final note   = settlement['note'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFE3F2FD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF1565C0),
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('Raised on $date', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (note != null && note.isNotEmpty)
                Text(note, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('Acknowledge Receipt — ₹${amount.toStringAsFixed(0)}'),
              onPressed: onAcknowledge,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PendingRequestTile extends ConsumerWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAction;
  final VoidCallback? onSettle; // optional — shown for approved-not-raised items
  const _PendingRequestTile({required this.request, required this.onAction, this.onSettle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = (request['amount'] as num).toDouble();
    final collector = (request['collector_name'] ?? request['salesman_name'] ?? request['collected_by'])?.toString() ?? 'Unknown';
    final userName = (request['user_name'] ?? request['customer_name'] as String?)?.toString() ?? '';
    final date = (request['created_at'] as String).substring(0, 16);
    final id = request['id'] as int;
    final isApproved = (request['status'] as String?) == 'approved';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Text(collector.isNotEmpty ? collector[0].toUpperCase() : '?',
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
            ),
            title: Text('₹${amount.toStringAsFixed(0)} via $collector',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('$userName  •  $date', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: isApproved
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve',
                      onPressed: () async {
                        final dio = ref.read(dioProvider);
                        await dio.post(Endpoints.adminApproveTopup(id));
                        onAction();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Reject',
                      onPressed: () async {
                        final dio = ref.read(dioProvider);
                        await dio.post(Endpoints.adminRejectTopup(id));
                        onAction();
                      },
                    ),
                  ]),
          ),
          // Settle button for approved-but-not-raised items
          if (onSettle != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Mark as Settled'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: onSettle,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> s;
  const _HistoryTile({required this.s});
  @override
  Widget build(BuildContext context) {
    final name   = s['salesman_name'] as String;
    final amount = (s['amount'] as num).toDouble();
    final raisedAt  = (s['created_at'] as String).length >= 16
        ? (s['created_at'] as String).substring(0, 16).replaceAll('T', ' ')
        : (s['created_at'] as String).substring(0, 10);
    final ackedAt   = s['updated_at'] != null && (s['updated_at'] as String).length >= 16
        ? (s['updated_at'] as String).substring(0, 16).replaceAll('T', ' ')
        : null;
    final note   = s['note'] as String?;
    final by     = s['settled_by_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFFE8F5E9),
              child: Icon(Icons.done_all, color: Color(0xFF2E7D32), size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name — ₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.send_to_mobile, size: 11, color: Colors.grey),
              const SizedBox(width: 3),
              Text('Raised: $raisedAt', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if (ackedAt != null && by != null) ...[
              const SizedBox(height: 1),
              Row(children: [
                Icon(Icons.check_circle, size: 11, color: Colors.green.shade600),
                const SizedBox(width: 3),
                Text('Acked by $by: $ackedAt',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
              ]),
            ] else if (by != null) ...[
              Text('Acknowledged by $by', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            if (note != null && note.isNotEmpty)
              Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
        ]),
      ),
    );
  }
}
