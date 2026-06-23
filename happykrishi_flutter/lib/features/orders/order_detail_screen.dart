import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/services/pdf_service.dart';
import '../orders/order_list_screen.dart';
import '../wallet/wallet_screen.dart';

final orderDetailProvider = FutureProvider.family.autoDispose<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.order(id));
  return res.data as Map<String, dynamic>;
});

class OrderDetailScreen extends ConsumerWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(orderDetailProvider(orderId));

    final currentUser = ref.watch(authStateProvider).user;
    final isAdmin = currentUser?.role == 'admin' || currentUser?.role == 'subadmin';
    final isSalesman = currentUser?.role == 'salesman';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isAdmin) {
              context.go('/admin/orders');
            } else if (isSalesman) {
              context.go('/salesman');
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/orders');
            }
          },
        ),
        actions: [
          data.when(
            data: (d) {
              final order = Order.fromJson(d['order']);
              final items = (d['items'] as List).map((e) => OrderItem.fromJson(e)).toList();
              final user = ref.read(authStateProvider).user;
              return IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download Invoice',
                onPressed: user == null ? null : () => PdfService.shareOrderInvoice(
                  context: context, user: user, order: order, items: items,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: data.when(
        data: (d) {
          final order = Order.fromJson(d['order']);
          final items = (d['items'] as List).map((e) => OrderItem.fromJson(e)).toList();
          final delivery = d['delivery'] != null ? DeliveryInfo.fromJson(d['delivery']) : null;

          final user = ref.read(authStateProvider).user;
          final isAdmin = user?.role == 'admin' || user?.role == 'subadmin';
          final isSalesman = user?.role == 'salesman';

          // Salesman can mark delivered from here; admin edits weights with immediate wallet update
          final canEditItems = isAdmin;
          final salesmanCanAct = isSalesman &&
              (order.status == 'assigned' || order.status == 'dispatched' || order.status == 'picked');

          return ListView(padding: const EdgeInsets.all(16), children: [
            _StatusCard(order: order, delivery: delivery),
            const SizedBox(height: 16),
            if (salesmanCanAct)
              _SalesmanItemsEditor(items: items, orderId: orderId, delivery: delivery)
            else
              _OrderItemsList(items: items, orderId: orderId, canEdit: canEditItems),
            const SizedBox(height: 16),
            _PriceSummary(order: order),
            const SizedBox(height: 16),
            if (order.status == 'dispatched' || order.status == 'assigned')
              ElevatedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Track Live'),
                onPressed: () => context.push('/track/${order.id}'),
              ),
            // Customer: restricted cancel (cutoff + only pending/confirmed)
            if (!isAdmin && !isSalesman &&
                (order.status == 'pending' || order.status == 'confirmed'))
              _CancelButton(order: order),
            // Admin/salesman: cancel anytime except delivered/cancelled
            if ((isAdmin || isSalesman) &&
                !['delivered', 'cancelled'].contains(order.status)) ...[
              const SizedBox(height: 8),
              _StaffCancelButton(order: order, role: user!.role),
            ],
            if (order.status == 'delivered')
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Reorder'),
                onPressed: () => _reorder(context, ref, order),
              ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref, Order order) async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(Endpoints.reorder(order.id));
      final cartItems = (res.data['cart_items'] as List).cast<Map<String, dynamic>>();

      if (cartItems.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No available items to reorder (out of stock or inactive)')));
        }
        return;
      }

      // Clear existing cart then add all items
      ref.read(cartProvider.notifier).clear();
      for (final item in cartItems) {
        final product = Product.fromJson(item['product'] as Map<String, dynamic>);
        final qty = (item['qty'] as num).toDouble();
        ref.read(cartProvider.notifier).addItem(product, qty);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${cartItems.length} item(s) added to cart'),
          backgroundColor: const Color(0xFF2E7D32),
          action: SnackBarAction(label: 'View Cart', onPressed: () => context.go('/cart')),
        ));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ── Cancel button — shows cutoff warning or confirmation ──────────────────────
class _CancelButton extends ConsumerStatefulWidget {
  final Order order;
  const _CancelButton({required this.order});
  @override
  ConsumerState<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends ConsumerState<_CancelButton> {
  bool _loading = false;

  bool get _withinCutoff {
    try {
      final delivery = DateTime.parse(widget.order.deliveryDate);
      final cutoff = DateTime.now().add(const Duration(days: 1));
      // cutoff: delivery date must be at least 2 days away (i.e. not tomorrow or today)
      final deliveryDay = DateTime(delivery.year, delivery.month, delivery.day);
      final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
      return deliveryDay.isBefore(cutoffDay) || deliveryDay.isAtSameMomentAs(cutoffDay);
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The full amount will be refunded to your wallet immediately.'),
          const SizedBox(height: 16),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason for cancellation *',
              hintText: 'e.g. Changed my mind, ordered by mistake...',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter a reason')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.cancelOrder(widget.order.id),
          data: {'reason': reasonCtrl.text.trim()});
      ref.invalidate(orderDetailProvider(widget.order.id));
      ref.invalidate(ordersProvider);
      await ref.read(authStateProvider.notifier).refreshUser();
      ref.invalidate(walletProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cancelled. Refund added to wallet.'),
          backgroundColor: Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.response?.data['error'] ?? 'Cancellation failed'),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_withinCutoff) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cancellation is not allowed within 1 day of delivery (${widget.order.deliveryDate}). Contact us for help.',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ]),
      );
    }

    return OutlinedButton.icon(
      icon: _loading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cancel_outlined),
      label: const Text('Cancel Order'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
      ),
      onPressed: _loading ? null : _cancel,
    );
  }
}

// ── Staff cancel button (admin / salesman — no cutoff, any active status) ─────

class _StaffCancelButton extends ConsumerStatefulWidget {
  final Order order;
  final String role;
  const _StaffCancelButton({required this.order, required this.role});
  @override
  ConsumerState<_StaffCancelButton> createState() => _StaffCancelButtonState();
}

class _StaffCancelButtonState extends ConsumerState<_StaffCancelButton> {
  bool _loading = false;

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDs) => AlertDialog(
        title: Text('Cancel Order #${widget.order.orderNumber}?'),
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
              labelText: 'Reason *',
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
      final dio = ref.read(dioProvider);
      await dio.post(
        Endpoints.staffCancelOrder(widget.order.id, widget.role),
        data: {'reason': reasonCtrl.text.trim()},
      );
      ref.invalidate(orderDetailProvider(widget.order.id));
      await ref.read(authStateProvider.notifier).refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cancelled. Refund added to wallet.'),
          backgroundColor: Color(0xFF2E7D32),
        ));
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Cancellation failed')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: _loading
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.cancel_outlined),
    label: const Text('Cancel Order'),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.red,
      side: const BorderSide(color: Colors.red),
    ),
    onPressed: _loading ? null : _cancel,
  );
}

