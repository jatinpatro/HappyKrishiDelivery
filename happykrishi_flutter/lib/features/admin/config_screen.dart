import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/endpoints.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/firebase_upload.dart';
import '../../core/widgets/location_picker_screen.dart';

final configProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminConfig);
  return Map<String, String>.from(res.data['config']);
});

final _salesmenForConfigProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminSalesmen);
  return List<Map<String, dynamic>>.from(res.data['salesmen']);
});

class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});
  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _saving = false;
  bool _uploadingQr = false;
  String? _qrPreviewUrl;
  int? _selectedSalesmanId; // null = none (no auto-assign)

  static const _qrField = 'upi_qr_image_url';

  final _labels = {
    'free_delivery_above': 'Free Delivery Above (₹)',
    'base_delivery_charge': 'Base Delivery Charge (₹)',
    'delivery_charge_per_km': 'Charge Per KM (₹)',
    'min_order_amount': 'Min Order Amount — Delivery (₹)',
    'min_pickup_order_amount': 'Min Order Amount — Pickup (₹)',
    'min_wallet_balance': 'Min Wallet Balance (₹)',
    'max_wallet_negative_limit': 'Max Wallet Negative Limit (₹)',
    'geofence_radius_m': 'Geofence Radius (m)',
    'password_change_fee': 'Password Change Fee (₹)',
    'farm_name': 'Farm Name',
    'farm_address': 'Farm Address',
    'contact_phone': 'Contact Phone',
    'contact_whatsapp': 'WhatsApp Number',
    'contact_email': 'Contact Email',
    'working_hours': 'Working Hours',
    'upi_id': 'UPI ID',
    'upi_name': 'UPI Display Name',
    _qrField: 'UPI QR Code Image',
    'cash_payment_address': 'Cash Payment Instructions',
    'salesmen_list': 'Cash Salesmen (comma-separated)',
    'farm_lat': 'Store Latitude',
    'farm_lng': 'Store Longitude',
  };

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Config'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(configProvider),
          ),
        ],
      ),
      body: config.when(
        data: (cfg) {
          for (final k in _labels.keys) {
            if (k != _qrField) {
              _ctrls.putIfAbsent(k, () => TextEditingController(text: cfg[k] ?? ''));
            }
          }
          // Set initial QR URL from config
          _qrPreviewUrl ??= cfg[_qrField]?.isNotEmpty == true ? cfg[_qrField] : null;
          // Init default salesman from config (once)
          if (_selectedSalesmanId == null && (cfg['default_salesman_id'] ?? '').isNotEmpty) {
            _selectedSalesmanId = int.tryParse(cfg['default_salesman_id']!);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(configProvider),
            child: ListView(padding: const EdgeInsets.all(16), children: [
            _configSection('Delivery Rules', Icons.local_shipping, Colors.orange, [
              'free_delivery_above', 'base_delivery_charge', 'delivery_charge_per_km',
              'min_order_amount', 'min_pickup_order_amount', 'min_wallet_balance', 'max_wallet_negative_limit', 'geofence_radius_m',
            ]),
            const SizedBox(height: 16),
            _configSection('Fees', Icons.currency_rupee, Colors.red, ['password_change_fee']),
            const SizedBox(height: 16),
            _configSection('Contact & Farm Info', Icons.contact_phone, Colors.green, [
              'farm_name', 'farm_address', 'contact_phone', 'contact_whatsapp',
              'contact_email', 'working_hours',
            ]),
            const SizedBox(height: 16),
            _storeLocationSection(),
            const SizedBox(height: 16),
            _defaultSalesmanSection(),
            const SizedBox(height: 16),
            // Payment section with special QR upload
            _paymentSection(),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _saveConfig,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Config'),
            ),
            const SizedBox(height: 24),
          ]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('admin-config', e); return Center(child: Text(friendlyError(e))); },
      ),
    );
  }

  Widget _defaultSalesmanSection() {
    final salesmen = ref.watch(_salesmenForConfigProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.person_pin_circle, color: Colors.blue, size: 18),
            SizedBox(width: 8),
            Text('Auto-Assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 20),
          const Text('Default Salesman', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          const Text(
            'When an order is confirmed, it will be auto-assigned to this salesman. Leave blank to assign manually.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          salesmen.when(
            data: (list) => DropdownButtonFormField<int>(
              initialValue: _selectedSalesmanId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'No auto-assignment',
              ),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('None (assign manually)')),
                ...list.map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text('${s['name']}  •  ${s['phone']}'),
                )),
              ],
              onChanged: (v) => setState(() => _selectedSalesmanId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) { logError('admin-config', e); return Text(friendlyError(e),
                style: const TextStyle(color: Colors.red, fontSize: 12)); },
          ),
        ]),
      ),
    );
  }

  Widget _storeLocationSection() {
    final latCtrl  = _ctrls['farm_lat']  ?? TextEditingController();
    final lngCtrl  = _ctrls['farm_lng']  ?? TextEditingController();
    final lat = double.tryParse(latCtrl.text);
    final lng = double.tryParse(lngCtrl.text);
    final hasPin = lat != null && lng != null;
    final pinPoint = hasPin ? LatLng(lat, lng) : const LatLng(20.5937, 78.9629); // India center fallback

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.store_mall_directory, color: Colors.teal, size: 18),
            SizedBox(width: 8),
            Text('Store / Farm Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 20),
          const Text(
            'This pin is shown on the live salesman map and as the origin on customer order tracking.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),

          // Mini map preview
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 160,
              child: Stack(children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: pinPoint,
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.happykrishi.delivery',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: pinPoint,
                        width: 36,
                        height: 40,
                        child: const Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.location_pin, color: Colors.red, size: 36),
                        ]),
                      ),
                    ]),
                  ],
                ),
                // Google-maps style "Edit" button overlay
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit_location_alt, size: 16),
                    label: const Text('Move Pin'),
                    onPressed: () async {
                      final picked = await Navigator.push<LatLng>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LocationPickerScreen(
                            initialCenter: pinPoint,
                            existingPin: hasPin ? pinPoint : null,
                          ),
                        ),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _ctrls['farm_lat']!.text = picked.latitude.toStringAsFixed(6);
                          _ctrls['farm_lng']!.text = picked.longitude.toStringAsFixed(6);
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _textField('farm_lat')),
            const SizedBox(width: 10),
            Expanded(child: _textField('farm_lng')),
          ]),
        ]),
      ),
    );
  }

  Widget _paymentSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.payment, color: Colors.purple, size: 18),
            SizedBox(width: 8),
            Text('Payment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 20),

          // UPI ID
          _textField('upi_id'),
          const SizedBox(height: 12),
          _textField('upi_name'),
          const SizedBox(height: 16),

          // QR Code Upload
          const Text('UPI QR Code Image', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          _QrUploadWidget(
            currentUrl: _qrPreviewUrl,
            uploading: _uploadingQr,
            onUpload: _uploadQr,
          ),
          const SizedBox(height: 16),

          _textField('cash_payment_address', maxLines: 3),
          const SizedBox(height: 12),
          _textField('salesmen_list'),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Comma-separated names, e.g. Tarini,Abhi,Jatin,Sunil',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ]),
      ),
    );
  }

  Future<void> _uploadQr() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingQr = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final filename = 'config/upi_qr.$ext';
      final dio = ref.read(dioProvider);

      // Use signed URL — works on web and mobile, no client Firebase auth needed
      final downloadUrl = await uploadImageViaSignedUrl(
        dio: dio,
        bytes: bytes,
        filename: filename,
        contentType: 'image/$ext',
      );

      if (downloadUrl == null) throw Exception('Upload returned no URL');

      // Save URL to backend config
      await dio.put(Endpoints.adminConfig, data: {'config': {'upi_qr_image_url': downloadUrl}});
      setState(() => _qrPreviewUrl = downloadUrl);
      ref.invalidate(configProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code uploaded ✅'), backgroundColor: AppColors.primary),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data['error'] ?? 'Upload failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingQr = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = ref.read(dioProvider);
      final data = Map.fromEntries(_ctrls.entries.map((e) => MapEntry(e.key, e.value.text)));
      // Include default salesman ID (empty string = no auto-assign)
      data['default_salesman_id'] = _selectedSalesmanId != null ? '$_selectedSalesmanId' : '';
      await dio.put(Endpoints.adminConfig, data: {'config': data});
      ref.invalidate(configProvider);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Config saved ✅')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _textField(String key, {int maxLines = 1}) {
    final label = _labels[key] ?? key;
    const numericKeys = {
      'free_delivery_above', 'base_delivery_charge', 'delivery_charge_per_km',
      'min_order_amount', 'min_pickup_order_amount', 'min_wallet_balance', 'max_wallet_negative_limit', 'geofence_radius_m', 'password_change_fee',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrls[key],
        keyboardType: numericKeys.contains(key)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _configSection(String title, IconData icon, Color color, List<String> keys) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 20),
          ...keys.map((k) => _textField(k)),
        ]),
      ),
    );
  }
}

