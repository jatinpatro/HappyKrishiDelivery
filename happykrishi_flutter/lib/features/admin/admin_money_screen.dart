import '../../core/theme/app_theme.dart'; 
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/widgets/active_filter.dart';
import '../../core/services/pdf_service.dart';
import '../../core/models/models.dart' show AppUser, WalletTransaction;
import 'wallet_credit_screen.dart' show WalletCreditScreen;

// ── Providers ─────────────────────────────────────────────────────────────────

final _topupsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final sep    = key.indexOf('|');
  final status = sep < 0 ? key : key.substring(0, sep);
  final fKey   = sep < 0 ? '' : key.substring(sep + 1);
  final params = _parseFilterKey(fKey);
  if (status != 'all') params['status'] = status;
  params['limit'] = '500';
  final res = await ref.read(dioProvider).get(Endpoints.adminTopupRequests,
      queryParameters: params.isEmpty ? null : params);
  return res.data as Map<String, dynamic>;
});

final _creditAdvancesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final params = _parseFilterKey(key);
  params['limit'] = '500';
  final res = await ref.read(dioProvider).get(Endpoints.adminCreditAdvances,
      queryParameters: params.isEmpty ? null : params);
  return res.data as Map<String, dynamic>;
});

final _directHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts  = key.split('|');
  final params = <String, String>{};
  if (parts.isNotEmpty && parts[0].isNotEmpty) params['date_from'] = parts[0];
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_to']   = parts[1];
  if (parts.length > 2 && parts[2].isNotEmpty) params['customer_search'] = parts[2];
  if (parts.length > 3 && parts[3].isNotEmpty) params['type'] = parts[3];
  else if (parts.length <= 3) params['type'] = 'admin'; // Direct tab default
  final res = await ref.read(dioProvider).get(Endpoints.adminWalletAudit,
      queryParameters: params);
  return res.data as Map<String, dynamic>;
});

Map<String, String> _parseFilterKey(String key) {
  if (key.isEmpty) return {};
  final parts = key.split('|');
  final params = <String, String>{};
  if (parts.isNotEmpty && parts[0].isNotEmpty) params['date_from'] = parts[0];
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_to']   = parts[1];
  return params;
}

// ── Filter configs ─────────────────────────────────────────────────────────────

const _topupsFilterConfig = FilterFormConfig(
  title: 'Filter Topups',
  showDateRange: true,
  showTextSearch: true,
  textSearchHint: 'Customer name, phone or amount',
  dynamicFields: [
    FilterDefinition(field: 'status',             label: 'Status',             type: FilterType.select,
        options: ['pending', 'approved', 'rejected'], serverSide: true),
    FilterDefinition(field: 'payment_method',    label: 'Payment method',     type: FilterType.select,
        options: ['cash', 'upi', 'bank_transfer'], serverSide: true),
    FilterDefinition(field: 'approved_by',       label: 'Approved by',        type: FilterType.select,
        options: ['admin', 'salesman'], serverSide: true),
    FilterDefinition(field: 'user_name',         label: 'Customer',           type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'collector_name',    label: 'Salesman/collector', type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'amount',            label: 'Amount (₹)',         type: FilterType.number, serverSide: false),
  ],
);

const _advancesFilterConfig = FilterFormConfig(
  title: 'Filter Advances',
  showDateRange: true,
  showTextSearch: true,
  textSearchHint: 'Customer name or phone',
  dynamicFields: [
    FilterDefinition(field: 'payment_received', label: 'Payment status', type: FilterType.select,
        options: ['0', '1'], serverSide: true),
    FilterDefinition(field: 'credited_by_role', label: 'Credited by',   type: FilterType.select,
        options: ['admin', 'salesman'], serverSide: true),
    FilterDefinition(field: 'user_name',         label: 'Customer',      type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'credited_by_name',  label: 'Credited by (name)',  type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'amount',            label: 'Amount (₹)',    type: FilterType.number, serverSide: false),
  ],
);

const _topupSearchFields = [
  'user_name', 'user_phone', 'collector_name', 'approved_by_name', 'credited_by_name', 'transaction_ref', 'amount',
];
const _advanceSearchFields = [
  'user_name', 'user_phone', 'credited_by_name', 'amount',
];

// ── Main Screen ───────────────────────────────────────────────────────────────

class AdminMoneyScreen extends ConsumerStatefulWidget {
  const AdminMoneyScreen({super.key});
  @override
  ConsumerState<AdminMoneyScreen> createState() => _AdminMoneyScreenState();
}

class _AdminMoneyScreenState extends ConsumerState<AdminMoneyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/admin/dashboard')),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Topups'),
            Tab(text: 'Advances'),
            Tab(text: 'Direct'),
            Tab(text: 'Wallet Activity'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [
        _TopupsTab(),
        _AdvancesTab(),
        _DirectTab(),
        _WalletActivityTab(),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: TOPUPS
// Sub-tabs: Pending | Approved | Rejected | Yet to Raise | Awaiting Ack | History
// ─────────────────────────────────────────────────────────────────────────────

class _TopupsTab extends ConsumerStatefulWidget {
  const _TopupsTab();
  @override
  ConsumerState<_TopupsTab> createState() => _TopupsTabState();
}

class _TopupsTabState extends ConsumerState<_TopupsTab>
    with SingleTickerProviderStateMixin {
  late final _inner = TabController(length: 6, vsync: this);
  FilterFormState _filter = FilterFormState.empty;

  @override
  void dispose() { _inner.dispose(); super.dispose(); }

  String _key(String status) => '$status|${_filter.toProviderKey(_topupsFilterConfig)}';

  void _invalidate() {
    for (final s in ['pending', 'approved', 'rejected', 'all']) {
      ref.invalidate(_topupsProvider(_key(s)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = (ref.watch(_topupsProvider(_key('pending'))).value?['summary'] as List? ?? []).cast<Map<String, dynamic>>();
    int cnt(String s) => (summary.firstWhere((r) => r['status'] == s, orElse: () => {'count': 0})['count'] as int? ?? 0);
    double sum(String s) => ((summary.firstWhere((r) => r['status'] == s, orElse: () => {'total': 0.0})['total'] as num?)?.toDouble() ?? 0);

    final allData = ref.watch(_topupsProvider(_key('all')));
    final raisedCount = (allData.value?['raised_settlements'] as List? ?? []).length;

    // Compute Yet to Raise count for badge
    final allRequests = (allData.value?['requests'] as List? ?? []).cast<Map<String, dynamic>>();
    final localFilters = _filter.toLocalFilters(_topupsFilterConfig);
    final filtered = allRequests.where((r) =>
        matchesSearch(r, _filter.search, _topupSearchFields) &&
        matchesAllFilters(r, localFilters)).toList();
    final yetToRaiseCount = filtered.where((r) =>
        r['status'] == 'approved' && r['settlement_id'] == null && r['settled_at'] == null).length;

    return Column(children: [
      // ── Summary row ───────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(children: [
          _StatChip('${cnt('pending')} pending', '₹${sum('pending').toStringAsFixed(0)}', Colors.orange),
          const SizedBox(width: 6),
          _StatChip('${cnt('approved')} approved', '₹${sum('approved').toStringAsFixed(0)}', AppColors.primary),
          const SizedBox(width: 6),
          _StatChip('${cnt('rejected')} rejected', '₹${sum('rejected').toStringAsFixed(0)}', Colors.red),
        ]),
      ),

      // ── Filter bar ────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: FilterBar(
          config: _topupsFilterConfig,
          state: _filter,
          onChanged: (f) { setState(() => _filter = f); _invalidate(); },
          onLoad: _invalidate,
          trailing: [
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Export',
              onPressed: () => _ExportSheet.show(
                context: context,
                title: 'Export Topups',
                filterFields: const ['dateRange', 'customer', 'salesman', 'status'],
                fetchFn: (params) async {
                  params['limit'] = '500';
                  final res = await ref.read(dioProvider).get(Endpoints.adminTopupRequests, queryParameters: params);
                  return (res.data['requests'] as List).cast<Map<String, dynamic>>();
                },
                pdfFn: (ctx, records, dateLabel) => PdfService.shareAdminTopupsReport(
                  context: ctx, requests: records, title: 'Topups Export$dateLabel'),
              ),
            ),
          ],
        ),
      ),

      // ── Inner tab bar ─────────────────────────────────────────────────────
      TabBar(
        controller: _inner,
        labelColor: AppColors.primary,
        unselectedLabelColor: Colors.grey,
        indicatorColor: AppColors.primary,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: [
          Tab(text: cnt('pending') > 0 ? 'Pending (${cnt('pending')})' : 'Pending'),
          const Tab(text: 'Approved'),
          const Tab(text: 'Rejected'),
          Tab(text: yetToRaiseCount > 0 ? 'Yet to Raise ($yetToRaiseCount)' : 'Yet to Raise'),
          Tab(text: raisedCount > 0 ? 'Awaiting Ack ($raisedCount)' : 'Awaiting Ack'),
          const Tab(text: 'History'),
        ],
      ),
      const Divider(height: 1),

      Expanded(child: TabBarView(controller: _inner, children: [
        // ── Pending ──────────────────────────────────────────────────────────
        _TopupList(statusKey: _key('pending'), filter: _filter, onRefresh: _invalidate),
        // ── Approved ─────────────────────────────────────────────────────────
        _TopupList(statusKey: _key('approved'), filter: _filter, onRefresh: _invalidate),
        // ── Rejected ─────────────────────────────────────────────────────────
        _TopupList(statusKey: _key('rejected'), filter: _filter, onRefresh: _invalidate),
        // ── Yet to Raise ─────────────────────────────────────────────────────
        _TopupYetToRaise(filterKey: _key('all'), filter: _filter, onRefresh: _invalidate),
        // ── Awaiting Acknowledgement ─────────────────────────────────────────
        _TopupSettlementList(
          filterKey: _key('all'),
          section: 'raised',
          onRefresh: _invalidate,
        ),
        // ── History ──────────────────────────────────────────────────────────
        _TopupSettlementList(
          filterKey: _key('all'),
          section: 'done',
          onRefresh: _invalidate,
        ),
      ])),
    ]);
  }
}

