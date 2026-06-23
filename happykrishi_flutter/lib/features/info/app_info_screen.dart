import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';

// Public — no auth needed
final appInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.appInfo);
  return res.data as Map<String, dynamic>;
});

/// Compact banner showing delivery charge rules — use in cart/checkout
class DeliveryInfoBanner extends ConsumerWidget {
  final double? subtotal;
  const DeliveryInfoBanner({super.key, this.subtotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    return info.when(
      data: (data) {
        final delivery = data['delivery'] as Map<String, dynamic>;
        final freeAbove = (delivery['free_above'] as num).toDouble();
        final baseCharge = (delivery['base_charge'] as num).toDouble();
        final remaining = subtotal != null ? freeAbove - subtotal! : null;
        final isFree = subtotal != null && subtotal! >= freeAbove;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isFree ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFree ? const Color(0xFF2E7D32) : Colors.orange.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              isFree ? Icons.local_shipping : Icons.info_outline,
              color: isFree ? const Color(0xFF2E7D32) : Colors.orange.shade700,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isFree
                  ? const Text(
                      'You qualify for FREE delivery! 🎉',
                      style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    )
                  : remaining != null
                      ? Text(
                          'Add ₹${remaining.toStringAsFixed(0)} more for FREE delivery (₹$freeAbove+). Delivery charge: ₹${baseCharge.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: Colors.orange.shade800, fontSize: 12),
                        )
                      : Text(
                          'Free delivery on orders ₹$freeAbove+. Delivery charge: ₹${baseCharge.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: Colors.orange.shade800, fontSize: 12),
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
      appBar: AppBar(title: const Text('About & Contact')),
      body: info.when(
        data: (data) {
          final delivery = data['delivery'] as Map<String, dynamic>;
          final contact = data['contact'] as Map<String, dynamic>;
          final farm = data['farm'] as Map<String, dynamic>;

          return ListView(padding: const EdgeInsets.all(16), children: [
            // Farm info card
            _InfoCard(
              icon: Icons.agriculture,
              iconColor: const Color(0xFF2E7D32),
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
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.icon, required this.iconColor, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 20),
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
          Icon(icon, size: 18, color: color ?? const Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? const Color(0xFF2E7D32))),
          ]),
          const Spacer(),
          const Icon(Icons.copy, size: 14, color: Colors.grey),
        ]),
      ),
    );
  }
}
