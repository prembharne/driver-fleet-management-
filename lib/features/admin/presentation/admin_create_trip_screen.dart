import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:driver_app/core/services/routing_service.dart';

class AdminCreateTripScreen extends StatefulWidget {
  const AdminCreateTripScreen({super.key});

  @override
  State<AdminCreateTripScreen> createState() => _AdminCreateTripScreenState();
}

class _AdminCreateTripScreenState extends State<AdminCreateTripScreen> {
  final _supabase = Supabase.instance.client;
  final _routingService = RoutingService();

  // Driver selection
  String? _selectedDriverId;
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoading = false;

  // Route inputs — index 0 = source, last = dest, middle = stops
  // We manage them as a list for easy reordering / insertion
  final List<TextEditingController> _stopCtrls = [];
  final List<LatLng?> _stopLatLngs = [];

  // Route Preview
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;
  String? _encodedPolyline;
  double _totalDistanceKm = 0.0;
  int _durationSec = 0;

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 5,
  );

  @override
  void initState() {
    super.initState();
    // Start with Source + Destination fields
    _stopCtrls.add(TextEditingController()); // source
    _stopLatLngs.add(null);
    _stopCtrls.add(TextEditingController()); // destination
    _stopLatLngs.add(null);
    _fetchDrivers();
  }

  @override
  void dispose() {
    for (final c in _stopCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _fetchDrivers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name, phone_number')
          .order('full_name');
      setState(() {
        _drivers = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _snack('Error loading drivers: $e', isError: true);
    }
  }

  void _addStop() {
    // Insert a new stop BEFORE the destination (last index)
    setState(() {
      _stopCtrls.insert(_stopCtrls.length - 1, TextEditingController());
      _stopLatLngs.insert(_stopLatLngs.length - 1, null);
      _clearRoute();
    });
  }

  void _removeStop(int index) {
    // Don't allow removing source (0) or destination (last)
    if (index == 0 || index == _stopCtrls.length - 1) return;
    setState(() {
      _stopCtrls[index].dispose();
      _stopCtrls.removeAt(index);
      _stopLatLngs.removeAt(index);
      _clearRoute();
    });
  }

  void _clearRoute() {
    _polylines.clear();
    _encodedPolyline = null;
    _totalDistanceKm = 0.0;
    _durationSec = 0;
  }

  Future<void> _geocode(int index) async {
    final query = _stopCtrls[index].text.trim();
    if (query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final pos = LatLng(locations.first.latitude, locations.first.longitude);
        setState(() {
          _stopLatLngs[index] = pos;
          _updateMarkers();
          _clearRoute();
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
      } else {
        if (mounted) _snack('Location not found');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', isError: true);
    }
  }

  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _stopLatLngs.length; i++) {
      final pos = _stopLatLngs[i];
      if (pos == null) continue;
      if (i == 0) {
        _markers.add(Marker(markerId: const MarkerId('stop_0'), position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: '🟢 Start: ${_stopCtrls[0].text}')));
      } else if (i == _stopCtrls.length - 1) {
        _markers.add(Marker(markerId: MarkerId('stop_$i'), position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: '🏁 End: ${_stopCtrls[i].text}')));
      } else {
        _markers.add(Marker(markerId: MarkerId('stop_$i'), position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: '📍 Stop $i: ${_stopCtrls[i].text}')));
      }
    }
  }

  Future<void> _calculateRoute() async {
    // Auto-geocode any unresolved stops
    for (int i = 0; i < _stopCtrls.length; i++) {
      if (_stopCtrls[i].text.isNotEmpty && _stopLatLngs[i] == null) {
        await _geocode(i);
      }
    }

    final source = _stopLatLngs.first;
    final dest = _stopLatLngs.last;
    if (source == null || dest == null) {
      _snack('Please set Source and Destination', isError: true);
      return;
    }

    final waypoints = _stopLatLngs.sublist(1, _stopLatLngs.length - 1)
        .where((e) => e != null).cast<LatLng>().toList();

    setState(() => _isLoading = true);

    final result = await _routingService.getRoute(
      origin: source,
      destination: dest,
      waypoints: waypoints,
    );

    setState(() {
      _isLoading = false;
      if (result != null) {
        _encodedPolyline = result['polyline'];
        _totalDistanceKm = result['distance_meters'] / 1000;
        _durationSec = result['duration_seconds'];

        _polylines.clear();
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: PolylinePoints.decodePolyline(_encodedPolyline!)
              .map((e) => LatLng(e.latitude, e.longitude)).toList(),
          color: const Color(0xFF1565C0),
          width: 5,
          patterns: [],
        ));

        _updateMarkers();

        // Fit map to route bounds
        if (_mapController != null) {
          final bounds = result['bounds'];
          final ne = bounds['northeast'];
          final sw = bounds['southwest'];
          _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
              LatLngBounds(
                  southwest: LatLng(sw['lat'], sw['lng']),
                  northeast: LatLng(ne['lat'], ne['lng'])),
              60));
        }
      } else {
        _snack('Could not calculate route. Check locations.', isError: true);
      }
    });
  }

  Future<void> _assignTrip() async {
    if (_selectedDriverId == null) {
      _snack('Please select a driver', isError: true);
      return;
    }
    if (_encodedPolyline == null) {
      _snack('Please calculate the route first', isError: true);
      return;
    }

    // Build waypoints list (exclude source and dest)
    final waypointsJson = <Map<String, dynamic>>[];
    for (int i = 1; i < _stopCtrls.length - 1; i++) {
      if (_stopLatLngs[i] != null) {
        waypointsJson.add({
          'name': _stopCtrls[i].text,
          'lat': _stopLatLngs[i]!.latitude,
          'lng': _stopLatLngs[i]!.longitude,
        });
      }
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.from('trips').insert({
        'driver_id': _selectedDriverId,
        'start_location': _stopCtrls.first.text,
        'start_lat': _stopLatLngs.first!.latitude,
        'start_lng': _stopLatLngs.first!.longitude,
        'dest_location': _stopCtrls.last.text,
        'dest_lat': _stopLatLngs.last!.latitude,
        'dest_lng': _stopLatLngs.last!.longitude,
        'waypoints': waypointsJson,
        'planned_route_polyline': _encodedPolyline,
        'total_distance_km': double.parse(_totalDistanceKm.toStringAsFixed(2)),
        'status': 'assigned',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        _snack('Trip assigned successfully! ✅');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Assign Trip Route', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          // ─── Form panel ───────────────────────────────────────────
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Driver selector
                  _sectionLabel('Select Driver'),
                  DropdownButtonFormField<String>(
                    value: _selectedDriverId,
                    hint: const Text('Choose a driver'),
                    items: _drivers.map((d) => DropdownMenuItem(
                      value: d['id'].toString(),
                      child: Row(children: [
                        const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
                        const SizedBox(width: 10),
                        Text(d['full_name'] ?? 'Unknown'),
                      ]),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedDriverId = v),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(), fillColor: Colors.white, filled: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Route builder
                  _sectionLabel('Define Route (in order)'),
                  const Text('Admin sets the exact route. Driver will follow it as-is.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),

                  // Visual route builder
                  _buildRouteBuilder(),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _calculateRoute,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.map_outlined),
                      label: Text(_isLoading ? 'Calculating...' : 'Calculate Route Preview'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),

                  // Route info summary
                  if (_encodedPolyline != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green[300]!),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_totalDistanceKm.toStringAsFixed(1)} km',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('Est. ${_formatDuration(_durationSec)} driving time',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ]),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ─── Map preview ──────────────────────────────────────────
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _kInitialPosition,
                  onMapCreated: (c) => _mapController = c,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                ),
                if (_encodedPolyline != null)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _assignTrip,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'ASSIGN TO DRIVER  ·  ${_totalDistanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF333333))),
    );
  }

  /// Visual vertical route builder: Source → Stop1 → Stop2 → Destination
  Widget _buildRouteBuilder() {
    return Column(
      children: _stopCtrls.asMap().entries.map((entry) {
        final index = entry.key;
        final isFirst = index == 0;
        final isLast = index == _stopCtrls.length - 1;
        final isStop = !isFirst && !isLast;

        Color dotColor = isFirst ? Colors.green : (isLast ? Colors.red : Colors.orange);
        IconData dotIcon = isFirst ? Icons.radio_button_checked : (isLast ? Icons.flag : Icons.location_on);
        String label = isFirst ? 'Source' : (isLast ? 'Destination' : 'Stop $index');

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Icon(dotIcon, color: dotColor, size: 22),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 52,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.grey[300],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Input field
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: entry.value,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    fillColor: Colors.white,
                    filled: true,
                    isDense: true,
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_stopLatLngs[index] != null)
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                      IconButton(
                        icon: const Icon(Icons.search, size: 20),
                        tooltip: 'Find location',
                        onPressed: () => _geocode(index),
                      ),
                    ]),
                  ),
                  onChanged: (_) {
                    _stopLatLngs[index] = null; // reset latlng on text change
                    _clearRoute();
                  },
                  onSubmitted: (_) => _geocode(index),
                ),
              ),
            ),
            // Remove button (only for intermediate stops)
            if (isStop)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 22),
                  tooltip: 'Remove stop',
                  onPressed: () => _removeStop(index),
                ),
              )
            else
              const SizedBox(width: 48), // alignment placeholder
          ],
        );
      }).cast<Widget>().toList()
        // Add Stop button at the end (before destination)
        ..insert(_stopCtrls.length - 1, Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 4),
          child: TextButton.icon(
            onPressed: _addStop,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Add Intermediate Stop'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue[700]),
          ),
        )),
    );
  }
}