class _TopupList extends ConsumerWidget {
  final String statusKey;
  final FilterFormState filter;
  final VoidCallback onRefresh;
  const _TopupList({required this.statusKey, required this.filter, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_topupsProvider(statusKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-money', e); return Center(child: Text(friendlyError(e))); },
      data: (data) {
        final all = (data['requests'] as List).cast<Map<String, dynamic>>();
        final localFilters = filter.toLocalFilters(_topupsFilterConfig);
        final items = all.where((r) =>
            matchesSearch(r, filter.search, _topupSearchFields) &&
            matchesAllFilters(r, localFilters)).toList();
        final label = statusKey.split('|').first;
        if (items.isEmpty) return Center(child: Text('No $label requests', style: const TextStyle(color: Colors.grey)));
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_topupsProvider(statusKey)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (_, i) => _TopupCard(request: items[i], onRefresh: onRefresh),
          ),
        );
      },
    );
  }
}

class _TopupYetToRaise extends ConsumerWidget {
  final String filterKey;
  final FilterFormState filter;
  final VoidCallback onRefresh;
  const _TopupYetToRaise({required this.filterKey, required this.filter, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_topupsProvider(filterKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (data) {
        final all = (data['requests'] as List).cast<Map<String, dynamic>>();
        final localFilters = filter.toLocalFilters(_topupsFilterConfig);
        final items = all.where((r) =>
            matchesSearch(r, filter.search, _topupSearchFields) &&
            matchesAllFilters(r, localFilters) &&
            r['status'] == 'approved' &&
            r['settlement_id'] == null &&
            r['settled_at'] == null &&
            r['collected_by'] != null &&
            r['payment_method'] == 'cash').toList();

        if (items.isEmpty) {
          return const Center(child: Text('No collections waiting to be raised', style: TextStyle(color: Colors.grey)));
        }

        // Group by salesman
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final r in items) {
          final name = r['salesman_name'] as String? ?? r['collector_name'] as String? ?? r['collected_by']?.toString() ?? 'Unknown';
          (grouped[name] ??= []).add(r);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_topupsProvider(filterKey)),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            ...grouped.entries.map((e) {
              final name    = e.key;
              final records = e.value;
              final total   = records.fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());
              final phone   = records.first['salesman_phone'] as String?;
              final pendingCount  = 0; // already filtered to approved only
              final approvedCount = records.length;
              final salesmanUserId = int.tryParse(records.first['collected_by']?.toString() ?? '');
              return _SalesmanCollectionCard(
                name: name,
                phone: phone,
                records: records,
                total: total,
                pendingCount: pendingCount,
                approvedCount: approvedCount,
                salesmanUserId: salesmanUserId,
                onRaised: () { ref.invalidate(_topupsProvider(filterKey)); onRefresh(); },
              );
            }),
          ]),
        );
      },
    );
  }
}

