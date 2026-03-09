import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── colour tokens ─────────────────────────────────────────────────────────────
const _bg       = Color(0xFF0F0F1A);
const _surface  = Color(0xFF1A1A2E);
const _surface2 = Color(0xFF16213E);
const _accent   = Color(0xFF4FC3F7);
const _textHigh = Colors.white;
const _textMid  = Color(0xFFB0B8C8);
const _textLow  = Color(0xFF6B7A99);
const _border   = Color(0xFF2D3555);
const _green    = Color(0xFF4CAF50);
const _red      = Color(0xFFEF5350);
const _orange   = Color(0xFFFFB74D);
// ─────────────────────────────────────────────────────────────────────────────

/// Redesigned Admin "Assign Trip" screen — dropdown-driven.
/// Admin selects: Route → Vehicle (auto-suggested) → Driver.
/// No manual geocoding or text input required.
class AdminAssignTripWeb extends StatefulWidget {
  const AdminAssignTripWeb({super.key});

  @override
  State<AdminAssignTripWeb> createState() => _AdminAssignTripWebState();
}

class _AdminAssignTripWebState extends State<AdminAssignTripWeb> {
  final _supabase = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _routes  = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _drivers  = [];

  bool _loadingRoutes   = true;
  bool _loadingVehicles = true;
  bool _loadingDrivers  = true;
  bool _submitting      = false;