class _StatusCard extends StatelessWidget {
  final Order order;
  final DeliveryInfo? delivery;
  const _StatusCard({required this.order, this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('#${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Spacer(),
        Chip(label: Text(order.status.toUpperCase()), backgroundColor: _statusColor(order.status).withValues(alpha: 0.15)),
      ]),
      const SizedBox(height: 8),
      Text('Delivery: ${order.deliveryDate}', style: const TextStyle(color: Colors.grey)),
      if (order.slotLabel != null) Text('Slot: ${order.slotLabel}', style: const TextStyle(color: Colors.grey)),
      // Salesman who confirmed/placed the order
      if (order.salesmanName != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.indigo.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.badge_outlined, size: 14, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Salesman', style: TextStyle(fontSize: 10, color: Colors.grey)),
              Text(order.salesmanName!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
              if (order.salesmanPhone != null)
                Text('+91 ${order.salesmanPhone}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
          ]),
        ),
      ],
      if (delivery?.agentName != null) ...[
        const SizedBox(height: 8),
        Builder(builder: (_) {
          final d = delivery!;
          if (order.status == 'delivered') {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.done_all, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Delivered by', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(d.agentName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (d.agentPhone != null)
                    Text('+91 ${d.agentPhone}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
                if (d.deliveredAt != null)
                  Text(d.deliveredAt!.substring(0, 16).replaceAll('T', ' '),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            );
          }
          return Row(children: [
            const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text('${d.agentName}  •  +91 ${d.agentPhone ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]);
        }),
      ],
      // Show cancellation reason if cancelled
      if (order.status == 'cancelled' && order.cancelledReason != null && order.cancelledReason!.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Colors.red, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Builder(builder: (_) {
                // Parse "Cancelled by role (name): reason" format from staff cancellations
                final raw = order.cancelledReason!;
                final staffMatch = RegExp(r'^Cancelled by (\w+) \(([^)]+)\): (.+)$', dotAll: true).firstMatch(raw);
                if (staffMatch != null) {
                  final role = staffMatch.group(1)!;
                  final name = staffMatch.group(2)!;
                  final reason = staffMatch.group(3)!;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('Cancelled by ',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$name ($role)',
                            style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Reason:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(reason, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ]);
                }
                // Plain reason (customer cancelled)
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Cancellation Reason',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(raw, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ]);
              }),
            ),
          ]),
        ),
      ],
    ])));
  }

  Color _statusColor(String s) => switch (s) {
    'delivered' => Colors.green, 'cancelled' => Colors.red,
    'dispatched' || 'assigned' => Colors.blue, _ => Colors.orange,
  };
}