class _TopupSettlementList extends ConsumerWidget {
  final String filterKey;
  final String section; // 'raised' or 'done'
  final VoidCallback onRefresh;
  const _TopupSettlementList({required this.filterKey, required this.section, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_topupsProvider(filterKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (data) {
        final items = section == 'raised'
            ? (data['raised_settlements'] as List? ?? []).cast<Map<String, dynamic>>()
            : (data['settlements'] as List? ?? []).cast<Map<String, dynamic>>();
        final canAck = section == 'raised';

        if (items.isEmpty) {
          return Center(child: Text(
            canAck ? 'No settlements awaiting acknowledgement' : 'No settlement history yet',
            style: const TextStyle(color: Colors.grey),
          ));
        }

        return RefreshIndicator(
          onRefresh: () async { ref.invalidate(_topupsProvider(filterKey)); onRefresh(); },
          child: ListView(padding: const EdgeInsets.all(12), children: [
            ...items.map((s) => _SettlementCard(
              settlement: s,
              canAcknowledge: canAck,
              onAcknowledged: canAck ? () { ref.invalidate(_topupsProvider(filterKey)); onRefresh(); } : null,
            )),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: ADVANCES
// Sub-tabs: All | Outstanding | Paid–Not Raised | Awaiting Ack | Settled
// ─────────────────────────────────────────────────────────────────────────────

class _AdvancesTab extends ConsumerStatefulWidget {
  const _AdvancesTab();
  @override
  ConsumerState<_AdvancesTab> createState() => _AdvancesTabState();
}

class _AdvancesTabState extends ConsumerState<_AdvancesTab>
    with SingleTickerProviderStateMixin {
  late final _inner = TabController(length: 5, vsync: this);
  FilterFormState _filter = FilterFormState.empty;

  @override
  void dispose() { _inner.dispose(); super.dispose(); }

  String get _key => _filter.toProviderKey(_advancesFilterConfig);

  void _invalidate() => ref.invalidate(_creditAdvancesProvider(_key));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_creditAdvancesProvider(_key));

    // Compute badge counts
    final allAdv = (async.value?['requests'] as List? ?? []).cast<Map<String, dynamic>>();
    final localFilters = _filter.toLocalFilters(_advancesFilterConfig);
    final advances = allAdv.where((r) =>
        matchesSearch(r, _filter.search, _advanceSearchFields) &&
        matchesAllFilters(r, localFilters)).toList();
    final outstandingCount = advances.where((a) => (a['payment_received'] as int? ?? 0) == 0).length;
    final paidNotRaisedCount = advances.where((a) =>
        (a['payment_received'] as int? ?? 0) == 1 &&
        (a['paid_by_role'] as String?) == 'salesman' &&
        a['settlement_id'] == null).length;
    final raisedCount = (async.value?['raised_settlements'] as List? ?? []).length;

    // Summary totals
    final totalGiven  = advances.fold(0.0, (s, a) => s + (a['amount'] as num).toDouble());
    final totalOut    = advances.where((a) => (a['payment_received'] as int? ?? 0) == 0).fold(0.0, (s, a) => s + (a['amount'] as num).toDouble());
    final totalPaid   = advances.where((a) => (a['payment_received'] as int? ?? 0) == 1).fold(0.0, (s, a) => s + (a['amount'] as num).toDouble());

    // By-staff breakdown
    final Map<String, _SalesmanBreakdown> byStaff = {};
    for (final a in advances) {
      final role   = a['credited_by_role'] as String? ?? 'admin';
      final name   = a['credited_by_name'] as String? ?? role;
      final mapKey = '$role:$name';
      final entry  = byStaff.putIfAbsent(mapKey, () => _SalesmanBreakdown(name: name, role: role));
      entry.total += (a['amount'] as num).toDouble();
      if ((a['payment_received'] as int? ?? 0) == 0) entry.outstanding += (a['amount'] as num).toDouble();
      else entry.received += (a['amount'] as num).toDouble();
    }

    return Column(children: [
      // ── Summary box ───────────────────────────────────────────────────────
      if (advances.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.indigo.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _StatChip('${advances.length} total', '₹${totalGiven.toStringAsFixed(0)}', Colors.indigo),
              const SizedBox(width: 6),
              _StatChip('$outstandingCount outstanding', '₹${totalOut.toStringAsFixed(0)}', Colors.orange),
              const SizedBox(width: 6),
              _StatChip('paid back', '₹${totalPaid.toStringAsFixed(0)}', Colors.green),
            ]),
            if (byStaff.length > 1) ...[
              const SizedBox(height: 8),
              ...byStaff.values.map((b) => Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: (b.role == 'admin' ? Colors.indigo : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(b.role, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                      color: b.role == 'admin' ? Colors.indigo : Colors.orange)),
                ),
                const SizedBox(width: 5),
                Expanded(child: Text(b.name, style: const TextStyle(fontSize: 11))),
                Text('₹${b.total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                if (b.outstanding > 0) ...[
                  const SizedBox(width: 4),
                  Text('(₹${b.outstanding.toStringAsFixed(0)} due)', style: const TextStyle(fontSize: 9, color: Colors.orange)),
                ],
              ])),
            ],
          ]),
        ),

      // ── Filter bar ────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: FilterBar(
          config: _advancesFilterConfig,
          state: _filter,
          onChanged: (f) { setState(() => _filter = f); _invalidate(); },
          onLoad: _invalidate,
          trailing: [
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Export',
              onPressed: () => _ExportSheet.show(
                context: context,
                title: 'Export Credit Advances',
                filterFields: const ['dateRange', 'customer', 'creditedBy', 'status'],
                fetchFn: (params) async {
                  params['limit'] = '500';
                  final res = await ref.read(dioProvider).get(Endpoints.adminCreditAdvances, queryParameters: params);
                  return (res.data['requests'] as List).cast<Map<String, dynamic>>();
                },
                pdfFn: (ctx, records, dateLabel) => PdfService.shareAdminAdvancesReport(
                  context: ctx, advances: records, title: 'Advances Export$dateLabel'),
              ),
            ),
          ],
        ),
      ),

      // ── Inner tab bar ─────────────────────────────────────────────────────
      TabBar(
        controller: _inner,
        labelColor: Colors.indigo,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.indigo,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: [
          Tab(text: 'All (${advances.length})'),
          Tab(text: outstandingCount > 0 ? 'Outstanding ($outstandingCount)' : 'Outstanding'),
          Tab(text: paidNotRaisedCount > 0 ? 'Paid — Not Raised ($paidNotRaisedCount)' : 'Paid — Not Raised'),
          Tab(text: raisedCount > 0 ? 'Awaiting Ack ($raisedCount)' : 'Awaiting Ack'),
          const Tab(text: 'Settled'),
        ],
      ),
      const Divider(height: 1),

      Expanded(child: TabBarView(controller: _inner, children: [
        // ── All ──────────────────────────────────────────────────────────────
        _AdvanceList(advances: advances, onRefresh: _invalidate),
        // ── Outstanding ──────────────────────────────────────────────────────
        _AdvanceList(
          advances: advances.where((a) => (a['payment_received'] as int? ?? 0) == 0).toList(),
          onRefresh: _invalidate,
          emptyText: 'No outstanding advances',
        ),
        // ── Paid — Not Raised ────────────────────────────────────────────────
        _AdvancePaidNotRaised(
          advances: advances.where((a) =>
              (a['payment_received'] as int? ?? 0) == 1 &&
              (a['paid_by_role'] as String?) == 'salesman' &&
              a['settlement_id'] == null).toList(),
          advancesKey: _key,
          onRefresh: _invalidate,
        ),
        // ── Awaiting Acknowledgement ─────────────────────────────────────────
        _AdvanceSettlementList(
          advancesKey: _key,
          section: 'raised',
          onRefresh: _invalidate,
        ),
        // ── Settled ──────────────────────────────────────────────────────────
        _AdvanceSettledList(
          advances: advances.where((a) =>
              (a['paid_by_role'] as String?) == 'admin' ||
              (a['settlement_id'] != null)).toList(),
          advancesKey: _key,
          onRefresh: _invalidate,
        ),
      ])),
    ]);
  }
}

class _AdvanceList extends ConsumerWidget {
  final List<Map<String, dynamic>> advances;
  final VoidCallback onRefresh;
  final String? emptyText;
  const _AdvanceList({required this.advances, required this.onRefresh, this.emptyText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (advances.isEmpty) {
      return Center(child: Text(emptyText ?? 'No advances', style: const TextStyle(color: Colors.grey)));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      ...advances.map((a) => _AdvanceCard(advance: a, onAction: onRefresh)),
    ]);
  }
}

class _AdvancePaidNotRaised extends ConsumerWidget {
  final List<Map<String, dynamic>> advances;
  final String advancesKey;
  final VoidCallback onRefresh;
  const _AdvancePaidNotRaised({required this.advances, required this.advancesKey, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (advances.isEmpty) {
      return const Center(child: Text('No advances paid and waiting to be raised', style: TextStyle(color: Colors.grey)));
    }

    final Map<String, List<Map<String, dynamic>>> bySalesman = {};
    for (final a in advances) {
      final name = a['credited_by_name'] as String? ?? 'Unknown';
      (bySalesman[name] ??= []).add(a);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      ...bySalesman.entries.map((e) {
        final items = e.value;
        final total = items.fold(0.0, (s, a) => s + (a['amount'] as num).toDouble());
        final smId  = items.first['credited_by_id'] as int?;
        return _SalesmanAdvanceGroupCard(
          salesmanName: e.key, salesmanId: smId,
          advances: items, total: total,
          settlementType: 'credit_advance',
          onRaised: () { ref.invalidate(_creditAdvancesProvider(advancesKey)); onRefresh(); },
        );
      }),
    ]);
  }
}

