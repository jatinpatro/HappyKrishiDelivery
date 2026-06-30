import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';

final myCustomDeliveryRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.myCustomDeliveryRequests);
  return List<Map<String, dynamic>>.from(res.data['requests']);
});

class CustomDeliveryRequestScreen extends ConsumerStatefulWidget {
  final String? prefillPincode;
  final double? distanceKm;
  const CustomDeliveryRequestScreen({super.key, this.prefillPincode, this.distanceKm});

  @override
  ConsumerState<CustomDeliveryRequestScreen> createState() =>
      _CustomDeliveryRequestScreenState();
}

class _CustomDeliveryRequestScreenState
    extends ConsumerState<CustomDeliveryRequestScreen> {
  final _pincodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillPincode != null) {
      _pincodeCtrl.text = widget.prefillPincode!;
    }
  }

  @override
  void dispose() {
    _pincodeCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pincodeCtrl.text.trim().length != 6) {
      _show('Enter a valid 6-digit pincode');
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _show('Please enter your address');
      return;
    }
    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.customDeliveryRequests, data: {
        'pincode': _pincodeCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      ref.invalidate(myCustomDeliveryRequestsProvider);
      if (mounted) setState(() => _submitted = true);
    } on DioException catch (e) {
      _show(e.response?.data['error'] ?? 'Failed to submit request');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final myRequests = ref.watch(myCustomDeliveryRequestsProvider);
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Custom Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.location_off_outlined, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.distanceKm != null
                        ? 'Your area is ${widget.distanceKm} km away — outside our 20 km standard delivery zone.'
                        : 'This pincode is outside our standard 20 km delivery zone.',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'We can still try to arrange delivery for you! Submit a request and our team will review it and contact you within 24 hours.',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2EA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                const Icon(Icons.check_circle, color: AppColors.primary, size: 48),
                const SizedBox(height: 12),
                const Text('Request Submitted!',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 8),
                Text(
                  'We\'ll review your request and contact you at +91 ${user?.phone ?? ''} within 24 hours.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ]),
            ),
            const SizedBox(height: 20),
          ] else ...[
            const Text('Your Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            // Pincode
            TextField(
              controller: _pincodeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Pincode *',
                prefixIcon: Icon(Icons.location_pin),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),

            // Address
            TextField(
              controller: _addressCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Full Address *',
                prefixIcon: Icon(Icons.home_outlined),
                border: OutlineInputBorder(),
                hintText: 'House no., street, village/town',
              ),
            ),
            const SizedBox(height: 12),

            // Note
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Additional Note (optional)',
                prefixIcon: Icon(Icons.note_outlined),
                border: OutlineInputBorder(),
                hintText: 'e.g. preferred delivery days, landmark, etc.',
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label:
                  Text(_submitting ? 'Submitting…' : 'Submit Delivery Request'),
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Our team will call you to confirm and quote a delivery charge.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Past requests
          const SizedBox(height: 32),
          const Text('My Requests',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          myRequests.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              logError('custom-delivery-request', e);
              return Text(friendlyError(e));
            },
            data: (reqs) => reqs.isEmpty
                ? const Text('No requests yet.', style: TextStyle(color: Colors.grey))
                : Column(
                    children: reqs.map((r) => _RequestTile(request: r)).toList()),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  const _RequestTile({required this.request});
  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _resubmitting = false;

  Future<void> _resubmit() async {
    final pincode = widget.request['pincode'] as String;
    final address = widget.request['address'] as String;
    final noteCtrl = TextEditingController(text: widget.request['note'] as String? ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Again'),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pincode: $pincode',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(address, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Add more details to help us approve',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Submit Again'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resubmitting = true);
    try {
      await ref.read(dioProvider).post(Endpoints.customDeliveryRequests, data: {
        'pincode': pincode,
        'address': address,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });
      ref.invalidate(myCustomDeliveryRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request submitted again ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to submit')));
      }
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status   = widget.request['status'] as String;
    final pincode  = widget.request['pincode'] as String;
    final address  = widget.request['address'] as String;
    final note     = widget.request['note'] as String?;
    final adminNote = widget.request['admin_note'] as String?;
    final date     = (widget.request['created_at'] as String).substring(0, 10);
    final distKm   = widget.request['distance_km'] as num?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.location_pin, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text('Pincode: $pincode',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (distKm != null) ...[
              const SizedBox(width: 6),
              Text('(${distKm}km)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(address, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text('Note: $note', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (adminNote != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.admin_panel_settings_outlined, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('Admin: $adminNote',
                        style: TextStyle(fontSize: 12, color: statusColor))),
              ]),
            ),
          ],
          const SizedBox(height: 4),
          Text('Submitted $date',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (status == 'approved') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFEAF2EA),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Your area is approved! You can now place delivery orders to this pincode.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 8),
            _SaveAddressButton(request: widget.request),
          ],
          if (status == 'rejected') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _resubmitting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Request Again'),
                onPressed: _resubmitting ? null : _resubmit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade400),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SaveAddressButton extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  const _SaveAddressButton({required this.request});
  @override
  ConsumerState<_SaveAddressButton> createState() => _SaveAddressButtonState();
}

class _SaveAddressButtonState extends ConsumerState<_SaveAddressButton> {
  bool _saving = false;
  bool _saved  = false;

  Future<void> _save() async {
    final pincode = widget.request['pincode'] as String;
    final address = widget.request['address'] as String;
    final labelCtrl  = TextEditingController(text: 'Home');
    final cityCtrl   = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to Addresses'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Pincode: $pincode',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(
              labelText: 'Label (e.g. Home, Farm)',
              border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City / Town',
              border: OutlineInputBorder(), isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(Endpoints.addresses, data: {
        'label':        labelCtrl.text.trim().isEmpty ? 'Home' : labelCtrl.text.trim(),
        'address_line': address,
        'city':         cityCtrl.text.trim().isEmpty ? '' : cityCtrl.text.trim(),
        'pincode':      pincode,
        'is_default':   false,
      });
      if (mounted) setState(() => _saved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Address saved ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['error'] ?? 'Failed to save address')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return const Row(children: [
        Icon(Icons.check, color: AppColors.primary, size: 14),
        SizedBox(width: 6),
        Text('Saved to addresses', style: TextStyle(fontSize: 12, color: AppColors.primary)),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: _saving
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_location_alt_outlined, size: 16),
        label: const Text('Save to My Addresses'),
        onPressed: _saving ? null : _save,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
