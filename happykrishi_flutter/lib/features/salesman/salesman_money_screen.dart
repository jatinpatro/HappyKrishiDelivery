import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _smPendingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.salesmanPendingCollections);
  return res.data as Map<String, dynamic>;
});

final _smApprovedProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.salesmanApprovedCollections);
  return res.data as Map<String, dynamic>;
});

final _smAdvancesProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final params = <String, String>{};
  if (parts.isNotEmpty && parts[0].isNotEmpty) params['date_from'] = parts[0];
  if (parts.length > 1 && parts[1].isNotEmpty) params['date_to']   = parts[1];
  final res = await ref.read(dioProvider).get(Endpoints.salesmanCreditAdvances,
      queryParameters: params.isNotEmpty ? params : null);
  return res.data as Map<String, dynamic>;
});

// ── Main Screen ───────────────────────────────────────────────────────────────

class SalesmanMoneyScreen extends ConsumerStatefulWidget {
  const SalesmanMoneyScreen({super.key});
  @override
  ConsumerState<SalesmanMoneyScreen> createState() => _SalesmanMoneyScreenState();
}

class _SalesmanMoneyScreenState extends ConsumerState<SalesmanMoneyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  void _refresh() {
    ref.invalidate(_smPendingProvider);
    ref.invalidate(_smApprovedProvider);
    ref.invalidate(_smAdvancesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(_smPendingProvider).value?['count'] as int? ?? 0;
    final now = DateTime.now();
    final defaultKey = '${now.year}-${now.month.toString().padLeft(2,'0')}-01|${now.year}-${now.month.toString().padLeft(2,'0')}-${DateTime(now.year, now.month+1, 0).day.toString().padLeft(2,'0')}';
    final unpaidAdvances = (ref.watch(_smAdvancesProvider(defaultKey)).value?['advances'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((a) => (a['payment_received'] as int? ?? 0) == 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/salesman')),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: pendingCount > 0 ? 'Collections ($pendingCount)' : 'Collections'),
            Tab(text: unpaidAdvances > 0 ? 'Advances ($unpaidAdvances)' : 'Advances'),
            const Tab(text: 'Settlements'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _CollectionsTab(onRefresh: _refresh),
        _AdvancesTab(onRefresh: _refresh),
        _SettlementsTab(onRefresh: _refresh),
      ]),
    );
  }
}

// ── Tab 1: Collections ────────────────────────────────────────────────────────

class _CollectionsTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _CollectionsTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_smPendingProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (data) {
        final items = (data['pending'] as List? ?? []).cast<Map<String, dynamic>>();
        final total = (data['total_pending'] as num?)?.toDouble() ?? 0;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_smPendingProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.pending_actions, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${items.length} pending approval',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('Total: ₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ]),
            ),
            if (items.isEmpty) ...[
              const SizedBox(height: 48),
              const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 8),
                Text('No pending collections', style: TextStyle(color: Colors.grey, fontSize: 15)),
              ])),
            ] else ...[
              const SizedBox(height: 16),
              const Text('Approve to credit customer wallet immediately',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              ...items.map((r) => _PendingCollectionCard(request: r, onApproved: () {
                ref.invalidate(_smPendingProvider);
                ref.invalidate(_smApprovedProvider);
              })),
            ],
          ]),
        );
      },
    );
  }
}

class _PendingCollectionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApproved;
  const _PendingCollectionCard({required this.request, required this.onApproved});
  @override
  ConsumerState<_PendingCollectionCard> createState() => _PendingCollectionCardState();
}