class _AdvanceSettlementList extends ConsumerWidget {
  final String advancesKey;
  final String section; // 'raised' or 'done'
  final VoidCallback onRefresh;
  const _AdvanceSettlementList({required this.advancesKey, required this.section, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_creditAdvancesProvider(advancesKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (data) {
        final items = (data['raised_settlements'] as List? ?? []).cast<Map<String, dynamic>>();
        if (items.isEmpty) {
          return const Center(child: Text('No settlements awaiting acknowledgement', style: TextStyle(color: Colors.grey)));
        }
        return RefreshIndicator(
          onRefresh: () async { ref.invalidate(_creditAdvancesProvider(advancesKey)); onRefresh(); },
          child: ListView(padding: const EdgeInsets.all(12), children: [
            ...items.map((s) => _SettlementCard(
              settlement: s, canAcknowledge: true,
              onAcknowledged: () { ref.invalidate(_creditAdvancesProvider(advancesKey)); onRefresh(); },
            )),
          ]),
        );
      },
    );
  }
}

class _AdvanceSettledList extends ConsumerWidget {
  final List<Map<String, dynamic>> advances;
  final String advancesKey;
  final VoidCallback onRefresh;
  const _AdvanceSettledList({required this.advances, required this.advancesKey, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneSettlements = (ref.watch(_creditAdvancesProvider(advancesKey)).value?['settlements'] as List? ?? []).cast<Map<String, dynamic>>();

    if (advances.isEmpty && doneSettlements.isEmpty) {
      return const Center(child: Text('No settled advances yet', style: TextStyle(color: Colors.grey)));
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      if (doneSettlements.isNotEmpty) ...[
        const _SectionHeader('Settled via Salesman Settlements', AppColors.primary),
        const SizedBox(height: 8),
        ...doneSettlements.map((s) => _SettlementCard(settlement: s, canAcknowledge: false, onAcknowledged: null)),
        const SizedBox(height: 16),
      ],
      if (advances.isNotEmpty) ...[
        const _SectionHeader('Admin Direct Settlements', Colors.indigo),
        const SizedBox(height: 8),
        ...advances.where((a) => (a['paid_by_role'] as String?) == 'admin' && a['settlement_id'] == null)
            .map((a) => _AdvanceCard(advance: a, onAction: null)),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3: DIRECT
// Sub-tabs: Credit/Deduct | History
// ─────────────────────────────────────────────────────────────────────────────

class _DirectTab extends ConsumerStatefulWidget {
  const _DirectTab();
  @override
  ConsumerState<_DirectTab> createState() => _DirectTabState();
}

class _DirectTabState extends ConsumerState<_DirectTab>
    with SingleTickerProviderStateMixin {
  late final _inner = TabController(length: 2, vsync: this);
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() { _inner.dispose(); _searchCtrl.dispose(); super.dispose(); }

  String get _key {
    String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    return '${_dateFrom != null ? fmt(_dateFrom!) : ''}|${_dateTo != null ? fmt(_dateTo!) : ''}|$_search';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(
        controller: _inner,
        labelColor: Colors.indigo,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.indigo,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: const [
          Tab(text: 'Credit / Deduct'),
          Tab(text: 'History'),
        ],
      ),
      const Divider(height: 1),
      Expanded(child: TabBarView(controller: _inner, children: [
        const WalletCreditScreen(),
        _DirectHistory(
          providerKey: _key,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          search: _search,
          searchCtrl: _searchCtrl,
          onDateChanged: (from, to) => setState(() { _dateFrom = from; _dateTo = to; }),
          onSearchChanged: (v) => setState(() => _search = v),
          onExport: () => _ExportSheet.show(
            context: context,
            title: 'Export Direct Transactions',
            filterFields: const ['dateRange', 'customer'],
            fetchFn: (params) async {
              params['type'] = 'admin';
              params['limit'] = '500';
              final res = await ref.read(dioProvider).get(Endpoints.adminWalletAudit, queryParameters: params);
              return (res.data['transactions'] as List).cast<Map<String, dynamic>>();
            },
            pdfFn: (ctx, records, dateLabel) => PdfService.shareAdminDirectTransactionsReport(
              context: ctx, transactions: records, title: 'Direct Transactions$dateLabel'),
          ),
        ),
      ])),
    ]);
  }
}

class _DirectHistory extends ConsumerWidget {
  final String providerKey;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String search;
  final TextEditingController searchCtrl;
  final void Function(DateTime?, DateTime?) onDateChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onExport;
  const _DirectHistory({
    required this.providerKey, required this.dateFrom, required this.dateTo,
    required this.search, required this.searchCtrl, required this.onDateChanged,
    required this.onSearchChanged, required this.onExport,
  });

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_directHistoryProvider(providerKey));
    final hasDate = dateFrom != null || dateTo != null;

    return Column(children: [
      // ── Filters ───────────────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: dateFrom != null && dateTo != null
                        ? DateTimeRange(start: dateFrom!, end: dateTo!)
                        : null,
                  );
                  if (picked != null) onDateChanged(picked.start, picked.end);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasDate ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hasDate ? AppColors.primary : Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_outlined, size: 15, color: hasDate ? AppColors.primary : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      hasDate
                          ? '${dateFrom != null ? _fmt(dateFrom!) : '…'} → ${dateTo != null ? _fmt(dateTo!) : '…'}'
                          : 'All dates',
                      style: TextStyle(fontSize: 12, color: hasDate ? AppColors.primary : Colors.grey),
                    )),
                    if (hasDate)
                      GestureDetector(
                        onTap: () => onDateChanged(null, null),
                        child: const Icon(Icons.close, size: 14, color: Colors.grey),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export',
              onPressed: onExport,
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by customer name…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () {
                      searchCtrl.clear(); onSearchChanged('');
                    })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),