class _OrderItemsList extends ConsumerWidget {
  final List<OrderItem> items;
  final int orderId;
  final bool canEdit;
  const _OrderItemsList({required this.items, required this.orderId, this.canEdit = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        if (canEdit) ...[
          const Spacer(),
          Text('Tap ✏️ to update weight', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ]),
      const SizedBox(height: 8),
      ...items.map((i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.productName ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${i.estimatedQty.toStringAsFixed(2)} ${i.unit ?? ''}  •  ₹${i.unitPrice.toStringAsFixed(0)}/unit',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (i.actualQty != null)
              Row(children: [
                const Icon(Icons.scale, size: 12, color: Colors.orange),
                const SizedBox(width: 4),
                Text('Actual: ${i.actualQty!.toStringAsFixed(2)} ${i.unit ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                if ((i.actualQty! - i.estimatedQty).abs() > 0.01)
                  Text('  (est ${i.estimatedQty.toStringAsFixed(2)})',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${(i.actualTotal ?? i.estimatedTotal).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (i.actualTotal != null && (i.actualTotal! - i.estimatedTotal).abs() > 0.01)
              Text('est ₹${i.estimatedTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey,
                      decoration: TextDecoration.lineThrough)),
          ]),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: const Color(0xFF2E7D32),
              tooltip: 'Update actual quantity',
              padding: const EdgeInsets.only(left: 8),
              constraints: const BoxConstraints(),
              onPressed: () => _showEditDialog(context, ref, i),
            ),
        ]),
      )),
    ])));
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, OrderItem item) async {
    final ctrl = TextEditingController(
        text: (item.actualQty ?? item.estimatedQty).toStringAsFixed(2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDs) {
          double? newQty = double.tryParse(ctrl.text);
          double? preview = newQty != null ? newQty * item.unitPrice : null;
          double diff = preview != null
              ? preview - (item.actualTotal ?? item.estimatedTotal) : 0;

          return AlertDialog(
            title: Text('Update: ${item.productName ?? 'Item'}'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Estimated: ${item.estimatedQty.toStringAsFixed(2)} ${item.unit ?? ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Actual quantity', suffixText: item.unit ?? '',
                    border: const OutlineInputBorder()),
                onChanged: (_) => setDs(() {}),
              ),
              const SizedBox(height: 10),
              if (preview != null) ...[
                Text('New total: ₹${preview.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  diff > 0.01 ? 'Customer wallet debited ₹${diff.toStringAsFixed(2)}'
                      : diff < -0.01 ? 'Customer wallet credited ₹${diff.abs().toStringAsFixed(2)}'
                      : 'No wallet change',
                  style: TextStyle(fontSize: 12,
                      color: diff > 0.01 ? Colors.red : diff < -0.01 ? Colors.green : Colors.grey),
                ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (double.tryParse(ctrl.text) == null) return;
                  Navigator.pop(dialogCtx, true);
                },
                child: const Text('Update & Adjust Wallet'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final dio = ref.read(dioProvider);
      final user = ref.read(authStateProvider).user;
      final endpoint = user?.role == 'salesman'
          ? Endpoints.salesmanUpdateOrderItems(orderId)
          : Endpoints.adminUpdateOrderItems(orderId);

      final res = await dio.put(endpoint, data: {
        'items': [{'order_item_id': item.id, 'actual_qty': double.parse(ctrl.text)}],
      });

      ref.invalidate(orderDetailProvider(orderId));
      await ref.read(authStateProvider.notifier).refreshUser();

      if (context.mounted) {
        final adj       = (res.data['wallet_adjustment']   as num).toDouble();
        final newFinal  = (res.data['new_final_amount']    as num).toDouble();
        final newCharge = (res.data['new_delivery_charge'] as num?)?.toDouble();
        final sign = adj > 0 ? '-' : '+';
        String msg = adj.abs() > 0.01
            ? 'Updated! Wallet $sign₹${adj.abs().toStringAsFixed(2)}'
            : 'Updated! No wallet change.';
        if (newCharge != null) {
          msg += '  •  Delivery ₹${newCharge.toStringAsFixed(0)}  •  Total ₹${newFinal.toStringAsFixed(2)}';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 5),
        ));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.response?.data['error'] ?? 'Update failed')));
      }
    }
  }
}

