import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:badges/badges.dart' as badges;
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/utils/error_handler.dart';
import '../admin/admin_tiers_screen.dart' show tierColor;

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

/// Fetches fresh user profile including tier info from backend
final customerProfileProvider = FutureProvider<AppUser?>((ref) async {
  try {
    final dio = ref.read(dioProvider);
    final res = await dio.get(Endpoints.me);
    return AppUser.fromJson(res.data['user']);
  } catch (_) {
    return null;
  }
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh user silently on open so tier/balance stays current
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    // authStateProvider.user already has tierName — set by _tryRestore via /me
    final user = ref.watch(authStateProvider).user;
    final categories = ref.watch(categoriesProvider);
    final featured = ref.watch(featuredProductsProvider);
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
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
              backgroundColor: AppColors.primary,
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

                // ── Verification nudge banners ─────────────────────────────
                if (user != null && !user.phoneVerified)
                  _VerifyBanner(
                    icon: Icons.phone_outlined,
                    message: 'Verify your phone number to access all features.',
                    color: Colors.orange,
                    onTap: () => context.push('/auth/verify?phone=${user.phone}&mode=customer'),
                  ),
                if (user != null && user.phoneVerified && user.email != null && !user.emailVerified)
                  _VerifyBanner(
                    icon: Icons.email_outlined,
                    message: 'Verify your email for free OTP logins.',
                    color: Colors.indigo,
                    onTap: () => context.push('/auth/verify-email?next=/home'),
                  ),

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

                // ── Tier card ──────────────────────────────────────────────
                if (user != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _TierCard(user: user!),
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
                            foregroundColor: AppColors.primary,
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
                  error: (e, _) {
                    logError('home', e);
                    return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(friendlyError(e), style: const TextStyle(color: Colors.red)));
                  },
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
                            foregroundColor: AppColors.primary,
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
                  error: (e, _) {
                    logError('home', e);
                    return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(friendlyError(e)));
                  },
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
    final firstName = user?.name.split(' ').first ?? 'there';
    final tierName = user?.tierName;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF43A047)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Logo row
        Row(children: [
          Image.asset('assets/images/logo.png', height: 38, width: 38, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🌿', style: TextStyle(fontSize: 20))),
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('HappyKrishi',
                style: TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.bold, letterSpacing: 0.3)),
            Text('Farm Fresh Delivery',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 10),
        // Greeting + tier badge
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('$greeting, $firstName 👋',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14, fontWeight: FontWeight.w500)),
          if (tierName != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.workspace_premium, size: 11, color: Colors.white),
                const SizedBox(width: 3),
                Text(tierName,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ]),
            ),
          ],
        ]),
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
                      imageUrl: cat.imageUrl != null && cat.imageUrl!.startsWith('http') ? cat.imageUrl! : Endpoints.imageUrl(cat.imageUrl),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) => Container(
                          color: const Color(0xFFEAF2EA),
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
    color: const Color(0xFFEAF2EA),
    child: Center(
      child: Text(cat.icon ?? cat.name.substring(0, 1).toUpperCase(),
          style: TextStyle(
              fontSize: cat.icon != null ? 28 : 22,
              color: AppColors.primary,
              fontWeight: FontWeight.bold)),
    ),
  );
}