      // ── List ──────────────────────────────────────────────────────────────
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (data) {
            final txns = (data['transactions'] as List? ?? []).cast<Map<String, dynamic>>();
            final summary = data['summary'] as Map<String, dynamic>? ?? {};

            if (txns.isEmpty) {
              return const Center(child: Text('No direct transactions', style: TextStyle(color: Colors.grey)));
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(_directHistoryProvider(providerKey)),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(children: [
                      Text('₹${(summary['total_credited'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
                      const Text('Credited', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ])),
                    Container(width: 1, height: 32, color: Colors.indigo.shade200),
                    Expanded(child: Column(children: [
                      Text('₹${(summary['total_debited'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
                      const Text('Debited', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ])),
                    Container(width: 1, height: 32, color: Colors.indigo.shade200),
                    Expanded(child: Column(children: [
                      Text('${txns.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
                      const Text('Transactions', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ])),
                  ]),
                ),
                ...txns.map((t) => _DirectTxnCard(txn: t)),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _DirectTxnCard extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _DirectTxnCard({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn['type'] == 'credit';
    final amount   = (txn['amount'] as num).toDouble();
    final color    = isCredit ? AppColors.primary : Colors.red;
    final name     = txn['customer_name'] as String? ?? txn['user_name'] as String? ?? '';
    final phone    = txn['customer_phone'] as String? ?? txn['user_phone'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            radius: 18,
            child: Icon(isCredit ? Icons.add : Icons.remove, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (phone.isNotEmpty) Text('+91 $phone', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (txn['description'] != null)
              Text(txn['description'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text((txn['created_at'] as String).substring(0, 16).replaceAll('T', ' '),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            Text('Bal: ₹${(txn['balance_after'] as num).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ExportSheet {
  static void show({
    required BuildContext context,
    required String title,
    required List<String> filterFields,
    required Future<List<Map<String, dynamic>>> Function(Map<String, String> params) fetchFn,
    required Future<void> Function(BuildContext ctx, List<Map<String, dynamic>> records, String dateLabel) pdfFn,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ExportSheetContent(
        title: title,
        filterFields: filterFields,
        fetchFn: fetchFn,
        pdfFn: pdfFn,
      ),
    );
  }
}

class _ExportSheetContent extends ConsumerStatefulWidget {
  final String title;
  final List<String> filterFields;
  final Future<List<Map<String, dynamic>>> Function(Map<String, String> params) fetchFn;
  final Future<void> Function(BuildContext ctx, List<Map<String, dynamic>> records, String dateLabel) pdfFn;
  const _ExportSheetContent({
    required this.title, required this.filterFields,
    required this.fetchFn, required this.pdfFn,
  });
  @override
  ConsumerState<_ExportSheetContent> createState() => _ExportSheetContentState();
}

class _ExportSheetContentState extends ConsumerState<_ExportSheetContent> {
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _customerCtrl  = TextEditingController();
  final _salesmanCtrl  = TextEditingController();
  String? _statusFilter;
  bool _loading = false;

  static const _statuses = ['pending', 'approved', 'rejected'];

  @override
  void dispose() {
    _customerCtrl.dispose();
    _salesmanCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _download() async {
    setState(() => _loading = true);
    try {
      final params = <String, String>{};
      if (_dateFrom != null) params['date_from'] = _fmt(_dateFrom!);
      if (_dateTo   != null) params['date_to']   = _fmt(_dateTo!);
      if (_customerCtrl.text.trim().isNotEmpty) params['search'] = _customerCtrl.text.trim();
      if (_salesmanCtrl.text.trim().isNotEmpty) params['collector_name'] = _salesmanCtrl.text.trim();
      if (_statusFilter != null) params['status'] = _statusFilter!;

      final records = await widget.fetchFn(params);
      if (!mounted) return;

      final dateLabel = _dateFrom != null
          ? ' (${_fmt(_dateFrom!)} – ${_fmt(_dateTo ?? _dateFrom!)})'
          : '';

      await widget.pdfFn(context, records, dateLabel);
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      logError('export', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = _dateFrom != null || _dateTo != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 16),

            // Date range
            if (widget.filterFields.contains('dateRange')) ...[
              const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: _dateFrom != null && _dateTo != null
                        ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
                        : null,
                  );
                  if (picked != null) setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: hasDate ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hasDate ? AppColors.primary : Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_outlined, size: 16, color: hasDate ? AppColors.primary : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      hasDate
                          ? '${_dateFrom != null ? _fmt(_dateFrom!) : '…'}  →  ${_dateTo != null ? _fmt(_dateTo!) : '…'}'
                          : 'All dates — tap to filter',
                      style: TextStyle(fontSize: 13, color: hasDate ? AppColors.primary : Colors.grey),
                    )),
                    if (hasDate)
                      GestureDetector(
                        onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                        child: const Icon(Icons.close, size: 15, color: Colors.grey),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Customer name
            if (widget.filterFields.contains('customer')) ...[
              const Text('Customer Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _customerCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by customer name…',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Salesman / collector name
            if (widget.filterFields.contains('salesman')) ...[
              const Text('Salesman / Collector', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _salesmanCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by salesman name…',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Status chips
            if (widget.filterFields.contains('status')) ...[
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
                ..._statuses.map((s) => ChoiceChip(
                  label: Text(s[0].toUpperCase() + s.substring(1)),
                  selected: _statusFilter == s,
                  onSelected: (_) => setState(() => _statusFilter = _statusFilter == s ? null : s),
                )),
              ]),
              const SizedBox(height: 14),
            ],

            // Credited by chips
            if (widget.filterFields.contains('creditedBy')) ...[
              const Text('Credited By', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _salesmanCtrl,
                decoration: InputDecoration(
                  hintText: 'Salesman or admin name…',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Download button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text(_loading ? 'Fetching records…' : 'Download PDF'),
                onPressed: _loading ? null : _download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOPUP CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TopupCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onRefresh;
  const _TopupCard({required this.request, required this.onRefresh});
  @override
  ConsumerState<_TopupCard> createState() => _TopupCardState();
}

class _TopupCardState extends ConsumerState<_TopupCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Approve Top-up?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Credit ₹${(widget.request['amount'] as num).toStringAsFixed(0)} to ${widget.request['user_name']}?'),
        const SizedBox(height: 10),
        TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('Approve')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminApproveTopup(widget.request['id'] as int),
          data: {'note': noteCtrl.text.isEmpty ? null : noteCtrl.text});
      widget.onRefresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Approved ✅'), backgroundColor: AppColors.primary));
    } catch (e, st) {
      logError('topup-approve', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _reject() async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reject Request?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Reject ₹${(widget.request['amount'] as num).toStringAsFixed(0)} from ${widget.request['user_name']}?'),
        const SizedBox(height: 10),
        TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Reject')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminRejectTopup(widget.request['id'] as int),
          data: {'note': noteCtrl.text.isEmpty ? null : noteCtrl.text});
      widget.onRefresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejected')));
    } catch (e, st) {
      logError('topup-reject', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final status = r['status'] as String;
    final amount = (r['amount'] as num).toDouble();
    final method = r['payment_method'] as String? ?? 'cash';
    final isPending = status == 'pending';
    final statusColor = status == 'approved' ? AppColors.primary : status == 'rejected' ? Colors.red : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: statusColor.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xFFEAF2EA),
                child: Text((r['user_name'] as String? ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['user_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('+91 ${r['user_phone'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            _Tag(method == 'upi' ? '💳 UPI' : method == 'bank_transfer' ? '🏦 Bank' : '💵 Cash',
                method == 'upi' ? Colors.purple : Colors.blue),
            if ((r['collector_name'] ?? r['collected_by']) != null)
              _Tag('via ${r['collector_name'] ?? r['collected_by']}', Colors.teal),
            _Tag('📅 ${(r['created_at'] as String).substring(0, 10)}', Colors.grey),
            if (r['admin_note'] != null) _Tag('📝 ${r['admin_note']}', Colors.grey),
          ]),
          if (status == 'approved') ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final approvedBy   = r['approved_by_name'] as String?;
              final approvedRole = r['approved_by_role'] as String?;
              final collector    = (r['collector_name'] ?? r['collected_by'])?.toString();
              final isAdminApproved = approvedRole == 'admin';
              final settlementAcknowledged = r['settlement_acknowledged'] != null;
              final cashStillWithSalesman  = isAdminApproved && collector != null && collector.isNotEmpty && !settlementAcknowledged;
              String label;
              if (approvedBy != null) {
                label = 'Approved by ${isAdminApproved ? 'Admin' : 'Salesman'}: $approvedBy';
                if (cashStillWithSalesman) {
                  label += ' · Cash with salesman: $collector';
                } else if (isAdminApproved && collector != null && collector.isNotEmpty) {
                  label += ' · Cash settled by salesman: $collector';
                }
              } else {
                label = 'Approved';
              }
              final color  = isAdminApproved ? Colors.indigo : Colors.green.shade700;
              final bg     = isAdminApproved ? Colors.indigo.shade50 : Colors.green.shade50;
              final border = isAdminApproved ? Colors.indigo.shade200 : Colors.green.shade300;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(isAdminApproved ? Icons.admin_panel_settings_outlined : Icons.badge_outlined, size: 15, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
                ]),
              );
            }),
          ],
          if (isPending) ...[
            const SizedBox(height: 10),
            _loading
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: _reject,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 8)),
                      child: const Text('Reject'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(
                      onPressed: _approve,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)),
                      child: const Text('Approve & Credit'),
                    )),
                  ]),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTLEMENT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SettlementCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> settlement;
  final bool canAcknowledge;
  final VoidCallback? onAcknowledged;
  const _SettlementCard({required this.settlement, required this.canAcknowledge, required this.onAcknowledged});
  @override
  ConsumerState<_SettlementCard> createState() => _SettlementCardState();
}

class _SettlementCardState extends ConsumerState<_SettlementCard> {
  bool _loading = false;

  Future<void> _acknowledge() async {
    final s = widget.settlement;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Acknowledge Settlement?'),
      content: Text('Confirm ₹${(s['amount'] as num).toStringAsFixed(0)} received from ${s['salesman_name']}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Acknowledge')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminAcknowledgeSettlement(s['id'] as int));
      widget.onAcknowledged?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Settlement from ${s['salesman_name']} acknowledged ✅'),
          backgroundColor: AppColors.primary));
    } catch (e, st) {
      logError('settlement-ack', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settlement;
    final amount = (s['amount'] as num).toDouble();
    final acknowledged = s['settled_by'] != null;
    final ackedBy = s['settled_by_name'] ?? s['acknowledged_by_name'] as String?;
    final ids = (() { try { return (s['topup_request_ids'] as List?)?.length ?? 0; } catch (_) { return 0; } })();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: acknowledged ? Colors.green.shade200 : Colors.blue.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xFFEAF2EA),
                child: Text((s['salesman_name'] as String? ?? 'S')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s['salesman_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                () {
                  final t = s['settlement_type'] as String? ?? 'cash';
                  final label = t == 'credit_advance' ? 'Credit Advance' : t == 'mixed' ? 'Mixed' : 'Cash';
                  final color = t == 'credit_advance' ? Colors.indigo : t == 'mixed' ? Colors.deepPurple : const Color(0xFF1565C0);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.3))),
                    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                  );
                }(),
              ]),
              Text('$ids collection${ids == 1 ? '' : 's'} · ${(s['created_at'] as String).substring(0, 10)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (s['note'] != null) Text(s['note'] as String, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: acknowledged ? Colors.green.shade50 : Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text(acknowledged ? 'Done' : 'Pending',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: acknowledged ? Colors.green : Colors.blue)),
              ),
            ]),
          ]),
          if (acknowledged && ackedBy != null) ...[
            const SizedBox(height: 6),
            Text('Acknowledged by $ackedBy', style: const TextStyle(fontSize: 11, color: Colors.green)),
          ],
          if (widget.canAcknowledge) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _loading
                  ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Acknowledge Receipt'),
                      onPressed: _acknowledge,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADVANCE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AdvanceCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> advance;
  final VoidCallback? onAction;
  const _AdvanceCard({required this.advance, required this.onAction});
  @override
  ConsumerState<_AdvanceCard> createState() => _AdvanceCardState();
}

class _AdvanceCardState extends ConsumerState<_AdvanceCard> {
  bool _loading = false;

