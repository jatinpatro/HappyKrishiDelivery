import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salesman Management'),
        actions: [
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
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
      error: (e, _) => Center(child: Text('Error: $e')),
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
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
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

class _CashCollectionsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(salesmanSummaryProvider);

    return data.when(
      data: (d) {
        final collected         = d['collected'] as List? ?? [];
        final pending           = d['pending'] as List? ?? [];
        final raisedSettlements = (d['raised_settlements'] as List? ?? []).cast<Map<String, dynamic>>();
        final settlements       = d['settlements'] as List? ?? [];

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(salesmanSummaryProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [

            // ── Raised settlement requests (salesman → admin) ──────────
            if (raisedSettlements.isNotEmpty) ...[
              _SecHeader('Settlement Requests', Icons.send_to_mobile, const Color(0xFF1565C0),
                  badge: '${raisedSettlements.length}'),
              const SizedBox(height: 4),
              const Text('Salesmen have raised these — acknowledge once you receive the cash.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              ...raisedSettlements.map((s) => _RaisedSettlementCard(
                settlement: s,
                onAcknowledge: () => _acknowledgeSettlement(context, ref, s),
              )),
              const SizedBox(height: 16),
            ],

            // ── Pending cash requests ──────────────────────────────────
            if (pending.isNotEmpty) ...[
              _SecHeader('Pending Cash Requests', Icons.hourglass_empty, Colors.orange,
                  badge: '${pending.length}'),
              ...pending.map((r) => _PendingRequestTile(request: r,
                  onAction: () => ref.invalidate(salesmanSummaryProvider))),
              const SizedBox(height: 16),
            ],

            // ── Unsettled collections (old flow) ───────────────────────
            if (collected.isNotEmpty) ...[
              _SecHeader('Cash to Settle to Central Account', Icons.account_balance,
                  const Color(0xFF2E7D32)),
              ...collected.map((c) => _CollectionCard(
                  summary: c,
                  onSettle: () => _showSettleDialog(context, ref, c))),
              const SizedBox(height: 16),
            ],

            // ── Settlement history ────────────────────────────────────
            _SecHeader('Settlement History', Icons.history, Colors.grey),
            settlements.isEmpty
                ? const _Empty('No settlements yet')
                : Column(children: settlements.map((s) => _HistoryTile(s: s)).toList()),
          ]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
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

  void _showSettleDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> summary) {
    final salesmanName = summary['salesman_name'] as String;
    final total = (summary['total_collected'] as num).toDouble();
    final requestIds = (summary['request_ids'] as String)
        .split(',').map(int.parse).toList();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Settle: $salesmanName'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.payments, color: Color(0xFF2E7D32)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cash received from salesman',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32))),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Text('${requestIds.length} collection(s) will be marked settled.',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, decoration: const InputDecoration(
              labelText: 'Note (optional)', hintText: 'e.g. Cash deposited to bank',
              border: OutlineInputBorder(), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final dio = ref.read(dioProvider);
              await dio.post(Endpoints.adminSalesmanSettle, data: {
                'salesman_name': salesmanName,
                'request_ids': requestIds,
                'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              });
              ref.invalidate(salesmanSummaryProvider);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('₹${total.toStringAsFixed(0)} from $salesmanName marked settled ✅'),
                  backgroundColor: const Color(0xFF2E7D32),
                ));
              }
            },
            child: const Text('Mark as Received & Settled'),
          ),
        ],
      ),
    );
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
    final date   = (settlement['created_at'] as String).substring(0, 10);
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

class _CollectionCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final VoidCallback onSettle;
  const _CollectionCard({required this.summary, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final name = summary['salesman_name'] as String;
    final total = (summary['total_collected'] as num).toDouble();
    final count = summary['request_count'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xFF2E7D32),
                child: Text(name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('$count collection(s) pending settlement',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Text('₹${total.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text('Mark ₹${total.toStringAsFixed(0)} Received — Settle'),
            onPressed: onSettle,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          )),
        ]),
      ),
    );
  }
}

class _PendingRequestTile extends ConsumerWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAction;
  const _PendingRequestTile({required this.request, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = (request['amount'] as num).toDouble();
    final collector = request['collected_by'] as String? ?? 'Unknown';
    final userName = request['user_name'] as String? ?? '';
    final date = (request['created_at'] as String).substring(0, 16);
    final id = request['id'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: Text(collector.substring(0, 1).toUpperCase(),
              style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
        ),
        title: Text('₹${amount.toStringAsFixed(0)} via $collector',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$userName  •  $date', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> s;
  const _HistoryTile({required this.s});
  @override
  Widget build(BuildContext context) {
    final name = s['salesman_name'] as String;
    final amount = (s['amount'] as num).toDouble();
    final date = (s['created_at'] as String).substring(0, 10);
    final note = s['note'] as String?;
    final by = s['settled_by_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.done_all, color: Color(0xFF2E7D32), size: 18)),
        title: Text('$name — ₹${amount.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('$date${by != null ? '  •  by $by' : ''}${note != null ? '\n$note' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }
}
