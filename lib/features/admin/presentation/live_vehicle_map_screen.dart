import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

/// Admin screen: shows all active vehicles on a live map
class LiveVehicleMapScreen extends StatefulWidget {
  const LiveVehicleMapScreen({super.key});

  @override
  State<LiveVehicleMapScreen> createState() => _LiveVehicleMapScreenState();
}

class _LiveVehicleMapScreenState extends State<LiveVehicleMapScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Completer<GoogleMapController> _controller = Completer();

  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _activeTrips = [];
  Timer? _refreshTimer;
  bool _isLoading = true;

  static const CameraPosition _kIndiaCenter = CameraPosition(
    target: LatLng(20.5937, 78.9629), // Center of India
    zoom: 5,
  );

  @override
  void initState() {
    super.initState();
    _loadActiveVehicles();
    // Auto-refresh every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadActiveVehicles();
    });
  }

  Future<void> _loadActiveVehicles() async {
    try {
      final response = await _supabase
          .from('trips')
          .select()
          .eq('status', 'active')
          .order('started_at', ascending: false);

      final trips = List<Map<String, dynamic>>.from(response);

      final Set<Marker> markers = {};
      for (final trip in trips) {
        final lat = trip['current_lat'] as double?;
        final lng = trip['current_lng'] as double?;
        final driverId = trip['driver_id'] ?? 'Unknown';
        final distance = (trip['total_distance_km'] ?? 0.0).toDouble();

        if (lat != null && lng != null) {
          markers.add(
            Marker(
              markerId: MarkerId(trip['id'] ?? driverId),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(
                title: 'Driver: $driverId',
                snippet: 'Distance: ${distance.toStringAsFixed(2)} km',
              ),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _activeTrips = trips;
          _markers = markers;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading active vehicles: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _focusOnVehicle(Map<String, dynamic> trip) async {
    final lat = trip['current_lat'] as double?;
    final lng = trip['current_lng'] as double?;
    if (lat == null || lng == null) return;

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(lat, lng), zoom: 16),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Vehicle Map'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActiveVehicles,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kIndiaCenter,
            markers: _markers,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            myLocationEnabled: false,
          ),

          // Active vehicles panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Active Vehicles',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_activeTrips.length} online',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: _isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _activeTrips.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No active trips right now',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                itemCount: _activeTrips.length,
                                itemBuilder: (context, index) {
                                  return _buildVehicleTile(
                                    _activeTrips[index],
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),

          // Loading indicator
          if (_isLoading)
            const Positioned(
              top: 16,
              right: 16,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleTile(Map<String, dynamic> trip) {
    final driverId = trip['driver_id'] ?? 'Unknown';
    final distance = (trip['total_distance_km'] ?? 0.0).toDouble();

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.green[50],
        child: Icon(Icons.local_shipping, size: 18, color: Colors.green[700]),
      ),
      title: Text(
        'Driver: $driverId',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${distance.toStringAsFixed(2)} km traveled',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _focusOnVehicle(trip),
    );
  }
}
