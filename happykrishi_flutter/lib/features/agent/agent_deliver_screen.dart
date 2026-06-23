import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import 'agent_home_screen.dart';

class AgentDeliverScreen extends ConsumerStatefulWidget {
  final int deliveryId;
  const AgentDeliverScreen({super.key, required this.deliveryId});
  @override
  ConsumerState<AgentDeliverScreen> createState() => _AgentDeliverScreenState();
}

class _AgentDeliverScreenState extends ConsumerState<AgentDeliverScreen> {
  final Map<int, TextEditingController> _actualWeightCtrls = {};
  bool _loading = false;

  Future<void> _markDelivered(List<Map<String, dynamic>> items) async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final actualWeights = items
          .where((i) => i['is_weight_adjusted'] == 1)
          .map((i) {
            final id = i['id'] as int;
            final ctrl = _actualWeightCtrls[id];
            final qty = double.tryParse(ctrl?.text ?? '') ?? (i['estimated_qty'] as num).toDouble();
            return {'order_item_id': id, 'actual_qty': qty};
          })
          .toList();

      final res = await dio.put(Endpoints.markDelivered(widget.deliveryId), data: {'actual_weights': actualWeights});
      ref.invalidate(agentOrderProvider);
      if (mounted) {
        final adjustments = res.data['adjustments'] as List? ?? [];
        final walletBalance = res.data['wallet_balance'];
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Delivery Complete! ✅'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (adjustments.isNotEmpty) ...[
                const Text('Weight Adjustments:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...adjustments.map((a) => Text('${a['name']}: ${a['estimated_qty']} → ${a['actual_qty']} ${a['unit'] ?? ''}')),
                const Divider(),
              ],
              Text('Customer wallet balance: ₹$walletBalance'),
            ]),
            actions: [TextButton(onPressed: () { Navigator.pop(context); context.go('/agent'); }, child: const Text('Done'))],
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.response?.data['error'] ?? 'Error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderData = ref.watch(agentOrderProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Record Delivery')),
      body: orderData.when(
        data: (data) {
          if (data == null) return const Center(child: Text('No active delivery'));
          final items = (data['items'] as List).cast<Map<String, dynamic>>();
          final weightItems = items.where((i) => i['is_weight_adjusted'] == 1).toList();

          for (final i in weightItems) {
            final id = i['id'] as int;
            _actualWeightCtrls.putIfAbsent(id, () => TextEditingController(text: i['estimated_qty'].toString()));
          }

          return ListView(padding: const EdgeInsets.all(16), children: [
            if (weightItems.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No weight-adjusted items. Tap Confirm to complete delivery.')))
            else ...[
              const Text('Enter actual weights:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...weightItems.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(child: Text('${i['product_name']}\nEst: ${i['estimated_qty']} ${i['unit']}')),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _actualWeightCtrls[i['id'] as int],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Actual (${i['unit']})'),
                    ),
                  ),
                ]),
              )),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.done_all),
              label: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Confirm Delivery'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _loading ? null : () => _markDelivered(items),
            ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
