import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_app/core/constants/app_colors.dart';

class AvailableRoutesScreen extends StatefulWidget {
  const AvailableRoutesScreen({super.key});

  @override
  State<AvailableRoutesScreen> createState() => _AvailableRoutesScreenState();
}

class _AvailableRoutesScreenState extends State<AvailableRoutesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _availableRoutes = [];

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() => _isLoading = true);
    try {
      // DEBUG: Log authentication state for diagnosing sync issues
      final authUser = _supabase.auth.currentUser;
      debugPrint('[AvailableRoutes] Auth user: ${authUser?.id ?? 'null'}');
      debugPrint('[AvailableRoutes] Auth session: ${authUser != null ? "active" : "none"}');

      // 1. Get all routes from master
      final routesResp = await _supabase.from('route_master').select('*').order('route_id');
      final allRoutes = List<Map<String, dynamic>>.from(routesResp);
      debugPrint('[AvailableRoutes] Total routes in master: ${allRoutes.length}');

      // 2. Get today's trips
      final todayStr = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).toIso8601String();
      debugPrint('[AvailableRoutes] Fetching trips from: $todayStr');
      
      final tripsResp = await _supabase
          .from('trips')
          .select('route_id, driver_id, status, created_at')
          .gte('created_at', todayStr);

      final trips = List<Map<String, dynamic>>.from(tripsResp);
      debugPrint('[AvailableRoutes] Total trips today: ${trips.length}');
      debugPrint('[AvailableRoutes] Trip details: $trips');

      // 3. Filter out routes that are already assigned today
      final assignedRouteIds = trips.map((t) => t['route_id']).toSet();
      debugPrint('[AvailableRoutes] Assigned route IDs: $assignedRouteIds');
      
      final available = allRoutes.where((r) => !assignedRouteIds.contains(r['route_id'])).toList();
      debugPrint('[AvailableRoutes] Available routes: ${available.length}');

      if (mounted) {
        setState(() {
          _availableRoutes = available;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AvailableRoutes] Error fetching available routes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _claimRoute(Map<String, dynamic> route) async {
    final driverId = _supabase.auth.currentUser?.id;
    if (driverId == null) return;

    // DEBUG: Log driver ID for diagnosing sync issues
    debugPrint('[AvailableRoutes] Driver ID: $driverId');
    debugPrint('[AvailableRoutes] Current time: ${DateTime.now().toIso8601String()}');

    // Check if driver already has a trip for today - prevent multiple route claims per day
    try {
      final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      debugPrint('[AvailableRoutes] Checking for existing trips between $todayStart and $todayEnd');
      
      final existingTrip = await _supabase
          .from('trips')
          .select('id, status, created_at, start_location, end_location')
          .eq('driver_id', driverId)
          .gte('created_at', todayStart.toIso8601String())
          .lt('created_at', todayEnd.toIso8601String())
          .maybeSingle();

      debugPrint('[AvailableRoutes] Existing trip check result: $existingTrip');

      if (existingTrip != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You already have a route assigned for today: ${existingTrip['start_location'] ?? 'Unknown'} to ${existingTrip['end_location'] ?? 'Unknown'}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('[AvailableRoutes] Error checking existing trip: $e');
      // Continue with claim if check fails - don't block the user
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claim this Route?'),
        content: Text('Do you want to assign yourself to ${route['outlet_name']} for today?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Assign Route')
          ),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Check for vehicle assignment
      final profile = await _supabase.from('profiles').select('vehicle_number').eq('id', driverId).maybeSingle();
      String? vehicleId;
      
      if (profile != null && profile['vehicle_number'] != null) {
         final vData = await _supabase.from('vehicles').select('id').eq('vehicle_number', profile['vehicle_number']).maybeSingle();
         if (vData != null) vehicleId = vData['id'];
      }

      await _supabase.from('trips').insert({
        'driver_id': driverId,
        'route_id': route['route_id'],
        'vehicle_id': vehicleId, // Nullable if they don't have one assigned yet
        'status': 'assigned',
        
        'start_location': route['source_name'],
        'start_lat': route['source_lat'],
        'start_lng': route['source_lng'],
        'source_name': route['source_name'],
        'source_lat': route['source_lat'],
        'source_lng': route['source_lng'],
        
        'dest_location': route['destination_name'],
        'dest_lat': route['destination_lat'],
        'dest_lng': route['destination_lng'],
        'destination_name': route['destination_name'],
        'destination_lat': route['destination_lat'],
        'destination_lng': route['destination_lng'],
        
        'total_distance_km': route['fixed_distance_km'],
      });

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route confirmed!'), backgroundColor: Colors.green));
         _fetchRoutes(); // Refresh list to remove the claimed one
      }
    } catch (e) {
       debugPrint('Error claiming route: $e');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to claim route: $e'), backgroundColor: Colors.red));
         setState(() => _isLoading = false);
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Daily Routes'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _availableRoutes.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 80, color: Colors.green[200]),
                  const SizedBox(height: 16),
                  const Text('All routes are taken for today!', style: TextStyle(fontSize: 18, color: Colors.blueGrey)),
                ],
              )
            )
          : RefreshIndicator(
              onRefresh: _fetchRoutes,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _availableRoutes.length,
                itemBuilder: (context, index) {
                   final r = _availableRoutes[index];
                   return Card(
                     margin: const EdgeInsets.only(bottom: 16),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     elevation: 2,
                     child: Padding(
                       padding: const EdgeInsets.all(16),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Row(
                             children: [
                               Container(
                                 padding: const EdgeInsets.all(8),
                                 decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                 child: const Icon(Icons.route, color: Colors.blue),
                               ),
                               const SizedBox(width: 12),
                               Expanded(
                                 child: Text(
                                   r['outlet_name'] ?? 'Unknown Outlet',
                                   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                 ),
                               ),
                               Text(
                                 '${r['fixed_distance_km'] ?? 'N/A'} km',
                                 style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey),
                               ),
                             ],
                           ),
                           const SizedBox(height: 16),
                           Row(
                             children: [
                               const Icon(Icons.store, size: 16, color: Colors.grey),
                               const SizedBox(width: 8),
                               Expanded(child: Text(r['source_name'] ?? 'Warehouse', style: const TextStyle(color: Colors.grey))),
                             ],
                           ),
                           const SizedBox(height: 4),
                           const Padding(
                             padding: EdgeInsets.only(left: 6),
                             child: Icon(Icons.more_vert, size: 16, color: Colors.grey),
                           ),
                           const SizedBox(height: 4),
                           Row(
                             children: [
                               const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                               const SizedBox(width: 8),
                               Expanded(child: Text(r['destination_name'] ?? 'Destination', style: const TextStyle(color: Colors.grey))),
                             ],
                           ),
                           const SizedBox(height: 16),
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton(
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: AppColors.primary,
                                 foregroundColor: Colors.white,
                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                 padding: const EdgeInsets.symmetric(vertical: 12),
                               ),
                               onPressed: () => _claimRoute(r),
                               child: const Text('CLAIM THIS ROUTE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                             ),
                           )
                         ],
                       ),
                     ),
                   );
                },
              ),
          )
    );
  }
}
