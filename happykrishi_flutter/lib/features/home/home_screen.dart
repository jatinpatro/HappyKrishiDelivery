import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:badges/badges.dart' as badges;
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.categories);
  return (res.data['categories'] as List).map((e) => Category.fromJson(e)).toList();
});

final featuredProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.products, queryParameters: {'limit': 8});
  return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final categories = ref.watch(categoriesProvider);
    final featured = ref.watch(featuredProductsProvider);
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: RefreshIndicator(
        color: const Color(0xFF2E7D32),
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(featuredProductsProvider);
          await ref.read(authStateProvider.notifier).refreshUser();
        },
        child: CustomScrollView(
          slivers: [
            // ── App bar ──────────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 140,
              floating: true,
              snap: true,
              pinned: false,
              backgroundColor: const Color(0xFF2E7D32),
              flexibleSpace: FlexibleSpaceBar(
                background: _HomeHeader(user: user),
              ),
              actions: [
                badges.Badge(
                  badgeContent: Text('$cartCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                  showBadge: cartCount > 0,
                  position: badges.BadgePosition.topEnd(top: 4, end: 4),
                  child: IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                    onPressed: () => context.push('/cart'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                  onPressed: () => context.go('/notifications'),
                ),
                const SizedBox(width: 4),
              ],
            ),

            SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Search bar ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: GestureDetector(
                    onTap: () => context.go('/products'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(children: [
                        const Icon(Icons.search, color: Colors.grey, size: 20),
                        const SizedBox(width: 10),
                        Text('Search vegetables, dairy, fish…',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                      ]),
                    ),
                  ),
                ),

                // ── Wallet banner ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _WalletBanner(user: user),
                ),

                // ── Categories ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Shop by Category',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      TextButton(
                        onPressed: () => context.go('/products'),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero),
                        child: const Text('All Products →', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),

                categories.when(
                  loading: () => const SizedBox(
                      height: 120, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
                  data: (cats) => cats.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('No categories yet'))
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.82,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: cats.length,
                            itemBuilder: (_, i) => _CategoryCard(cat: cats[i]),
                          ),
                        ),
                ),

                // ── Featured products ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Fresh Today',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      TextButton(
                        onPressed: () => context.go('/products'),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero),
                        child: const Text('See all →', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),

                featured.when(
                  loading: () => const SizedBox(
                      height: 200, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Error: $e')),
                  data: (prods) => prods.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No products available',
                              style: TextStyle(color: Colors.grey))))
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.76,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: prods.length,
                            itemBuilder: (_, i) => _ProductCard(product: prods[i]),
                          ),
                        ),
                ),

                const SizedBox(height: 100),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header (inside SliverAppBar flexibleSpace) ────────────────────────────────

class _HomeHeader extends StatelessWidget {
  final AppUser? user;
  const _HomeHeader({this.user});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🌿', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('HappyKrishi',
                style: const TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.bold, letterSpacing: 0.3)),
            Text('Farm Fresh Delivery',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 10),
        Text('$greeting, ${user?.name.split(' ').first ?? 'there'} 👋',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.95),
                fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ── Wallet banner ─────────────────────────────────────────────────────────────

