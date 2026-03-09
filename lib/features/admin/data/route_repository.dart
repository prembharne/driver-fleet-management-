import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ParsedRouteResult {
  final List<Map<String, dynamic>> routeMasters;
  final List<Map<String, dynamic>> vehicles;
  final int skipped;

  ParsedRouteResult(this.routeMasters, this.vehicles, this.skipped);
}

class RouteRepository {
  RouteRepository._();
  static final instance = RouteRepository._();

  final _supabase = Supabase.instance.client;

  /// Parses Excel bytes into structured route_master and vehicle lists.
  ParsedRouteResult parseExcelFile(Uint8List bytes) {
    var excel = Excel.decodeBytes(bytes);
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];

    if (sheet == null) {
      throw Exception('No sheet found in the Excel file.');
    }

    final Map<int, Map<String, dynamic>> routeMastersMap = {};
    final Map<String, Map<String, dynamic>> vehiclesMap = {};
    int skipped = 0;

    for (int i = 1; i < sheet.maxRows; i++) {
      var row = sheet.row(i);
      if (row.isEmpty) continue;

      try {
        dynamic getValue(Data? data) => data?.value;

        final routeIdVal = getValue(row.length > 0 ? row[0] : null)?.toString();
        if (routeIdVal == null || routeIdVal.trim().isEmpty) {
          skipped++;
          continue; 
        }

        double? parsedDouble = double.tryParse(routeIdVal);
        int routeId = parsedDouble?.toInt() ?? int.parse(routeIdVal);

        final outletName = getValue(row.length > 1 ? row[1] : null)?.toString() ?? 'Unknown Outlet';
        final vehicleNum = getValue(row.length > 2 ? row[2] : null)?.toString() ?? '';
        final deliveryPartner = getValue(row.length > 4 ? row[4] : null)?.toString() ?? '';
        final vehicleType = getValue(row.length > 5 ? row[5] : null)?.toString() ?? 'Temp';

        routeMastersMap[routeId] = {
          'route_id': routeId,
          'outlet_name': outletName,
          'source_name': 'Bhoir Warehouse, Mumbai',
          'source_lat': 19.1950,
          'source_lng': 73.0535,
          'destination_name': outletName,
          'destination_lat': null,
          'destination_lng': null,
          'fixed_distance_km': null,
          'delivery_partner': deliveryPartner.isNotEmpty ? deliveryPartner : null,
        };

        if (vehicleNum.trim().isNotEmpty) {
          vehiclesMap[vehicleNum] = {
            'vehicle_number': vehicleNum,
            'vehicle_type': vehicleType,
            'route_id': routeId,
          };
        }
      } catch (e) {
        skipped++;
        debugPrint('Skipping row $i due to error: $e');
      }
    }
    return ParsedRouteResult(routeMastersMap.values.toList(), vehiclesMap.values.toList(), skipped);
  }

  /// Inserts routes and vehicles to Supabase.
  Future<void> bulkImport({
    required List<Map<String, dynamic>> routeMasterData,
    required List<Map<String, dynamic>> vehiclesData,
  }) async {
    if (routeMasterData.isNotEmpty) {
      for (var route in routeMasterData) {
        final routeId = route['route_id'];
        final existing = await _supabase
            .from('route_master')
            .select('id')
            .eq('route_id', routeId)
            .maybeSingle();
        
        final data = {
          ...route,
          'updated_at': DateTime.now().toIso8601String(),
        };
        
        if (existing != null) {
          await _supabase.from('route_master').update(data).eq('route_id', routeId);
        } else {
          data['created_at'] = DateTime.now().toIso8601String();
          await _supabase.from('route_master').insert(data);
        }
      }
    }

    if (vehiclesData.isNotEmpty) {
      for (var vehicle in vehiclesData) {
        final vehicleNumber = vehicle['vehicle_number'];
        final existing = await _supabase
            .from('vehicles')
            .select('id')
            .eq('vehicle_number', vehicleNumber)
            .maybeSingle();
        
        final data = {
          ...vehicle,
          'updated_at': DateTime.now().toIso8601String(),
        };
        
        if (existing != null) {
          await _supabase.from('vehicles').update(data).eq('vehicle_number', vehicleNumber);
        } else {
          await _supabase.from('vehicles').insert(data);
        }
      }
    }
  }
}
