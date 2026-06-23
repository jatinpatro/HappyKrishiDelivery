import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

final topupRequestsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, status) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminTopupRequests,
      queryParameters: status == 'all' ? null : {'status': status});
  return res.data as Map<String, dynamic>;
});

class TopupRequestsScreen extends ConsumerStatefulWidget {
  const TopupRequestsScreen({super.key});
  @override
  ConsumerState<TopupRequestsScreen> createState() => _TopupRequestsScreenState();
}

class _TopupRequestsScreenState extends ConsumerState<TopupRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

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

  void _invalidateAll() {
    ref.invalidate(topupRequestsProvider('pending'));
    ref.invalidate(topupRequestsProvider('approved'));
    ref.invalidate(topupRequestsProvider('rejected'));
  }

  @override
  Widget build(BuildContext context) {
    final pendingData = ref.watch(topupRequestsProvider('pending'));
    final allData = ref.watch(topupRequestsProvider('all'));

    // Summary from any loaded response
    final summary = (allData.value?['summary'] as List? ??
        pendingData.value?['summary'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    double sumOf(String s) =>
        (summary.firstWhere((x) => x['status'] == s, orElse: () => {'total': 0})['total'] as num)
            .toDouble();
    int cntOf(String s) =>
        (summary.firstWhere((x) => x['status'] == s, orElse: () => {'count': 0})['count'] as num)
            .toInt();

    final pendingCount = cntOf('pending');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top-up Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _invalidateAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: pendingCount > 0 ? 'Pending ($pendingCount)' : 'Pending'),
            const Tab(text: 'Approved'),
            const Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: Column(children: [
        // ── Summary cards ───────────────────────────────────────────────────
        if (summary.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(children: [
              _SummaryCard('Pending',  '${cntOf('pending')}  •  ₹${sumOf('pending').toStringAsFixed(0)}',  Colors.orange),
              const SizedBox(width: 8),
              _SummaryCard('Approved', '${cntOf('approved')} •  ₹${sumOf('approved').toStringAsFixed(0)}', const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              _SummaryCard('Rejected', '${cntOf('rejected')} •  ₹${sumOf('rejected').toStringAsFixed(0)}', Colors.red),
            ]),
          ),
        const Divider(height: 1),

        // ── Tab views ───────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _TopupList(status: 'pending',  onAction: _invalidateAll),
              _TopupList(status: 'approved', onAction: _invalidateAll),
              _TopupList(status: 'rejected', onAction: _invalidateAll),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}

// ── List for a specific status ────────────────────────────────────────────────

class _TopupList extends ConsumerWidget {
  final String status;
  final VoidCallback onAction;
  const _TopupList({required this.status, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(topupRequestsProvider(status));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (d) {
        final list = (d['requests'] as List).cast<Map<String, dynamic>>();
        if (list.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No $status requests',
                  style: const TextStyle(color: Colors.grey, fontSize: 16)),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(topupRequestsProvider(status)),
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: list.length,
            itemBuilder: (_, i) => _RequestTile(
                request: list[i], onAction: onAction),
          ),
        );
      },
    );
  }
}

// ── Request tile ──────────────────────────────────────────────────────────────

class _RequestTile extends ConsumerWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAction;
  const _RequestTile({required this.request, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status    = request['status'] as String? ?? 'pending';
    final amount    = (request['amount'] as num).toDouble();
    final createdAt = (request['created_at'] as String).substring(0, 16);
    final resolvedAt = request['resolved_at'] as String?;
    final method    = request['payment_method'] as String? ?? 'cash';
    final txnRef    = request['transaction_ref'] as String?;
    final collector = request['collected_by'] as String?;
    final adminNote = request['admin_note'] as String?;
    final isPending = status == 'pending';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved': statusColor = const Color(0xFF2E7D32); statusIcon = Icons.check_circle;
      case 'rejected': statusColor = Colors.red; statusIcon = Icons.cancel;
      default:         statusColor = Colors.orange; statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8F5E9),
              child: Text(
                (request['user_name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(request['user_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('+91 ${request['user_phone'] ?? ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 11, color: statusColor),
                  const SizedBox(width: 3),
                  Text(status.toUpperCase(),
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.bold, color: statusColor)),
                ]),
              ),
            ]),
          ]),
          const SizedBox(height: 10),

          // Details row
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Tag(method == 'upi' ? '💳 UPI' : '💵 Cash',
                method == 'upi' ? Colors.purple : Colors.blue),
            if (txnRef != null && txnRef.isNotEmpty)
              _Tag('UTR: $txnRef', Colors.grey),
            if (collector != null && collector.isNotEmpty)
              _Tag('via $collector', Colors.teal),
            _Tag('📅 $createdAt', Colors.grey),
            if (resolvedAt != null)
              _Tag('✅ ${resolvedAt.substring(0, 16)}', statusColor),
          ]),

          if (adminNote != null && adminNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(adminNote,
                    style: const TextStyle(fontSize: 12, color: Colors.grey))),
              ]),
            ),
          ],

          // Actions — only for pending
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () => _reject(context, ref),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () => _approve(context, ref, amount),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _approve(BuildContext ctx, WidgetRef ref, double amount) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Approve Top-up?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Credit ₹${amount.toStringAsFixed(0)} to ${request['user_name']}?'),
          const SizedBox(height: 12),
          TextField(controller: noteCtrl,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Cash received',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await ref.read(dioProvider).post(
        Endpoints.adminApproveTopup(request['id'] as int),
        data: {'note': noteCtrl.text.isEmpty ? null : noteCtrl.text},
      );
      onAction();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(0)} credited ✅'),
          backgroundColor: const Color(0xFF2E7D32),
        ));
      }
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject(BuildContext ctx, WidgetRef ref) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Reject Request?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Reject ₹${(request['amount'] as num).toStringAsFixed(0)} from ${request['user_name']}?'),
          const SizedBox(height: 12),
          TextField(controller: noteCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await ref.read(dioProvider).post(
        Endpoints.adminRejectTopup(request['id'] as int),
        data: {'note': noteCtrl.text.isEmpty ? null : noteCtrl.text},
      );
      onAction();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Request rejected')));
      }
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25))),
    child: Text(label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
  );
}
