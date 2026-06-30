import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../admin/admin_products_screen.dart' show adminProductsProvider;
import '../../core/utils/error_handler.dart';

final customDeliveryRequestsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, status) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(
    Endpoints.customDeliveryRequests,
    queryParameters: status == 'all' ? null : {'status': status},
  );
  return List<Map<String, dynamic>>.from(res.data['requests']);
});

final whitelistedPincodesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.whitelistedPincodes);
  return List<Map<String, dynamic>>.from(res.data['pincodes']);
});

class AdminCustomDeliveryScreen extends ConsumerStatefulWidget {
  const AdminCustomDeliveryScreen({super.key});
  @override
  ConsumerState<AdminCustomDeliveryScreen> createState() =>
      _AdminCustomDeliveryScreenState();
}

class _AdminCustomDeliveryScreenState
    extends ConsumerState<AdminCustomDeliveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

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
    final pending = ref.watch(customDeliveryRequestsProvider('pending'));
    final pincodes = ref.watch(whitelistedPincodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Delivery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _invalidateAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: pending.value?.isNotEmpty == true
                ? 'Pending (${pending.value!.length})'
                : 'Pending'),
            const Tab(text: 'Approved'),
            const Tab(text: 'Rejected'),
            Tab(text: pincodes.value?.isNotEmpty == true
                ? 'Pincodes (${pincodes.value!.length})'
                : 'Pincodes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _RequestsList(status: 'pending', onAction: _invalidateAll),
          _RequestsList(status: 'approved', onAction: _invalidateAll),
          _RequestsList(status: 'rejected', onAction: _invalidateAll),
          _WhitelistedPincodesTab(onChanged: _invalidateAll),
        ],
      ),
    );
  }

  void _invalidateAll() {
    ref.invalidate(customDeliveryRequestsProvider('pending'));
    ref.invalidate(customDeliveryRequestsProvider('approved'));
    ref.invalidate(customDeliveryRequestsProvider('rejected'));
    ref.invalidate(whitelistedPincodesProvider);
  }
}

class _RequestsList extends ConsumerWidget {
  final String status;
  final VoidCallback onAction;
  const _RequestsList({required this.status, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(customDeliveryRequestsProvider(status));
    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-custom-delivery', e); return Center(child: Text(friendlyError(e))); },
      data: (list) => list.isEmpty
          ? Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.location_off_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No $status requests',
                    style: const TextStyle(color: Colors.grey, fontSize: 16)),
              ]),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(customDeliveryRequestsProvider(status)),
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: list.length,
                itemBuilder: (_, i) => _AdminRequestCard(
                  request: list[i],
                  onAction: onAction,
                ),
              ),
            ),
    );
  }
}

class _AdminRequestCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAction;
  const _AdminRequestCard({required this.request, required this.onAction});
  @override
  ConsumerState<_AdminRequestCard> createState() => _AdminRequestCardState();
}

class _AdminRequestCardState extends ConsumerState<_AdminRequestCard> {
  bool _loading = false;

