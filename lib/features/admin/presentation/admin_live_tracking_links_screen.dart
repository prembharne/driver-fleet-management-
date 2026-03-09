import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:driver_fleet_admin/features/tracking/presentation/live_tracking_viewer_screen.dart';

class AdminLiveTrackingLinksScreen extends StatefulWidget {
  const AdminLiveTrackingLinksScreen({super.key});

  @override
  State<AdminLiveTrackingLinksScreen> createState() => _AdminLiveTrackingLinksScreenState();
}

class _AdminLiveTrackingLinksScreenState extends State<AdminLiveTrackingLinksScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeTrips = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchActiveTrips();
  }

  Future<void> _fetchActiveTrips() async {
    try {
      // Get active trips from Supabase
      final snapshot = await _supabase
          .from('trips')
          .select('*')
          .eq('status', 'active')
          .order('started_at', ascending: false);

      // ── Collect unique driver & vehicle IDs ──
      final Set<String> driverIds = {};
      final Set<String> vehicleIds = {};
      for (final data in snapshot) {
        final dId = data['driver_id'] as String?;
        final vId = data['vehicle_id'] as String?;
        if (dId != null && dId.isNotEmpty) driverIds.add(dId);
        if (vId != null && vId.isNotEmpty) vehicleIds.add(vId);
      }

      // ── PARALLEL batch-fetch profiles and vehicles ──
      final Map<String, String> nameCache = {};
      final Map<String, String> vehicleCache = {};

      final batchResults = await Future.wait([
        driverIds.isNotEmpty
            ? _supabase.from('profiles').select('id, full_name').inFilter('id', driverIds.toList())
            : Future.value(<Map<String, dynamic>>[]),
        vehicleIds.isNotEmpty
            ? _supabase.from('vehicles').select('id, vehicle_number').inFilter('id', vehicleIds.toList())
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      for (final p in (batchResults[0] as List)) {
        nameCache[p['id'] as String] = p['full_name'] as String? ?? 'Unknown Driver';
      }
      for (final v in (batchResults[1] as List)) {
        vehicleCache[v['id'] as String] = v['vehicle_number'] as String? ?? 'Unknown Vehicle';
      }

      final trips = <Map<String, dynamic>>[];
      for (var data in snapshot) {
        final driverId = data['driver_id'] as String? ?? '';
        final vehicleId = data['vehicle_id'] as String? ?? '';
        trips.add({
          ...data,
          'driver_name': nameCache[driverId] ?? 'Unknown Driver',
          'vehicle_number': vehicleCache[vehicleId] ?? data['vehicle_number'] ?? 'Unknown Vehicle',
        });
      }

      if (mounted) {
        setState(() {
          _activeTrips = trips;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Live Tracking Links'),
        backgroundColor: const Color(0xFFF44336), // matches tile color
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _activeTrips.isEmpty
                  ? const Center(child: Text('No active trips right now. (Notifications will pop here automatically)'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _activeTrips.length,
                      itemBuilder: (context, index) {
                        final trip = _activeTrips[index];
                        final token = trip['tracking_token'];
                        final vehicleStr = trip['vehicle_number'] ?? 'Unknown Vehicle';
                        final driverStr = trip['driver_name'] ?? 'Unknown Driver';
                        final dest = trip['dest_location'] ?? 'Unknown Destination';

                        // Use the current origin if available (for localhost dev) or fallback
                        final origin = (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') 
                            ? '${Uri.base.scheme}://${Uri.base.host}${Uri.base.port != 80 && Uri.base.port != 443 && Uri.base.port != 0 ? ":${Uri.base.port}" : ""}' 
                            : 'https://driver-fleet-manager.web.app';
                        
                        final trackingUrl = '$origin/track/$token';
                        
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          color: Colors.white,
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF44336).withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.share_location, color: Color(0xFFF44336)),
                                  ),
                                  title: Text('$vehicleStr ($driverStr)', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('Destination: $dest', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(trackingUrl, 
                                          style: const TextStyle(color: Colors.blue, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: trackingUrl));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Link copied to clipboard!')),
                                          );
                                        },
                                        icon: const Icon(Icons.copy, size: 18),
                                        label: const Text('Copy Link'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => LiveTrackingViewerScreen(trackingToken: token),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.map, size: 18),
                                        label: const Text('Open Map'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFF44336),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
