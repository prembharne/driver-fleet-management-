import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_app/core/services/routing_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Admin screen to view, edit, and delete all routes in route_master.
class AdminRouteMasterScreen extends StatefulWidget {
  final bool showAddDialogOnLoad;
  const AdminRouteMasterScreen({super.key, this.showAddDialogOnLoad = false});

  @override
  State<AdminRouteMasterScreen> createState() => _AdminRouteMasterScreenState();
}

class _AdminRouteMasterScreenState extends State<AdminRouteMasterScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _routes = [];
  bool _loading = true;
  String _search = '';

  static const _bg     = Color(0xFF0F1117);
  static const _card   = Color(0xFF1C1F2A);
  static const _accent = Color(0xFF4F8EF7);

  @override
  void initState() {
    super.initState();
    _fetch();
    if (widget.showAddDialogOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditDialog(null);
      });
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snapshot = await _supabase
          .from('route_master')
          .select('*')
          .order('route_id');
      
      final routes = <Map<String, dynamic>>[];
      for (var data in snapshot) {
        routes.add({'id': data['id'], ...data});
      }
      
      if (mounted) {
        setState(() {
          _routes = routes;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching routes: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _routes;
    final q = _search.toLowerCase();
    return _routes.where((r) {
      final name = (r['outlet_name'] as String? ?? '').toLowerCase();
      final id = r['route_id'].toString();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  Future<void> _delete(int routeId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Delete Route?', style: TextStyle(color: Colors.white)),
        content: Text('Route $routeId will be permanently deleted.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    
    await _supabase
        .from('route_master')
        .delete()
        .eq('route_id', routeId);
    _fetch();
  }

  void _showEditDialog(Map<String, dynamic>? existing) {
    final isNew = existing == null;
    final routeIdCtrl = TextEditingController(text: existing?['route_id']?.toString() ?? '');
    final outletCtrl  = TextEditingController(text: existing?['outlet_name'] ?? '');
    final srcCtrl     = TextEditingController(text: existing?['source_name'] ?? '');
    final dstCtrl     = TextEditingController(text: existing?['destination_name'] ?? '');
    final distCtrl    = TextEditingController(text: existing?['fixed_distance_km']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(isNew ? 'Add Route' : 'Edit Route ${existing!['route_id']}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isNew) _field(routeIdCtrl, 'Route ID', TextInputType.number),
            _field(outletCtrl, 'Outlet Name'),
            const SizedBox(height: 6),
            const Divider(color: Colors.white12),
            const Text('Source (Departure)', style: TextStyle(color: Colors.white54, fontSize: 12)),
            _field(srcCtrl, 'Source Name'),
            const Divider(color: Colors.white12),
            const Text('Destination (Outlet)', style: TextStyle(color: Colors.white54, fontSize: 12)),
            _field(dstCtrl, 'Destination Name'),
            const Divider(color: Colors.white12),
            _field(distCtrl, 'Distance (km)', const TextInputType.numberWithOptions(decimal: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () async {
              final String sName = srcCtrl.text.trim();
              final String dName = dstCtrl.text.trim();
              double? calcDist = double.tryParse(distCtrl.text);

              // Source and Destination are required, Distance is optional
              if (sName.isEmpty || dName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Source and Destination are required.'),
                  backgroundColor: Colors.red,
                ));
                return;
              }

              Navigator.pop(ctx);
              setState(() => _loading = true);

              double? sLat;
              double? sLng;
              double? dLat;
              double? dLng;

              final routing = RoutingService();

              // Geocode source
              final originLatLng = await routing.getCoordinatesFromAddress(sName);
              if (originLatLng != null) {
                sLat = originLatLng.latitude;
                sLng = originLatLng.longitude;
              }

              // Geocode destination
              final destLatLng = await routing.getCoordinatesFromAddress(dName);
              if (destLatLng != null) {
                dLat = destLatLng.latitude;
                dLng = destLatLng.longitude;
              }

              // Auto-fetch distance if not provided by user
              if (calcDist == null && sLat != null && sLng != null && dLat != null && dLng != null) {
                try {
                  final routeResponse = await routing.getRoute(
                    origin: LatLng(sLat, sLng),
                    destination: LatLng(dLat, dLng),
                  );
                  if (routeResponse != null && routeResponse['distance_meters'] != null) {
                    calcDist = (routeResponse['distance_meters'] as num) / 1000.0;
                    debugPrint('API Calced Distance: $calcDist');
                  }
                } catch (e) {
                  debugPrint('Failed to calculate distance: $e');
                }
              }

              final routeId = int.tryParse(routeIdCtrl.text) ?? existing?['route_id'];
              final payload = {
                'route_id'        : routeId,
                'outlet_name'     : outletCtrl.text.trim(),
                'source_name'     : srcCtrl.text.trim(),
                'source_lat'      : sLat,
                'source_lng'      : sLng,
                'destination_name': dstCtrl.text.trim(),
                'destination_lat' : dLat,
                'destination_lng' : dLng,
                'fixed_distance_km': calcDist,
                'updated_at': DateTime.now().toIso8601String(),
              };
              
              debugPrint('Payload to DB: $payload');
              
              if (isNew) {
                payload['created_at'] = DateTime.now().toIso8601String();
                await _supabase.from('route_master').insert(payload);
              } else {
                await _supabase
                    .from('route_master')
                    .update(payload)
                    .eq('route_id', existing['route_id']);
              }
              _fetch();
            },
            child: Text(isNew ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, [TextInputType? type]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filtered;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Route Master', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _showEditDialog(null)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search route or outlet…',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: routes.isEmpty
                  ? Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route_outlined, size: 60, color: Colors.white.withOpacity(0.15)),
                        const SizedBox(height: 16),
                        const Text('No routes yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showEditDialog(null),
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Add Route'),
                          style: ElevatedButton.styleFrom(backgroundColor: _accent),
                        ),
                      ],
                    ))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: routes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = routes[i];
                        final dist = r['fixed_distance_km'];
                        return Container(
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: _accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(child: Text('${r['route_id']}',
                                  style: const TextStyle(color: _accent,
                                      fontWeight: FontWeight.bold, fontSize: 13))),
                            ),
                            title: Text(r['outlet_name'] as String? ?? '',
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 3),
                                Row(children: [
                                  if (dist != null) ...[
                                    const Icon(Icons.route, size: 12, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text('${dist.toStringAsFixed(1)} km',
                                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                    const SizedBox(width: 12),
                                  ],
                                ]),
                              ],
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 20),
                                onPressed: () => _showEditDialog(r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                                onPressed: () => _delete(r['route_id'] as int),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