class _WalletBanner extends ConsumerWidget {
  final AppUser? user;
  const _WalletBanner({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNegative = (user?.walletBalance ?? 0) < 0;
    return GestureDetector(
      onTap: () => context.go('/wallet'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isNegative
                ? [const Color(0xFFC62828), const Color(0xFFE53935), const Color(0xFFEF5350)]
                : [const Color(0xFF1565C0), const Color(0xFF1976D2), const Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: (isNegative ? const Color(0xFFC62828) : const Color(0xFF1565C0))
                    .withValues(alpha: 0.35),
                blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNegative ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isNegative ? 'Balance Overdue' : 'Wallet Balance',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            Text('₹${user?.walletBalance.toStringAsFixed(2) ?? '0.00'}',
                style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold)),
            if (isNegative)
              Text('Top up to place new orders',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Text(isNegative ? 'Top Up' : 'Add Money',
                style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final Category cat;
  const _CategoryCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/products?category_id=${cat.id}'),
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: cat.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: '${Endpoints.baseUrl}${cat.imageUrl}',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) => Container(
                          color: const Color(0xFFE8F5E9),
                          child: const Center(
                              child: Icon(Icons.image_outlined,
                                  color: Colors.grey, size: 24))),
                      errorWidget: (context, url, error) => _fallbackAvatar(cat),
                    )
                  : _fallbackAvatar(cat),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          cat.name,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: Color(0xFF333333)),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }

  Widget _fallbackAvatar(Category cat) => Container(
    color: const Color(0xFFE8F5E9),
    child: Center(
      child: Text(cat.icon ?? cat.name.substring(0, 1).toUpperCase(),
          style: TextStyle(
              fontSize: cat.icon != null ? 28 : 22,
              color: const Color(0xFF2E7D32),
              fontWeight: FontWeight.bold)),
    ),
  );
}

// ── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerStatefulWidget {
  final Product product;
  const _ProductCard({required this.product});
  @override
  ConsumerState<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<_ProductCard> {
  double _qty = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final inCart = ref.watch(cartProvider).any((i) => i.product.id == p.id);
    final outOfStock = p.stockQty <= 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          Expanded(
            child: GestureDetector(
              onTap: () => context.go('/products/${p.id}'),
              child: Stack(fit: StackFit.expand, children: [
                p.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: '${Endpoints.baseUrl}${p.imageUrl}',
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: const Color(0xFFE8F5E9),
                            child: const Center(child: Icon(Icons.eco,
                                color: Color(0xFF2E7D32), size: 36))),
                        errorWidget: (context, url, error) => Container(
                            color: const Color(0xFFE8F5E9),
                            child: const Center(child: Icon(Icons.eco,
                                color: Color(0xFF2E7D32), size: 36))),
                      )
                    : Container(
                        color: const Color(0xFFE8F5E9),
                        child: const Center(child: Icon(Icons.eco,
                            color: Color(0xFF2E7D32), size: 36))),

                // Out of stock overlay
                if (outOfStock)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(
                        child: Text('Out of\nStock',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold, fontSize: 13))),
                  ),

                // Badges
                if (p.isWeightAdjusted && !outOfStock)
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('⚖️ Weighed',
                          style: TextStyle(fontSize: 9, color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),

                if (inCart && !outOfStock)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      width: 22, height: 22,
                      decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32), shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 13),
                    ),
                  ),
              ]),
            ),
          ),

          // Info + cart
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => context.go('/products/${p.id}'),
                child: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 2),
              Text('₹${p.pricePerUnit}/${p.unit}',
                  style: const TextStyle(color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 7),

              if (outOfStock)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Center(
                      child: Text('Out of Stock',
                          style: TextStyle(color: Colors.red, fontSize: 11,
                              fontWeight: FontWeight.w600))),
                )
              else if (_qty == 0)
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('ADD', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() => _qty = p.minQty);
                      ref.read(cartProvider.notifier).addItem(p, p.minQty);
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('${p.name} added to cart'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ));
                    },
                    style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                  ),
                )
              else
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    _StepBtn(
                      icon: Icons.remove,
                      onTap: () {
                        final nq = _qty - p.qtyStep;
                        if (nq < p.minQty) {
                          setState(() => _qty = 0);
                          ref.read(cartProvider.notifier).removeItem(p.id);
                        } else {
                          setState(() => _qty = nq);
                          ref.read(cartProvider.notifier).updateQty(p.id, nq);
                        }
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text('${_qty.toStringAsFixed(1)} ${p.unit}',
                            style: const TextStyle(fontWeight: FontWeight.bold,
                                fontSize: 11, color: Color(0xFF2E7D32))),
                      ),
                    ),
                    _StepBtn(
                      icon: Icons.add,
                      onTap: () {
                        setState(() => _qty = _qty + p.qtyStep);
                        ref.read(cartProvider.notifier).updateQty(p.id, _qty);
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
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
        width: 30, height: 32,
        decoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}
