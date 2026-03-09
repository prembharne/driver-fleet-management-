import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

/// Service for fetching turn-by-turn routing from OSRM (Open Source Routing Machine).
/// OSRM is free, open source, and requires no API key.
/// 
/// Usage: OsrmService().fetchRoute(origin, destination)
class OsrmService {
  static const _baseUrl = 'https://router.project-osrm.org/route/v1';

  /// Fetch a routing route from OSRM as a list of LatLng points.
  /// 
  /// [origin] - Starting point (latitude, longitude)
  /// [destination] - Ending point (latitude, longitude)
  /// 
  /// Returns a list of LatLng points representing the route geometry.
  /// Throws an exception if the route cannot be fetched.
  Future<List<LatLng>> fetchRoute(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=polyline',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'DriverFleetApp/1.0',
      });

       if (response.statusCode == 200) {
         final data = json.decode(response.body);
         if (data['code'] == 'Ok') {
           final geometry = data['routes'][0]['geometry'] as String;
           return PolylinePoints.decodePolyline(geometry)
               .map((p) => LatLng(p.latitude, p.longitude))
               .toList();
         } else {
           throw Exception('OSRM API returned error: ${data['code']}');
         }
       } else {
         throw Exception('Failed to fetch route from OSRM: ${response.statusCode}');
       }
    } catch (e) {
      debugPrint('OSRM fetchRoute error: $e');
      rethrow;
    }
  }

  /// Get the distance and duration for a route from OSRM.
  /// 
  /// [origin] - Starting point (latitude, longitude)
  /// [destination] - Ending point (latitude, longitude)
  /// 
  /// Returns a map with 'distance_km' (double) and 'duration_seconds' (int).
  Future<Map<String, dynamic>> getRouteDetails(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=false',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'DriverFleetApp/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok') {
          final route = data['routes'][0] as Map<String, dynamic>;
          return {
            'distance_km': (route['distance'] as num).toDouble() / 1000,
            'duration_seconds': route['duration'] as int,
          };
        } else {
          throw Exception('OSRM API returned error: ${data['code']}');
        }
      } else {
        throw Exception('Failed to fetch route details from OSRM: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OSRM getRouteDetails error: $e');
      rethrow;
    }
  }

  /// Check if OSRM service is available.
  Future<bool> isAvailable() async {
    try {
      final url = Uri.parse('$_baseUrl/health');
      final response = await http.get(url);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('OSRM health check failed: $e');
      return false;
    }
  }
}
