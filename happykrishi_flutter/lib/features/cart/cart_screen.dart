import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../info/app_info_screen.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: cart.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text('Your cart is empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ]))
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: cart.length,
                  itemBuilder: (_, i) => _CartItemTile(item: cart[i]),
                ),
              ),
              _CartSummary(subtotal: subtotal),
            ]),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = item.product;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: p.imageUrl != null
                ? CachedNetworkImage(imageUrl: '${Endpoints.baseUrl}${p.imageUrl}', width: 60, height: 60, fit: BoxFit.cover)
                : Container(width: 60, height: 60, color: const Color(0xFFE8F5E9), child: const Icon(Icons.eco, color: Color(0xFF2E7D32))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (p.isWeightAdjusted) const Text('⚖️ Weight adjusted at delivery', style: TextStyle(fontSize: 11, color: Colors.orange)),
              Text('₹${p.pricePerUnit}/${p.unit}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          Column(children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () {
                  final nq = item.qty - p.qtyStep;
                  if (nq < p.minQty) {
                    ref.read(cartProvider.notifier).removeItem(p.id);
                  } else {
                    ref.read(cartProvider.notifier).updateQty(p.id, nq);
                  }
                },
              ),
              Text(item.qty.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: item.qty + p.qtyStep > p.stockQty
                    ? null
                    : () => ref.read(cartProvider.notifier).updateQty(p.id, item.qty + p.qtyStep),
              ),
            ]),
            Text('₹${(p.pricePerUnit * item.qty).toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
            if (item.qty >= p.stockQty)
              Text('Max stock', style: TextStyle(fontSize: 9, color: Colors.orange.shade700)),
          ]),
        ]),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  final double subtotal;
  const _CartSummary({required this.subtotal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(children: [
        DeliveryInfoBanner(subtotal: subtotal),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Subtotal', style: TextStyle(fontSize: 16)),
          Text('₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: () => context.push('/checkout'), child: const Text('Proceed to Checkout')),
      ]),
    );
  }
}
