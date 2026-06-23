import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

final productDetailProvider = FutureProvider.family.autoDispose<Product, int>((ref, id) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.product(id));
  return Product.fromJson(res.data['product']);
});

class ProductDetailScreen extends ConsumerStatefulWidget {
  final int productId;
  const ProductDetailScreen({super.key, required this.productId});
  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  double _qty = 0; // initialized from product.minQty on first build

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailProvider(widget.productId));

    return Scaffold(
      body: productAsync.when(
        data: (product) {
          if (_qty == 0) _qty = product.minQty;
          return CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: product.imageUrl != null
                  ? Image.network('${Endpoints.baseUrl}${product.imageUrl}', fit: BoxFit.cover)
                  : Container(color: const Color(0xFFE8F5E9), child: const Center(child: Icon(Icons.eco, size: 80, color: Color(0xFF2E7D32)))),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(product.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                  Text('₹${product.pricePerUnit}/${product.unit}', style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                if (product.isWeightAdjusted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                    child: const Text('⚖️ Actual weight billed at delivery', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ),
                const SizedBox(height: 12),
                if (product.description != null) Text(product.description!, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
                Text('Stock: ${product.stockQty.toStringAsFixed(1)} ${product.unit}', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                Row(children: [
                  const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: _qty > product.minQty ? () => setState(() => _qty = (_qty - product.qtyStep).clamp(product.minQty, 9999)) : null),
                  Text('${_qty.toStringAsFixed(2)} ${product.unit}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _qty = (_qty + product.qtyStep).clamp(product.minQty, 9999))),
                ]),
                const SizedBox(height: 8),
                Text('Estimated: ₹${(product.pricePerUnit * _qty).toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: product.stockQty > 0 ? () {
                    ref.read(cartProvider.notifier).addItem(product, _qty);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${product.name} added to cart'),
                      action: SnackBarAction(label: 'View Cart', onPressed: () => context.push('/cart')),
                    ));
                  } : null,
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Add to Cart'),
                ),
              ]),
            ),
          ),
        ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