  Future<void> _approve() async {
    // Show the approval sheet — it returns the submitted data or null if cancelled
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ApprovalSheet(request: widget.request),
    );
    if (result == null || !mounted) return;

    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(
        Endpoints.approveCustomDelivery(widget.request['id'] as int),
        data: result,
      );
      widget.onAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Approved & pincode whitelisted ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e, st) {
      logError('admin-custom-delivery', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Reject delivery request for pincode ${widget.request['pincode']}?',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
                labelText: 'Reason (shown to customer)',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'e.g. Too far from our route'),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(
        Endpoints.rejectCustomDelivery(widget.request['id'] as int),
        data: {'admin_note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim()},
      );
      widget.onAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request rejected')));
      }
    } catch (e, st) {
      logError('admin-custom-delivery', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editApproved() async {
    final pincode = widget.request['pincode'] as String;
    setState(() => _loading = true);

    // Fetch current rules from whitelisted pincodes
    Map<String, dynamic>? existing;
    try {
      final res = await ref.read(dioProvider).get(Endpoints.whitelistedPincodes);
      final list = (res.data['pincodes'] as List).cast<Map<String, dynamic>>();
      existing = list.where((p) => p['pincode'] == pincode).firstOrNull;
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loading = false);
    }

    if (!mounted) return;

    final minOrderCtrl = TextEditingController(
        text: existing?['min_order_amount']?.toString() ?? '');
    final chargeCtrl = TextEditingController(
        text: existing?['custom_delivery_charge']?.toString() ?? '');
    final initialIds = ((existing?['allowed_product_ids'] as List?) ?? [])
        .map((e) => e as int).toSet();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditPincodeSheet(
        pincode: pincode,
        minOrderCtrl: minOrderCtrl,
        chargeCtrl: chargeCtrl,
        initialAllowedIds: initialIds,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).put(Endpoints.whitelistedPincode(pincode), data: result);
      widget.onAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rules updated ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e, st) {
      logError('admin-custom-delivery', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revokeApproved() async {
    final pincode = widget.request['pincode'] as String;
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Approval'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Revoke delivery access for pincode $pincode?\n\n'
              'This will remove the pincode from the delivery area and notify affected customers.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
                labelText: 'Reason (shown to customer)',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'e.g. Route changed'),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      // Remove from whitelist (this also marks request as rejected)
      await ref.read(dioProvider).delete(Endpoints.whitelistedPincode(pincode));
      widget.onAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pincode $pincode revoked and removed from delivery area'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e, st) {
      logError('admin-custom-delivery', e, st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final status = r['status'] as String;
    final isPending = status == 'pending';
    final distKm = r['distance_km'] as num?;
    final adminNote = r['admin_note'] as String?;
    final note = r['note'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPending ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFEAF2EA),
              radius: 18,
              child: Text(
                (r['name'] as String).substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('+91 ${r['phone']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            if (distKm != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${distKm}km away',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700)),
              ),
          ]),

          const Divider(height: 16),

          // Pincode + address
          Row(children: [
            const Icon(Icons.location_pin, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Pincode: ${r['pincode']}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.home_outlined, size: 15, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(child: Text(r['address'] as String,
                style: const TextStyle(fontSize: 13))),
          ]),
          if (note != null) ...[
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.note_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(note,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
            ]),
          ],

          // Admin note (if already actioned)
          if (adminNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(adminNote,
                    style: const TextStyle(fontSize: 12, color: Colors.grey))),
              ]),
            ),
          ],

          const SizedBox(height: 4),
          Text(
            'Requested: ${(r['created_at'] as String).substring(0, 16).replaceAll('T', ' ')}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),

          // Action buttons — pending: approve+reject; rejected: re-approve only; approved: edit+revoke
          if (isPending || status == 'rejected' || status == 'approved') ...[
            const SizedBox(height: 12),
            Row(children: [
              if (isPending) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _loading
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    onPressed: _loading ? null : _reject,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (status == 'approved') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _loading
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Rules'),
                    onPressed: _loading ? null : _editApproved,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Revoke'),
                  onPressed: _loading ? null : _revokeApproved,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
              ],
              if (isPending || status == 'rejected')
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _loading
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check, size: 16),
                    label: Text(isPending ? 'Approve' : 'Re-approve'),
                    onPressed: _loading ? null : _approve,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Approval bottom sheet: min-order, delivery charge, product selection ──────

class _ApprovalSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  const _ApprovalSheet({required this.request});
  @override
  ConsumerState<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends ConsumerState<_ApprovalSheet> {
  final _noteCtrl = TextEditingController(text: 'Your area has been approved for delivery!');
  final _minOrderCtrl = TextEditingController();
  final _chargeCtrl = TextEditingController();
  final Set<int> _selectedProductIds = {};
  bool _restrictProducts = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _minOrderCtrl.dispose();
    _chargeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(adminProductsProvider('||'));
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + 20;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Approve Custom Delivery',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),

          // Pincode info
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2EA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.location_pin, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                'Pincode: ${widget.request['pincode']}  •  ${widget.request['name']}  •  +91 ${widget.request['phone']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ]),
          ),

          const Text('Delivery Rules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),

          // Min order + delivery charge
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minOrderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Min Order (₹)',
                  hintText: 'e.g. 500',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _chargeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Delivery Charge (₹)',
                  hintText: 'e.g. 100',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Leave blank to use default values',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 16),

          // Product restriction toggle
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Restrict Products', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Only selected products can be ordered to this pincode',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
            Switch(
              value: _restrictProducts,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => setState(() {
                _restrictProducts = v;
                if (!v) _selectedProductIds.clear();
              }),
            ),
          ]),

          if (_restrictProducts) ...[
            const SizedBox(height: 8),
            productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) { logError('admin-custom-delivery', e); return Text(friendlyError(e),
                  style: const TextStyle(color: Colors.red)); },
              data: (products) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('${_selectedProductIds.length} of ${products.length} selected',
                        style: TextStyle(
                            fontSize: 12,
                            color: _selectedProductIds.isEmpty ? Colors.red : AppColors.primary,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_selectedProductIds.length == products.length) {
                          _selectedProductIds.clear();
                        } else {
                          _selectedProductIds.addAll(products.map((p) => p.id));
                        }
                      }),
                      style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: Text(
                          _selectedProductIds.length == products.length
                              ? 'Deselect All'
                              : 'Select All'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: products.length,
                      itemBuilder: (_, i) {
                        final p = products[i];
                        final selected = _selectedProductIds.contains(p.id);
                        return CheckboxListTile(
                          dense: true,
                          value: selected,
                          activeColor: AppColors.primary,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(p.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('₹${p.pricePerUnit}/${p.unit}',
                              style: const TextStyle(fontSize: 11)),
                          secondary: p.categoryName != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFEAF2EA),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(p.categoryName!,
                                      style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                                )
                              : null,
                          onChanged: (v) => setState(() {
                            if (v == true) { _selectedProductIds.add(p.id); }
                            else { _selectedProductIds.remove(p.id); }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Message to customer
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Message to customer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // Approve button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve & Whitelist Pincode'),
              onPressed: () {
                if (_restrictProducts && _selectedProductIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Select at least one product, or turn off restriction')));
                  return;
                }
                Navigator.pop(context, {
                  'admin_note': _noteCtrl.text.trim(),
                  if (_minOrderCtrl.text.trim().isNotEmpty)
                    'min_order_amount': double.tryParse(_minOrderCtrl.text.trim()),
                  if (_chargeCtrl.text.trim().isNotEmpty)
                    'custom_delivery_charge': double.tryParse(_chargeCtrl.text.trim()),
                  if (_restrictProducts && _selectedProductIds.isNotEmpty)
                    'allowed_product_ids': _selectedProductIds.toList(),
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Whitelisted Pincodes tab ──────────────────────────────────────────────────

class _WhitelistedPincodesTab extends ConsumerStatefulWidget {
  final VoidCallback onChanged;
  const _WhitelistedPincodesTab({required this.onChanged});
  @override
  ConsumerState<_WhitelistedPincodesTab> createState() => _WhitelistedPincodesTabState();
}

class _WhitelistedPincodesTabState extends ConsumerState<_WhitelistedPincodesTab> {
  final _searchCtrl = TextEditingController();
  String _searchQ = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pincodesAsync = ref.watch(whitelistedPincodesProvider);

    return pincodesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) { logError('admin-custom-delivery-pincodes', e); return Center(child: Text(friendlyError(e))); },
      data: (all) {
        final q = _searchQ.toLowerCase();
        final list = q.isEmpty ? all : all.where((p) {
          return (p['pincode']?.toString().contains(q) ?? false)
              || (p['district']?.toString().toLowerCase().contains(q) ?? false)
              || (p['state']?.toString().toLowerCase().contains(q) ?? false)
              || (p['requester_name']?.toString().toLowerCase().contains(q) ?? false);
        }).toList();

        return Column(children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search pincode, district, requester…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: _searchQ.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () { _searchCtrl.clear(); setState(() => _searchQ = ''); })
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQ = v.trim()),
            ),
          ),
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Text('${list.length} of ${all.length} pincodes',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          const SizedBox(height: 4),
          if (list.isEmpty)
            Expanded(child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.location_on_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(_searchQ.isEmpty ? 'No custom pincodes yet' : 'No pincodes match "$_searchQ"',
                    style: const TextStyle(color: Colors.grey, fontSize: 16)),
              ]),
            ))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(whitelistedPincodesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _PincodeTile(
                    data: list[i],
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _PincodeTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  const _PincodeTile({required this.data, required this.onChanged});
  @override
  ConsumerState<_PincodeTile> createState() => _PincodeTileState();
}

class _PincodeTileState extends ConsumerState<_PincodeTile> {
  bool _loading = false;

  Future<void> _remove() async {
    final pincode = widget.data['pincode'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Pincode?'),
        content: Text(
            'Remove delivery access for pincode $pincode?\n\n'
            'Customers with addresses in this area will no longer be able to place orders.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).delete(Endpoints.whitelistedPincode(pincode));
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pincode $pincode removed'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } catch (e, st) {
      logError('admin-custom-delivery-pincodes', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddressesSheet(BuildContext ctx, WidgetRef ref, String pincode, int count) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PincodeAddressesSheet(pincode: pincode, count: count),
    );
  }

  Future<void> _edit() async {
    final pincode = widget.data['pincode'] as String;
    final minOrderCtrl = TextEditingController(
        text: widget.data['min_order_amount']?.toString() ?? '');
    final chargeCtrl = TextEditingController(
        text: widget.data['custom_delivery_charge']?.toString() ?? '');
    final allowedIds = (widget.data['allowed_product_ids'] as List?)
        ?.map((e) => e as int)
        .toSet() ?? {};

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditPincodeSheet(
        pincode: pincode,
        minOrderCtrl: minOrderCtrl,
        chargeCtrl: chargeCtrl,
        initialAllowedIds: allowedIds,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).put(
        Endpoints.whitelistedPincode(pincode),
        data: result,
      );
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rules updated ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e, st) {
      logError('admin-custom-delivery-pincodes', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final pincode = d['pincode'] as String;
    final district = d['district'] as String? ?? '';
    final state = d['state'] as String? ?? '';
    final distKm = d['distance_km'] as num?;
    final minOrder = d['min_order_amount'] as num?;
    final charge = d['custom_delivery_charge'] as num?;
    final allowedIds = d['allowed_product_ids'] as List?;
    final addrCount = d['address_count'] as int? ?? 0;
    final requester = d['requester_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(pincode,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                      letterSpacing: 1.5)),
            ),
            if (distKm != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${distKm}km',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ],
            const Spacer(),
            if (_loading)
              const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit rules',
                color: AppColors.primary,
                onPressed: _edit,
              ),
              IconButton(
                icon: const Icon(Icons.table_rows_outlined, size: 20),
                tooltip: 'Delivery Tiers',
                color: Colors.indigo,
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _DeliveryTiersSheet(pincode: pincode),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Remove pincode',
                color: Colors.red,
                onPressed: _remove,
              ),
            ],
          ]),

          if (district.isNotEmpty || state.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${district.isNotEmpty ? district : ''}${district.isNotEmpty && state.isNotEmpty ? ', ' : ''}$state',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],

          const SizedBox(height: 8),

          // Rules chips
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (addrCount > 0)
              GestureDetector(
                onTap: () => _showAddressesSheet(context, ref, pincode, addrCount),
                child: _Chip(Icons.home_outlined, '$addrCount address${addrCount == 1 ? '' : 'es'}',
                    Colors.blue),
              ),
            if (minOrder != null)
              _Chip(Icons.shopping_bag_outlined, 'Min ₹${minOrder.toStringAsFixed(0)}',
                  Colors.purple),
            if (charge != null)
              _Chip(Icons.local_shipping_outlined,
                  '₹${charge.toStringAsFixed(0)} delivery', Colors.teal),
            if (allowedIds != null)
              _Chip(Icons.checklist_outlined,
                  '${allowedIds.length} product${allowedIds.length == 1 ? '' : 's'} only',
                  Colors.orange),
            if (minOrder == null && charge == null && allowedIds == null)
              _Chip(Icons.check_circle_outline, 'Standard rules', AppColors.primary),
          ]),

          if (requester != null) ...[
            const SizedBox(height: 6),
            Text('Requested by $requester',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Edit pincode rules sheet ──────────────────────────────────────────────────

class _EditPincodeSheet extends ConsumerStatefulWidget {
  final String pincode;
  final TextEditingController minOrderCtrl;
  final TextEditingController chargeCtrl;
  final Set<int> initialAllowedIds;
  const _EditPincodeSheet({
    required this.pincode,
    required this.minOrderCtrl,
    required this.chargeCtrl,
    required this.initialAllowedIds,
  });
  @override
  ConsumerState<_EditPincodeSheet> createState() => _EditPincodeSheetState();
}

class _EditPincodeSheetState extends ConsumerState<_EditPincodeSheet> {
  late Set<int> _selectedIds;
  bool _restrictProducts = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialAllowedIds);
    _restrictProducts = _selectedIds.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(adminProductsProvider('||'));
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + 20;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Edit Rules — ${widget.pincode}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
              child: TextField(
                controller: widget.minOrderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Min Order (₹)', prefixText: '₹ ',
                    border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.chargeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Delivery Charge (₹)', prefixText: '₹ ',
                    border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Leave blank to use defaults',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 14),

          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Restrict Products', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('Limit which products can be ordered',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            Switch(
              value: _restrictProducts,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => setState(() {
                _restrictProducts = v;
                if (!v) _selectedIds.clear();
              }),
            ),
          ]),

          if (_restrictProducts) ...[
            const SizedBox(height: 8),
            productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) { logError('admin-custom-delivery', e); return Text(friendlyError(e),
                  style: const TextStyle(color: Colors.red)); },
              data: (products) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${_selectedIds.length}/${products.length} selected',
                      style: TextStyle(
                          fontSize: 12,
                          color: _selectedIds.isEmpty ? Colors.red : AppColors.primary,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selectedIds.length == products.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds.addAll(products.map((p) => p.id));
                      }
                    }),
                    style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: Text(_selectedIds.length == products.length
                        ? 'Deselect All' : 'Select All'),
                  ),
                ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: products.length,
                    itemBuilder: (_, i) {
                      final p = products[i];
                      return CheckboxListTile(
                        dense: true,
                        value: _selectedIds.contains(p.id),
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(p.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('₹${p.pricePerUnit}/${p.unit}',
                            style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setState(() {
                          if (v == true) { _selectedIds.add(p.id); }
                          else { _selectedIds.remove(p.id); }
                        }),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_restrictProducts && _selectedIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Select at least one product or turn off restriction')));
                  return;
                }
                Navigator.pop(context, {
                  if (widget.minOrderCtrl.text.trim().isNotEmpty)
                    'min_order_amount': double.tryParse(widget.minOrderCtrl.text.trim()),
                  if (widget.chargeCtrl.text.trim().isNotEmpty)
                    'custom_delivery_charge': double.tryParse(widget.chargeCtrl.text.trim()),
                  if (_restrictProducts && _selectedIds.isNotEmpty)
                    'allowed_product_ids': _selectedIds.toList(),
                  // Pass null explicitly to clear if not set
                  if (widget.minOrderCtrl.text.trim().isEmpty) 'min_order_amount': null,
                  if (widget.chargeCtrl.text.trim().isEmpty) 'custom_delivery_charge': null,
                  if (!_restrictProducts || _selectedIds.isEmpty) 'allowed_product_ids': null,
                });
              },
              child: const Text('Save Changes'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Delivery Tiers Sheet ──────────────────────────────────────────────────────

class _DeliveryTiersSheet extends ConsumerStatefulWidget {
  final String pincode;
  const _DeliveryTiersSheet({required this.pincode});
  @override
  ConsumerState<_DeliveryTiersSheet> createState() => _DeliveryTiersSheetState();
}

class _DeliveryTiersSheetState extends ConsumerState<_DeliveryTiersSheet> {
  List<Map<String, dynamic>> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get(Endpoints.pincodeRules(widget.pincode));
      setState(() => _rules = List<Map<String, dynamic>>.from(res.data['rules']));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? existing]) async {
    final minCtrl     = TextEditingController(text: existing?['min_subtotal']?.toString() ?? '0');
    final maxCtrl     = TextEditingController(text: existing?['max_subtotal']?.toString() ?? '');
    final chargeCtrl  = TextEditingController(text: existing?['delivery_charge']?.toString() ?? '');
    final msgCtrl     = TextEditingController(text: existing?['blocked_message'] as String? ?? '');
    bool isBlocked    = (existing?['blocked'] as int? ?? 0) == 1;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: Text(existing == null ? 'Add Delivery Tier' : 'Edit Tier'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Define a delivery charge rule for a subtotal range.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: minCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Min subtotal (₹)', prefixText: '₹ ', isDense: true, border: OutlineInputBorder()),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: maxCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Max subtotal (₹, blank = no limit)', prefixText: '₹ ', isDense: true, border: OutlineInputBorder()),
              )),
            ]),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Block orders in this range', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Customer sees a message, cannot place order', style: TextStyle(fontSize: 12)),
              value: isBlocked,
              activeTrackColor: Colors.red,
              onChanged: (v) => setDs(() => isBlocked = v),
            ),
            if (isBlocked) ...[
              const SizedBox(height: 8),
              TextField(
                controller: msgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Message to customer *',
                  hintText: 'e.g. Minimum ₹200 order required for this area',
                  border: OutlineInputBorder(), isDense: true,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              TextField(
                controller: chargeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Delivery charge (₹) *',
                  prefixText: '₹ ',
                  helperText: 'Enter 0 for free delivery',
                  border: OutlineInputBorder(), isDense: true,
                ),
              ),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final min = double.tryParse(minCtrl.text.trim()) ?? 0;
    final max = maxCtrl.text.trim().isEmpty ? null : double.tryParse(maxCtrl.text.trim());
    final charge = isBlocked ? null : double.tryParse(chargeCtrl.text.trim());
    if (!isBlocked && charge == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid delivery charge')));
      return;
    }
    if (isBlocked && msgCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a message for blocked orders')));
      return;
    }

    try {
      final body = {
        if (existing?['id'] != null) 'id': existing!['id'],
        'min_subtotal': min,
        if (max != null) 'max_subtotal': max,
        if (!isBlocked) 'delivery_charge': charge,
        'blocked': isBlocked ? 1 : 0,
        if (isBlocked) 'blocked_message': msgCtrl.text.trim(),
      };
      if (existing?['id'] != null) {
        await ref.read(dioProvider).put(Endpoints.pincodeRule(widget.pincode, existing!['id'] as int), data: body);
      } else {
        await ref.read(dioProvider).post(Endpoints.pincodeRules(widget.pincode), data: body);
      }
      _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tier saved ✅'), backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tier?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(dioProvider).delete(Endpoints.pincodeRule(widget.pincode, id));
    _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.table_rows_outlined, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(child: Text('Delivery Tiers — ${widget.pincode}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 4),
        const Text('Rules are matched by subtotal range. First match wins.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No tiers set — standard distance-based pricing applies.',
                  style: TextStyle(color: Colors.grey))),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rules.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rules[i];
                  final blocked = (r['blocked'] as int? ?? 0) == 1;
                  final minS = (r['min_subtotal'] as num).toStringAsFixed(0);
                  final maxS = r['max_subtotal'] != null ? '₹${(r['max_subtotal'] as num).toStringAsFixed(0)}' : '∞';
                  final rangeLabel = '₹$minS – $maxS';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: blocked ? Colors.red.shade50 : Colors.green.shade50,
                      child: Icon(blocked ? Icons.block : Icons.local_shipping_outlined,
                          color: blocked ? Colors.red : Colors.green, size: 18),
                    ),
                    title: Text(rangeLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      blocked
                          ? r['blocked_message'] as String? ?? 'Blocked'
                          : r['delivery_charge'] == 0 || r['delivery_charge'] == null
                              ? 'FREE delivery'
                              : '₹${(r['delivery_charge'] as num).toStringAsFixed(0)} delivery charge',
                      style: TextStyle(fontSize: 12, color: blocked ? Colors.red : Colors.grey),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                          onPressed: () => _showAddEditDialog(r)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => _delete(r['id'] as int)),
                    ]),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Tier'),
              onPressed: () => _showAddEditDialog(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Pincode Addresses Sheet ───────────────────────────────────────────────────

class _PincodeAddressesSheet extends ConsumerStatefulWidget {
  final String pincode;
  final int count;
  const _PincodeAddressesSheet({required this.pincode, required this.count});

  @override
  ConsumerState<_PincodeAddressesSheet> createState() => _PincodeAddressesSheetState();
}

class _PincodeAddressesSheetState extends ConsumerState<_PincodeAddressesSheet> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get(Endpoints.pincodeAddresses(widget.pincode));
      setState(() => _addresses = List<Map<String, dynamic>>.from(res.data['addresses']));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        // Handle
        Container(margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            const Icon(Icons.home_outlined, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text('Addresses in ${widget.pincode}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
              child: Text('${widget.count} total',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _addresses.isEmpty
                  ? const Center(child: Text('No addresses found', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _addresses.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _addresses[i];
                        final wallet = (a['wallet_balance'] as num?)?.toDouble() ?? 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEAF2EA),
                            child: Text(
                              (a['customer_name'] as String? ?? 'C')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(a['customer_name'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('+91 ${a['customer_phone'] ?? ''}',
                                style: const TextStyle(fontSize: 12)),
                            Text(
                              '${a['label'] ?? 'Address'}: ${a['address_line']}, ${a['city']}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(
                              wallet >= 0 ? '₹${wallet.toStringAsFixed(0)}' : '-₹${wallet.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13,
                                color: wallet < 0 ? Colors.red : AppColors.primary,
                              ),
                            ),
                            Text('wallet', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
