import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:driver_fleet_admin/core/services/routing_service.dart';
import '../data/route_repository.dart';
import 'admin_route_master_screen.dart';

/// Admin screen to upload an Excel (.xlsx) file and import routes into route_master + vehicles.
class AdminRouteImportScreen extends StatefulWidget {
  const AdminRouteImportScreen({super.key});

  @override
  State<AdminRouteImportScreen> createState() => _AdminRouteImportScreenState();
}

class _AdminRouteImportScreenState extends State<AdminRouteImportScreen> {
  static const _bg      = Color(0xFF0F1117);
  static const _card    = Color(0xFF1C1F2A);
  static const _accent  = Color(0xFF4F8EF7);
  static const _border  = Color(0xFF2D3555);

  bool _importing = false;
  bool _parseDone = false;
  List<_RouteRow> _parsedRows = [];
  String? _fileName;

  // ── pick + parse file ──────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        throw Exception('Could not read file bytes.');
      }

      setState(() {
        _fileName = file.name;
      });

      _parseExcelFile(bytes);

    } catch (e) {
      _snack('Error picking file: $e', Colors.red);
    }
  }

  void _parseExcelFile(Uint8List bytes) {
    try {
      var excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];

      if (sheet == null) {
        throw Exception('No sheet found in the Excel file.');
      }

      List<_RouteRow> parsed = [];
      int skipped = 0;

      // Start reading from row index 1 (skip header)
      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.row(i);
        if (row.isEmpty) continue;

        try {
          // Fallback reading different types of cell values safely
          dynamic getValue(Data? data) => data?.value;

          final routeIdVal = getValue(row.length > 0 ? row[0] : null)?.toString();
          if (routeIdVal == null || routeIdVal.trim().isEmpty) {
            skipped++;
            continue; // Route ID is mandatory
          }

          // Handle double IDs from excel parsing
          double? parsedDouble = double.tryParse(routeIdVal);
          int routeId = parsedDouble?.toInt() ?? int.parse(routeIdVal);

          final outletName = getValue(row.length > 1 ? row[1] : null)?.toString() ?? 'Unknown Outlet';
          final vehicleNum = getValue(row.length > 2 ? row[2] : null)?.toString() ?? '';
          final daNumber = getValue(row.length > 3 ? row[3] : null)?.toString() ?? '';
          final deliveryPartner = getValue(row.length > 4 ? row[4] : null)?.toString() ?? '';
          final vehicleType = getValue(row.length > 5 ? row[5] : null)?.toString() ?? 'Temp';
          final tempDistance = getValue(row.length > 6 ? row[6] : null)?.toString() ?? '';
          
          double? distanceKm = double.tryParse(tempDistance);
          // Safety to prevent mapping a 10-digit mobile number as Distance in case Excel columns shifted
          if (distanceKm != null && distanceKm > 15000) {
            distanceKm = null;
          }

          parsed.add(_RouteRow(
            routeId,
            outletName,
            vehicleNum,
            vehicleType,
            daNumber,
            deliveryPartner,
            distanceKm,
          ));
        } catch (e) {
          skipped++;
          debugPrint('Skipping row $i due to error: $e');
        }
      }

      setState(() {
        _parsedRows = parsed;
        _parseDone = true;
      });

      if (skipped > 0) {
        _snack('Parsed ${parsed.length} rows. Skipped $skipped invalid rows.', Colors.orange);
      } else {
        _snack('Successfully parsed ${parsed.length} rows.', Colors.green);
      }
    } catch (e) {
      _snack('Error parsing excel: $e', Colors.red);
    }
  }

  // ── import to Supabase ─────────────────────────────────────────────────────
  Future<void> _importAll() async {
    if (_parsedRows.isEmpty) return;
    setState(() => _importing = true);

    try {
      final Map<int, Map<String, dynamic>> routeMastersMap = {};
      final Map<String, Map<String, dynamic>> vehiclesMap = {};

      final routing = RoutingService();
      
      // Default Source as seen before
      final defaultSource = 'Bhoir Warehouse, Mumbai';
      LatLng? cachedSourceLatLng;

      int processedCount = 0;

      for (final row in _parsedRows) {
        // Find destination Lat/Lng via Google API
        LatLng? destLatLng = await routing.getCoordinatesFromAddress(row.outletName);
        
        // Find source Lat/Lng (cache it to save api calls since it is the same default every time)
        if (cachedSourceLatLng == null) {
          cachedSourceLatLng = await routing.getCoordinatesFromAddress(defaultSource);
        }

        double? sLat = cachedSourceLatLng?.latitude ?? 19.1950;
        double? sLng = cachedSourceLatLng?.longitude ?? 73.0535;
        double? dLat = destLatLng?.latitude;
        double? dLng = destLatLng?.longitude;
        
        double? calcDist = row.distanceKm;

        if (calcDist == null && dLat != null && dLng != null) {
           final routeResponse = await routing.getRoute(
             origin: LatLng(sLat, sLng),
             destination: LatLng(dLat, dLng),
           );
           if (routeResponse != null && routeResponse['distance_meters'] != null) {
             calcDist = (routeResponse['distance_meters'] as num) / 1000.0;
           }
        }

        routeMastersMap[row.routeId] = {
          'route_id': row.routeId,
          'outlet_name': row.outletName,
          'source_name': defaultSource,
          'source_lat': sLat,
          'source_lng': sLng,
          'destination_name': row.outletName,
          'destination_lat': dLat,
          'destination_lng': dLng,
          'fixed_distance_km': calcDist,
          'delivery_partner': row.deliveryPartner.isNotEmpty ? row.deliveryPartner : null,
        };

        // Only upsert vehicle if a number was provided
        if (row.vehicleNumber.trim().isNotEmpty) {
          vehiclesMap[row.vehicleNumber] = {
            'vehicle_number': row.vehicleNumber,
            'vehicle_type': row.vehicleType,
            'route_id': row.routeId,
          };
        }
        
        processedCount++;
        // Optional debug
        debugPrint('Geocoded $processedCount / ${_parsedRows.length}');
      }

      await RouteRepository.instance.bulkImport(
         routeMasterData: routeMastersMap.values.toList(),
         vehiclesData: vehiclesMap.values.toList(),
      );

      if (mounted) {
        _snack('✅ Geocoded & Imported ${_parsedRows.length} routes successfully!', Colors.green);
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminRouteMasterScreen()),
          );
        }
      }
    } catch (e) {
      _snack('Import failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Import Routes from Excel',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Add Route Manually ──
            const Text('Add New Route', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enter route details with Start Location, Destination, and Distance (KM).',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminRouteMasterScreen(showAddDialogOnLoad: true),
                    ),
                  );
                },
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Add Route Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // ── Preview table ──
            if (_parsedRows.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(children: [
                const Text('Preview', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_parsedRows.length} rows',
                      style: const TextStyle(color: _accent, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 12),
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                ),
                child: const Row(children: [
                  SizedBox(width: 42, child: Text('Route', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(child: Text('Outlet Name', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                  SizedBox(width: 110, child: Text('Vehicle', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                  SizedBox(width: 90, child: Text('Type', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                ]),
              ),
              ..._parsedRows.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: i.isEven ? _card : _card.withOpacity(0.7),
                    border: Border(bottom: BorderSide(color: _border.withOpacity(0.3))),
                  ),
                  child: Row(children: [
                    SizedBox(width: 42,
                      child: Text('${r.routeId}',
                          style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(child: Text(r.outletName,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 110, child: Text(r.vehicleNumber.isEmpty ? '-' : r.vehicleNumber,
                        style: const TextStyle(color: Colors.white70, fontSize: 11))),
                    SizedBox(width: 90, child: Text(r.vehicleType.isEmpty ? '-' : r.vehicleType,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                );
              }),
              const SizedBox(height: 24),

              // Import button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _importing ? null : _importAll,
                  icon: _importing
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(_importing ? 'Importing…' : 'Import All ${_parsedRows.length} Routes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _RouteRow {
  final int routeId;
  final String outletName;
  final String vehicleNumber;
  final String vehicleType;
  final String daNumber;
  final String deliveryPartner;
  final double? distanceKm;

  _RouteRow(this.routeId, this.outletName, this.vehicleNumber, this.vehicleType,
      this.daNumber, this.deliveryPartner, this.distanceKm);
}
