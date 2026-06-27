import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/filter_form.dart';
import '../../core/widgets/active_filter.dart';

final rewardRulesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminRewardsRules);
  return List<Map<String, dynamic>>.from(res.data['rules']);
});

final rewardPayoutsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, month) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminRewardsPayouts,
      queryParameters: month.isNotEmpty ? {'month': month} : null);
  return res.data as Map<String, dynamic>;
});

final productsAndCategoriesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminRewardsProductsCategories);
  return res.data as Map<String, dynamic>;
});

const _payoutsFilterConfig = FilterFormConfig(
  title: 'Filter Payouts',
  showDateRange: false,
  showTextSearch: true,
  textSearchHint: 'Customer name, product, rule…',
  dynamicFields: [
    FilterDefinition(field: 'customer_name', label: 'Customer',     type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'target_name',   label: 'Product/Rule', type: FilterType.text,   serverSide: false),
    FilterDefinition(field: 'month',         label: 'Month',        type: FilterType.text,   serverSide: false),
  ],
);

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});
  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _selectedPayoutMonth = '';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Rewards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(rewardRulesProvider);
              ref.invalidate(rewardPayoutsProvider(_selectedPayoutMonth));
            },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'Calculate Rewards Now',
            onPressed: () => _showCalculateDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.rule, size: 16), text: 'Cashback Rules'),
            Tab(icon: Icon(Icons.history, size: 16), text: 'Payout History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _RulesTab(),
          _PayoutsTab(
            selectedMonth: _selectedPayoutMonth,
            onMonthChanged: (m) => setState(() => _selectedPayoutMonth = m),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRuleDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Rule'),
      ),
    );
  }

  void _showCalculateDialog(BuildContext context) {
    final monthCtrl = TextEditingController(
      text: () {
        final now = DateTime.now();
        return '${now.year}-${now.month.toString().padLeft(2, '0')}';
      }(),
    );
    bool calculating = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) => AlertDialog(
          title: const Text('Calculate Rewards'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Calculates cashback for the month and creates pending payouts.\n\n'
              'Eligible customers must have wallet balance ≥ ₹100. Review and approve in the Payout History tab.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: monthCtrl,
              decoration: const InputDecoration(
                labelText: 'Month (YYYY-MM)',
                hintText: 'e.g. 2026-06',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: calculating ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: calculating
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.calculate_outlined),
              label: const Text('Calculate'),
              onPressed: calculating
                  ? null
                  : () async {
                      setDs(() => calculating = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final dio = ref.read(dioProvider);
                        final res = await dio.post(Endpoints.adminRewardsCalculate,
                            data: {'month': monthCtrl.text.trim()});
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        ref.invalidate(rewardPayoutsProvider(_selectedPayoutMonth));
                        if (context.mounted) {
                          final d = res.data as Map<String, dynamic>;
                          final found    = d['newPayouts']        as int? ?? 0;
                          final total    = (d['totalCalculated']  as num?) ?? 0;
                          final skipped  = d['skipped']           as int? ?? 0;
                          final msg = found > 0
                              ? '$found new payout${found == 1 ? '' : 's'} — ₹${total.toStringAsFixed(2)} total'
                                  '${skipped > 0 ? ' ($skipped skipped)' : ''}'
                              : d['message'] as String? ?? 'No new eligible orders';
                          messenger.showSnackBar(SnackBar(
                            content: Text(msg),
                            backgroundColor: found > 0 ? const Color(0xFF2E7D32) : Colors.orange,
                            duration: const Duration(seconds: 5),
                          ));
                          if (found > 0) {
                            _tabs.animateTo(1); // jump to Payout History tab
                          }
                        }
                      } catch (e, st) {
                        logError('admin-rewards', e, st);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        messenger.showSnackBar(SnackBar(
                            content: Text(friendlyError(e)), backgroundColor: Colors.red));
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _AddRuleDialog(
        onCreated: () => ref.invalidate(rewardRulesProvider),
      ),
    );
  }
}

// ── Rules Tab ─────────────────────────────────────────────────────────────────

class _RulesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rewardRulesProvider);

    return rules.when(
      data: (list) => list.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.card_giftcard_outlined, size: 72, color: Colors.grey),
              SizedBox(height: 12),
              Text('No cashback rules yet', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 6),
              Text('Tap + to add a rule', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(rewardRulesProvider),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) => _RuleTile(rule: list[i],
                    onToggle: () => ref.invalidate(rewardRulesProvider),
                    onDelete: () => ref.invalidate(rewardRulesProvider)),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-rewards', e); return Center(child: Text(friendlyError(e))); },
    );
  }
}