class _PendingCollectionCardState extends ConsumerState<_PendingCollectionCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final amount = (widget.request['amount'] as num).toDouble();
    final name   = widget.request['customer_name'] as String? ?? 'customer';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Approve Collection?'),
      content: Text('Credit ₹${amount.toStringAsFixed(0)} to $name\'s wallet?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Approve & Credit')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.salesmanApproveCollection(widget.request['id'] as int));
      widget.onApproved();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} credited to $name ✅'),
          backgroundColor: const Color(0xFF2E7D32)));
    } catch (e, st) {
      logError('sm-collection', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final amount = (r['amount'] as num).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.orange, width: 0.5)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(backgroundColor: Colors.orange.shade50,
              child: Text((r['customer_name'] as String? ?? 'C')[0].toUpperCase(),
                  style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['customer_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('+91 ${r['customer_phone'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text((r['created_at'] as String).substring(0, 10), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32))),
            const SizedBox(height: 4),
            _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : ElevatedButton(
                    onPressed: _approve,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        textStyle: const TextStyle(fontSize: 11)),
                    child: const Text('Approve')),
          ]),
        ]),
      ),
    );
  }
}

// ── Tab 2: Credit Advances ────────────────────────────────────────────────────

class _AdvancesTab extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const _AdvancesTab({required this.onRefresh});
  @override
  ConsumerState<_AdvancesTab> createState() => _AdvancesTabState();
}

