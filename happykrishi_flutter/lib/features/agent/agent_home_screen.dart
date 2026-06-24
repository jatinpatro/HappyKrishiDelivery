import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final agentOrderProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.myDeliveryOrder);
  if (res.data['delivery'] == null) return null;
  return res.data as Map<String, dynamic>;
});

class AgentHomeScreen extends ConsumerWidget {
  const AgentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderData = ref.watch(agentOrderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Delivery'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(agentOrderProvider)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            ref.read(authStateProvider.notifier).logout();
            if (context.mounted) context.go('/auth/otp');
          }),
        ],
      ),
      body: orderData.when(
        data: (data) => data == null
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                SizedBox(height: 16),
                Text('No active delivery', style: TextStyle(fontSize: 18, color: Colors.grey)),
                SizedBox(height: 8),
                Text('Waiting for next assignment...', style: TextStyle(color: Colors.grey)),
              ]))
            : _ActiveDeliveryCard(data: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('agent-home', e); return Center(child: Text(friendlyError(e))); },
      ),
    );
  }
}

class _ActiveDeliveryCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _ActiveDeliveryCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = data['delivery'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final deliveryId = delivery['id'] as int;
    final deliveryStatus = delivery['status'] as String;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          color: const Color(0xFFE8F5E9),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.local_shipping, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Text('Order #${delivery['order_number']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Text('Customer: ${delivery['customer_name']}'),
            Text('Phone: ${delivery['customer_phone']}'),
            Text('Address: ${delivery['address_line']}, ${delivery['city']}'),
            Text('Slot: ${delivery['slot_label'] ?? '-'}'),
            Text('Amount: ₹${delivery['final_amount']}'),
          ])),
        ),
        const SizedBox(height: 12),
        const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ...items.map((i) => ListTile(
          title: Text(i['product_name'] as String),
          subtitle: Text('${i['estimated_qty']} ${i['unit']}${i['is_weight_adjusted'] == 1 ? ' ⚖️' : ''}'),
          dense: true,
        )),
        const SizedBox(height: 16),
        if (deliveryStatus == 'assigned')
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Mark as Picked Up'),
            onPressed: () => _markPicked(context, ref, deliveryId),
          ),
        if (deliveryStatus == 'picked')
          ElevatedButton.icon(
            icon: const Icon(Icons.done_all),
            label: const Text('Mark as Delivered'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => context.push('/agent/deliver/$deliveryId'),
          ),
      ]),
    );
  }

  Future<void> _markPicked(BuildContext context, WidgetRef ref, int deliveryId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put(Endpoints.markPicked(deliveryId));
      ref.invalidate(agentOrderProvider);
    } catch (e, st) {
      logError('agent-home', e, st);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}
