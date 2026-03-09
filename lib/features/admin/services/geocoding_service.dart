import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service for geocoding addresses to coordinates using Nominatim (OpenStreetMap).
/// Nominatim is free, open source, and requires no API key.
/// 
/// Usage: GeocodingService().geocode('SS Mumbai Virar ES73')
class GeocodingService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org/search';

  /// Geocode an address to get its latitude and longitude.
  /// 
  /// [query] - The address or place name to geocode
  /// 
  /// Returns a map with 'lat' and 'lng' as doubles, or null if not found.
  Future<Map<String, double>?> geocode(String query) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?q=${Uri.encodeComponent(query)}&format=json&limit=1',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'DriverFleetApp/1.0',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final firstResult = data[0] as Map<String, dynamic>;
          return {
            'lat': double.parse(firstResult['lat'] as String),
            'lng': double.parse(firstResult['lon'] as String),
          };
        }
      } else {
        debugPrint('Nominatim API returned status: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      debugPrint('Geocoding error for "$query": $e');
      return null;
    }
  }

  /// Validate if coordinates are within Mumbai bounds.
  /// Mumbai bounds: approximately 18.8-19.3°N, 72.7-73.1°E
  bool isValidMumbaiCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat >= 18.8 && lat <= 19.3 && lng >= 72.7 && lng <= 73.1;
  }

  /// Batch geocode multiple addresses.
  /// 
  /// [addresses] - List of address strings to geocode
  /// 
  /// Returns a map of address -> {lat, lng} for successfully geocoded addresses.
  Future<Map<String, Map<String, double>>> batchGeocode(List<String> addresses) async {
    final results = <String, Map<String, double>>{};
    
    for (final address in addresses) {
      final coords = await geocode(address);
      if (coords != null) {
        results[address] = coords;
      }
    }
    
    return results;
  }
}
