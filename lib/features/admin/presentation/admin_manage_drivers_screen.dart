import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminManageDriversScreen extends StatefulWidget {
  const AdminManageDriversScreen({super.key});

  @override
  State<AdminManageDriversScreen> createState() => _AdminManageDriversScreenState();
}

class _AdminManageDriversScreenState extends State<AdminManageDriversScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String _searchQuery = '';

  static const _bg      = Color(0xFFF0F2F5); // Calm professional bg
  static const _surface = Colors.white;
  static const _indigo  = Color(0xFF6366F1);
  static const _slate   = Color(0xFF1E293B); // Dark slate for text/headers
  static const _green   = Color(0xFF10B981);
  static const _amber   = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _fetchDrivers();
  }

  Future<void> _fetchDrivers() async {
    setState(() => _loading = true);
    try {
      // ── PARALLEL: fetch profiles, active trips, and verified docs all at once ──
      final results = await Future.wait([
        _supabase.from('profiles').select('*').eq('role', 'driver').order('full_name'),
        _supabase.from('trips').select('*').inFilter('status', ['assigned', 'active', 'paused', 'scheduled']).order('created_at', ascending: false),
        _supabase.from('documents').select('driver_id').eq('status', 'verified'),
      ]);

      final profilesSnapshot = results[0] as List;
      final allTrips = results[1] as List;
      final allDocs = results[2] as List;

      // ── Build lookup maps in memory (no more per-driver API calls) ──
      final Map<String, Map<String, dynamic>> latestTripMap = {};
      for (final trip in allTrips) {
        final driverId = trip['driver_id'] as String? ?? '';
        if (!latestTripMap.containsKey(driverId)) {
          latestTripMap[driverId] = trip; // already sorted desc by created_at
        }
      }

      final Map<String, int> docCountMap = {};
      for (final doc in allDocs) {
        final driverId = doc['driver_id'] as String? ?? '';
        docCountMap[driverId] = (docCountMap[driverId] ?? 0) + 1;
      }

      final drivers = <Map<String, dynamic>>[];
      for (var profile in profilesSnapshot) {
        final driverId = profile['id'] as String;
        drivers.add({
          'id': driverId,
          ...profile,
          'latestTrip': latestTripMap[driverId],
          'verifiedDocs': docCountMap[driverId] ?? 0,
        });
      }

      if (mounted) {
        setState(() {
          _drivers = drivers;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch drivers error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _drivers;
    final q = _searchQuery.toLowerCase();
    return _drivers.where((d) {
      final name = (d['full_name'] as String? ?? '').toLowerCase();
      final phone = (d['phone_number'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _slate,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Manage Drivers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchDrivers,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name or phone...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withOpacity(0.12),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : RefreshIndicator(
              onRefresh: _fetchDrivers,
              color: _indigo,
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text('No drivers found',
                              style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisExtent: 200,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => _DriverCard(
                        driver: _filtered[i],
                        onTap: () => _showDriverDetail(_filtered[i]),
                      ),
                    ),
            ),
    );
  }

  void _showDriverDetail(Map<String, dynamic> driver) {
    final trip = driver['latestTrip'] as Map<String, dynamic>?;
    final verifiedDocs = driver['verifiedDocs'] as int;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _indigo.withOpacity(0.1),
                child: Text(
                  (driver['full_name'] as String? ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: _indigo, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(driver['full_name'] as String? ?? 'Unknown',
                    style: const TextStyle(color: _slate, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(driver['phone_number'] as String? ?? 'No phone',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 20),
            _detailRow(Icons.local_shipping_outlined, 'Vehicle', driver['vehicle_number'] as String? ?? 'Not set'),
            _detailRow(Icons.folder_open, 'Verified Documents', '$verifiedDocs / 6'),
            if (trip != null) ...[
              _detailRow(Icons.route, 'Active Trip', trip['dest_location'] as String? ?? 'Unknown'),
              _detailRow(Icons.circle, 'Trip Status', (trip['status'] as String? ?? '').toUpperCase()),
            ] else
              _detailRow(Icons.do_not_disturb_alt, 'Trip Status', 'No active trip'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: _indigo, size: 20),
        const SizedBox(width: 12),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Expanded(
          child: Text(value,
              style: const TextStyle(color: _slate, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final VoidCallback onTap;

  const _DriverCard({required this.driver, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final trip = driver['latestTrip'] as Map<String, dynamic>?;
    final verifiedDocs = driver['verifiedDocs'] as int;
    final tripStatus = trip?['status'] as String?;
    final isActive = tripStatus == 'active';
    final isPaused = tripStatus == 'paused';
    final isScheduled = tripStatus == 'scheduled' || tripStatus == 'assigned';

    Color statusColor = Colors.grey;
    String statusLabel = 'Idle';
    if (isActive) { statusColor = const Color(0xFF10B981); statusLabel = 'On Trip'; }
    else if (isPaused) { statusColor = const Color(0xFFF59E0B); statusLabel = 'Paused'; }
    else if (isScheduled) { statusColor = const Color(0xFF6366F1); statusLabel = 'Assigned'; }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            // Header with status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (verifiedDocs == 6)
                    const Icon(Icons.verified, color: Color(0xFF10B981), size: 14),
                ],
              ),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                      child: Text(
                        (driver['full_name'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      driver['full_name'] as String? ?? 'Unknown',
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      driver['vehicle_number'] as String? ?? 'No Vehicle',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Stats footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statItem(Icons.folder_shared_outlined, '$verifiedDocs/6'),
                  _statItem(Icons.history_toggle_off, tripStatus == null ? 'None' : 'Active'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
