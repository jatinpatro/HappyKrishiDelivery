import '../../core/theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import '../../core/api/endpoints.dart';
import '../../core/api/dio_client.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/utils/error_handler.dart';

// Farm location (matches .env)
const _farmLat = 19.0746;
const _farmLng = 84.5027;

final _trackingOrderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, orderId) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('${Endpoints.orders}/$orderId');
  return res.data as Map<String, dynamic>;
});

class TrackingScreen extends ConsumerStatefulWidget {
  final int orderId;
  final bool shareLocation;
  const TrackingScreen({super.key, required this.orderId, this.shareLocation = true});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  WebSocketChannel? _channel;
  LatLng? _agentLoc;
  LatLng? _customerLoc;
  String _status = 'Connecting...';
  int? _etaMinutes;
  final _mapController = MapController();
  bool _mapReady = false;
  Timer? _locationTimer;
  bool _sharingLocation = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _connectWs();
    if (widget.shareLocation) _startSharingLocation();
  }

  // ── Customer location sharing ─────────────────────────────────────────────
  Future<void> _startSharingLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationError = 'Location permission denied');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _locationError = 'Location services off');
      return;
    }
    if (mounted) setState(() { _sharingLocation = true; _locationError = null; });
    _sendLocation();
    // Update every 10 seconds while order is active
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendLocation());
  }

  Future<void> _sendLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() => _customerLoc = LatLng(pos.latitude, pos.longitude));
      final dio = ref.read(dioProvider);
      await dio.post(Endpoints.customerLocation(widget.orderId),
          data: {'lat': pos.latitude, 'lng': pos.longitude});
    } catch (_) {}
  }

  void _connectWs() async {
    final token = await readToken();
    if (token == null) return;
    final uri = Uri.parse(
        '${Endpoints.wsBaseUrl}?token=$token&order_id=${widget.orderId}');
    try {
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          if (msg['type'] == 'location') {
            _agentLoc = LatLng(
              (msg['lat'] as num).toDouble(),
              (msg['lng'] as num).toDouble(),
            );
            _etaMinutes = msg['eta_minutes'] as int?;
            _status = 'Salesman is on the way';
            if (_mapReady) _mapController.move(_agentLoc!, 15);
          } else if (msg['type'] == 'customer_location') {
            // Customer's real-time GPS — visible to salesman/admin on their tracking view
            _customerLoc = LatLng(
              (msg['lat'] as num).toDouble(),
              (msg['lng'] as num).toDouble(),
            );
          } else if (msg['type'] == 'status') {
            _status = _statusLabel(msg['status'] as String? ?? '');
          }
        });
      }, onError: (_) {
        if (mounted) setState(() => _status = 'Connection lost — retrying…');
        Future.delayed(const Duration(seconds: 5), _connectWs);
      });
    } catch (_) {}
  }

  String _statusLabel(String s) => switch (s) {
    'assigned'   => 'Salesman assigned',
    'picked'     => 'Order picked up — on the way!',
    'delivered'  => 'Delivered ✅',
    'cancelled'  => 'Order cancelled',
    _ => s,
  };

  @override
  void dispose() {
    _locationTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_trackingOrderProvider(widget.orderId));

    final currentUser = ref.watch(authStateProvider).user;
    final isAdmin    = currentUser?.role == 'admin' || currentUser?.role == 'subadmin';
    final isSalesman = currentUser?.role == 'salesman';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => isAdmin
                ? context.go('/admin/dashboard')
                : isSalesman
                    ? context.go('/salesman')
                    : context.go('/home'),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) { logError('tracking', e); return Center(child: Text(friendlyError(e))); },
        data: (data) {
          final order    = data['order']    as Map<String, dynamic>;
          final delivery = data['delivery'] as Map<String, dynamic>?;

          // Delivery address coords
          final addrLat = (order['lat'] as num?)?.toDouble();
          final addrLng = (order['lng'] as num?)?.toDouble();
          final deliveryLoc = (addrLat != null && addrLng != null)
              ? LatLng(addrLat, addrLng)
              : null;

          // Salesman initial location (from REST, then updates via WS)
          if (_agentLoc == null && delivery != null) {
            final aLat = (delivery['agent_lat'] as num?)?.toDouble();
            final aLng = (delivery['agent_lng'] as num?)?.toDouble();
            if (aLat != null && aLng != null) {
              _agentLoc = LatLng(aLat, aLng);
              if (_status == 'Connecting...') _status = 'Salesman assigned';
            }
          }

          // Customer GPS — last saved location, visible to admin/salesman on page load
          if (_customerLoc == null && delivery != null) {
            final cLat = (delivery['customer_lat'] as num?)?.toDouble();
            final cLng = (delivery['customer_lng'] as num?)?.toDouble();
            if (cLat != null && cLng != null) {
              _customerLoc = LatLng(cLat, cLng);
            }
          }

          // Map center: salesman/admin → delivery address; customer → salesman location
          final center = widget.shareLocation
              ? (_agentLoc ?? deliveryLoc ?? const LatLng(_farmLat, _farmLng))
              : (deliveryLoc ?? _agentLoc ?? const LatLng(_farmLat, _farmLng));

          final orderNum  = order['order_number'] as String? ?? '#${widget.orderId}';
          final staffName = delivery?['agent_name'] as String?;
          final staffPhone = delivery?['agent_phone'] as String?;
          final status    = order['status'] as String? ?? '';
          final deliveryDate = order['delivery_date'] as String? ?? '';
          final city      = order['city'] as String? ?? '';
          final addrLine  = order['address_line'] as String? ?? '';

          return Stack(children: [
            // ── Map ───────────────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                onMapReady: () => setState(() => _mapReady = true),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.happykrishi.delivery',
                ),

                // Line from salesman to delivery address
                if (_agentLoc != null && deliveryLoc != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [_agentLoc!, deliveryLoc],
                      color: AppColors.primary,
                      strokeWidth: 4,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ]),

                MarkerLayer(markers: [
                  // Farm / pickup origin marker
                  Marker(
                    point: const LatLng(_farmLat, _farmLng),
                    width: 36, height: 36,
                    child: Tooltip(
                      message: 'HappyKrishi Farm',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green.shade800,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.agriculture, color: Colors.white, size: 20),
                      ),
                    ),
                  ),

                  // Delivery address marker
                  if (deliveryLoc != null)
                    Marker(
                      point: deliveryLoc,
                      width: 40, height: 40,
                      child: Tooltip(
                        message: '$addrLine, $city',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 8)],
                          ),
                          child: const Icon(Icons.home, color: Colors.white, size: 22),
                        ),
                      ),
                    ),

                  // Salesman marker
                  if (_agentLoc != null)
                    Marker(
                      point: _agentLoc!,
                      width: 52, height: 52,
                      child: Tooltip(
                        message: staffName ?? 'Salesman',
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 10)],
                          ),
                          child: const Icon(Icons.delivery_dining, color: Colors.white, size: 28),
                        ),
                      ),
                    ),

                  // Customer (me) marker
                  if (_customerLoc != null)
                    Marker(
                      point: _customerLoc!,
                      width: 44, height: 44,
                      child: Tooltip(
                      message: widget.shareLocation ? 'Your location' : 'Customer location',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.4),
                                blurRadius: 10)],
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                ]),
              ],
            ),

            // ── Fit-bounds button ─────────────────────────────────────────
            Positioned(
              top: 12, right: 12,
              child: FloatingActionButton.small(
                heroTag: 'fit',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  final points = <LatLng>[
                    ?_agentLoc,
                    ?deliveryLoc,
                    ?_customerLoc,
                    const LatLng(_farmLat, _farmLng),
                  ];
                  if (points.length == 1) {
                    _mapController.move(points.first, 15);
                  } else if (points.length > 1) {
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(points),
                        padding: const EdgeInsets.all(60),
                      ),
                    );
                  }
                },
                child: const Icon(Icons.fit_screen),
              ),
            ),

            // ── Status panel ──────────────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // Order number + status badge
                      Row(children: [
                        Text('Order $orderNum',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        _StatusBadge(status: status),
                      ]),
                      const SizedBox(height: 10),

                      // Progress stepper
                      _StatusStepper(status: status),
                      const SizedBox(height: 14),

                      // Delivery info
                      if (addrLine.isNotEmpty || city.isNotEmpty)
                        _InfoRow(Icons.location_on_outlined,
                            '$addrLine${city.isNotEmpty ? ', $city' : ''}'),
                      if (deliveryDate.isNotEmpty)
                        _InfoRow(Icons.calendar_today_outlined, deliveryDate),

                      // Navigate button — shown to salesman (shareLocation=false, has delivery coords)
                      if (!widget.shareLocation && deliveryLoc != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.navigation_outlined, size: 18),
                            label: Text('Navigate to $addrLine${city.isNotEmpty ? ', $city' : ''}',
                                overflow: TextOverflow.ellipsis),
                            onPressed: () {
                              final lat = deliveryLoc.latitude;
                              final lng = deliveryLoc.longitude;
                              final label = Uri.encodeComponent('$addrLine, $city');
                              launchUrl(
                                Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$label&travelmode=driving'),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                      ],

                      // Salesman info
                      if (staffName != null) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0xFFEAF2EA),
                            child: Icon(Icons.delivery_dining,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(staffName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (staffPhone != null)
                              Text('+91 $staffPhone',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                          ]),
                          const Spacer(),
                          if (staffPhone != null) ...[
                            _ContactIcon(phone: staffPhone, isWhatsApp: false),
                            const SizedBox(width: 6),
                            _ContactIcon(phone: staffPhone, isWhatsApp: true),
                            const SizedBox(width: 8),
                          ],
                          if (_etaMinutes != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF2EA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('~$_etaMinutes min',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ),
                        ]),
                      ],

                      // Delivery code — show to customer (shareLocation=true) only
                      Builder(builder: (ctx) {
                        final code = delivery?['delivery_code'] as String?;
                        final confirmed = delivery?['customer_confirmed_at'] != null;
                        if (code == null || !widget.shareLocation) return const SizedBox.shrink();
                        if (status == 'delivered' || status == 'cancelled') return const SizedBox.shrink();
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: confirmed ? Colors.green.shade50 : const Color(0xFFEAF2EA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: confirmed ? Colors.green.shade400 : AppColors.primary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(confirmed ? Icons.verified_outlined : Icons.lock_outline,
                                    color: AppColors.primary, size: 14),
                                const SizedBox(width: 6),
                                Text(confirmed ? 'Delivery Confirmed' : 'Your Delivery Code',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Text(code, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                                    letterSpacing: 5, color: AppColors.primary)),
                                const Spacer(),
                                if (!confirmed)
                                  _TrackingConfirmButton(orderId: widget.orderId),
                                if (confirmed)
                                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
                              ]),
                              if (!confirmed)
                                const Text('Tell this code to your salesman, or tap to confirm receipt',
                                    style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ]),
                          ),
                        ]);
                      }),

                      // Location sharing status
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(
                          !widget.shareLocation
                              ? Icons.admin_panel_settings_outlined
                              : _locationError != null
                                  ? Icons.location_off_outlined
                                  : _sharingLocation
                                      ? Icons.location_on
                                      : Icons.location_searching,
                          size: 14,
                          color: !widget.shareLocation
                              ? Colors.indigo
                              : _locationError != null
                                  ? Colors.red
                                  : _sharingLocation
                                      ? Colors.blue.shade700
                                      : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            !widget.shareLocation
                                ? 'Admin view — monitoring only'
                                : _locationError ?? (_sharingLocation
                                    ? 'Sharing your location with salesman'
                                    : 'Getting your location…'),
                            style: TextStyle(
                              fontSize: 12,
                              color: !widget.shareLocation
                                  ? Colors.indigo
                                  : _locationError != null
                                      ? Colors.red
                                      : Colors.grey,
                            ),
                          ),
                        ),
                        if (_locationError != null && widget.shareLocation)
                          TextButton(
                            onPressed: _startSharingLocation,
                            style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(horizontal: 8)),
                            child: const Text('Retry', style: TextStyle(fontSize: 12)),
                          ),
                      ]),

                      // WS connecting indicator
                      if (_agentLoc == null && status != 'delivered') ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                          const SizedBox(width: 8),
                          Text(_status,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ]),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  (Color, IconData) get _meta => switch (status) {
    'pending'    => (const Color(0xFFE65100), Icons.hourglass_empty),
    'confirmed'  => (const Color(0xFF0277BD), Icons.check_circle_outline),
    'assigned'   => (const Color(0xFF6A1B9A), Icons.person_pin),
    'dispatched' => (const Color(0xFF00838F), Icons.local_shipping),
    'delivered'  => (AppColors.primary, Icons.done_all),
    'cancelled'  => (const Color(0xFFC62828), Icons.cancel_outlined),
    _ => (Colors.grey, Icons.help_outline),
  };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _meta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(status.toUpperCase(),
            style: TextStyle(fontSize: 11, color: color,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ── Progress stepper ──────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  final String status;
  const _StatusStepper({required this.status});

  static const _steps = [
    'pending', 'confirmed', 'assigned', 'dispatched', 'delivered',
  ];

  static const _labels = [
    'Placed', 'Confirmed', 'Assigned', 'On way', 'Delivered',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _steps.indexOf(status);
    return Row(children: List.generate(_steps.length * 2 - 1, (i) {
      if (i.isOdd) {
        final stepIdx = i ~/ 2;
        final done = stepIdx < idx;
        return Expanded(child: Container(
          height: 2,
          color: done ? AppColors.primary : Colors.grey.shade300,
        ));
      }
      final stepIdx = i ~/ 2;
      final done = stepIdx <= idx;
      final active = stepIdx == idx;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: done ? AppColors.primary : Colors.grey.shade200,
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: AppColors.primary, width: 2.5)
                : null,
          ),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null,
        ),
        const SizedBox(height: 3),
        Text(_labels[stepIdx],
            style: TextStyle(
              fontSize: 9,
              color: done ? AppColors.primary : Colors.grey,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
      ]);
    }));
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── Confirm delivery button (used in tracking screen) ─────────────────────────

