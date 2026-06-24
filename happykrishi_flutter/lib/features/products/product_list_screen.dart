import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../home/home_screen.dart' show categoriesProvider;
import '../../core/utils/error_handler.dart';

// Keep alive while browsing (inside ShellRoute) — refreshed by pull-to-refresh
final productListProvider =
    FutureProvider.family<List<Product>, String>((ref, key) async {
  final parts = key.split('|');
  final categoryId = parts[0].isEmpty ? null : parts[0];
  final search = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.products, queryParameters: {
    if (categoryId != null) 'category_id': categoryId,
    if (search != null) 'search': search,
    'limit': 50,
  });
  return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
});

class ProductListScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  const ProductListScreen({super.key, this.categoryId});
  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  String? _search;
  String? _selectedCategoryId;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.categoryId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerKey = '${_selectedCategoryId ?? ''}|${_search ?? ''}';
    final products = ref.watch(productListProvider(providerKey));
    final categories = ref.watch(categoriesProvider);
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
          if (cartCount > 0)
            Stack(alignment: Alignment.topRight, children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: () => context.push('/cart'),
              ),
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.orange, shape: BoxShape.circle),
                  child: Text('$cartCount',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
        ],
      ),
      body: Column(children: [
        // ── Search + category chips ──────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Search bar
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.isEmpty ? null : v),
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = null);
                        })
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              ),
            ),
            const SizedBox(height: 10),
            // Category chips
            categories.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
              data: (cats) => cats.isEmpty
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _CatChip(
                          label: 'All',
                          selected: _selectedCategoryId == null,
                          onTap: () => setState(() => _selectedCategoryId = null),
                        ),
                        const SizedBox(width: 6),
                        ...cats.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _CatChip(
                            label: c.name,
                            selected: _selectedCategoryId == c.id.toString(),
                            onTap: () => setState(() =>
                                _selectedCategoryId = _selectedCategoryId == c.id.toString()
                                    ? null
                                    : c.id.toString()),
                          ),
                        )),
                      ]),
                    ),
            ),
            const SizedBox(height: 10),
          ]),
        ),
        const Divider(height: 1),

        Expanded(
          child: products.when(
            data: (prods) => prods.isEmpty
                ? Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _search != null
                            ? 'No results for "$_search"'
                            : 'No products available',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(productListProvider(providerKey)),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.78,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: prods.length,
                      itemBuilder: (_, i) => _ProductCard(product: prods[i]),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) { logError('products', e); return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(height: 8),
                Text(friendlyError(e)),
                TextButton(
                  onPressed: () => ref.invalidate(productListProvider(providerKey)),
                  child: const Text('Retry'),
                ),
              ]),
            ); },
          ),
        ),
      ]),

      // Floating cart button when items in cart
      floatingActionButton: cartCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              backgroundColor: const Color(0xFF2E7D32),
              icon: const Icon(Icons.shopping_cart, color: Colors.white),
              label: Text('Cart ($cartCount)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

// ── Product card with inline add-to-cart (same as home screen) ───────────────

class _ProductCard extends ConsumerWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final cartItems = ref.watch(cartProvider);
    final cartItem = cartItems.where((i) => i.product.id == p.id).firstOrNull;
    final qty = cartItem?.qty ?? 0.0;
    final inCart = cartItem != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: GestureDetector(
            onTap: () => context.go('/products/${p.id}'),
            child: Stack(fit: StackFit.expand, children: [
              p.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: '${Endpoints.baseUrl}${p.imageUrl}',
                      fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFFE8F5E9),
                      child: const Center(
                          child: Icon(Icons.eco, size: 40, color: Color(0xFF2E7D32)))),
              if (p.isWeightAdjusted)
                Positioned(
                  top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('⚖️',
                        style: TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ),
              if (inCart)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32), shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 12),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => context.go('/products/${p.id}'),
              child: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('₹${p.pricePerUnit}/${p.unit}',
                style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            // Stock info
            if (p.stockQty > 0) Builder(builder: (_) {
              final low = p.stockQty <= p.lowStockThreshold;
              return Text(
                low
                    ? 'Only ${p.stockQty.toStringAsFixed(p.stockQty.truncateToDouble() == p.stockQty ? 0 : 1)} ${p.unit} left!'
                    : '${p.stockQty.toStringAsFixed(p.stockQty.truncateToDouble() == p.stockQty ? 0 : 1)} ${p.unit}',
                style: TextStyle(
                  fontSize: 10,
                  color: low ? Colors.orange.shade700 : Colors.grey,
                  fontWeight: low ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }),
            const SizedBox(height: 6),
            if (p.stockQty <= 0)
              const Center(
                child: Text('Out of Stock',
                    style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
              )
            else if (qty == 0)
              SizedBox(
                width: double.infinity,
                height: 30,
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(cartProvider.notifier).addItem(p, p.minQty);
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${p.name} added'),
                      duration: const Duration(seconds: 1),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('ADD', style: TextStyle(fontSize: 12)),
                ),
              )
            else
              Row(children: [
                _StepBtn(
                  icon: Icons.remove,
                  onTap: () {
                    final n = qty - p.qtyStep;
                    if (n < p.minQty) {
                      ref.read(cartProvider.notifier).removeItem(p.id);
                    } else {
                      ref.read(cartProvider.notifier).updateQty(p.id, n);
                    }
                  },
                ),
                Expanded(
                  child: Center(
                    child: Text('${qty.toStringAsFixed(1)} ${p.unit}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                _StepBtn(
                  icon: Icons.add,
                  onTap: () {
                    final n = qty + p.qtyStep;
                    if (n > p.stockQty) return;
                    ref.read(cartProvider.notifier).updateQty(p.id, n);
                  },
                ),
              ]),
          ]),
        ),
      ]),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF2E7D32);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