// ── QR Upload Widget ──────────────────────────────────────────────────────────

class _QrUploadWidget extends StatelessWidget {
  final String? currentUrl;
  final bool uploading;
  final VoidCallback onUpload;
  const _QrUploadWidget({this.currentUrl, required this.uploading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Preview box
      GestureDetector(
        onTap: onUpload,
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.primary,
              width: 2,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade100,
          ),
          child: uploading
              ? const Center(child: CircularProgressIndicator())
              : currentUrl != null && currentUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        currentUrl!.startsWith('http')
                            ? currentUrl!
                            : '${Endpoints.baseUrl}$currentUrl',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.qr_code, size: 60, color: Colors.grey),
                        ),
                      ),
                    )
                  : const Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.qr_code, size: 40, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('No QR', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
        ),
      ),
      const SizedBox(width: 16),

      // Instructions + button
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Upload a QR code image from your UPI app (Google Pay, PhonePe, Paytm, etc.)',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.upload, size: 16),
            label: Text(currentUrl != null && currentUrl!.isNotEmpty ? 'Change QR Image' : 'Upload QR Image'),
            onPressed: uploading ? null : onUpload,
            style: ElevatedButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          if (currentUrl != null && currentUrl!.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 14),
              SizedBox(width: 4),
              Text('QR image set', style: TextStyle(color: Colors.green, fontSize: 12)),
            ]),
          ],
        ]),
      ),
    ]);
  }
}
