import '../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../core/api/endpoints.dart';
import '../../core/providers/auth_provider.dart';

// Farm location loaded from app_config at runtime
final _farmLocationProvider = FutureProvider.autoDispose<LatLng>((ref) async {
  final res = await ref.read(dioProvider).get(Endpoints.adminConfig);
  final cfg = Map<String, String>.from(res.data['config']);
  final lat = double.tryParse(cfg['farm_lat'] ?? '') ?? 19.0746;
  final lng = double.tryParse(cfg['farm_lng'] ?? '') ?? 84.5027;
  return LatLng(lat, lng);
});

final _agentLocationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(Endpoints.adminAgentLocations);
  return List<Map<String, dynamic>>.from(res.data['agents']);
});

class AdminLiveMapScreen extends ConsumerStatefulWidget {
  const AdminLiveMapScreen({super.key});

  @override
  ConsumerState<AdminLiveMapScreen> createState() => _AdminLiveMapScreenState();
}

class _AdminLiveMapScreenState extends ConsumerState<AdminLiveMapScreen> {
  final _mapController = MapController();
  bool _mapReady = false;
  Timer? _pollTimer;
  int _secondsSinceRefresh = 0;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 15 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.invalidate(_agentLocationsProvider);
      setState(() => _secondsSinceRefresh = 0);
    });
    // Tick clock every second
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsSinceRefresh++);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _fitAgents(List<Map<String, dynamic>> agents) {
    final points = agents
        .where((a) => a['current_lat'] != null && a['current_lng'] != null)
        .map((a) => LatLng(
              (a['current_lat'] as num).toDouble(),
              (a['current_lng'] as num).toDouble(),
            ))
        .toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  String _lastSeenLabel(String? lastSeen) {
    if (lastSeen == null) return 'Never';
    try {
      final dt = DateTime.parse(lastSeen.replaceFirst(' ', 'T'));
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return lastSeen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(_agentLocationsProvider);
    final farmAsync   = ref.watch(_farmLocationProvider);
    final farmPoint   = farmAsync.value ?? const LatLng(19.0746, 84.5027);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Salesman Locations'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Dashboard',
            onPressed: () => context.go('/admin/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh now',
            onPressed: () {
              ref.invalidate(_agentLocationsProvider);
              setState(() => _secondsSinceRefresh = 0);
            },
          ),
        ],
      ),
      body: agentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (agents) {
          final located = agents
              .where((a) => a['current_lat'] != null && a['current_lng'] != null)
              .toList();
          final unlocated = agents
              .where((a) => a['current_lat'] == null || a['current_lng'] == null)
              .toList();

          // Fit map on first load
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_mapReady && located.isNotEmpty) _fitAgents(located);
          });

          final markers = <Marker>[
            // Farm marker
            Marker(
              point: farmPoint,
              width: 36,
              height: 36,
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
            // Agent markers
            ...located.map((a) {
              final hasActive = (a['active_deliveries'] as int? ?? 0) > 0;
              final isOnline = () {
                final ls = a['last_seen_at'] as String?;
                if (ls == null) return false;
                try {
                  final dt = DateTime.parse(ls.replaceFirst(' ', 'T'));
                  return DateTime.now().difference(dt).inMinutes < 5;
                } catch (_) { return false; }
              }();
              final color = hasActive
                  ? AppColors.primary
                  : isOnline
                      ? Colors.orange.shade700
                      : Colors.grey.shade500;

              return Marker(
                point: LatLng(
                  (a['current_lat'] as num).toDouble(),
                  (a['current_lng'] as num).toDouble(),
                ),
                width: 52,
                height: 52,
                child: GestureDetector(
                  onTap: () => _showAgentInfo(context, a),
                  child: Tooltip(
                        message: '${a['name']} — ${hasActive ? '${a['active_deliveries']} delivery' : 'No delivery'}',
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 10,
                          )
                        ],
                      ),
                      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              );
            }),
          ];

          return Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: farmPoint,
                initialZoom: 12,
                onMapReady: () => setState(() {
                  _mapReady = true;
                  if (located.isNotEmpty) _fitAgents(located);
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.happykrishi.delivery',
                ),
                MarkerLayer(markers: markers),
              ],
            ),

            // Fit bounds button
            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'fit',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () => _fitAgents(located),
                child: const Icon(Icons.fit_screen),
              ),
            ),

            // Status panel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Legend + refresh timer
                      Row(children: [
                        _LegendDot(Colors.green.shade700, 'Active delivery'),
                        const SizedBox(width: 12),
                        _LegendDot(Colors.orange.shade700, 'Online, no delivery'),
                        const SizedBox(width: 12),
                        _LegendDot(Colors.grey.shade500, 'Offline'),
                        const Spacer(),
                        Text(
                          'Updated ${_secondsSinceRefresh}s ago',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ]),
                      if (located.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: located.length,
                            separatorBuilder: (_, i) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final a = located[i];
                              final hasActive = (a['active_deliveries'] as int? ?? 0) > 0;
                              return GestureDetector(
                                onTap: () {
                                  _mapController.move(
                                    LatLng(
                                      (a['current_lat'] as num).toDouble(),
                                      (a['current_lng'] as num).toDouble(),
                                    ),
                                    16,
                                  );
                                  _showAgentInfo(context, a);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: hasActive
                                        ? const Color(0xFFEAF2EA)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: hasActive
                                          ? AppColors.primary
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(a['name'] as String,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600, fontSize: 12)),
                                      Text(
                                        hasActive
                                            ? '${a['active_deliveries']} delivery'
                                            : 'No delivery',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: hasActive
                                              ? AppColors.primary
                                              : Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        _lastSeenLabel(a['last_seen_at'] as String?),
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (unlocated.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${unlocated.length} salesman(s) not sharing location: '
                          '${unlocated.map((a) => a['name']).join(', ')}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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

  void _showAgentInfo(BuildContext context, Map<String, dynamic> agent) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFEAF2EA),
              child: Text(
                (agent['name'] as String).substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(agent['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('+91 ${agent['phone']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (agent['active_deliveries'] as int? ?? 0) > 0
                    ? const Color(0xFFEAF2EA)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                (agent['active_deliveries'] as int? ?? 0) > 0
                    ? '${agent['active_deliveries']} active'
                    : 'No delivery',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: (agent['active_deliveries'] as int? ?? 0) > 0
                      ? AppColors.primary
                      : Colors.grey,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            'Last seen: ${_lastSeenLabel(agent['last_seen_at'] as String?)}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Role: ${agent['role']}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]);
}