  Future<void> _markPaid() async {
    final amount = (widget.advance['amount'] as num).toDouble();
    final name   = widget.advance['user_name'] as String? ?? 'customer';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Mark Payment Received?'),
      content: Text('Confirm ₹${amount.toStringAsFixed(0)} received from $name.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Mark Paid')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminMarkCreditPaid(widget.advance['id'] as int));
      widget.onAction?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} marked paid ✅'), backgroundColor: Colors.indigo));
    } catch (e, st) {
      logError('advance-paid', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.advance;
    final paid        = (a['payment_received'] as int? ?? 0) == 1;
    final amount      = (a['amount'] as num).toDouble();
    final paidByRole  = a['paid_by_role'] as String?;
    final creditedBy  = a['credited_by_role'] as String?;
    final settlementId = a['settlement_id'];

    String? settlementLine;
    if (paid) {
      if (paidByRole == 'admin') {
        settlementLine = creditedBy == 'admin' ? 'Admin gave & received — fully settled' : 'Admin received cash directly';
      } else if (settlementId != null) {
        settlementLine = 'Settled via salesman settlement #$settlementId';
      } else if (paidByRole == 'salesman') {
        settlementLine = 'Salesman received — pending settlement raise';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: paid ? Colors.green.shade200 : Colors.indigo.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.add_card_outlined, color: Colors.indigo, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['user_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('+91 ${a['user_phone'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (a['credited_by_name'] != null)
              Text('By ${a['credited_by_role']}: ${a['credited_by_name']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (settlementLine != null)
              Text(settlementLine, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                  color: paid ? Colors.green.shade700 : Colors.grey)),
            if (a['admin_note'] != null)
              Text(a['admin_note'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text((a['created_at'] as String).substring(0, 10), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: paid ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(paid ? 'Paid' : 'Pending', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: paid ? Colors.green : Colors.orange)),
            ),
            if (!paid && widget.onAction != null) ...[
              const SizedBox(height: 4),
              _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _markPaid,
                      style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
                      child: const Text('Mark Paid', style: TextStyle(fontSize: 11, color: Colors.indigo))),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALESMAN COLLECTION CARD (Topups — Yet to Raise)
// ─────────────────────────────────────────────────────────────────────────────

class _SalesmanCollectionCard extends ConsumerStatefulWidget {
  final String name;
  final String? phone;
  final List<Map<String, dynamic>> records;
  final double total;
  final int pendingCount, approvedCount;
  final int? salesmanUserId;
  final VoidCallback onRaised;
  const _SalesmanCollectionCard({
    required this.name, required this.phone, required this.records,
    required this.total, required this.pendingCount, required this.approvedCount,
    required this.salesmanUserId, required this.onRaised,
  });
  @override
  ConsumerState<_SalesmanCollectionCard> createState() => _SalesmanCollectionCardState();
}

class _SalesmanCollectionCardState extends ConsumerState<_SalesmanCollectionCard> {
  bool _raising = false;

  Future<void> _raiseOnBehalf() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Settlement on Behalf?'),
        content: Text('Raise ₹${widget.total.toStringAsFixed(0)} (${widget.records.length} collection${widget.records.length == 1 ? '' : 's'}) for ${widget.name}?\n\nThis will create a settlement request that you can then acknowledge.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Raise'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _raising = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminRaiseSalesmanSettlement(widget.salesmanUserId!));
      widget.onRaised();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Settlement of ₹${widget.total.toStringAsFixed(0)} raised for ${widget.name} ✅'),
        backgroundColor: AppColors.primary,
      ));
    } catch (e, st) {
      logError('admin-raise-settlement', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _raising = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.orange.shade300)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Colors.orange.shade50,
            child: Text(widget.name[0].toUpperCase(), style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
          ),
          title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(
            '${widget.records.length} collection${widget.records.length == 1 ? '' : 's'}${widget.phone != null ? ' · +91 ${widget.phone}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Text('₹${widget.total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange.shade700)),
          children: [
            ...widget.records.map((r) => ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline, size: 16, color: AppColors.primary),
              title: Text(r['customer_name'] as String? ?? r['user_name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
              subtitle: Text('${(r['created_at'] as String).substring(0, 10)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Text('₹${(r['amount'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            )),
            if (widget.salesmanUserId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: _raising
                      ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.upload_outlined, size: 16),
                          label: Text('Raise ₹${widget.total.toStringAsFixed(0)} on Behalf of ${widget.name}'),
                          onPressed: _raiseOnBehalf,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 10), textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALESMAN ADVANCE GROUP CARD (Advances — Paid Not Raised)
// ─────────────────────────────────────────────────────────────────────────────

class _SalesmanAdvanceGroupCard extends ConsumerStatefulWidget {
  final String salesmanName;
  final int? salesmanId;
  final List<Map<String, dynamic>> advances;
  final double total;
  final String settlementType;
  final VoidCallback onRaised;
  const _SalesmanAdvanceGroupCard({
    required this.salesmanName, required this.salesmanId,
    required this.advances, required this.total,
    required this.settlementType, required this.onRaised,
  });
  @override
  ConsumerState<_SalesmanAdvanceGroupCard> createState() => _SalesmanAdvanceGroupCardState();
}

class _SalesmanAdvanceGroupCardState extends ConsumerState<_SalesmanAdvanceGroupCard> {
  bool _raising = false;

  Future<void> _raiseOnBehalf() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Settlement on Behalf?'),
        content: Text('Raise ₹${widget.total.toStringAsFixed(0)} (${widget.advances.length} credit advance repayment${widget.advances.length == 1 ? '' : 's'}) for ${widget.salesmanName}?\n\nA settlement request will be created and can then be acknowledged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Raise'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _raising = true);
    try {
      await ref.read(dioProvider).post(Endpoints.adminRaiseSalesmanSettlement(widget.salesmanId!), data: {'settlement_type': widget.settlementType});
      widget.onRaised();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settlement raised for ${widget.salesmanName} ✅'), backgroundColor: Colors.blue));
    } catch (e, st) {
      logError('admin-raise-advance', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _raising = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.blue.shade200)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(backgroundColor: Colors.blue.shade50,
              child: Text(widget.salesmanName[0].toUpperCase(), style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold))),
          title: Text(widget.salesmanName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text('${widget.advances.length} repayment${widget.advances.length == 1 ? '' : 's'} · customer paid back', style: const TextStyle(fontSize: 11)),
          trailing: Text('₹${widget.total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue.shade700)),
          children: [
            ...widget.advances.map((a) => ListTile(
              dense: true,
              leading: const Icon(Icons.add_card_outlined, size: 16, color: Colors.blue),
              title: Text(a['user_name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
              subtitle: Text('+91 ${a['user_phone'] ?? ''}  •  ${(a['created_at'] as String).substring(0, 10)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              trailing: Text('₹${(a['amount'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            )),
            if (widget.salesmanId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: _raising
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.send_to_mobile, size: 16),
                          label: Text('Raise ₹${widget.total.toStringAsFixed(0)} on Behalf of ${widget.salesmanName}'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                          onPressed: _raiseOnBehalf,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4: WALLET ACTIVITY
// ─────────────────────────────────────────────────────────────────────────────

// Dedicated provider for Wallet Activity (no type default, supports page)
final _walletActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts  = key.split('|');
  final params = <String, String>{'limit': '50'};
  if (parts.isNotEmpty && parts[0].isNotEmpty) params['date_from'] = parts[0];
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_to']   = parts[1];
  if (parts.length > 2 && parts[2].isNotEmpty) params['customer_search'] = parts[2];
  if (parts.length > 3 && parts[3].isNotEmpty) params['type'] = parts[3];
  if (parts.length > 4 && parts[4].isNotEmpty) params['page'] = parts[4];
  final res = await ref.read(dioProvider).get(Endpoints.adminWalletAudit,
      queryParameters: params);
  return res.data as Map<String, dynamic>;
});

final _walletSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts  = key.split('|');
  final params = <String, String>{};
  if (parts.isNotEmpty && parts[0].isNotEmpty) params['date_from'] = parts[0];
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_to']   = parts[1];
  if (parts.length > 2 && parts[2].isNotEmpty) params['customer_search'] = parts[2];
  if (parts.length > 3 && parts[3].isNotEmpty) params['type'] = parts[3];
  final res = await ref.read(dioProvider).get(Endpoints.adminWalletAuditSummary,
      queryParameters: params.isEmpty ? null : params);
  return res.data as Map<String, dynamic>;
});

final _customerWalletHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts  = key.split('|');
  final userId = parts[0];
  final params = <String, String>{'limit': '200'};
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_from'] = parts[1];
  if (parts.length > 2 && parts[2].isNotEmpty) params['date_to']   = parts[2];
  final res = await ref.read(dioProvider).get(Endpoints.adminCustomerWalletHistory(int.parse(userId)),
      queryParameters: params);
  return res.data as Map<String, dynamic>;
});

class _WalletActivityTab extends ConsumerStatefulWidget {
  const _WalletActivityTab();
  @override
  ConsumerState<_WalletActivityTab> createState() => _WalletActivityTabState();
}

class _WalletActivityTabState extends ConsumerState<_WalletActivityTab> {
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _typeFilter;
  double? _minAmount;
  double? _maxAmount;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  // Pagination state
  final List<Map<String, dynamic>> _allTxns = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _total = 0;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  static const _types = [
    (key: 'topup',          label: '💵 Topup',      color: Color(0xFFE65100)),
    (key: 'order',          label: '🛒 Order',       color: Color(0xFFC62828)),
    (key: 'refund',         label: '↩️ Refund',      color: Color(0xFF00695C)),
    (key: 'cashback',       label: '🎁 Cashback',    color: Color(0xFF6A1B9A)),
    (key: 'admin',          label: '🔧 Admin',       color: Color(0xFF1565C0)),
    (key: 'adjust',         label: '⚖️ Adjustment',  color: Color(0xFFE65100)),
    (key: 'credit_advance', label: '💳 Advance',     color: Colors.indigo),
    (key: 'referral',       label: '🔗 Referral',    color: Color(0xFF6A1B9A)),
  ];

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String get _filterKey {
    final from = _dateFrom != null ? _fmt(_dateFrom!) : '';
    final to   = _dateTo   != null ? _fmt(_dateTo!)   : '';
    return '$from|$to|$_search|${_typeFilter ?? ''}';
  }

  String _pageKey(int page) => '$_filterKey|$page';

  void _resetAndLoad() {
    setState(() { _allTxns.clear(); _currentPage = 1; _hasMore = false; _total = 0; });
    ref.invalidate(_walletActivityProvider);
    ref.invalidate(_walletSummaryProvider);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _currentPage + 1;
      final data = await ref.read(_walletActivityProvider(_pageKey(next)).future);
      final txns = (data['transactions'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _allTxns.addAll(txns);
        _currentPage = next;
        _total = (data['total'] as num?)?.toInt() ?? _total;
        _hasMore = _allTxns.length < _total;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _allTxns.where((t) {
      final amt = (t['amount'] as num).toDouble();
      if (_minAmount != null && amt < _minAmount!) return false;
      if (_maxAmount != null && amt > _maxAmount!) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Watch page 1 to populate initial data
    final async = ref.watch(_walletActivityProvider(_pageKey(1)));
    async.whenData((data) {
      final txns = (data['transactions'] as List).cast<Map<String, dynamic>>();
      if (_currentPage == 1 && _allTxns.isEmpty && txns.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {
            _allTxns.addAll(txns);
            _total = (data['total'] as num?)?.toInt() ?? txns.length;
            _hasMore = _allTxns.length < _total;
          });
        });
      }
    });

    final summaryAsync = ref.watch(_walletSummaryProvider(_filterKey));
    final hasDate = _dateFrom != null || _dateTo != null;

    final filtered = _filtered;

    return Column(children: [
      // ── Filters ──────────────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: _dateFrom != null && _dateTo != null
                        ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
                        : null,
                  );
                  if (picked != null) { setState(() { _dateFrom = picked.start; _dateTo = picked.end; }); _resetAndLoad(); }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasDate ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hasDate ? AppColors.primary : Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_outlined, size: 15, color: hasDate ? AppColors.primary : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      hasDate ? '${_dateFrom != null ? _fmt(_dateFrom!) : '…'} → ${_dateTo != null ? _fmt(_dateTo!) : '…'}' : 'All dates',
                      style: TextStyle(fontSize: 12, color: hasDate ? AppColors.primary : Colors.grey),
                    )),
                    if (hasDate) GestureDetector(
                      onTap: () { setState(() { _dateFrom = null; _dateTo = null; }); _resetAndLoad(); },
                      child: const Icon(Icons.close, size: 14, color: Colors.grey),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Export',
              onPressed: () => _ExportSheet.show(
                context: context,
                title: 'Export Wallet Activity',
                filterFields: const ['dateRange', 'customer'],
                fetchFn: (params) async {
                  params['limit'] = '1000';
                  if (_typeFilter != null) params['type'] = _typeFilter!;
                  final res = await ref.read(dioProvider).get(Endpoints.adminWalletAudit, queryParameters: params);
                  return (res.data['transactions'] as List).cast<Map<String, dynamic>>();
                },
                pdfFn: (ctx, records, dateLabel) => PdfService.shareAdminDirectTransactionsReport(
                  context: ctx, transactions: records,
                  title: 'Wallet Activity${_typeFilter != null ? ' — $_typeFilter' : ''}$dateLabel'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Customer search
          TextField(
            controller: _searchCtrl,
            onChanged: (v) {
                setState(() => _search = v.trim());
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 400), _resetAndLoad);
              },
            decoration: InputDecoration(
              hintText: 'Search by customer name or phone…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); _resetAndLoad(); })
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          const SizedBox(height: 6),
          // Amount range filters
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minCtrl,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _minAmount = double.tryParse(v)),
                decoration: InputDecoration(
                  hintText: 'Min ₹',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  prefixText: '₹ ',
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: Colors.grey))),
            Expanded(
              child: TextField(
                controller: _maxCtrl,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _maxAmount = double.tryParse(v)),
                decoration: InputDecoration(
                  hintText: 'Max ₹',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  prefixText: '₹ ',
                ),
              ),
            ),
          ]),
        ]),
      ),

      // ── Type chips — wrap layout so all chips visible ────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ImprovedChip(label: 'All types', selected: _typeFilter == null, color: Colors.grey,
                onTap: () { setState(() => _typeFilter = null); _resetAndLoad(); }),
            _ImprovedChip(label: '+ Credit', selected: _typeFilter == 'credit', color: AppColors.primary,
                onTap: () { setState(() => _typeFilter = _typeFilter == 'credit' ? null : 'credit'); _resetAndLoad(); }),
            _ImprovedChip(label: '- Debit', selected: _typeFilter == 'debit', color: Colors.red,
                onTap: () { setState(() => _typeFilter = _typeFilter == 'debit' ? null : 'debit'); _resetAndLoad(); }),
            ..._types.map((t) => _ImprovedChip(
              label: t.label,
              selected: _typeFilter == t.key,
              color: t.color,
              onTap: () { setState(() => _typeFilter = _typeFilter == t.key ? null : t.key); _resetAndLoad(); },
            )),
          ],
        ),
      ),
      const Divider(height: 1),

      // ── Expandable analytics summary ──────────────────────────────────────
      _WalletAnalyticsCard(summaryAsync: summaryAsync),

      // ── Transaction list ──────────────────────────────────────────────────
      Expanded(
        child: async.when(
          loading: () => _allTxns.isEmpty ? const Center(child: CircularProgressIndicator()) : _buildList(context, filtered),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (_) => _buildList(context, filtered),
        ),
      ),
    ]);
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> txns) {
    if (txns.isEmpty && _allTxns.isEmpty) {
      return const Center(child: Text('No transactions found', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: () async => _resetAndLoad(),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        ...txns.map((t) => _WalletActivityCard(
          txn: t,
          onTap: () => _showCustomerSheet(context, t),
        )),
        if (_hasMore || _loadingMore) ...[
          const SizedBox(height: 8),
          _loadingMore
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ))
              : OutlinedButton.icon(
                  icon: const Icon(Icons.expand_more, size: 16),
                  label: Text('Load more (${_total - _allTxns.length} remaining)'),
                  onPressed: _loadMore,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                  ),
                ),
        ],
        if (!_hasMore && _allTxns.length > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(child: Text('${_allTxns.length} records shown',
                style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ),
      ]),
    );
  }

  void _showCustomerSheet(BuildContext context, Map<String, dynamic> txn) {
    final userId  = txn['user_id'] as int;
    final name    = txn['customer_name'] as String? ?? txn['user_name'] as String? ?? 'Customer';
    final phone   = txn['customer_phone'] as String? ?? txn['user_phone'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CustomerWalletSheet(userId: userId, name: name, phone: phone),
    );
  }
}

// ── Improved type chip ────────────────────────────────────────────────────────

class _ImprovedChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ImprovedChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? color : color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (selected) ...[
          Icon(Icons.check, size: 12, color: Colors.white),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : color,
        )),
      ]),
    ),
  );
}

