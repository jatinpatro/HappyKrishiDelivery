import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminDashboard);
  return res.data['stats'] as Map<String, dynamic>;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardProvider);
    final user = ref.watch(authStateProvider).user;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F0),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2E7D32),
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: CustomScrollView(
            slivers: [

              // ── Header ──────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Image.asset('assets/images/logo.png', height: 40, width: 40, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(child: Text('🌿', style: TextStyle(fontSize: 20))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('HappyKrishi', style: TextStyle(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                        Text('Farm Dashboard', style: TextStyle(color: Colors.white60, fontSize: 11)),
                      ]),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.person_outline, color: Colors.white, size: 20),
                        tooltip: 'Edit Profile',
                        onPressed: () => context.push('/admin/profile'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: () => ref.invalidate(dashboardProvider),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                        onPressed: () {
                          ref.read(authStateProvider.notifier).logout();
                          context.go('/auth/otp');
                        },
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text('$greeting,', style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    Text(user?.name ?? 'Admin', style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),

                    const SizedBox(height: 20),

                    // Revenue hero card
                    stats.when(
                      data: (s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text("Today's Revenue",
                                style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('₹${(s['todays_revenue'] as num).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold)),
                          ]),
                          const Spacer(),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            _HeroBadge('${s['total_orders']}', 'orders today', Colors.white),
                            const SizedBox(height: 8),
                            _HeroBadge('${s['active_deliveries']}', 'in transit', Colors.white70),
                          ]),
                        ]),
                      ),
                      loading: () => const SizedBox(height: 70,
                          child: Center(child: CircularProgressIndicator(color: Colors.white54))),
                      error: (e, st) => const SizedBox.shrink(),
                    ),
                  ]),
                ),
              ),

              // ── Stats grid ───────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: stats.when(
                  data: (s) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const _SectionTitle('Overview'),
                      const SizedBox(height: 10),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.55,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: [
                          _StatCard(
                            label: 'Pending Orders',
                            value: '${s['pending_orders']}',
                            sub: 'need confirmation',
                            icon: Icons.hourglass_top_outlined,
                            color: const Color(0xFFE65100),
                            bgColor: const Color(0xFFFFF3E0),
                            onTap: () => context.go('/admin/orders'),
                            badge: (s['pending_orders'] as int) > 0,
                          ),
                          _StatCard(
                            label: 'Active Deliveries',
                            value: '${s['active_deliveries']}',
                            sub: 'assigned / picked',
                            icon: Icons.local_shipping_outlined,
                            color: const Color(0xFF6A1B9A),
                            bgColor: const Color(0xFFF3E5F5),
                            onTap: () => context.go('/admin/orders'),
                          ),
                          _StatCard(
                            label: 'Pending Top-ups',
                            value: '${s['pending_topups']}',
                            sub: 'awaiting approval',
                            icon: Icons.account_balance_wallet_outlined,
                            color: const Color(0xFFC62828),
                            bgColor: const Color(0xFFFFEBEE),
                            onTap: () => context.go('/admin/topup-requests'),
                            badge: (s['pending_topups'] as int) > 0,
                          ),
                          _StatCard(
                            label: 'Low Stock',
                            value: '${s['low_stock_products']}',
                            sub: 'products need restock',
                            icon: Icons.inventory_2_outlined,
                            color: const Color(0xFF558B2F),
                            bgColor: const Color(0xFFF9FBE7),
                            onTap: () => context.go('/admin/products'),
                            badge: (s['low_stock_products'] as int) > 0,
                          ),
                          _StatCard(
                            label: 'Custom Delivery',
                            value: '${s['pending_custom_delivery'] ?? 0}',
                            sub: 'requests pending',
                            icon: Icons.location_off_outlined,
                            color: const Color(0xFF00695C),
                            bgColor: const Color(0xFFE0F2F1),
                            onTap: () => context.go('/admin/custom-delivery'),
                            badge: (s['pending_custom_delivery'] as int? ?? 0) > 0,
                          ),
                        ],
                      ),
                    ]),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) {
                    logError('dashboard', e);
                    return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(child: Text(friendlyError(e), style: const TextStyle(fontSize: 13))),
                        TextButton(
                            onPressed: () => ref.invalidate(dashboardProvider),
                            child: const Text('Retry')),
                      ]),
                    ),
                  ); },
                ),
              ),

              // ── Quick actions ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: const _SectionTitle('Quick Actions'),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildListDelegate([
                    _ActionTile('Orders',    Icons.receipt_long,          const Color(0xFF1565C0), () => context.go('/admin/orders')),
                    _ActionTile('Products',  Icons.inventory_2_outlined,  const Color(0xFF2E7D32), () => context.go('/admin/products')),
                    _ActionTile('Customers', Icons.people_outline,        const Color(0xFF6A1B9A), () => context.go('/admin/customers')),
                    _ActionTile('Salesmen',  Icons.badge_outlined,        const Color(0xFFE65100), () => context.go('/admin/salesman')),
                    _ActionTile('Wallet',    Icons.account_balance_wallet, const Color(0xFF00695C), () => context.go('/admin/wallet-credit')),
                    _ActionTile('Top-ups',   Icons.pending_actions,       const Color(0xFFC62828), () => context.go('/admin/topup-requests')),
                    _ActionTile('Analytics', Icons.bar_chart,             const Color(0xFF1565C0), () => context.go('/admin/analytics')),
                    _ActionTile('Rewards',   Icons.card_giftcard,         const Color(0xFF880E4F), () => context.go('/admin/rewards')),
                    _ActionTile('Custom\nDelivery', Icons.location_off_outlined, const Color(0xFF00695C), () => context.go('/admin/custom-delivery')),
                    _ActionTile('Config',    Icons.settings_outlined,         Colors.blueGrey,         () => context.go('/admin/config')),
                    _ActionTile('Tiers',     Icons.workspace_premium_outlined, const Color(0xFF6A1B9A), () => context.go('/admin/tiers')),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String value, label;
  final Color color;
  const _HeroBadge(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
    Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
  ]);
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B5E20)));
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color, bgColor;
  final VoidCallback? onTap;
  final bool badge;
  const _StatCard({
    required this.label, required this.value, required this.sub,
    required this.icon, required this.color, required this.bgColor,
    this.onTap, this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 18),
              ),
              if (badge && value != '0')
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
              Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1.2),
                textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