class _AdvancesTabState extends ConsumerState<_AdvancesTab> {
  DateTime? _dateFrom;
  DateTime? _dateTo;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String get _key {
    final now = DateTime.now();
    final from = _dateFrom ?? DateTime(now.year, now.month, 1);
    final to   = _dateTo   ?? DateTime(now.year, now.month + 1, 0);
    return '${_fmt(from)}|${_fmt(to)}';
  }

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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_smAdvancesProvider(_key));
    final hasDate = _dateFrom != null || _dateTo != null;

    return Column(children: [
      // ── Date filter bar ─────────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: hasDate ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hasDate ? const Color(0xFF2E7D32) : Colors.grey.shade300),
            ),
            child: Row(children: [
              Icon(Icons.date_range_outlined, size: 16,
                  color: hasDate ? const Color(0xFF2E7D32) : Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(
                hasDate
                    ? '${_dateFrom != null ? _fmt(_dateFrom!) : '…'}  →  ${_dateTo != null ? _fmt(_dateTo!) : '…'}'
                    : 'Filter by date (this month by default)',
                style: TextStyle(fontSize: 13, color: hasDate ? const Color(0xFF2E7D32) : Colors.grey),
              )),
              if (hasDate)
                GestureDetector(
                  onTap: () => setState(() { _dateFrom = null; _dateTo = null; }),
                  child: const Icon(Icons.close, size: 16, color: Colors.grey),
                ),
            ]),
          ),
        ),
      ),
      const Divider(height: 1),

      // ── List ────────────────────────────────────────────────────────────────
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (data) {
            final advances = (data['advances'] as List? ?? []).cast<Map<String, dynamic>>();
            final totalGiven       = (data['totalGiven'] as num?)?.toDouble() ?? 0;
            final totalOutstanding = (data['totalOutstanding'] as num?)?.toDouble() ?? 0;
            final totalReceived    = (data['totalReceived'] as num?)?.toDouble() ?? 0;
            final unpaid = advances.where((a) => (a['payment_received'] as int? ?? 0) == 0).toList();
            final paidNotRaised = advances.where((a) =>
                (a['payment_received'] as int? ?? 0) == 1 &&
                (a['paid_by_role'] as String?) == 'salesman' &&
                a['settlement_id'] == null).toList();
            final settledWithAdmin = advances.where((a) =>
                (a['payment_received'] as int? ?? 0) == 1 &&
                ((a['paid_by_role'] as String?) == 'admin' ||
                 a['settlement_id'] != null)).toList();

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(_smAdvancesProvider(_key)),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                // ── Analytics summary ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Credit Advance Summary',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _StatBox('Total Given', '₹${totalGiven.toStringAsFixed(0)}', Colors.indigo),
                      const SizedBox(width: 8),
                      _StatBox('Outstanding', '₹${totalOutstanding.toStringAsFixed(0)}', Colors.orange),
                      const SizedBox(width: 8),
                      _StatBox('Received', '₹${totalReceived.toStringAsFixed(0)}', Colors.green),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),

                if (advances.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No credit advances in this period', style: TextStyle(color: Colors.grey)),
                  ))
                else ...[
                  if (unpaid.isNotEmpty) ...[
                    _SectionHeader('🟠 Awaiting Customer Payment (${unpaid.length})', Colors.orange),
                    const SizedBox(height: 8),
                    ...unpaid.map((a) => _AdvanceCard(advance: a, onAction: () {
                      ref.invalidate(_smAdvancesProvider(_key));
                      widget.onRefresh();
                    })),
                    const SizedBox(height: 16),
                  ],
                  if (paidNotRaised.isNotEmpty) ...[
                    _SectionHeader('🔵 Customer Paid — Raise with Admin (${paidNotRaised.length})', Colors.blue),
                    const SizedBox(height: 8),
                    ...paidNotRaised.map((a) => _AdvanceCard(advance: a, onAction: null)),
                    const SizedBox(height: 16),
                  ],
                  if (settledWithAdmin.isNotEmpty) ...[
                    _SectionHeader('🟢 Settled with Admin (${settledWithAdmin.length})', Colors.green),
                    const SizedBox(height: 8),
                    ...settledWithAdmin.map((a) => _AdvanceCard(advance: a, onAction: null)),
                  ],
                ],
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
    ]),
  ));
}

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
      await ref.read(dioProvider).post(Endpoints.salesmanMarkCreditPaid(widget.advance['id'] as int));
      widget.onAction?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} marked paid ✅'), backgroundColor: Colors.indigo));
    } catch (e, st) {
      logError('sm-advance', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final a    = widget.advance;
    final paid = (a['payment_received'] as int? ?? 0) == 1;
    final amount = (a['amount'] as num).toDouble();
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
            if (a['admin_note'] != null)
              Text(a['admin_note'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text((a['created_at'] as String).substring(0, 10), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: paid ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(paid ? 'Paid' : 'Pending',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: paid ? Colors.green : Colors.orange)),
            ),
            if (!paid && widget.onAction != null) ...[
              const SizedBox(height: 4),
              _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _markPaid,
                      style: TextButton.styleFrom(minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
                      child: const Text('Mark Paid', style: TextStyle(fontSize: 11, color: Colors.indigo))),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ── Tab 3: Settlements ────────────────────────────────────────────────────────

class _SettlementsTab extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const _SettlementsTab({required this.onRefresh});
  @override
  ConsumerState<_SettlementsTab> createState() => _SettlementsTabState();
}

class _SettlementsTabState extends ConsumerState<_SettlementsTab>
    with SingleTickerProviderStateMixin {
  late final _inner = TabController(length: 2, vsync: this);
  final Set<int> _selected = {};
  bool _raising = false;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() { _inner.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _raiseSettlement(List<Map<String, dynamic>> unsettled) async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one collection to raise')));
      return;
    }
    final total = unsettled
        .where((r) => _selected.contains(r['id'] as int))
        .fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Raise Settlement?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Raise ₹${total.toStringAsFixed(0)} (${_selected.length} collection${_selected.length == 1 ? '' : 's'}) to admin?'),
        const SizedBox(height: 10),
        TextField(controller: _noteCtrl, decoration: const InputDecoration(
            labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Raise')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _raising = true);
    try {
      await ref.read(dioProvider).post(Endpoints.salesmanRaiseSettlement, data: {
        'request_ids': _selected.toList(),
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });
      setState(() => _selected.clear());
      ref.invalidate(_smApprovedProvider);
      _noteCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${total.toStringAsFixed(0)} raised to admin ✅'),
          backgroundColor: const Color(0xFF2E7D32)));
    } catch (e, st) {
      logError('sm-settle', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally { if (mounted) setState(() => _raising = false); }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_smApprovedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (data) {
        final unsettled    = (data['unsettled'] as List? ?? []).cast<Map<String, dynamic>>();
        final settlements  = (data['settlements'] as List? ?? []).cast<Map<String, dynamic>>();
        final totalUnsettled = (data['unsettled_total'] as num?)?.toDouble() ?? 0;
        final selectedTotal = unsettled
            .where((r) => _selected.contains(r['id'] as int))
            .fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());

        return Column(children: [
          // Summary bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFE8F5E9),
            child: Row(children: [
              _Chip('${unsettled.length} to settle', '₹${totalUnsettled.toStringAsFixed(0)}', Colors.orange),
              const SizedBox(width: 8),
              _Chip('${settlements.length} raised', '', Colors.blue),
            ]),
          ),
          TabBar(
            controller: _inner,
            labelColor: Colors.orange.shade700,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.orange.shade700,
            tabs: [
              Tab(text: unsettled.isNotEmpty ? 'Raise (${unsettled.length})' : 'Raise'),
              Tab(text: settlements.isNotEmpty ? 'Status (${settlements.length})' : 'Status'),
            ],
          ),
          Expanded(child: TabBarView(controller: _inner, children: [
            // Raise tab
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(_smApprovedProvider),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (unsettled.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No unsettled collections', style: TextStyle(color: Colors.grey)),
                  ))
                else ...[
                  Row(children: [
                    Expanded(child: Text(
                      _selected.isEmpty
                          ? 'Select collections to raise'
                          : '${_selected.length} selected · ₹${selectedTotal.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 13,
                          color: _selected.isEmpty ? Colors.grey : const Color(0xFF2E7D32),
                          fontWeight: _selected.isEmpty ? FontWeight.normal : FontWeight.bold),
                    )),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_selected.length == unsettled.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(unsettled.map((r) => r['id'] as int));
                        }
                      }),
                      child: Text(_selected.length == unsettled.length ? 'Deselect all' : 'Select all',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                  ...unsettled.map((r) {
                    final id = r['id'] as int;
                    final isCreditAdvance = r['payment_method'] == 'credit_advance';
                    return CheckboxListTile(
                      value: _selected.contains(id),
                      onChanged: (v) => setState(() { v == true ? _selected.add(id) : _selected.remove(id); }),
                      title: Row(children: [
                        Expanded(child: Text(r['customer_name'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (isCreditAdvance)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: Text('Credit Advance',
                                style: TextStyle(fontSize: 9, color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      subtitle: Text('+91 ${r['customer_phone'] ?? ''} · ${(r['created_at'] as String).substring(0, 10)}',
                          style: const TextStyle(fontSize: 12)),
                      secondary: Text('₹${(r['amount'] as num).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32), fontSize: 15)),
                      activeColor: const Color(0xFF2E7D32),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _raising
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.send_outlined, size: 16),
                            label: Text(_selected.isEmpty
                                ? 'Select collections above'
                                : 'Raise ₹${selectedTotal.toStringAsFixed(0)} to Admin'),
                            onPressed: _selected.isEmpty ? null : () => _raiseSettlement(unsettled),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                  ),
                ],
              ]),
            ),
            // Status tab
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(_smApprovedProvider),
              child: settlements.isEmpty
                  ? const Center(child: Text('No settlements yet', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: settlements.length,
                      itemBuilder: (_, i) {
                        final s = settlements[i];
                        final acked = s['settled_by'] != null;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: acked ? Colors.green.shade200 : Colors.blue.shade200)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: acked ? Colors.green.shade50 : Colors.blue.shade50,
                              child: Icon(acked ? Icons.check_circle : Icons.pending_outlined,
                                  color: acked ? Colors.green : Colors.blue, size: 20),
                            ),
                            title: Text('₹${(s['amount'] as num).toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text(
                              acked
                                  ? 'Acknowledged by ${s['acknowledged_by_name'] ?? 'admin'}'
                                  : 'Pending admin acknowledgement',
                              style: TextStyle(fontSize: 12, color: acked ? Colors.green : Colors.blue),
                            ),
                            trailing: Text((s['created_at'] as String).substring(0, 10),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        );
                      },
                    ),
            ),
          ])),
        ]);
      },
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label, amount;
  final Color color;
  const _Chip(this.label, this.amount, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        if (amount.isNotEmpty)
          Text(amount, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
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
    Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color))),
  ]);
}
