import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_app/features/tracking/services/tracking_service.dart';
import 'package:driver_app/core/services/routing_service.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'issue_report_screen.dart';

enum TripStatus { idle, active, paused }


class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  final Completer<GoogleMapController> _mapController = Completer();
  final TrackingService _service = TrackingService.instance;
  // Removed _searchCtrl as search is disabled

  String? _tripId;
  TripStatus _tripStatus = TripStatus.idle;
  double _totalDistance = 0.0;
  Map<String, dynamic>? _currentTrip; // Store current trip data for route_id access
  
  final List<LatLng> _drivenPath = [];
  final List<LatLng> _projectedRoute = [];

  Position? _lastPosition;
  final Set<Marker> _markers = {};
  // Removed _isSearching
  BitmapDescriptor? _truckIcon;

  // Average speed tracking
  final List<double> _speedReadings = [];
  static const int _maxSpeedReadings = 10;

  LatLng? _destination;
  LatLng? _source;           // Admin-defined origin
  String _sourceName = '';
  String _destinationName = '';
  List<String> _waypointNames = [];  // Stop names in order
  double _remainingDistanceKm = 0.0;

  final Stopwatch _tripStopwatch = Stopwatch();
  Timer? _uiTimer;
  String _elapsedTimeDisplay = '00:00:00';
  Duration? _elapsedOffset; // Tracks real elapsed from server started_at

  String _etaDisplay = '--:--';
  double _currentSpeedMps = 0.0;
  
  bool _routeLoaded = false;

  static const double _geoFenceRadius = 300.0;
  bool _leftSourceFence = false;
  bool _enteredDestFence = false;
  bool _deviationAlerted = false; // prevents repeated alerts
  bool _hasArrived = false; // prevents duplicate arrival handling

  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _tripChannel;

  // Daily earnings tracking
  List<Map<String, dynamic>> _dailyStats = [];
  bool _showEarnings = false;

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 14.5,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTruckIcon();
    _initLocation();
    _subscribeToTripUpdates();
  }

  /// Subscribe to Realtime so the screen refreshes when admin assigns a new trip.
  void _subscribeToTripUpdates() {
    final driverId = _service.currentDriverId;
    _tripChannel = Supabase.instance.client
        .channel('tracking_trips_$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (payload) {
            debugPrint('[TrackingScreen] Realtime: new trip inserted → refreshing');
            // Only refresh if driver is currently idle (not mid-trip)
            if (_tripStatus == TripStatus.idle) {
              _refreshTrip();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (payload) {
            debugPrint('[TrackingScreen] Realtime: trip updated → refreshing');
            if (_tripStatus == TripStatus.idle) {
              _refreshTrip();
            }
          },
        )
        .subscribe();
  }

  /// Clear cached trip state and reload the latest trip from DB.
  Future<void> _refreshTrip() async {
    if (!mounted) return;
    setState(() {
      _tripId = null;
      _tripStatus = TripStatus.idle;
      _sourceName = '';
      _destinationName = '';
      _waypointNames = [];
      _source = null;
      _destination = null;
      _projectedRoute.clear();
      _routeLoaded = false;
      _elapsedOffset = null;
      _tripStopwatch.reset();
      _elapsedTimeDisplay = '00:00:00';
      _markers.removeWhere((m) =>
          m.markerId.value == 'source' ||
          m.markerId.value == 'destination' ||
          m.markerId.value.startsWith('waypoint_'));
    });
    await _loadAssignedTrip();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _uiTimer?.cancel();
    _tripChannel?.unsubscribe();
    _tripStopwatch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<void> _loadTruckIcon() async {
    try {
      _truckIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/truck_marker.png',
      );
    } catch (_) {
      // Fallback if asset missing
    }
  }

  Future<void> _initLocation() async {
    // Load trip first so it's visible even if GPS fails
    _loadAssignedTrip();

    try {
      final hasPermission = await _service.checkPermissions();
      if (!hasPermission) {
        if (mounted) _showSnackbar('Location services required for tracking', isError: true);
        return;
      }
      _getCurrentLocation();
    } catch (e) {
      debugPrint('Location init failed: $e');
      if (mounted) _showSnackbar('Please enable Location Services', isError: true);
    }
  }

  Future<void> _loadAssignedTrip() async {
    final driverId = _service.currentDriverId;
    if (driverId == null) return;
    debugPrint('[TrackingScreen] _loadAssignedTrip for driver: $driverId');

    final trip = await _service.getAssignedTrip(driverId);
    debugPrint('[TrackingScreen] trip found: $trip');

    if (trip == null) {
      debugPrint('[TrackingScreen] No trip found — driver idle');
      return; // Normal idle state, no snackbar
    }
    
    setState(() {
      _tripId = trip['id'];
      _currentTrip = trip; // Store trip data for route_id access
      debugPrint('[TrackingScreen] _tripId set to: $_tripId');
      final status = trip['status'] as String? ?? 'scheduled';
      _tripStatus = status == 'active'
          ? TripStatus.active
          : (status == 'paused' ? TripStatus.paused : TripStatus.idle);

      // Initialize distance from DB
      _totalDistance = (trip['total_distance_km'] as num? ?? 0.0).toDouble();

      // Always capture text names (works even when lat/lng is null)
      _sourceName      = trip['start_location'] as String? ?? '';
      _destinationName = trip['dest_location']  as String? ?? '';

      // Parse Source coordinates (admin-defined)
      if (trip['start_lat'] != null && trip['start_lng'] != null) {
        _source = LatLng(
          (trip['start_lat'] as num).toDouble(),
          (trip['start_lng'] as num).toDouble(),
        );
        _markers.add(Marker(
          markerId: const MarkerId('source'),
          position: _source!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Start: $_sourceName'),
        ));
      }
      
      // Parse destination coordinates
      if (trip['dest_lat'] != null && trip['dest_lng'] != null) {
        _destination = LatLng(
          (trip['dest_lat'] as num).toDouble(),
          (trip['dest_lng'] as num).toDouble(),
        );
        _markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: _destinationName),
        ));
      }

      // Parse Waypoints
      _waypointNames = [];
      if (trip['waypoints'] != null) {
        final List<dynamic> waypoints = trip['waypoints'];
        for (int i = 0; i < waypoints.length; i++) {
          final wp = waypoints[i];
          final pos = LatLng(
            (wp['lat'] as num).toDouble(),
            (wp['lng'] as num).toDouble(),
          );
          final name = wp['name'] as String? ?? 'Stop ${i + 1}';
          _waypointNames.add(name);
          _markers.add(Marker(
             markerId: MarkerId('waypoint_$i'),
             position: pos,
             icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
             infoWindow: InfoWindow(title: '📍 Stop ${i + 1}: $name'),
          ));
        }
      }

      // Parse Polyline
      if (trip['planned_route_polyline'] != null) {
        _projectedRoute.clear();
        final points = PolylinePoints.decodePolyline(trip['planned_route_polyline'] as String);
        for (var p in points) {
           _projectedRoute.add(LatLng(p.latitude, p.longitude));
        }
        _routeLoaded = true; // Mark as loaded since we got it from DB
      } else {
        _routeLoaded = false;
      }
      
      // Restore timer state if trip was already active
      if (_tripStatus == TripStatus.active) {
        // ── Fix: Restore elapsed time from DB started_at so timer doesn't reset ──
        if (trip['started_at'] != null) {
          final startTime = DateTime.tryParse(trip['started_at'].toString());
          if (startTime != null) {
            final elapsed = DateTime.now().difference(startTime);
            // Offset the stopwatch so it shows correct elapsed time
            _tripStopwatch
              ..reset()
              ..start();
            // We can't directly set elapsed on a Stopwatch, so we track offset
            _elapsedOffset = elapsed;
          }
        }
        if (!_tripStopwatch.isRunning) _tripStopwatch.start();
        _positionSub ??= _service.getPositionStream().listen(_handleLocationUpdate);
        _uiTimer?.cancel();
        _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _elapsedTimeDisplay = _formatDuration(
                _tripStopwatch.elapsed + (_elapsedOffset ?? Duration.zero)));
          }
        });
      }
    });

    // If we have a destination but no route yet, attempt to fetch it using source or last known position.
    if (_destination != null && !_routeLoaded) {
       if (_lastPosition != null) {
         _fitBounds(_lastPosition!, _destination!);
         _fetchRoute();
       } else if (_source != null) {
         // Fallback to fetch route starting from source if last position isn't ready
         _fetchRouteFromSource();
       }
    } else if (_destination != null && _lastPosition != null && _routeLoaded) {
        // If route is loaded from DB, just fit the bounds
        _fitBounds(_lastPosition!, _destination!);
    }
  }

  // Fallback if _lastPosition is null
  Future<void> _fetchRouteFromSource() async {
    if (_source == null || _destination == null || _routeLoaded) return;
    try {
      final routing = RoutingService();
      final res = await routing.getRoute(origin: _source!, destination: _destination!);
      
      if (mounted && res != null && res['polyline'] != null && res['polyline'].toString().isNotEmpty) {
        final points = PolylinePoints.decodePolyline(res['polyline']);
        setState(() {
          _projectedRoute.clear();
          for (var p in points) {
            _projectedRoute.add(LatLng(p.latitude, p.longitude));
          }
           _routeLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch API route from source: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _moveCamera(position.latitude, position.longitude);
      setState(() {
        _lastPosition = position;
        _updateCurrentMarker(position);
      });
      // If we already loaded the trip destination but couldn't fetch the route
      // because we lacked the user's location, fetch it now.
      if (!_routeLoaded && _destination != null) {
        _fitBounds(position, _destination!);
        _fetchRoute();
      }
    } catch (e) {
      _showSnackbar('Could not get current location.', isError: true);
    }
  }

  // _searchLocation removed

  // _onMapTapSetDestination removed

  // _setDestination removed

  // _fetchRouteCurve removed

  /// Fetch route from Google Directions API and display on map.
  Future<void> _fetchRoute() async {
    if (_lastPosition == null || _destination == null || _routeLoaded) return;
    
    try {
      final routing = RoutingService();
      final origin = LatLng(_lastPosition!.latitude, _lastPosition!.longitude);
      final res = await routing.getRoute(origin: origin, destination: _destination!);
      
      if (mounted && res != null && res['polyline'] != null && res['polyline'].toString().isNotEmpty) {
        final points = PolylinePoints.decodePolyline(res['polyline']);
        setState(() {
          _projectedRoute.clear();
          for (var p in points) {
            _projectedRoute.add(LatLng(p.latitude, p.longitude));
          }
          _routeLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch API route: $e');
    }
  }

  void _fitBounds(Position start, LatLng end) async {
     final controller = await _mapController.future;
     LatLngBounds bounds;
     if (start.latitude > end.latitude && start.longitude > end.longitude) {
       bounds = LatLngBounds(southwest: end, northeast: LatLng(start.latitude, start.longitude));
     } else if (start.longitude > end.longitude) {
       bounds = LatLngBounds(
           southwest: LatLng(start.latitude, end.longitude),
           northeast: LatLng(end.latitude, start.longitude));
     } else if (start.latitude > end.latitude) {
       bounds = LatLngBounds(
           southwest: LatLng(end.latitude, start.longitude),
           northeast: LatLng(start.latitude, end.longitude));
     } else {
       bounds = LatLngBounds(southwest: LatLng(start.latitude, start.longitude), northeast: end);
     }
     controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _source = null;
      _sourceName = '';
      _destinationName = '';
      _waypointNames = [];
      _remainingDistanceKm = 0.0;
      _markers.removeWhere((m) =>
          m.markerId.value == 'destination' ||
          m.markerId.value == 'source' ||
          m.markerId.value.startsWith('waypoint_'));
      _projectedRoute.clear();
    });
  }

  Future<void> _startTrip() async {
    if (_tripId == null) {
        _showSnackbar('No assigned trip to start.');
        return;
    }
    if (_lastPosition == null) {
        _showSnackbar('Waiting for GPS...');
        return;
    }
    
    final success = await _service.startAssignedTrip(
       _tripId!,
       _lastPosition!.latitude,
       _lastPosition!.longitude,
    );
    
    if (!mounted) return;
    if (!success) {
      _showSnackbar('Failed to start trip.', isError: true);
      return;
    }

    if (_destination != null && _lastPosition != null) {
      _fitBounds(_lastPosition!, _destination!);
      _routeLoaded = false;
      _fetchRoute();
    }

    setState(() {
      _tripStatus = TripStatus.active;
      // Do not reset _totalDistance here; it was initialized from DB in _loadAssignedTrip
      _drivenPath.clear();
      _leftSourceFence = false;
      _enteredDestFence = false;
      _deviationAlerted = false;
      _markers.removeWhere((m) => m.markerId.value == 'tripStart');
      _markers.add(Marker(
        markerId: const MarkerId('tripStart'),
        position: LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Trip Start'),
      ));
    });
    _tripStopwatch
      ..reset()
      ..start();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedTimeDisplay = _formatDuration(_tripStopwatch.elapsed));
      }
    });

    // Subscribe to updates from service
    _service.distanceStream.listen((distKm) {
      if (mounted) setState(() => _totalDistance = distKm);
    });

    _positionSub = _service.positionStream.listen(_handleLocationUpdate);
  }

  Future<void> _pauseTrip() async {
    if (_tripId == null) return;
    await _service.pauseTrip(_tripId!);
    _positionSub?.pause();
    _tripStopwatch.stop();
    if (mounted) setState(() => _tripStatus = TripStatus.paused);
  }

  Future<void> _resumeTrip() async {
    if (_tripId == null) return;
    await _service.resumeTrip(_tripId!);
    _positionSub?.resume();
    _tripStopwatch.start();
    if (mounted) setState(() => _tripStatus = TripStatus.active);
  }

  Future<void> _stopTrip() async {
    if (_tripId != null && _lastPosition != null) {
      await _service.endTrip(
        _tripId!,
        _lastPosition!.latitude,
        _lastPosition!.longitude,
      );
    }
    _positionSub?.cancel();
    _tripStopwatch.stop();
    _uiTimer?.cancel();

    final distance = _totalDistance;
    final duration = _elapsedTimeDisplay == '00:00:00' ? _formatDuration(_tripStopwatch.elapsed) : _elapsedTimeDisplay;
    final avgSpeed = _tripStopwatch.elapsed.inSeconds > 0 ? (distance / (_tripStopwatch.elapsed.inSeconds / 3600)).toStringAsFixed(1) : '0.0';

    if (mounted) {
      setState(() {
        _tripStatus = TripStatus.idle;
        _tripId = null;
        _elapsedTimeDisplay = '00:00:00';
        _etaDisplay = '--:--';
        _projectedRoute.clear();
        _drivenPath.clear();
        _clearDestination();
      });
      _showTripSummaryDialog(distance, duration, avgSpeed);
    }
  }

  void _handleLocationUpdate(Position position) {
    if (mounted) {
      setState(() {
        _lastPosition = position;
        _currentSpeedMps = position.speed;
        _drivenPath.add(LatLng(position.latitude, position.longitude));
        _updateCurrentMarker(position);
        _updateRemainingDistance(position);
      });
    }
    _moveCamera(position.latitude, position.longitude);

    // Update speed readings
    if (position.speed > 0) {
      _speedReadings.add(position.speed);
      if (_speedReadings.length > _maxSpeedReadings) {
        _speedReadings.removeAt(0);
      }
    }

    _checkGeoFences(position);
    _checkRouteDeviation(position);
  }

  void _checkRouteDeviation(Position position) {
    if (_tripId == null || _projectedRoute.isEmpty) return;
    final planned = _projectedRoute
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();
    final deviated = _service.isDeviatingFromRoute(
      position.latitude, position.longitude, planned);
    if (deviated && !_deviationAlerted) {
      _deviationAlerted = true;
      _showDeviationAlert();
      _service.logDeviation(_tripId!, position.latitude, position.longitude);
    } else if (!deviated) {
      _deviationAlerted = false; // reset when back on route
    }
  }

  void _showDeviationAlert() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.white),
        SizedBox(width: 8),
        Expanded(child: Text('You have deviated from the planned route!')),
      ]),
      backgroundColor: Colors.deepOrange,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      action: SnackBarAction(
        label: 'DISMISS',
        textColor: Colors.white,
        onPressed: () {},
      ),
    ));
  }

  void _updateCurrentMarker(Position position) {
    _markers.removeWhere((m) => m.markerId.value == 'currentLocation');
    _markers.add(Marker(
      markerId: const MarkerId('currentLocation'),
      position: LatLng(position.latitude, position.longitude),
      rotation: position.heading,
      icon: _truckIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      infoWindow: InfoWindow(title: 'My Location', snippet: '${(position.speed * 3.6).toStringAsFixed(1)} km/h'),
    ));
  }

  void _updateRemainingDistance(Position position) {
    if (_destination == null) return;
    _remainingDistanceKm = Geolocator.distanceBetween(
      position.latitude, position.longitude, _destination!.latitude, _destination!.longitude) / 1000;
    _remainingDistanceKm = Geolocator.distanceBetween(
      position.latitude, position.longitude, _destination!.latitude, _destination!.longitude) / 1000;
    
    double avgSpeedMps = _currentSpeedMps;
    if (_speedReadings.isNotEmpty) {
      avgSpeedMps = _speedReadings.reduce((a, b) => a + b) / _speedReadings.length;
    }

    // Simple ETA calculation based on remaining distance and average speed
    if (avgSpeedMps > 0 && _remainingDistanceKm > 0) {
      final etaSeconds = (_remainingDistanceKm * 1000) / avgSpeedMps;
      final arrival = DateTime.now().add(Duration(seconds: etaSeconds.round()));
      _etaDisplay = '${arrival.hour.toString().padLeft(2,'0')}:${arrival.minute.toString().padLeft(2,'0')}';
    }
  }

  void _checkGeoFences(Position position) {
    if (_drivenPath.isNotEmpty && !_leftSourceFence) {
      final start = _drivenPath.first;
      if (!_service.isInsideGeoFence(position.latitude, position.longitude, start.latitude, start.longitude, _geoFenceRadius)) {
        _leftSourceFence = true;
        _showGeoFenceAlert('Left source geo-fence');
      }
    }
    if (_destination != null && !_enteredDestFence && !_hasArrived) {
      if (_service.isInsideGeoFence(position.latitude, position.longitude, _destination!.latitude, _destination!.longitude, _geoFenceRadius)) {
        _enteredDestFence = true;
        _hasArrived = true;
        _handleArrival();
      }
    }
  }

  /// Handle driver arrival at destination.
  /// Updates trip status to 'arrived' and shows confirmation dialog.
  Future<void> _handleArrival() async {
    if (_tripId == null) return;
    
    // Update trip status to arrived
    final success = await _service.markTripArrived(
      _tripId!,
      _lastPosition!.latitude,
      _lastPosition!.longitude,
    );
    
    if (success && mounted) {
      _showArrivalDialog();
    }
  }

  /// Show arrival confirmation dialog when driver reaches destination.
  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('Destination Reached!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text('You have arrived at:', style: TextStyle(fontWeight: FontWeight.bold)),
             SizedBox(height: 4),
             Text(_destinationName, style: TextStyle(fontSize: 16)),
             SizedBox(height: 16),
             Text('Route ID: ${_currentTrip?['route_id'] ?? 'N/A'}'),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(ctx);
              _stopTrip(); // End the trip
            },
            child: Text('Complete Trip'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveCamera(double lat, double lng) async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(lat, lng), zoom: 17, tilt: 45)));
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showGeoFenceAlert(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.location_on, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message))]),
      backgroundColor: Colors.deepPurple,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showTripSummaryDialog(double distanceKm, String duration, String avgSpeed) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Trip Summary'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
         _summaryRow(Icons.straighten, 'Distance', '${distanceKm.toStringAsFixed(2)} km'),
         const SizedBox(height: 10),
         _summaryRow(Icons.timer, 'Duration', duration),
         const SizedBox(height: 10),
         _summaryRow(Icons.speed, 'Avg Speed', '$avgSpeed km/h'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }
  
  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(children: [Icon(icon, size: 20, color: Colors.grey), const SizedBox(width: 10), Text(label), const Spacer(), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]);
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Trip?'),
        content: const Text('Are you sure you want to exit? The trip will be stopped.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.pop(ctx); _stopTrip(); Navigator.pop(context); }, child: const Text('End Trip', style: TextStyle(color: Colors.red))),
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: _kInitialPosition,
          markers: _markers,
          polylines: {
            if (_drivenPath.isNotEmpty) Polyline(polylineId: const PolylineId('drivenPath'), color: Colors.grey, width: 5, points: _drivenPath),
            if (_projectedRoute.isNotEmpty) Polyline(polylineId: const PolylineId('projectedRoute'), color: Colors.blueAccent, width: 6, points: _projectedRoute),
          },
          circles: _buildGeoFenceCircles(),
          onMapCreated: (c) => _mapController.complete(c),
          // onTap removed
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          padding: const EdgeInsets.only(top: 100, bottom: 200),
        ),
        // ── Top Route Header ──────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 20),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.route, color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        const Text('Assigned Route', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        if (_tripId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _tripStatus == TripStatus.active ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _tripStatus == TripStatus.active ? 'ACTIVE' : (_tripStatus == TripStatus.paused ? 'PAUSED' : 'ASSIGNED'),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        // Manual refresh button — always visible
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20, color: Colors.blueGrey),
                          tooltip: 'Reload latest trip',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            if (_tripStatus == TripStatus.idle) {
                              _refreshTrip();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot refresh during an active trip')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  // Route stops
                  if (_tripId != null) _buildRouteStopsRow(),
                  if (_tripId == null)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange, size: 16),
                          SizedBox(width: 6),
                          Text('No trip assigned yet', style: TextStyle(color: Colors.orange, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 20, top: 120,
          child: FloatingActionButton.small(backgroundColor: Colors.white, child: const Icon(Icons.my_location, color: Colors.blue), onPressed: _lastPosition != null ? () => _moveCamera(_lastPosition!.latitude, _lastPosition!.longitude) : null),
        ),
        _buildBottomPanel(),
      ]),
    );
  }

  Widget _buildBottomPanel() {
     return Positioned(
       bottom: 0, left: 0, right: 0,
       child: Container(
         padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
         decoration: const BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
           boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]
         ),
         child: Column(mainAxisSize: MainAxisSize.min, children: [
             // Drag handle
             Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
             if (_tripStatus != TripStatus.idle) ...[  
               // Active trip stats
               Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                 _statItem('Dist', '${_totalDistance.toStringAsFixed(1)}km', Icons.map, Colors.blue),
                 _statItem('Time', _elapsedTimeDisplay, Icons.timer, Colors.orange),
                 _statItem('ETA', _etaDisplay, Icons.schedule, Colors.green),
               ]),
               const SizedBox(height: 12),
               if (_destination != null)
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                   child: Row(
                     children: [
                       const Icon(Icons.flag, color: Colors.red, size: 18),
                       const SizedBox(width: 8),
                       Expanded(child: Text('$_destinationName  ·  ${_remainingDistanceKm.toStringAsFixed(1)} km remaining', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                     ],
                   ),
                 ),
               const SizedBox(height: 12),
             ] else if (_tripId != null) ...[  
               // Assigned but not started — show route info
               Container(
                 padding: const EdgeInsets.all(12),
                 margin: const EdgeInsets.only(bottom: 12),
                 decoration: BoxDecoration(
                   color: Colors.blue[50],
                   borderRadius: BorderRadius.circular(10),
                   border: Border.all(color: Colors.blue[100]!),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     const Text('Your Trip Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                     const SizedBox(height: 8),
                     _routeInfoRow(Icons.radio_button_checked, Colors.green, 'From', _sourceName.isNotEmpty ? _sourceName : 'Your current location'),
                     if (_waypointNames.isNotEmpty) ..._waypointNames.asMap().entries.map((e) =>
                       _routeInfoRow(Icons.location_on, Colors.orange, 'Stop ${e.key + 1}', e.value)
                     ),
                     _routeInfoRow(Icons.flag, Colors.red, 'To', _destinationName.isNotEmpty ? _destinationName : 'Destination'),
                   ],
                 ),
               ),
             ],
             // Daily Earnings section (shown for any trip)
             if (_tripId != null) _buildEarningsSection(),
             _buildActionButtons(),
           ]),
       ),
     );
  }

  Widget _routeInfoRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  /// Load daily stats from DB
  Future<void> _loadDailyStats() async {
    if (_tripId == null) return;
    final stats = await _service.getTripDailyStats(_tripId!);
    if (mounted) setState(() => _dailyStats = stats);
  }

  /// Collapsible distance breakdown card (no earnings/rate shown)
  Widget _buildEarningsSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            if (!_showEarnings && _dailyStats.isEmpty) _loadDailyStats();
            setState(() => _showEarnings = !_showEarnings);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Distance Travelled  ·  ${_totalDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue),
                  ),
                ),
                Icon(_showEarnings ? Icons.expand_less : Icons.expand_more, color: Colors.blue, size: 20),
              ],
            ),
          ),
        ),
        if (_showEarnings)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: _dailyStats.isEmpty
                ? const Center(child: Text('No daily data yet', style: TextStyle(fontSize: 12, color: Colors.grey)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily Distance Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      // Table header
                      Row(children: [
                        Expanded(flex: 2, child: Text('Day', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600))),
                        Expanded(flex: 3, child: Text('Daily KM', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600))),
                        Expanded(flex: 3, child: Text('Total KM', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600))),
                      ]),
                      const Divider(height: 8),
                      ..._dailyStats.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final stat = entry.value;
                        final dailyKm = (stat['distance_km'] as num?)?.toDouble() ?? 0;
                        double cumulativeKm = 0;
                        for (int i = 0; i <= idx; i++) {
                          cumulativeKm += (_dailyStats[i]['distance_km'] as num?)?.toDouble() ?? 0;
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(flex: 2, child: Text('Day ${idx + 1}', style: const TextStyle(fontSize: 11))),
                            Expanded(flex: 3, child: Text('${dailyKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11))),
                            Expanded(flex: 3, child: Text('${cumulativeKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue))),
                          ]),
                        );
                      }),
                    ],
                  ),
          ),
      ],
    );
  }
  
  Widget _circleButton(IconData icon, Color color, VoidCallback onTap) {
      return CircleAvatar(backgroundColor: Colors.white, radius: 22, child: IconButton(icon: Icon(icon, color: color), onPressed: onTap));
  }
  
  Widget _statItem(String l, String v, IconData i, Color c) => Column(children:[Icon(i, color:c), Text(l, style:const TextStyle(fontSize:10)), Text(v, style:const TextStyle(fontWeight:FontWeight.bold))]);

  /// Builds a horizontal scrollable row showing: Source → Stop1 → Stop2 → Dest
  Widget _buildRouteStopsRow() {
    final stops = <Map<String, dynamic>>[];
    if (_sourceName.isNotEmpty) stops.add({'label': _sourceName, 'icon': Icons.radio_button_checked, 'color': Colors.green});
    for (int i = 0; i < _waypointNames.length; i++) {
      stops.add({'label': _waypointNames[i], 'icon': Icons.location_on, 'color': Colors.orange});
    }
    if (_destinationName.isNotEmpty) stops.add({'label': _destinationName, 'icon': Icons.flag, 'color': Colors.red});

    if (stops.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: stops.asMap().entries.map((e) {
            final isLast = e.key == stops.length - 1;
            return Row(children: [
              Icon(e.value['icon'] as IconData, size: 14, color: e.value['color'] as Color),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  e.value['label'] as String,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isLast) const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_tripStatus == TripStatus.idle) {
      if (_tripId == null) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange[200]!)),
          child: const Row(children: [
            Icon(Icons.access_time, color: Colors.orange, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Waiting for admin to assign a trip...', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500))),
          ]),
        );
      }
      return SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(
        onPressed: _startTrip,
        icon: const Icon(Icons.play_arrow),
        label: const Text('START ASSIGNED TRIP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ));
    } else {
         return Column(children: [
           Row(children: [
             Expanded(child: ElevatedButton(onPressed: _tripStatus==TripStatus.active ? _pauseTrip : _resumeTrip, child: Text(_tripStatus==TripStatus.active ? 'PAUSE' : 'RESUME'))),
             const SizedBox(width: 10),
             Expanded(child: ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor:Colors.red, foregroundColor: Colors.white), onPressed: _stopTrip, child: const Text('STOP'))),
           ]),
           const SizedBox(height: 10),
           SizedBox(width: double.infinity, child: OutlinedButton.icon(
             icon: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
             label: const Text('Report Issue', style: TextStyle(color: Colors.deepOrange)),
             style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange)),
             onPressed: _tripId != null ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueReportScreen(tripId: _tripId!))) : null,
           )),
         ]);
    }
  }

  Set<Circle> _buildGeoFenceCircles() {
     Set<Circle> c = {};
     if (_destination != null) c.add(Circle(circleId: const CircleId('destFence'), center: _destination!, radius: _geoFenceRadius, fillColor: Colors.red.withOpacity(0.1), strokeColor: Colors.red, strokeWidth: 1));
     if (_tripStatus != TripStatus.idle && _drivenPath.isNotEmpty) {
       c.add(Circle(circleId: const CircleId('sourceFence'), center: _drivenPath.first, radius: _geoFenceRadius, fillColor: Colors.green.withOpacity(0.1), strokeColor: Colors.green, strokeWidth: 1));
     }
     return c;
  }
}
