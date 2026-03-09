import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Singleton service for all GPS tracking & Supabase trip operations.
/// Usage: TrackingService.instance
class TrackingService {
  static final TrackingService instance = TrackingService._internal();
  TrackingService._internal();

  final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionSubscription;
  String? _activeTripId;
  
  /// Total distance in METERS.
  double _totalDistanceMeters = 0;
  Position? _lastPosition;

  /// Stream to notify UI of distance updates
  final _distanceStreamCtrl = StreamController<double>.broadcast();
  Stream<double> get distanceStream => _distanceStreamCtrl.stream;

  /// Stream to notify UI of position updates
  final _positionStreamCtrl = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionStreamCtrl.stream;

  double get currentDistanceKm => _totalDistanceMeters / 1000;

  /// Starts location tracking for a trip.
  /// Call this when trip status becomes 'active'.
  /// [initialDistanceKm] allows resuming from previous state.
  void startLocationTracking(String tripId, {double initialDistanceKm = 0}) {
    _activeTripId = tripId;
    _totalDistanceMeters = initialDistanceKm * 1000;
    _lastPosition = null;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _handlePositionUpdate(position);
    });
    
    debugPrint('[TrackingService] Started tracking for $tripId at ${initialDistanceKm.toStringAsFixed(2)} km');
  }

  /// Stops location tracking.
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeTripId = null;
    _totalDistanceMeters = 0;
    _lastPosition = null;
  }

  void _handlePositionUpdate(Position position) async {
    if (_activeTripId == null) return;

    try {
      final lat = position.latitude;
      final lng = position.longitude;
      double deltaMeters = 0;

      // Calculate distance if we have a previous position
      if (_lastPosition != null) {
        deltaMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          lat,
          lng,
        );
        
        // Threshold to ignore GPS noise if not moving much
        if (deltaMeters < 5) return;
        
        _totalDistanceMeters += deltaMeters;
      }
      _lastPosition = position;
      
      // Notify listeners (UI)
      _positionStreamCtrl.add(position);
      _distanceStreamCtrl.add(_totalDistanceMeters / 1000);

      // 1. Create location log
      await _supabase.from('location_logs').insert({
        'trip_id': _activeTripId,
        'driver_id': _supabase.auth.currentUser?.id,
        'lat': lat,
        'lng': lng,
        'heading': position.heading,
        'speed': position.speed,
      });

      // 2. Update trip with current location and cumulative distance
      await _supabase
          .from('trips')
          .update({
            'current_lat': lat,
            'current_lng': lng,
            'total_distance_km': _totalDistanceMeters / 1000,
          })
          .eq('id', _activeTripId!);

      // 3. Update daily stats (Incremental)
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day).toIso8601String();
      
      final existingStats = await _supabase
          .from('trip_daily_stats')
          .select('id, distance_km')
          .eq('trip_id', _activeTripId!)
          .eq('date', todayDate)
          .maybeSingle();

      if (existingStats != null) {
        // Add ONLY the delta to the existing daily total
        final currentDailyKm = (existingStats['distance_km'] as num? ?? 0).toDouble();
        await _supabase
            .from('trip_daily_stats')
            .update({
              'distance_km': currentDailyKm + (deltaMeters / 1000),
            })
            .eq('id', existingStats['id']);
      } else {
        await _supabase.from('trip_daily_stats').insert({
          'trip_id': _activeTripId,
          'date': todayDate,
          'distance_km': deltaMeters / 1000,
        });
      }

      debugPrint(
        '[TrackingService] Trip $_activeTripId updated: ($lat, $lng), '
        'Total: ${(_totalDistanceMeters / 1000).toStringAsFixed(3)} km (+$deltaMeters m)',
      );
    } catch (e) {
      debugPrint('[TrackingService] Error updating location: $e');
    }
  }

  /// Gets daily stats for a trip
  Future<List<Map<String, dynamic>>> getTripDailyStats(String tripId) async {
    try {
      final response = await _supabase
          .from('trip_daily_stats')
          .select('*')
          .eq('trip_id', tripId)
          .order('date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[TrackingService] Error getting daily stats: $e');
      return [];
    }
  }

  /// Creates a new trip in Supabase
  Future<String?> createTrip({
    required String driverId,
    required String startLocation,
    required String endLocation,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    String? vehicleId,
    int? routeId,
    String? trackingToken,
  }) async {
    try {
      final response = await _supabase
          .from('trips')
          .insert({
            'driver_id': driverId,
            'start_location': startLocation,
            'end_location': endLocation,
            'start_lat': startLat,
            'start_lng': startLng,
            'end_lat': endLat,
            'end_lng': endLng,
            'current_lat': startLat,
            'current_lng': startLng,
            'status': 'scheduled',
            'vehicle_id': vehicleId,
            'route_id': routeId,
            'tracking_token': trackingToken,
          })
          .select('id')
          .single();

      return response['id'];
    } catch (e) {
      debugPrint('[TrackingService] Error creating trip: $e');
      return null;
    }
  }

  /// Starts a trip (changes status to active)
  Future<bool> startTrip(String tripId, {bool isResuming = false}) async {
    try {
      double initialKm = 0.0;
      if (isResuming) {
        final existing = await _supabase.from('trips').select('total_distance_km').eq('id', tripId).maybeSingle();
        initialKm = (existing?['total_distance_km'] as num? ?? 0).toDouble();
      }

      await _supabase
          .from('trips')
          .update({
            'status': 'active',
            'started_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId);

      startLocationTracking(tripId, initialDistanceKm: initialKm);
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error starting trip: $e');
      return false;
    }
  }

  /// Pauses a trip
  Future<bool> pauseTrip(String tripId) async {
    try {
      await _supabase
          .from('trips')
          .update({
            'status': 'paused',
            'paused_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId);

      stopLocationTracking();
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error pausing trip: $e');
      return false;
    }
  }

  /// Resumes a paused trip
  Future<bool> resumeTrip(String tripId) async {
    try {
      final existing = await _supabase.from('trips').select('total_distance_km').eq('id', tripId).maybeSingle();
      final initialKm = (existing?['total_distance_km'] as num? ?? 0).toDouble();
      
      await _supabase
          .from('trips')
          .update({
            'status': 'active',
            'resumed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId);

      startLocationTracking(tripId, initialDistanceKm: initialKm);
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error resuming trip: $e');
      return false;
    }
  }

  /// Ends a trip (marks as completed)
  Future<bool> endTrip(String tripId, double lat, double lng) async {
    try {
      await _supabase
          .from('trips')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'end_lat': lat,
            'end_lng': lng,
          })
          .eq('id', tripId);

      stopLocationTracking();
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error ending trip: $e');
      return false;
    }
  }

  /// Gets trip history for a driver
  Future<List<Map<String, dynamic>>> getTripHistory(String driverId) async {
    try {
      final response = await _supabase
          .from('trips')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[TrackingService] Error getting trip history: $e');
      return [];
    }
  }

  /// Gets location logs for a trip
  Future<List<Map<String, dynamic>>> getLocationLogs(String tripId) async {
    try {
      final response = await _supabase
          .from('location_logs')
          .select('*')
          .eq('trip_id', tripId)
          .order('timestamp', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[TrackingService] Error getting location logs: $e');
      return [];
    }
  }

  /// Gets active trip for a driver
  Future<Map<String, dynamic>?> getActiveTrip(String driverId) async {
    try {
      final response = await _supabase
          .from('trips')
          .select('*')
          .eq('driver_id', driverId)
          .inFilter('status', ['scheduled', 'assigned', 'active', 'paused'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('[TrackingService] Error getting active trip: $e');
      return null;
    }
  }

  /// Updates trip status
  Future<bool> updateTripStatus(String tripId, String status, {Map<String, dynamic>? extras}) async {
    try {
      final update = <String, dynamic>{'status': status};
      if (extras != null) update.addAll(extras);
      await _supabase.from('trips').update(update).eq('id', tripId);
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error updating trip status: $e');
      return false;
    }
  }

  /// Marks trip as arrived at destination
  Future<bool> markArrived(String tripId) async {
    try {
      await _supabase
          .from('trips')
          .update({
            'status': 'arrived',
            'arrived_at': DateTime.now().toIso8601String(),
          })
          .eq('id', tripId);
      return true;
    } catch (e) {
      debugPrint('[TrackingService] Error marking arrived: $e');
      return false;
    }
  }

  // ─── Supabase Real-time Subscriptions ─────────────────────────────────

  Stream<List<Map<String, dynamic>>> subscribeToAssignedTrips(String driverId) {
    return _supabase
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Stream<Map<String, dynamic>?> subscribeToTrip(String tripId) {
    return _supabase
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('id', tripId)
        .map((data) => data.isNotEmpty ? data.first : null);
  }

  // ─── Helpers ─────────────────────────────────

  String? get currentDriverId => _supabase.auth.currentUser?.id;

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<Map<String, dynamic>?> getAssignedTrip(String driverId) => getActiveTrip(driverId);

  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  Future<bool> startAssignedTrip(String tripId, double lat, double lng) => startTrip(tripId);

  /// REDUNDANT: Fixed to use distanceStream instead.
  /// Kept for compatibility but now just returns success.
  Future<bool> updateTripLocation(String tripId, double lat, double lng, double distance, {double? deltaKm}) async {
    return true;
  }

  bool isDeviatingFromRoute(double currentLat, double currentLng, List<Map<String, dynamic>> plannedRoute) => false;

  Future<void> logDeviation(String tripId, double lat, double lng) async {
    try {
      await _supabase.from('trip_issues').insert({
        'trip_id': tripId,
        'issue_type': 'route_deviation',
        'description': 'Driver deviated from route',
        'latitude': lat,
        'longitude': lng,
      });
    } catch (_) {}
  }

  bool isInsideGeoFence(double lat, double lng, double fenceLat, double fenceLng, double radiusMeters) {
    final distance = Geolocator.distanceBetween(lat, lng, fenceLat, fenceLng);
    return distance <= radiusMeters;
  }

  Future<bool> markTripArrived(String tripId, double lat, double lng) => markArrived(tripId);
}