class _RuleTile extends ConsumerWidget {
  final Map<String, dynamic> rule;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _RuleTile({required this.rule, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = rule['is_active'] == 1;
    final pct = (rule['cashback_percent'] as num).toDouble();
    final minQty = (rule['min_qty'] as num).toDouble();
    final minSpend = (rule['min_spend'] as num).toDouble();
    final isProduct = rule['type'] == 'product_cashback';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? const Color(0xFF2E7D32).withValues(alpha: 0.2) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Type icon
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isProduct ? Icons.inventory_2_outlined : Icons.category_outlined,
                color: isActive ? const Color(0xFF2E7D32) : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(rule['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$pct% cashback',
                      style: const TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                '${isProduct ? 'Product' : 'Category'}: ${rule['target_name']}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (minQty > 0 || minSpend > 0) ...[
                const SizedBox(height: 2),
                Row(children: [
                  if (minQty > 0) _Pill(Icons.scale_outlined, 'Min ${minQty.toStringAsFixed(1)} kg'),
                  if (minQty > 0 && minSpend > 0) const SizedBox(width: 6),
                  if (minSpend > 0) _Pill(Icons.currency_rupee, 'Min ₹${minSpend.toStringAsFixed(0)}'),
                ]),
              ],
            ])),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // Active toggle
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: isActive,
                activeTrackColor: const Color(0xFF2E7D32),
                onChanged: (_) async {
                  final dio = ref.read(dioProvider);
                  await dio.put(Endpoints.adminRewardsRule(rule['id'] as int),
                      data: {'is_active': !isActive});
                  onToggle();
                },
              ),
            ),
            Text(isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                    fontSize: 12,
                    color: isActive ? const Color(0xFF2E7D32) : Colors.grey)),
            const Spacer(),
            // Duplicate
            _ActionBtn(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              color: Colors.blue.shade700,
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => _AddRuleDialog(
                  onCreated: onToggle,
                  existing: {
                    ...rule,
                    'id': null,
                    'name': 'Copy of ${rule['name']}',
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Edit
            _ActionBtn(
              icon: Icons.edit_outlined,
              label: 'Edit',
              color: const Color(0xFF2E7D32),
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => _AddRuleDialog(onCreated: onToggle, existing: rule),
              ),
            ),
            const SizedBox(width: 6),
            // Delete
            _ActionBtn(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: Colors.red,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Delete Rule?'),
                    content: Text('Delete "${rule['name']}"? This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final dio = ref.read(dioProvider);
                await dio.delete(Endpoints.adminRewardsRule(rule['id'] as int));
                onDelete();
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: Colors.grey.shade600),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ── Payouts Tab ───────────────────────────────────────────────────────────────

class _PayoutsTab extends ConsumerStatefulWidget {
  final String selectedMonth;
  final ValueChanged<String> onMonthChanged;
  const _PayoutsTab({required this.selectedMonth, required this.onMonthChanged});
  @override
  ConsumerState<_PayoutsTab> createState() => _PayoutsTabState();
}

class _PayoutsTabState extends ConsumerState<_PayoutsTab> {
  String _statusFilter = 'pending';
  final Set<int> _selectedIds = {};
  FilterFormState _filter = FilterFormState.empty;

  Future<void> _approveAll(String month) async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.adminRewardsApprove,
          data: {'approve_all_month': month});
      ref.invalidate(rewardPayoutsProvider(widget.selectedMonth));
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.data['message'] as String),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } catch (e, st) {
      logError('admin-rewards', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _approveSelected() async {
    if (_selectedIds.isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.adminRewardsApprove,
          data: {'payout_ids': _selectedIds.toList()});
      ref.invalidate(rewardPayoutsProvider(widget.selectedMonth));
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.data['message'] as String),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } catch (e, st) {
      logError('admin-rewards', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _rejectSelected() async {
    if (_selectedIds.isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.adminRewardsReject,
          data: {'payout_ids': _selectedIds.toList()});
      ref.invalidate(rewardPayoutsProvider(widget.selectedMonth));
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payouts rejected')));
      }
    } catch (e, st) {
      logError('admin-rewards', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(rewardPayoutsProvider(widget.selectedMonth));

    return data.when(
      data: (d) {
        final allPayouts = (d['payouts'] as List? ?? []).cast<Map<String, dynamic>>();
        // Apply status filter, then text search + dynamic filters locally
        final localFilters = _filter.toLocalFilters();
        final searchQ = _filter.search.toLowerCase();
        final payouts = allPayouts.where((p) {
          if (_statusFilter.isNotEmpty && p['status'] != _statusFilter) return false;
          if (searchQ.isNotEmpty) {
            final hit = (p['customer_name']?.toString().toLowerCase().contains(searchQ) ?? false)
                || (p['target_name']?.toString().toLowerCase().contains(searchQ) ?? false)
                || (p['rule_name']?.toString().toLowerCase().contains(searchQ) ?? false)
                || (p['month']?.toString().contains(searchQ) ?? false);
            if (!hit) return false;
          }
          if (!matchesAllFilters(p, localFilters)) return false;
          return true;
        }).toList();
        final months = (d['months'] as List?)?.cast<String>() ?? [];
        final summary = (d['summary'] as List? ?? []).cast<Map<String, dynamic>>();
        final pendingCount = (summary.firstWhere((s) => s['status'] == 'pending', orElse: () => {'count': 0})['count'] as num).toInt();
        final pendingTotal = (summary.firstWhere((s) => s['status'] == 'pending', orElse: () => {'total': 0})['total'] as num).toDouble();

        return Column(children: [
          // Month chips
          if (months.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                _MonthChip(label: 'All', value: '', selected: widget.selectedMonth, onTap: widget.onMonthChanged),
                ...months.map((m) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _MonthChip(label: m, value: m, selected: widget.selectedMonth, onTap: (v) {
                    widget.onMonthChanged(v);
                    setState(() => _selectedIds.clear());
                  }),
                )),
              ]),
            ),

          // Status filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(children: [
              ...[('pending', 'Pending', Colors.orange),
                  ('approved', 'Approved', Color(0xFF2E7D32)),
                  ('rejected', 'Rejected', Colors.red),
                  ('', 'All', Colors.grey)]
                  .map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.$2, style: const TextStyle(fontSize: 11)),
                      selected: _statusFilter == s.$1,
                      selectedColor: s.$3.withValues(alpha: 0.15),
                      onSelected: (_) => setState(() {
                        _statusFilter = s.$1;
                        _selectedIds.clear();
                      }),
                    ),
                  )),
            ]),
          ),

          // Text search + dynamic filter bar
          FilterBar(
            config: _payoutsFilterConfig,
            state: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),

          // Pending summary + Approve All
          if (_statusFilter == 'pending' && pendingCount > 0 && widget.selectedMonth.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$pendingCount pending rewards', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Total: ₹${pendingTotal.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Approve All'),
                  onPressed: () => _approveAll(widget.selectedMonth),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white,
                      minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                ),
              ]),
            ),

          // Bulk action bar
          if (_selectedIds.isNotEmpty)
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Text('${_selectedIds.length} selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: () => setState(() => _selectedIds.clear()),
                    child: const Text('Clear', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 6),
                ElevatedButton(onPressed: _rejectSelected,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                        minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: const Text('Reject')),
                const SizedBox(width: 6),
                ElevatedButton(onPressed: _approveSelected,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white,
                        minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    child: const Text('Approve')),
              ]),
            ),

          // Payout list
          Expanded(
            child: payouts.isEmpty
                ? Center(child: Text(
                    _statusFilter == 'pending'
                        ? 'No pending rewards.\nTap ▶ to calculate for a month.'
                        : 'No payouts found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)))
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(rewardPayoutsProvider(widget.selectedMonth)),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: payouts.length,
                      itemBuilder: (_, i) {
                        final p = payouts[i];
                        final id = p['id'] as int;
                        final cashback = (p['cashback_amount'] as num).toDouble();
                        final spend = (p['spend_amount'] as num).toDouble();
                        final qty = (p['qty_purchased'] as num).toDouble();
                        final status = p['status'] as String;
                        final multiplier = (p['tier_multiplier'] as num? ?? 1.0).toDouble();
                        final tierName = p['tier_name'] as String?;
                        final pct = (p['cashback_percent'] as num).toDouble();
                        final calcStr = multiplier != 1.0
                            ? '₹${spend.toStringAsFixed(0)} × ${pct.toStringAsFixed(0)}% × ${multiplier.toStringAsFixed(1)}× = ₹${cashback.toStringAsFixed(2)}'
                            : '₹${spend.toStringAsFixed(0)} × ${pct.toStringAsFixed(0)}% = ₹${cashback.toStringAsFixed(2)}';
                        final isPending = status == 'pending';
                        final isSelected = _selectedIds.contains(id);
                        final statusColor = status == 'approved'
                            ? const Color(0xFF2E7D32)
                            : status == 'rejected' ? Colors.red : Colors.orange;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isSelected ? Colors.blue.shade50 : null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: isPending ? () => setState(() {
                              if (isSelected) _selectedIds.remove(id); else _selectedIds.add(id);
                            }) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                if (isPending)
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF2E7D32),
                                    onChanged: (_) => setState(() {
                                      if (isSelected) _selectedIds.remove(id); else _selectedIds.add(id);
                                    }),
                                  )
                                else
                                  CircleAvatar(radius: 16,
                                    backgroundColor: statusColor.withValues(alpha: 0.12),
                                    child: Icon(status == 'approved' ? Icons.check : Icons.close,
                                        color: statusColor, size: 16)),
                                const SizedBox(width: 8),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p['customer_name'] as String? ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.purple.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        '${pct.toStringAsFixed(0)}% on ${p['target_name'] ?? p['rule_name']}',
                                        style: const TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (tierName != null) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6)),
                                        child: Text(
                                          '$tierName ${multiplier.toStringAsFixed(1)}×',
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    Text(p['month'] as String? ?? '',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ]),
                                  Text('${qty.toStringAsFixed(1)} kg  •  $calcStr',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ])),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('+₹${cashback.toStringAsFixed(2)}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: statusColor)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text(status.toUpperCase(),
                                        style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.bold)),
                                  ),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-rewards', e); return Center(child: Text(friendlyError(e))); },
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label, value, selected;
  final ValueChanged<String> onTap;
  const _MonthChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label.isEmpty ? 'All' : label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black87)),
      ),
    );
  }
}

