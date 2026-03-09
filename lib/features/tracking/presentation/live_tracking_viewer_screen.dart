import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:async';

/// Public live tracking viewer - accessible via tracking token
/// Shows real-time location of driver on map
class LiveTrackingViewerScreen extends StatefulWidget {
  final String trackingToken;
    
  const LiveTrackingViewerScreen({super.key, required this.trackingToken});
    
  @override
  State<LiveTrackingViewerScreen> createState() => _LiveTrackingViewerScreenState();
}
  
class _LiveTrackingViewerScreenState extends State<LiveTrackingViewerScreen> {
  final _supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _tripData;
  
  LatLng? _driverPosition;
  LatLng? _destination;
  Set<Marker> _markers = {};
  List<LatLng> _routePoints = [];
  
  StreamSubscription? _tripSubscription;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    _loadTripData();
    _startAutoRefresh();
  }
  
  @override
  void dispose() {
    _tripSubscription?.cancel();
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
  
  Future<void> _loadTripData() async {
    try {
      // Query Supabase for trip with matching tracking token
      final response = await _supabase
          .from('trips')
          .select('*')
          .eq('tracking_token', widget.trackingToken)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _error = 'Trip not found or tracking link expired';
          _loading = false;
        });
        return;
      }

      final tripData = response;
      
      if (tripData['status'] != 'active') {
        setState(() {
          _error = 'Trip is ${tripData['status']}. Live tracking is only available for active trips.';
          _loading = false;
        });
        return;
      }

      // Get driver profile
      String driverName = 'Driver';
      String? phoneNumber;
      final driverId = tripData['driver_id'];
      if (driverId != null) {
        try {
          final profileDoc = await _supabase
              .from('profiles')
              .select('*')
              .eq('id', driverId)
              .maybeSingle();
          if (profileDoc != null) {
            driverName = profileDoc['full_name'] ?? 'Driver';
            phoneNumber = profileDoc['phone_number'];
          }
        } catch (e) {
          debugPrint('Error fetching driver profile: $e');
        }
      }

      // Get vehicle info
      String vehicleNumber = 'Vehicle';
      final vehicleId = tripData['vehicle_id'];
      if (vehicleId != null) {
        try {
          final vehicleDoc = await _supabase
              .from('vehicles')
              .select('*')
              .eq('id', vehicleId)
              .maybeSingle();
          if (vehicleDoc != null) {
            vehicleNumber = vehicleDoc['vehicle_number'] ?? 'Vehicle';
          }
        } catch (e) {
          debugPrint('Error fetching vehicle: $e');
        }
      }

      _tripData = {
        ...tripData,
        'driver_name': driverName,
        'phone_number': phoneNumber,
        'vehicle_number': vehicleNumber,
      };
      _updateMapData();
      
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading trip: $e';
        _loading = false;
      });
    }
  }
  
  void _updateMapData() {
    if (_tripData == null) return;
    
    _markers.clear();
    
    // Driver position
    final currentLat = _tripData!['current_lat'] as num?;
    final currentLng = _tripData!['current_lng'] as num?;
    
    if (currentLat != null && currentLng != null) {
      _driverPosition = LatLng(currentLat.toDouble(), currentLng.toDouble());
      _markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Driver Location'),
      ));
    }
    
    // Destination
    final destLat = _tripData!['dest_lat'] as num? ?? _tripData!['destination_lat'] as num?;
    final destLng = _tripData!['dest_lng'] as num? ?? _tripData!['destination_lng'] as num?;
    
    if (destLat != null && destLng != null) {
      _destination = LatLng(destLat.toDouble(), destLng.toDouble());
      final destName = _tripData!['dest_location'] ?? _tripData!['destination_name'] ?? 'Destination';
      _markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destination!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: destName),
      ));
    }
    
    // Route polyline
    if (_tripData!['planned_route_polyline'] != null) {
      _routePoints.clear();
      final points = PolylinePoints.decodePolyline(_tripData!['planned_route_polyline'] as String);
      for (var p in points) {
        _routePoints.add(LatLng(p.latitude, p.longitude));
      }
    }
    
    // Fit bounds if we have both positions
    if (_driverPosition != null && _destination != null && _mapController != null) {
      _fitBounds();
    }
  }
  
  void _fitBounds() {
    if (_driverPosition == null || _destination == null || _mapController == null) return;
    
    final bounds = LatLngBounds(
      southwest: LatLng(
        _driverPosition!.latitude < _destination!.latitude 
            ? _driverPosition!.latitude 
            : _destination!.latitude,
        _driverPosition!.longitude < _destination!.longitude 
            ? _driverPosition!.longitude 
            : _destination!.longitude,
      ),
      northeast: LatLng(
        _driverPosition!.latitude > _destination!.latitude 
            ? _driverPosition!.latitude 
            : _destination!.latitude,
        _driverPosition!.longitude > _destination!.longitude 
            ? _driverPosition!.longitude 
            : _destination!.longitude,
      ),
    );
    
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }
  
  void _startAutoRefresh() {
    // Refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshLocation();
    });
  }
  
  Future<void> _refreshLocation() async {
    if (_tripData == null) return;
    
    try {
      // Query Supabase for updated trip data
      final response = await _supabase
          .from('trips')
          .select('*')
          .eq('tracking_token', widget.trackingToken)
          .maybeSingle();
      
      if (response == null) {
        _refreshTimer?.cancel();
        setState(() {
          _error = 'Trip not found.';
        });
        return;
      }

      final tripData = response;
      
      if (tripData['status'] != 'active') {
        _refreshTimer?.cancel();
        setState(() {
          _error = 'Trip has ended.';
        });
        return;
      }
      
      final lat = tripData['current_lat'] as num?;
      final lng = tripData['current_lng'] as num?;
      
      if (lat != null && lng != null) {
        setState(() {
          _driverPosition = LatLng(lat.toDouble(), lng.toDouble());
          _markers.removeWhere((m) => m.markerId.value == 'driver');
          _markers.add(Marker(
            markerId: const MarkerId('driver'),
            position: _driverPosition!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'Driver Location'),
          ));
        });
      }
    } catch (e) {
      debugPrint('Error refreshing location: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        backgroundColor: const Color(0xFF4F8EF7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTripData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, 
                            style: const TextStyle(fontSize: 16, color: Colors.black54)),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _driverPosition ?? const LatLng(20.5937, 78.9629),
                        zoom: 12,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        if (_driverPosition != null && _destination != null) {
                          Future.delayed(const Duration(milliseconds: 500), _fitBounds);
                        }
                      },
                      markers: _markers,
                      polylines: {
                        if (_routePoints.isNotEmpty)
                          Polyline(
                            polylineId: const PolylineId('route'),
                            points: _routePoints,
                            color: const Color(0xFF4F8EF7),
                            width: 5,
                          ),
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                    // Trip info card
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _buildInfoCard(),
                    ),
                  ],
                ),
    );
  }
  
  Widget _buildInfoCard() {
    final driverName = _tripData?['driver_name'] as String? ?? 'Driver';
    final vehicleNumber = _tripData?['vehicle_number'] as String? ?? 'Vehicle';
    final destName = _tripData?['dest_location'] ?? _tripData?['destination_name'] ?? 'Destination';
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(vehicleNumber, style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.green),
                      SizedBox(width: 6),
                      Text('LIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('To: $destName', style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
