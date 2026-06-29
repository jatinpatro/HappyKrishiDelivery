import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';

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
          // Drive qty from cart — always in sync with cart state
          final cartItems = ref.watch(cartProvider);
          final cartItem = cartItems.where((i) => i.product.id == product.id).firstOrNull;
          final cartQty = cartItem?.qty ?? 0.0;
          final inCart = cartItem != null;

          // Local _qty for the quantity picker (used only when not yet in cart)
          if (_qty == 0 && !inCart) {
            _qty = product.minQty.clamp(0, product.stockQty);
          }
          // Once in cart, sync local picker to cart qty
          final displayQty = inCart ? cartQty : _qty;

          return CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: 'Home',
                onPressed: () => context.go('/home'),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: product.imageUrl != null
                  ? Image.network(Endpoints.imageUrl(product.imageUrl), fit: BoxFit.cover)
                  : Container(color: const Color(0xFFEAF2EA), child: const Center(child: Icon(Icons.eco, size: 80, color: AppColors.primary))),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(product.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                  Text('₹${product.pricePerUnit}/${product.unit}', style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
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
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: displayQty > product.minQty ? () {
                      final nq = (displayQty - product.qtyStep).clamp(product.minQty, product.stockQty);
                      if (inCart) {
                        ref.read(cartProvider.notifier).updateQty(product.id, nq);
                      } else {
                        setState(() => _qty = nq);
                      }
                    } : null,
                  ),
                  Text('${displayQty.toStringAsFixed(displayQty.truncateToDouble() == displayQty ? 0 : 2)} ${product.unit}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: displayQty < product.stockQty ? () {
                      final nq = (displayQty + product.qtyStep).clamp(product.minQty, product.stockQty);
                      if (inCart) {
                        ref.read(cartProvider.notifier).updateQty(product.id, nq);
                      } else {
                        setState(() => _qty = nq);
                      }
                    } : null,
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Estimated: ₹${(product.pricePerUnit * displayQty).toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 24),
                if (product.stockQty <= 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('Out of Stock', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                  )
                else if (inCart)
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
                        label: const Text('Remove from Cart'),
                        onPressed: () {
                          ref.read(cartProvider.notifier).removeItem(product.id);
                          setState(() => _qty = product.minQty.clamp(0, product.stockQty));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.shopping_cart),
                        label: const Text('View Cart'),
                        onPressed: () => context.push('/cart'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ])
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text('Add to Cart'),
                      onPressed: () {
                        ref.read(cartProvider.notifier).addItem(product, _qty);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${product.name} added to cart'),
                          action: SnackBarAction(label: 'View Cart', onPressed: () => context.push('/cart')),
                        ));
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
              ]),
            ),
          ),
        ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('product-detail', e); return Center(child: Text(friendlyError(e))); },
      ),
    );
  }
}