// ── Analytics card (expandable) ───────────────────────────────────────────────

class _WalletAnalyticsCard extends StatefulWidget {
  final AsyncValue<Map<String, dynamic>> summaryAsync;
  const _WalletAnalyticsCard({required this.summaryAsync});
  @override
  State<_WalletAnalyticsCard> createState() => _WalletAnalyticsCardState();
}

class _WalletAnalyticsCardState extends State<_WalletAnalyticsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return widget.summaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final summary = data['summary'] as Map<String, dynamic>? ?? {};
        final byType  = (data['by_type'] as List? ?? []).cast<Map<String, dynamic>>();

        return GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Totals row
              Row(children: [
                Expanded(child: _AnalyticsPill('${(summary['total_count'] as num?)?.toInt() ?? 0}', 'Records', Colors.indigo)),
                const SizedBox(width: 6),
                Expanded(child: _AnalyticsPill('₹${(summary['total_credited'] as num?)?.toStringAsFixed(0) ?? '0'}', 'Credited', AppColors.primary)),
                const SizedBox(width: 6),
                Expanded(child: _AnalyticsPill('₹${(summary['total_debited'] as num?)?.toStringAsFixed(0) ?? '0'}', 'Debited', Colors.red)),
                const SizedBox(width: 6),
                Expanded(child: _AnalyticsPill('${(summary['unique_customers'] as num?)?.toInt() ?? 0}', 'Customers', Colors.orange)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
              ]),
              // Per-type breakdown
              if (_expanded && byType.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...byType.map((b) {
                  final colorHex = b['color'] as String? ?? '#607D8B';
                  Color c = Colors.blueGrey;
                  try { c = Color(int.parse(colorHex.replaceFirst('#', '0xFF'))); } catch (_) {}
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(b['label'] as String? ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
                      ),
                      const Spacer(),
                      Text('${b['count']} txns', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(width: 12),
                      Text('₹${(b['total'] as num).toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
                    ]),
                  );
                }),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _AnalyticsPill extends StatelessWidget {
  final String value, label;
  final Color color;
  const _AnalyticsPill(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
    Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
  ]);
}

