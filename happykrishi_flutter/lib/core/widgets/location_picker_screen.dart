import '../theme/app_theme.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng initialCenter;
  final LatLng? existingPin;
  const LocationPickerScreen({super.key, required this.initialCenter, this.existingPin});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _center;
  final _mapController = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _center = widget.existingPin ?? widget.initialCenter;
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final loc = LatLng(pos.latitude, pos.longitude);
      _mapController.move(loc, 17);
      if (mounted) setState(() => _center = loc);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Your Location'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 16,
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture) setState(() => _center = pos.center);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.happykrishi.delivery',
            ),
          ],
        ),

        // Fixed crosshair pin
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_pin, size: 48, color: Colors.red),
              SizedBox(height: 24),
            ],
          ),
        ),

        // GPS button
        Positioned(
          top: 12,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'gps',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: _locating ? null : _goToMyLocation,
            child: _locating
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.my_location),
          ),
        ),

        // Instruction banner
        Positioned(
          top: 12,
          left: 0,
          right: 60,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Drag map to place pin on your home',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),

        // Confirm button
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm this location'),
            onPressed: () => Navigator.pop(context, _center),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}
