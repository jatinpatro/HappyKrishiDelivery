import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../api/dio_client.dart' show readTokenSync;
import '../../features/auth/otp_screen.dart';
import '../../features/auth/verify_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/admin_login_screen.dart';
import '../../features/auth/email_signup_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/products/product_list_screen.dart';
import '../../features/products/product_detail_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/checkout/checkout_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/orders/order_detail_screen.dart';
import '../../features/tracking/tracking_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../../features/wallet/topup_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/admin/dashboard_screen.dart';
import '../../features/admin/admin_orders_screen.dart';
import '../../features/admin/admin_products_screen.dart';
import '../../features/admin/admin_promo_codes_screen.dart';
import '../../features/admin/wallet_credit_screen.dart';
import '../../features/admin/config_screen.dart';
import '../../features/admin/topup_requests_screen.dart';
import '../../features/admin/analytics_screen.dart';
import '../../features/admin/rewards_screen.dart';
import '../../features/admin/admin_customers_screen.dart';
import '../../features/admin/admin_tiers_screen.dart';
import '../../features/admin/salesman_screen.dart';
import '../../features/admin/admin_custom_delivery_screen.dart';
import '../../features/admin/admin_live_map_screen.dart';
import '../../features/admin/admin_profile_screen.dart';
import '../../features/admin/admin_referrals_screen.dart';
import '../../features/admin/admin_money_screen.dart';
import '../../features/referral/referral_screen.dart';
import '../../features/salesman/salesman_money_screen.dart';
import '../../features/checkout/custom_delivery_request_screen.dart';
import '../../features/salesman/salesman_dashboard_screen.dart';
import '../../features/info/app_info_screen.dart';
import '../../features/auth/set_password_screen.dart';
import '../../features/auth/change_password_screen.dart';

// Bridges Riverpod authStateProvider → GoRouter refreshListenable
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (prev?.user != null && next.user == null) notifyListeners();
    });
  }
}

// Single GoRouter instance — no refreshListenable, navigation is explicit in each screen
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  // Protected routes that require a logged-in user
  const protectedPrefixes = [
    '/home', '/products', '/cart', '/checkout', '/orders',
    '/track/', '/wallet', '/profile', '/notifications', '/request-delivery',
    '/info',
    '/admin/', '/salesman/',
  ];

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final token = readTokenSync();
      final loc = state.uri.toString();

      // If no token and trying to access a protected route → send to login
      if (token == null) {
        final isProtected = protectedPrefixes.any((p) => loc.startsWith(p));
        if (isProtected) return '/auth/otp';
      }
      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/auth/otp', builder: (_, _) => const OtpScreen()),
      GoRoute(path: '/auth/verify', builder: (_, s) => VerifyScreen(
        phone: s.uri.queryParameters['phone'] ?? '',
        mode: s.uri.queryParameters['mode'] ?? 'default',
      )),
      GoRoute(path: '/auth/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/auth/admin', builder: (_, _) => const AdminLoginScreen()),
      GoRoute(path: '/auth/set-password', builder: (_, _) => const SetPasswordScreen()),
      GoRoute(path: '/auth/change-password', builder: (_, _) => const ChangePasswordScreen()),
      GoRoute(path: '/auth/signup', builder: (_, _) => const EmailSignupScreen()),

      ShellRoute(
        builder: (context, state, child) => CustomerShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/products', builder: (_, s) => ProductListScreen(categoryId: s.uri.queryParameters['category_id'])),
          GoRoute(path: '/products/:id', builder: (_, s) => ProductDetailScreen(productId: int.parse(s.pathParameters['id']!))),
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
          GoRoute(path: '/orders', builder: (_, _) => const OrderListScreen()),
          GoRoute(path: '/orders/:id', builder: (_, s) => OrderDetailScreen(orderId: int.parse(s.pathParameters['id']!))),
          GoRoute(path: '/track/:id', builder: (_, s) => TrackingScreen(orderId: int.parse(s.pathParameters['id']!))),
          GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
          GoRoute(path: '/wallet/topup', builder: (_, _) => const TopupScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
        ],
      ),

      GoRoute(path: '/admin/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/admin/orders', builder: (_, _) => const AdminOrdersScreen()),
      GoRoute(path: '/admin/products', builder: (_, _) => const AdminProductsScreen()),
      GoRoute(path: '/admin/wallet-credit', builder: (_, _) => const WalletCreditScreen()),
      GoRoute(path: '/admin/config', builder: (_, _) => const ConfigScreen()),
      GoRoute(path: '/admin/topup-requests', builder: (_, _) => const TopupRequestsScreen()),
      GoRoute(path: '/admin/analytics', builder: (_, _) => const AdminAnalyticsScreen()),
      GoRoute(path: '/admin/rewards', builder: (_, _) => const RewardsScreen()),
      GoRoute(path: '/admin/salesman', builder: (_, _) => const SalesmanScreen()),
      GoRoute(path: '/admin/customers', builder: (_, _) => const AdminCustomersScreen()),
      GoRoute(path: '/admin/tiers', builder: (_, _) => const AdminTiersScreen()),
      GoRoute(path: '/admin/custom-delivery', builder: (ctx, s) => const AdminCustomDeliveryScreen()),
      GoRoute(path: '/admin/profile', builder: (ctx, s) => const AdminProfileScreen()),
      GoRoute(path: '/admin/live-map', builder: (ctx, s) => const AdminLiveMapScreen()),
      GoRoute(path: '/admin/track/:id', builder: (_, s) => TrackingScreen(
        orderId: int.parse(s.pathParameters['id']!),
        shareLocation: false,
      )),
      GoRoute(path: '/salesman/track/:id', builder: (_, s) => TrackingScreen(
        orderId: int.parse(s.pathParameters['id']!),
        shareLocation: false,
      )),
      GoRoute(path: '/admin/referrals', builder: (ctx, s) => const AdminReferralsScreen()),
      GoRoute(path: '/admin/promo-codes', builder: (_, _) => const AdminPromoCodesScreen()),
      GoRoute(path: '/admin/money', builder: (ctx, s) => const AdminMoneyScreen()),
      GoRoute(path: '/salesman/money', builder: (ctx, s) => const SalesmanMoneyScreen()),
      GoRoute(path: '/referral', builder: (ctx, s) => const ReferralScreen()),

      GoRoute(
        path: '/request-delivery',
        builder: (_, s) => CustomDeliveryRequestScreen(
          prefillPincode: s.uri.queryParameters['pincode'],
          distanceKm: s.uri.queryParameters['distance_km'] != null
              ? double.tryParse(s.uri.queryParameters['distance_km']!)
              : null,
        ),
      ),

      GoRoute(path: '/salesman', builder: (_, _) => const SalesmanDashboardScreen()),
      GoRoute(path: '/salesman/orders/:id', builder: (_, s) => OrderDetailScreen(
        orderId: int.parse(s.pathParameters['id']!),
      )),
      GoRoute(path: '/info', builder: (_, _) => const AppInfoScreen()),
    ],
  );
});