// ── Customer wallet drill-down sheet ──────────────────────────────────────────

class _CustomerWalletSheet extends ConsumerStatefulWidget {
  final int userId;
  final String name;
  final String phone;
  const _CustomerWalletSheet({required this.userId, required this.name, required this.phone});
  @override
  ConsumerState<_CustomerWalletSheet> createState() => _CustomerWalletSheetState();
}

class _CustomerWalletSheetState extends ConsumerState<_CustomerWalletSheet> {
  DateTime? _dateFrom;
  DateTime? _dateTo;

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  String get _key => '${widget.userId}|${_dateFrom != null ? _fmt(_dateFrom!) : ''}|${_dateTo != null ? _fmt(_dateTo!) : ''}';

  @override
  Widget build(BuildContext context) {
    final async   = ref.watch(_customerWalletHistoryProvider(_key));
    final hasDate = _dateFrom != null || _dateTo != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(children: [
        // Handle + header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(backgroundColor: const Color(0xFFEAF2EA),
                  child: Text(widget.name[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('+91 ${widget.phone}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
              // Download PDF
              async.when(
                data: (d) {
                  final txns    = (d['transactions'] as List? ?? []).cast<Map<String, dynamic>>();
                  final balance = (d['customer']?['wallet_balance'] as num?)?.toDouble() ?? 0.0;
                  return IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Download Statement',
                    onPressed: () {
                      final user = AppUser.fromJson(d['customer'] as Map<String, dynamic>? ?? {'id': widget.userId, 'name': widget.name, 'phone': widget.phone, 'role': 'customer', 'wallet_balance': balance});
                      final wTxns = txns.map((t) => WalletTransaction.fromJson(t)).toList();
                      PdfService.shareWalletStatement(context: context, user: user, balance: balance, transactions: wTxns);
                    },
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ]),
            const SizedBox(height: 8),
            // Date range filter inside sheet
            GestureDetector(
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: _dateFrom != null && _dateTo != null
                      ? DateTimeRange(start: _dateFrom!, end: _dateTo!) : null,
                );
                if (picked != null) setState(() { _dateFrom = picked.start; _dateTo = picked.end; });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: hasDate ? const Color(0xFFEAF2EA) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: hasDate ? AppColors.primary : Colors.grey.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.date_range_outlined, size: 14, color: hasDate ? AppColors.primary : Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    hasDate ? '${_dateFrom != null ? _fmt(_dateFrom!) : '…'} → ${_dateTo != null ? _fmt(_dateTo!) : '…'}' : 'All dates',
                    style: TextStyle(fontSize: 12, color: hasDate ? AppColors.primary : Colors.grey),
                  )),
                  if (hasDate) GestureDetector(
                    onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                    child: const Icon(Icons.close, size: 13, color: Colors.grey),
                  ),
                ]),
              ),
            ),
          ]),
        ),

        // Transaction list
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(friendlyError(e))),
            data: (d) {
              final txns    = (d['transactions'] as List? ?? []).cast<Map<String, dynamic>>();
              final balance = (d['customer']?['wallet_balance'] as num?)?.toDouble() ?? 0.0;

              if (txns.isEmpty) {
                return const Center(child: Text('No transactions', style: TextStyle(color: Colors.grey)));
              }

              return ListView(controller: scrollCtrl, padding: const EdgeInsets.all(12), children: [
                // Balance chip
                Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: balance < 0 ? Colors.red.shade50 : const Color(0xFFEAF2EA),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: balance < 0 ? Colors.red.shade300 : AppColors.primary),
                  ),
                  child: Text('Balance: ₹${balance.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                          color: balance < 0 ? Colors.red : AppColors.primary)),
                )),
                const SizedBox(height: 12),
                ...txns.map((t) => _WalletActivityCard(txn: t, onTap: null)),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ── Wallet transaction card ────────────────────────────────────────────────────

class _WalletActivityCard extends StatelessWidget {
  final Map<String, dynamic> txn;
  final VoidCallback? onTap;
  const _WalletActivityCard({required this.txn, this.onTap});

  static ({Color color, IconData icon, String label}) _style(Map<String, dynamic> t) {
    final type = t['type'] as String? ?? '';
    final ref  = t['reference_type'] as String? ?? '';
    final desc = t['description'] as String? ?? '';
    if (type == 'discount' && ref == 'reward')   return (color: const Color(0xFF6A1B9A), icon: Icons.card_giftcard, label: 'Cashback');
    if (ref == 'admin')                           return (color: const Color(0xFF1565C0), icon: Icons.admin_panel_settings_outlined, label: 'Admin');
    if (type == 'credit' && ref == 'topup' && desc.startsWith('Credit advance')) return (color: Colors.indigo, icon: Icons.add_card_outlined, label: 'Advance');
    if (type == 'credit' && ref == 'topup')       return (color: const Color(0xFFE65100), icon: Icons.payments_outlined, label: 'Topup');
    if (type == 'debit' && ref == 'order')        return (color: const Color(0xFFC62828), icon: Icons.shopping_cart_outlined, label: 'Order');
    if (type == 'refund')                         return (color: const Color(0xFF00695C), icon: Icons.undo, label: 'Refund');
    if (type == 'adjustment')                     return (color: const Color(0xFFE65100), icon: Icons.scale_outlined, label: 'Adjustment');
    if (ref == 'referral_signup' || ref == 'referral_bonus') return (color: const Color(0xFF6A1B9A), icon: Icons.people_outline, label: 'Referral');
    final isCredit = ['credit', 'refund', 'discount'].contains(type);
    return (color: isCredit ? AppColors.primary : Colors.red, icon: isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline, label: isCredit ? 'Credit' : 'Debit');
  }

  @override
  Widget build(BuildContext context) {
    final s        = _style(txn);
    final amount   = (txn['amount'] as num).toDouble();
    final isCredit = ['credit', 'refund', 'discount'].contains(txn['type'] as String? ?? '');
    final name     = txn['customer_name'] as String? ?? txn['user_name'] as String? ?? '';
    final phone    = txn['customer_phone'] as String? ?? txn['user_phone'] as String? ?? '';
    final desc     = txn['description'] as String?;
    final date     = (txn['created_at'] as String).substring(0, 16).replaceAll('T', ' ');
    // Who handled this transaction
    final collectorName  = txn['collector_name'] as String?;
    final approvedByName = txn['approved_by_name'] as String?;
    final approvedByRole = txn['approved_by_role'] as String?;
    final handledBy = collectorName != null
        ? 'via Salesman: $collectorName'
        : approvedByName != null
            ? 'via ${approvedByRole == 'admin' ? 'Admin' : 'Salesman'}: $approvedByName'
            : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: s.color.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: s.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(s.icon, color: s.color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                Text('${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                        color: isCredit ? AppColors.primary : Colors.red)),
              ]),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: s.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(s.label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: s.color)),
                ),
                const SizedBox(width: 6),
                if (phone.isNotEmpty) Text('+91 $phone', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
                ],
              ]),
              if (desc != null && desc.isNotEmpty)
                Text(desc, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (handledBy != null)
                Text(handledBy, style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.w500)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(date, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text('Bal: ₹${(txn['balance_after'] as num).toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}
class _SalesmanBreakdown {
  final String name, role;
  double total = 0, outstanding = 0, received = 0;
  _SalesmanBreakdown({required this.name, required this.role});
}

class _StatChip extends StatelessWidget {
  final String label, amount;
  final Color color;
  const _StatChip(this.label, this.amount, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        if (amount.isNotEmpty) Text(amount, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader(this.title, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
  ]);
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: TextStyle(fontSize: 10, color: color)),
  );
}