// ── Add Rule Dialog ───────────────────────────────────────────────────────────

class _AddRuleDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  final Map<String, dynamic>? existing;
  const _AddRuleDialog({required this.onCreated, this.existing});
  @override
  ConsumerState<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends ConsumerState<_AddRuleDialog> {
  late final _nameCtrl = TextEditingController(
      text: widget.existing?['name'] as String? ?? '');
  late final _pctCtrl = TextEditingController(
      text: widget.existing != null ? '${(widget.existing!['cashback_percent'] as num).toDouble()}' : '');
  late final _minQtyCtrl = TextEditingController(
      text: widget.existing != null ? '${(widget.existing!['min_qty'] as num).toDouble()}' : '0');
  late final _minSpendCtrl = TextEditingController(
      text: widget.existing != null ? '${(widget.existing!['min_spend'] as num).toDouble()}' : '0');
  late String _type = widget.existing?['type'] as String? ?? 'product_cashback';
  late int? _selectedTargetId = widget.existing?['target_id'] as int?;
  late String? _selectedTargetName = widget.existing?['target_name'] as String?;
  bool _saving = false;

  // Editing only when existing has a real id (not null = duplicate as new)
  bool get _isEditing => widget.existing != null && widget.existing!['id'] != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pctCtrl.dispose();
    _minQtyCtrl.dispose();
    _minSpendCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use watch so the dropdown rebuilds when the provider loads
    final productsAndCats = ref.watch(productsAndCategoriesProvider);

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Cashback Rule' : 'Add Cashback Rule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Rule Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'product_cashback', child: Text('Product Cashback')),
              DropdownMenuItem(value: 'category_cashback', child: Text('Category Cashback')),
            ],
            onChanged: (v) => setState(() {
              _type = v!;
              _selectedTargetId = null;
              _selectedTargetName = null;
            }),
          ),
          const SizedBox(height: 10),
          productsAndCats.when(
            data: (d) {
              final items = _type == 'product_cashback'
                  ? (d['products'] as List).cast<Map<String, dynamic>>()
                  : (d['categories'] as List).cast<Map<String, dynamic>>();
              // Reset selection if it no longer exists in the new list
              if (_selectedTargetId != null &&
                  !items.any((i) => i['id'] == _selectedTargetId)) {
                _selectedTargetId = null;
                _selectedTargetName = null;
              }
              return DropdownButtonFormField<int>(
                initialValue: _selectedTargetId,
                decoration: InputDecoration(
                  labelText: _type == 'product_cashback' ? 'Product *' : 'Category *',
                  border: const OutlineInputBorder(),
                ),
                hint: Text('Select ${_type == 'product_cashback' ? 'product' : 'category'}'),
                items: items.map((i) => DropdownMenuItem<int>(
                  value: i['id'] as int,
                  child: Text(i['name'] as String),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final match = items.firstWhere((i) => i['id'] == id);
                  setState(() {
                    _selectedTargetId = id;
                    _selectedTargetName = match['name'] as String;
                  });
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) { logError('admin-rewards', e); return Text(friendlyError(e),
                style: const TextStyle(color: Colors.red, fontSize: 12)); },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pctCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Cashback % *', suffixText: '%', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _minQtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Min Qty (kg)', border: OutlineInputBorder(), isDense: true),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _minSpendCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Min Spend (₹)', border: OutlineInputBorder(), isDense: true),
            )),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_isEditing ? 'Save Changes' : 'Create Rule'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _pctCtrl.text.isEmpty || _selectedTargetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill all required fields')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final data = {
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'target_id': _selectedTargetId,
        'target_name': _selectedTargetName,
        'cashback_percent': double.parse(_pctCtrl.text),
        'min_qty': double.parse(_minQtyCtrl.text.isEmpty ? '0' : _minQtyCtrl.text),
        'min_spend': double.parse(_minSpendCtrl.text.isEmpty ? '0' : _minSpendCtrl.text),
      };
      if (_isEditing) {
        await dio.put(Endpoints.adminRewardsRule(widget.existing!['id'] as int), data: data);
      } else {
        await dio.post(Endpoints.adminRewardsRules, data: data);
      }
      widget.onCreated();
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Rule updated ✅' : 'Cashback rule created ✅'),
                backgroundColor: Color(0xFF2E7D32)));
      }
    } catch (e, st) {
      logError('admin-rewards', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