class _TrackingConfirmButton extends ConsumerStatefulWidget {
  final int orderId;
  const _TrackingConfirmButton({required this.orderId});
  @override
  ConsumerState<_TrackingConfirmButton> createState() => _TrackingConfirmButtonState();
}

class _TrackingConfirmButtonState extends ConsumerState<_TrackingConfirmButton> {
  bool _loading = false;

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delivery?'),
        content: const Text('Confirm you have received your order. The salesman will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Yes, I received it'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post(Endpoints.orderConfirmDelivery(widget.orderId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Delivery confirmed ✅'),
          backgroundColor: AppColors.primary,
        ));
      }
      // Refresh the tracking provider
      ref.invalidate(_trackingOrderProvider(widget.orderId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not confirm — try again')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
        : ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: const Text('I Received It'),
          );
  }
}

// ── Contact icon button (call or WhatsApp) ────────────────────────────────────

class _ContactIcon extends StatelessWidget {
  final String phone;
  final bool isWhatsApp;
  const _ContactIcon({required this.phone, required this.isWhatsApp});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = isWhatsApp
            ? Uri.parse('https://wa.me/91$phone')
            : Uri.parse('tel:+91$phone');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isWhatsApp ? Colors.green.shade50 : Colors.blue.shade50,
          shape: BoxShape.circle,
          border: Border.all(
              color: isWhatsApp ? Colors.green.shade300 : Colors.blue.shade300),
        ),
        child: Icon(
          isWhatsApp ? Icons.chat_outlined : Icons.call_outlined,
          size: 15,
          color: isWhatsApp ? Colors.green.shade700 : Colors.blue.shade700,
        ),
      ),
    );
  }
}