// Splash: waits for auth restore, then navigates once
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // If already initialized at build time, navigate on the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authStateProvider);
      if (auth.isInitialized && !_navigated) _navigate(auth);
    });
  }

  void _navigate(AuthState auth) {
    if (_navigated || !mounted) return;
    _navigated = true;
    final user = auth.user;
    if (user == null) {
      context.go('/auth/otp');
    } else if (user.role == 'admin' || user.role == 'subadmin') {
      context.go('/admin/dashboard');
    } else if (user.role == 'salesman') {
      context.go('/salesman');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Also listen in case auth restore finishes after build
    ref.listen<AuthState>(authStateProvider, (_, next) {
      if (next.isInitialized) _navigate(next);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.agriculture, size: 80, color: Color(0xFF2E7D32)),
          const SizedBox(height: 16),
          const Text('HappyKrishi',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          const Text('Farm Fresh Delivery',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 40),
          const CircularProgressIndicator(color: Color(0xFF2E7D32)),
        ]),
      ),
    );
  }
}

class CustomerShell extends ConsumerWidget {
  final Widget child;
  const CustomerShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _navIndex(location);
    final user = ref.watch(authStateProvider).user;
    final isNonCustomer = user != null &&
        (user.role == 'admin' || user.role == 'subadmin' || user.role == 'salesman');

    // Admin/salesman who ended up in the customer shell — show back button instead of bottom nav
    if (isNonCustomer) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Dashboard',
            onPressed: () {
              if (user.role == 'salesman') {
                context.go('/salesman');
              } else {
                context.go('/admin/dashboard');
              }
            },
          ),
          title: Text(user.role == 'salesman' ? 'Customer View' : 'Admin — Customer View'),
          backgroundColor: user.role == 'salesman' ? Colors.orange.shade700 : Colors.indigo,
        ),
        body: child,
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: idx >= 0
          ? NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) {
                const routes = ['/home', '/orders', '/wallet', '/profile'];
                context.go(routes[i]);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
                NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
            )
          : null,
    );
  }

  int _navIndex(String loc) {
    if (loc.startsWith('/home') || loc.startsWith('/products')) return 0;
    if (loc.startsWith('/orders') || loc.startsWith('/track')) return 1;
    if (loc.startsWith('/wallet')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return -1;
  }
}
