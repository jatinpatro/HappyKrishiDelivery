import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

// Public — no auth needed
final appInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.appInfo);
  return res.data as Map<String, dynamic>;
});

/// Compact banner showing delivery charge rules — use in cart/checkout.
/// If [fetchedCharge] is provided (pincode-resolved from backend), it takes
/// precedence over the global free_delivery_above threshold for the free check.
class DeliveryInfoBanner extends ConsumerWidget {
  final double? subtotal;

  /// Actual delivery charge fetched from the backend for the selected address.
  /// When provided, shows pincode-aware free delivery status instead of the
  /// global threshold.
  final double? fetchedCharge;

  const DeliveryInfoBanner({super.key, this.subtotal, this.fetchedCharge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    return info.when(
      data: (data) {
        final delivery = data['delivery'] as Map<String, dynamic>;
        final freeAbove = (delivery['free_above'] as num).toDouble();
        final baseCharge = (delivery['base_charge'] as num).toDouble();

        // If we have a pincode-resolved charge, use that to determine free status.
        // Otherwise fall back to the global threshold.
        final bool isFree;
        final String message;
        if (fetchedCharge != null) {
          isFree = fetchedCharge == 0;
          if (isFree) {
            message = 'You qualify for FREE delivery! 🎉';
          } else {
            final remaining = subtotal != null ? freeAbove - subtotal! : null;
            message = remaining != null && remaining > 0
                ? 'Add ₹${remaining.toStringAsFixed(0)} more for FREE delivery. Delivery charge: ₹${fetchedCharge!.toStringAsFixed(0)}'
                : 'Delivery charge for your area: ₹${fetchedCharge!.toStringAsFixed(0)}';
          }
        } else {
          final remaining = subtotal != null ? freeAbove - subtotal! : null;
          isFree = subtotal != null && subtotal! >= freeAbove;
          if (isFree) {
            message = 'You qualify for FREE delivery! 🎉';
          } else if (remaining != null) {
            message = 'Add ₹${remaining.toStringAsFixed(0)} more for FREE delivery (₹$freeAbove+). Delivery charge: ₹${baseCharge.toStringAsFixed(0)}';
          } else {
            message = 'Free delivery on orders ₹$freeAbove+. Delivery charge: ₹${baseCharge.toStringAsFixed(0)}';
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isFree ? const Color(0xFFEAF2EA) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFree ? AppColors.primary : Colors.orange.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              isFree ? Icons.local_shipping : Icons.info_outline,
              color: isFree ? AppColors.primary : Colors.orange.shade700,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isFree ? AppColors.primary : Colors.orange.shade800,
                  fontWeight: isFree ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ]),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Full info screen — contact + delivery rules
class AppInfoScreen extends ConsumerWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About & Contact'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: info.when(
        data: (data) {
          final delivery = data['delivery'] as Map<String, dynamic>;
          final contact = data['contact'] as Map<String, dynamic>;
          final farm = data['farm'] as Map<String, dynamic>;

          return ListView(padding: const EdgeInsets.all(16), children: [
            // Logo banner
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.agriculture, size: 80, color: AppColors.primary),
                  ),
                  const SizedBox(height: 10),
                  const Text('HappyKrishi',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                          color: AppColors.primary, letterSpacing: 0.5)),
                  const Text('Farm Fresh Delivery',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            // Farm info card
            _InfoCard(
              iconWidget: Image.asset('assets/images/logo.png', height: 20, width: 20,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.agriculture, color: AppColors.primary, size: 20)),
              iconColor: AppColors.primary,
              title: farm['name'] as String? ?? 'HappyKrishi',
              children: [
                if ((farm['address'] as String? ?? '').isNotEmpty)
                  _InfoRow(Icons.location_on, farm['address'] as String),
                if ((contact['working_hours'] as String? ?? '').isNotEmpty)
                  _InfoRow(Icons.access_time, contact['working_hours'] as String),
              ],
            ),
            const SizedBox(height: 12),

            // Contact card
            _InfoCard(
              icon: Icons.contact_support,
              iconColor: Colors.blue,
              title: 'Contact Us',
              children: [
                if ((contact['phone'] as String? ?? '').isNotEmpty)
                  _ContactRow(
                    icon: Icons.phone,
                    label: 'Call us',
                    value: '+91 ${contact['phone']}',
                    onTap: () => _copyToClipboard(context, contact['phone'] as String),
                  ),
                if ((contact['whatsapp'] as String? ?? '').isNotEmpty)
                  _ContactRow(
                    icon: Icons.chat,
                    label: 'WhatsApp',
                    value: '+91 ${contact['whatsapp']}',
                    onTap: () => _copyToClipboard(context, contact['whatsapp'] as String),
                    color: const Color(0xFF25D366),
                  ),
                if ((contact['email'] as String? ?? '').isNotEmpty)
                  _ContactRow(
                    icon: Icons.email,
                    label: 'Email',
                    value: contact['email'] as String,
                    onTap: () => _copyToClipboard(context, contact['email'] as String),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Delivery rules card
            _InfoCard(
              icon: Icons.local_shipping,
              iconColor: Colors.orange,
              title: 'Delivery Info',
              children: [
                _InfoRow(Icons.check_circle_outline,
                    'Free delivery on orders above ₹${(delivery['free_above'] as num).toStringAsFixed(0)}'),
                _InfoRow(Icons.currency_rupee,
                    'Delivery charge: ₹${(delivery['base_charge'] as num).toStringAsFixed(0)} base + ₹${(delivery['charge_per_km'] as num).toStringAsFixed(0)}/km'),
                _InfoRow(Icons.shopping_bag_outlined,
                    'Minimum order: ₹${(delivery['min_order'] as num).toStringAsFixed(0)}'),
                _InfoRow(Icons.account_balance_wallet_outlined,
                    'Minimum wallet balance to order: ₹${(delivery['min_wallet'] as num).toStringAsFixed(0)}'),
              ],
            ),
            const SizedBox(height: 12),

            // Slots info
            _InfoCard(
              icon: Icons.schedule,
              iconColor: Colors.purple,
              title: 'Delivery Slots',
              children: [
                _InfoRow(Icons.wb_sunny_outlined, 'Morning: 7:00 AM – 10:00 AM'),
                _InfoRow(Icons.lunch_dining, 'Afternoon: 12:00 PM – 3:00 PM'),
                _InfoRow(Icons.nights_stay_outlined, 'Evening: 5:00 PM – 8:00 PM'),
              ],
            ),
            const SizedBox(height: 12),

            // Policy note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Orders cannot be cancelled within 1 day of delivery. For help, please contact us via phone or WhatsApp.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

            // Download APK banner (web only)
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.android, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('Get the Android App',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Better experience — faster & works offline',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download APK',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => launchUrl(
                        Uri.parse('https://delivery.happykrishi.com/happykrishi-delivery.apk'),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          logError('app-info', e);
          return Center(child: Text(friendlyError(e)));
        },
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$text copied'), duration: const Duration(seconds: 1)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final Color iconColor;
  final String title;
  final List<Widget> children;
  const _InfoCard({this.icon, this.iconWidget, required this.iconColor, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            iconWidget ?? Icon(icon ?? Icons.info, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 16),
          ...children,
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? color;
  const _ContactRow({required this.icon, required this.label, required this.value, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: color ?? AppColors.primary),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? AppColors.primary)),
          ]),
          const Spacer(),
          const Icon(Icons.copy, size: 14, color: Colors.grey),
        ]),
      ),
    );
  }
}