// ── Salesman inline weight editor + mark delivered ────────────────────────────

class _SalesmanItemsEditor extends ConsumerStatefulWidget {
  final List<OrderItem> items;
  final int orderId;
  final DeliveryInfo? delivery;
  const _SalesmanItemsEditor({required this.items, required this.orderId, this.delivery});
  @override
  ConsumerState<_SalesmanItemsEditor> createState() => _SalesmanItemsEditorState();
}

class _SalesmanItemsEditorState extends ConsumerState<_SalesmanItemsEditor> {
  late final Map<int, TextEditingController> _controllers;
  bool _savingWeights = false;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final i in widget.items.where((i) => i.isWeightAdjusted))
        i.id: TextEditingController(
          text: (i.actualQty ?? i.estimatedQty).toStringAsFixed(2),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _saveWeights() async {
    setState(() => _savingWeights = true);
    try {
      final dio = ref.read(dioProvider);
      final items = _controllers.entries.map((e) {
        final qty = double.tryParse(e.value.text) ??
            widget.items.firstWhere((i) => i.id == e.key).estimatedQty;
        return {'order_item_id': e.key, 'actual_qty': qty};
      }).toList();

      final res = await dio.put(
        Endpoints.salesmanUpdateOrderItems(widget.orderId),
        data: {'items': items},
      );

      ref.invalidate(orderDetailProvider(widget.orderId));
      await ref.read(authStateProvider.notifier).refreshUser();

      if (mounted) {
        final adj        = (res.data['wallet_adjustment']  as num).toDouble();
        final newFinal   = (res.data['new_final_amount']   as num).toDouble();
        final newCharge  = (res.data['new_delivery_charge'] as num?)?.toDouble();

        String msg = adj.abs() > 0.01
            ? 'Weights saved! Wallet ${adj > 0 ? "-" : "+"}₹${adj.abs().toStringAsFixed(2)}'
            : 'Weights saved. No wallet change.';
        if (newCharge != null) {
          msg += '  •  Delivery ₹${newCharge.toStringAsFixed(0)}  •  Total ₹${newFinal.toStringAsFixed(2)}';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 5),
        ));
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Failed to save weights')));
    } finally {
      if (mounted) setState(() => _savingWeights = false);
    }
  }

  Future<void> _markDelivered() async {
    final deliveryId = widget.delivery?.id;
    if (deliveryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No delivery record found')));
      return;
    }

    setState(() => _marking = true);
    try {
      final dio = ref.read(dioProvider);
      // Weights already saved via _saveWeights — pass no actual_weights to avoid double deduction
      await dio.put(Endpoints.salesmanMarkDelivered(deliveryId));

      ref.invalidate(orderDetailProvider(widget.orderId));
      await ref.read(authStateProvider.notifier).refreshUser();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Marked as delivered ✅'),
          backgroundColor: Color(0xFF2E7D32),
        ));
        context.go('/salesman');
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Failed')));
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWeightItems = _controllers.isNotEmpty;
    final isPickup = widget.delivery?.status == 'assigned';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (hasWeightItems) ...[
              const Spacer(),
              Text('⚖️ Enter actual weight',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
            ],
          ]),
          const SizedBox(height: 8),
          ...widget.items.map((item) {
            final ctrl = _controllers[item.id];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.productName ?? 'Product',
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(
                      'Est: ${item.estimatedQty.toStringAsFixed(2)} ${item.unit ?? ''}  •  '
                      '₹${item.unitPrice.toStringAsFixed(0)}/unit',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (item.actualQty != null)
                      Text(
                        'Saved: ${item.actualQty!.toStringAsFixed(2)} ${item.unit ?? ''}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                      ),
                  ])),
                  if (ctrl != null)
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          suffixText: item.unit ?? '',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    )
                  else
                    Text('${item.estimatedQty.toStringAsFixed(2)} ${item.unit ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                ]),
                if (ctrl != null) Builder(builder: (_) {
                  final qty = double.tryParse(ctrl.text);
                  if (qty == null) return const SizedBox.shrink();
                  final newTotal = qty * item.unitPrice;
                  final diff = newTotal - (item.actualTotal ?? item.estimatedTotal);
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '₹${newTotal.toStringAsFixed(2)}'
                      '${diff.abs() > 0.01 ? (diff > 0 ? "  (+₹${diff.toStringAsFixed(2)})" : "  (-₹${diff.abs().toStringAsFixed(2)})") : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: diff > 0.01 ? Colors.red : diff < -0.01 ? Colors.green : Colors.grey,
                      ),
                    ),
                  );
                }),
              ]),
            );
          }),
        ],
      ))),
      const SizedBox(height: 10),

      // Step 1 — save weights and adjust wallet (only shown when weight-adjusted items exist)
      if (hasWeightItems) ...[
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _savingWeights
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Weights & Update Wallet'),
            onPressed: _savingWeights || _marking ? null : _saveWeights,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],

      // Step 2 — mark delivered (always shown)
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _marking
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(isPickup ? '✅ Mark as Collected' : '✅ Mark as Delivered'),
          onPressed: _savingWeights || _marking ? null : _markDelivered,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    ]);
  }
}

class _PriceSummary extends StatelessWidget {
  final Order order;
  const _PriceSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      _Row('Subtotal', '₹${order.subtotal.toStringAsFixed(2)}'),
      _Row('Delivery', order.deliveryCharge == 0 ? 'FREE' : '₹${order.deliveryCharge.toStringAsFixed(0)}'),
      if (order.discountAmount > 0) _Row('Discount', '-₹${order.discountAmount.toStringAsFixed(2)}'),
      const Divider(),
      _Row('Total', '₹${order.finalAmount.toStringAsFixed(2)}', bold: true),
    ])));
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row(this.label, this.value, {this.bold = false});
  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text(value, style: style?.copyWith(color: const Color(0xFF2E7D32)))]),
    );
  }
}