// ── Product card ──────────────────────────────────────────────────────────────

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
                        imageUrl: Endpoints.imageUrl(p.imageUrl),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: const Color(0xFFEAF2EA),
                            child: const Center(child: Icon(Icons.eco,
                                color: AppColors.primary, size: 36))),
                        errorWidget: (context, url, error) => Container(
                            color: const Color(0xFFEAF2EA),
                            child: const Center(child: Icon(Icons.eco,
                                color: AppColors.primary, size: 36))),
                      )
                    : Container(
                        color: const Color(0xFFEAF2EA),
                        child: const Center(child: Icon(Icons.eco,
                            color: AppColors.primary, size: 36))),

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
                          color: AppColors.primary, shape: BoxShape.circle),
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
                  style: const TextStyle(color: AppColors.primary,
                      fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 2),
              // Stock info
              if (!outOfStock) Builder(builder: (_) {
                final low = p.stockQty <= p.lowStockThreshold;
                return Text(
                  low
                      ? 'Only ${p.stockQty.toStringAsFixed(p.stockQty.truncateToDouble() == p.stockQty ? 0 : 1)} ${p.unit} left!'
                      : '${p.stockQty.toStringAsFixed(p.stockQty.truncateToDouble() == p.stockQty ? 0 : 1)} ${p.unit} available',
                  style: TextStyle(
                    fontSize: 10,
                    color: low ? Colors.orange.shade700 : Colors.grey,
                    fontWeight: low ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }),

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
              else if (qty == 0)
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('ADD', style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.bold)),
                    onPressed: () {
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
                    color: const Color(0xFFEAF2EA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    _StepBtn(
                      icon: Icons.remove,
                      onTap: () {
                        final nq = qty - p.qtyStep;
                        if (nq < p.minQty) {
                          ref.read(cartProvider.notifier).removeItem(p.id);
                        } else {
                          ref.read(cartProvider.notifier).updateQty(p.id, nq);
                        }
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text('${qty.toStringAsFixed(1)} ${p.unit}',
                            style: const TextStyle(fontWeight: FontWeight.bold,
                                fontSize: 11, color: AppColors.primary)),
                      ),
                    ),
                    _StepBtn(
                      icon: Icons.add,
                      onTap: () {
                        final newQty = qty + p.qtyStep;
                        if (newQty > p.stockQty) return;
                        ref.read(cartProvider.notifier).updateQty(p.id, newQty);
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
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

// ── Tier card ─────────────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final AppUser user;
  const _TierCard({required this.user});

  @override
  Widget build(BuildContext context) {
    // Don't show anything while tier data is loading
    if (user.tierName == null) return const SizedBox.shrink();

    final tierName = user.tierName!;
    final tc = tierColor(user.tierColor);
    final isRestricted = tierName == 'Restricted';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _TierInfoSheet(currentTierName: tierName, currentTierColor: user.tierColor),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: tc.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tc.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: tc.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.workspace_premium, color: tc, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Membership Tier',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
            Text(tierName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: tc)),
            if (isRestricted)
              Text('Top up to ₹0 to restore ordering',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade600))
            else
              Text('Tap to see all tiers & benefits',
                  style: TextStyle(fontSize: 11, color: tc.withValues(alpha: 0.7))),
          ])),
          if (isRestricted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text('Orders blocked',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade700,
                      fontWeight: FontWeight.bold)),
            )
          else
            Icon(Icons.chevron_right, color: tc.withValues(alpha: 0.5), size: 20),
        ]),
      ),
    );
  }
}

// ── Tier info bottom sheet ─────────────────────────────────────────────────────

class _TierInfoSheet extends ConsumerStatefulWidget {
  final String currentTierName;
  final String? currentTierColor;
  const _TierInfoSheet({required this.currentTierName, this.currentTierColor});

  @override
  ConsumerState<_TierInfoSheet> createState() => _TierInfoSheetState();
}

class _TierInfoSheetState extends ConsumerState<_TierInfoSheet> {
  List<Map<String, dynamic>> _tiers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get(Endpoints.publicTiers);
      setState(() {
        _tiers = List<Map<String, dynamic>>.from(res.data['tiers'] as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.workspace_premium, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Membership Tiers',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Top up your wallet to qualify for higher tiers and enjoy more cashback.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
        const Divider(height: 1),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
        else
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: _tiers.length,
              itemBuilder: (_, i) {
                final t = _tiers[i];
                final name = t['name'] as String;
                final tc = tierColor(t['color'] as String?);
                final isRestricted = name == 'Restricted';
                final isCurrent = name == widget.currentTierName;
                final minBal = (t['min_wallet_balance'] as num).toDouble();
                final maxNeg = (t['max_wallet_negative_limit'] as num).toDouble();
                final mult = (t['cashback_multiplier'] as num).toDouble();

                if (isRestricted) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isCurrent ? tc.withValues(alpha: 0.08) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isCurrent ? tc : Colors.grey.shade200, width: isCurrent ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: tc.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(Icons.workspace_premium, color: tc, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: tc)),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: tc, borderRadius: BorderRadius.circular(8)),
                            child: const Text('Your Tier', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 5),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (minBal > 0)
                          _InfoChip('Wallet ≥ ₹${minBal.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined)
                        else
                          _InfoChip('No min balance', Icons.check_circle_outline),
                        _InfoChip('${mult.toStringAsFixed(1)}× cashback', Icons.card_giftcard_outlined),
                        if (maxNeg > 0)
                          _InfoChip('Credit up to -₹${maxNeg.toStringAsFixed(0)}', Icons.credit_card_outlined),
                      ]),
                    ])),
                  ]),
                );
              },
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2EA),
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, color: AppColors.primary, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Top up your wallet to upgrade. Tiers update automatically when your balance changes.',
                style: TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _InfoChip(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: Colors.grey.shade600),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
    ]),
  );
}

class _VerifyBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onTap;
  const _VerifyBanner({required this.icon, required this.message, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(message,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
            Icon(Icons.arrow_forward_ios, color: color, size: 12),
          ]),
        ),
      ),
    ),
  );
}
