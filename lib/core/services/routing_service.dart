import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class RoutingService {
  static const String _apiKey = 'AIzaSyBEBMnwWHyXYbSuwBnzjBy3u558qE7eYY0'; // New User API Key
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  Future<Map<String, dynamic>?> getRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
  }) async {
    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${destination.latitude},${destination.longitude}';
    
    String waypointsStr = '';
    if (waypoints != null && waypoints.isNotEmpty) {
      waypointsStr = '&waypoints=${waypoints.map((e) => '${e.latitude},${e.longitude}').join('|')}';
    }

    String url = '$_baseUrl?origin=$originStr&destination=$destStr$waypointsStr&mode=driving&key=$_apiKey';

    List<String> proxyUrls = [];
    if (kIsWeb) {
      proxyUrls = [
        'https://corsproxy.io/?' + Uri.encodeComponent(url),
        'https://api.allorigins.win/raw?url=' + Uri.encodeComponent(url),
        'https://thingproxy.freeboard.io/fetch/' + url
      ];
    } else {
      proxyUrls = [url];
    }

    dynamic data;
    bool success = false;

    for (String targetUrl in proxyUrls) {
      try {
        debugPrint('RoutingService: Trying: $targetUrl');
        final response = await http.get(Uri.parse(targetUrl)).timeout(
          const Duration(seconds: 15),
        );
        
        if (response.statusCode == 200) {
          final baseData = jsonDecode(response.body);
          if (baseData is Map && baseData.containsKey('contents') && baseData['contents'] != null) {
            data = jsonDecode(baseData['contents']);
          } else {
            data = baseData;
          }

          if (data != null && data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
            success = true;
            break;
          }
        }
      } catch (e) {
        debugPrint('RoutingService Error for $targetUrl: $e');
      }
    }

    if (success && data != null) {
      final route = data['routes'][0];
      final polyline = route['overview_polyline']['points'];
      
      // Calculate total distance/duration
      int distance = 0;
      int duration = 0;
      for (var leg in route['legs']) {
        distance += (leg['distance']['value'] as num).toInt();
        duration += (leg['duration']['value'] as num).toInt();
      }

      return {
        'polyline': polyline,
        'distance_meters': distance,
        'duration_seconds': duration,
        'bounds': route['bounds'],
      };
    } else {
      debugPrint('Google Directions failed entirely.');
    }

    // fallback 1: Open Source Routing Machine (OSRM) if Google is blocked by CORS/Quota
    try {
       final osrmUrl = 'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full';
       final osrmRes = await http.get(Uri.parse(osrmUrl));
       if (osrmRes.statusCode == 200) {
          final osrmData = jsonDecode(osrmRes.body);
          if (osrmData['code'] == 'Ok' && (osrmData['routes'] as List).isNotEmpty) {
             final route = osrmData['routes'][0];
             return {
                'polyline': route['geometry'],
                'distance_meters': (route['distance'] as num).toInt(),
                'duration_seconds': (route['duration'] as num).toInt(),
                'bounds': null,
             };
          }
       }
    } catch (e) {
       debugPrint('OSRM fallback failed: $e');
    }

    // fallback 2: straight line / bird's eye distance 
    double straightDist = Geolocator.distanceBetween(
      origin.latitude, origin.longitude,
      destination.latitude, destination.longitude,
    );
    
    // add 30% to approximate road distance routing
    int estimatedRoadDist = (straightDist * 1.3).round();
    
    // Avg approx time assuming 35km/h in mixed traffic
    int estimatedDurationSec = ((estimatedRoadDist / 1000.0) / 35.0 * 3600.0).round();

    return {
      'polyline': '',
      'distance_meters': estimatedRoadDist,
      'duration_seconds': estimatedDurationSec,
      'bounds': null,
    };
  }

  /// Geocode an address to LatLng using Google Geocoding API with Nominatim Fallback
  Future<LatLng?> getCoordinatesFromAddress(String address) async {
    if (address.trim().isEmpty) return null;
    
    final encodedAddress = Uri.encodeComponent(address);
    String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$_apiKey';

    List<String> proxyUrls = [];
    if (kIsWeb) {
      proxyUrls = [
        'https://corsproxy.io/?' + Uri.encodeComponent(url),
        'https://api.allorigins.win/raw?url=' + Uri.encodeComponent(url),
        'https://thingproxy.freeboard.io/fetch/' + url // thingproxy does not need encodeComponent typically, but let's try it
      ];
    } else {
      proxyUrls = [url];
    }

    dynamic data;
    bool success = false;

    for (String targetUrl in proxyUrls) {
      try {
        debugPrint('RoutingService Geocode: Trying: $targetUrl');
        final response = await http.get(Uri.parse(targetUrl)).timeout(
          const Duration(seconds: 10),
        );
        
        if (response.statusCode == 200) {
          if (kIsWeb && targetUrl.contains('base64')) {
             // just in case we used a proxy that encodes
          }
          final baseData = jsonDecode(response.body);
          if (baseData is Map && baseData.containsKey('contents') && baseData['contents'] != null) {
            data = jsonDecode(baseData['contents']);
          } else {
            data = baseData;
          }

          if (data != null && data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
            success = true;
            break;
          }
        }
      } catch (e) {
        debugPrint('Geocode try failed for $targetUrl: $e');
      }
    }

    if (success && data != null) {
      final location = data['results'][0]['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    } else {
      debugPrint('Google Geocode failed entirely - falling back to Nominatim');
    }
    
    // Fallback: OpenStreetMap Nominatim
    try {
      final nomUrl = 'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1';
      final nomRes = await http.get(Uri.parse(nomUrl), headers: {
        'User-Agent': 'FleetManagementApp/1.0'
      });
      if (nomRes.statusCode == 200) {
        final nomData = jsonDecode(nomRes.body);
        if (nomData is List && nomData.isNotEmpty) {
          final lat = double.tryParse(nomData[0]['lat'].toString());
          final lon = double.tryParse(nomData[0]['lon'].toString());
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (e) {
      debugPrint('Nominatim Geocode Error: $e');
    }
    
    return null;
  }
}