  Map<String, dynamic>? _selectedRoute;
  Map<String, dynamic>? _selectedVehicle;
  String? _selectedDriverId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadRoutes(), _loadVehicles(), _loadDrivers()]);
  }

  Future<void> _loadRoutes() async {
    try {
      final snapshot = await _supabase
          .from('route_master')
          .select('*')
          .order('route_id');
      
      if (mounted) setState(() { _routes = snapshot; _loadingRoutes = false; });
    } catch (_) { if (mounted) setState(() => _loadingRoutes = false); }
  }

  Future<void> _loadVehicles() async {
    try {
      final snapshot = await _supabase
          .from('vehicles')
          .select('*')
          .order('vehicle_number');
      
      if (mounted) setState(() { _vehicles = snapshot; _loadingVehicles = false; });
    } catch (_) { if (mounted) setState(() => _loadingVehicles = false); }
  }

  Future<void> _loadDrivers() async {
    try {
      final snapshot = await _supabase
          .from('profiles')
          .select('*')
          .eq('role', 'driver')
          .order('full_name');
      
      if (mounted) setState(() { _drivers = snapshot; _loadingDrivers = false; });
    } catch (_) { if (mounted) setState(() => _loadingDrivers = false); }
  }

  /// When a route is selected, auto-suggest the vehicle linked to that route.
  void _onRouteSelected(Map<String, dynamic>? route) {
    setState(() {
      _selectedRoute = route;
      _selectedVehicle = null;
      if (route != null) {
        final routeId = route['route_id'];
        // Try to pre-select the linked vehicle
        final linked = _vehicles.where((v) => v['route_id'] == routeId).toList();
        if (linked.isNotEmpty) _selectedVehicle = linked.first;
      }
    });
  }

  bool get _canAssign =>
      _selectedRoute != null &&
      _selectedVehicle != null &&
      _selectedDriverId != null &&
      !_submitting;

  Future<void> _assignTrip() async {
    if (!_canAssign) return;

    setState(() => _submitting = true);
    try {
      // ── Guard: prevent double-assignment ──
      final existingTrips = await _supabase
          .from('trips')
          .select('id, status')
          .eq('driver_id', _selectedDriverId!)
          .inFilter('status', ['scheduled', 'assigned', 'active', 'paused']);

      if (existingTrips.isNotEmpty) {
        _snack('⚠️ This driver already has an active/scheduled trip. Complete or cancel it first.', _orange);
        setState(() => _submitting = false);
        return;
      }

      final r   = _selectedRoute!;
      final v   = _selectedVehicle!;
      final now = DateTime.now();

      await _supabase.from('trips').insert({
        // Route linkage
        'route_id'                  : r['route_id'],
        'vehicle_id'                : v['id'],
        'driver_id'                 : _selectedDriverId,
        'status'                    : 'scheduled',

        // Source (Bhoir Warehouse)
        'start_location'            : r['source_name'],
        'start_lat'                 : r['source_lat'],
        'start_lng'                 : r['source_lng'],
        'source_name'               : r['source_name'],
        'source_lat'                : r['source_lat'],
        'source_lng'                : r['source_lng'],

        // Destination (outlet)
        'dest_location'             : r['destination_name'],
        'dest_lat'                  : r['destination_lat'],
        'dest_lng'                  : r['destination_lng'],
        'destination_name'          : r['destination_name'],
        'destination_lat'           : r['destination_lat'],
        'destination_lng'           : r['destination_lng'],

        // Distance from Excel / route master
        'total_distance_km'         : r['fixed_distance_km'] ?? 0,
        'estimated_duration_seconds': _estimateDuration(r['fixed_distance_km']),

        // Timestamps
        'assigned_at'               : now.toIso8601String(),
        'created_at'                : now.toIso8601String(),
      });

      if (mounted) {
        _snack('✅ Trip assigned successfully!', _green);
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _snack('Failed to assign trip: $e', _red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  int? _estimateDuration(double? km) {
    if (km == null) return null;
    // Assume average 30 km/h speed
    return ((km / 30) * 3600).round();
  }

  void _snack(String msg, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: c,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textHigh,
        title: const Text('Assign Trip', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _loadingRoutes || _loadingVehicles || _loadingDrivers
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Route selector
                    _label('1. Select Route'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: DropdownButton<Map<String, dynamic>>(
                        value: _selectedRoute,
                        hint: const Text('Choose a route', style: TextStyle(color: _textLow)),
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: _surface,
                        items: _routes.map((r) => DropdownMenuItem(
                          value: r,
                          child: Text('${r['route_id']} - ${r['outlet_name']}', style: const TextStyle(color: _textHigh)),
                        )).toList(),
                        onChanged: _onRouteSelected,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Vehicle selector
                    _label('2. Select Vehicle'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: DropdownButton<Map<String, dynamic>>(
                        value: _selectedVehicle,
                        hint: const Text('Choose a vehicle', style: TextStyle(color: _textLow)),
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: _surface,
                        items: _vehicles.map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('${v['vehicle_number']} (${v['vehicle_type']})', style: const TextStyle(color: _textHigh)),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedVehicle = v),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Driver selector
                    _label('3. Select Driver'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedDriverId,
                        hint: const Text('Choose a driver', style: TextStyle(color: _textLow)),
                        isExpanded: true,
                        underline: const SizedBox(),
                        dropdownColor: _surface,
                        items: _drivers.map((d) => DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text('${d['full_name']} - ${d['phone_number']}', style: const TextStyle(color: _textHigh)),
                        )).toList(),
                        onChanged: (id) => setState(() => _selectedDriverId = id),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Summary card
                    if (_selectedRoute != null && _selectedVehicle != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Trip Summary', style: TextStyle(color: _textHigh, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          _summaryRow('Route', '${_selectedRoute!['route_id']} - ${_selectedRoute!['outlet_name']}'),
                          _summaryRow('Vehicle', _selectedVehicle!['vehicle_number']),
                          _summaryRow('Distance', '${_selectedRoute!['fixed_distance_km'] ?? '?'} km'),
                        ]),
                      ),

                    const SizedBox(height: 32),

                    // Assign button — warm amber for encouraging action
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _canAssign ? _assignTrip : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF57C00), // Warm amber — action psychology
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF3A3A50),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('ASSIGN TRIP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(color: _textMid, fontWeight: FontWeight.w600));
  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: _textLow)),
      Expanded(child: Text(value, style: const TextStyle(color: _textHigh))),
    ]),
  );
}
