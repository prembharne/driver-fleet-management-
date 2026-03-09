import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:driver_app/core/constants/app_colors.dart';
import 'package:driver_app/features/auth/services/auth_service.dart';
import 'package:driver_app/features/auth/presentation/login_screen.dart';
import 'widgets/kyc_banner.dart';
import 'widgets/service_grid.dart';
import 'widgets/bottom_nav_bar.dart';
import '../../tracking/presentation/trip_history_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../support/presentation/support_screen.dart';
import 'vehicles_screen.dart';
import 'payments_screen.dart';

/// Driver Home Screen — shows assigned trip banner, total stats, and service grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  int _selectedIndex = 0;

  // Driver stats
  double _totalKm = 0;
  double _totalEarnings = 0;
  Map<String, dynamic>? _activeTrip;
  bool _loadingStats = true;

  // Supabase real-time channel for trip updates
  RealtimeChannel? _tripChannel;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _subscribeToTripChanges();
  }

  @override
  void didPopNext() {
    // Refresh when navigating BACK to home from another screen
    _loadDriverData();
  }

  /// Subscribe to real-time trip changes for this driver.
  void _subscribeToTripChanges() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    _tripChannel = Supabase.instance.client
        .channel('home_trips_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: uid,
          ),
          callback: (_) {
            // Reload banner whenever any trip row changes
            if (mounted) _loadDriverData();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tripChannel?.unsubscribe();
    super.dispose();
  }

  /// Fetch driver's total KM, total earnings, and active trip from Supabase.
  Future<void> _loadDriverData() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Fetch all completed trips for total KM
      final trips = await Supabase.instance.client
          .from('trips')
          .select('total_distance_km, status')
          .eq('driver_id', uid);

      double totalKm = 0;
      for (final t in trips) {
        totalKm += (t['total_distance_km'] as num?)?.toDouble() ?? 0;
      }

      // Fetch approved advances as proxy for earnings/payouts received
      final advances = await Supabase.instance.client
          .from('advance_requests')
          .select('amount')
          .eq('driver_id', uid)
          .eq('status', 'approved');

      double totalEarnings = 0;
      for (final a in advances) {
        totalEarnings += (a['amount'] as num?)?.toDouble() ?? 0;
      }

      // Fetch active/scheduled trip (if any)
      final activeTrips = await Supabase.instance.client
          .from('trips')
          .select('*')
          .eq('driver_id', uid)
          .inFilter('status', ['scheduled', 'assigned', 'active'])
          .order('created_at', ascending: false)
          .limit(1);

      if (mounted) {
        setState(() {
          _totalKm = totalKm;
          _totalEarnings = totalEarnings;
          _activeTrip = activeTrips.isNotEmpty ? activeTrips.first : null;
          _loadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading driver data: $e');
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);

    if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const VehiclesScreen()))
          .then((_) => setState(() => _selectedIndex = 0));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TripHistoryScreen()))
          .then((_) => setState(() => _selectedIndex = 0));
    } else if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen()))
          .then((_) => setState(() => _selectedIndex = 0));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign Out',
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign Out'),
                content: const Text('Are you sure you want to sign out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sign Out',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirm != true) return;
            if (!mounted) return;

            final navigator = Navigator.of(context);
            await AuthService.instance.signOut();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          },
        ),
        title: const Text('Home Page'),
        centerTitle: true,
        actions: [
          // Headset icon opens Technical Support screen
          IconButton(
            icon: const Icon(Icons.headset_mic_outlined),
            tooltip: 'Technical Support',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),
      // KycBannerWrapper injects KycProvider so ServiceGrid can lock features
      body: KycBannerWrapper(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Driver Stats Row ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: _loadingStats
                    ? const SizedBox(
                        height: 60,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : Row(
                        children: [
                          // Total KM — blue for trust/reliability
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1565C0),
                                    Color(0xFF1976D2)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(children: [
                                const Icon(Icons.speed,
                                    color: Colors.white, size: 28),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total KM',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11)),
                                    Text(
                                        _totalKm.toStringAsFixed(1),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18)),
                                  ],
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Total Earnings — green for growth/safety
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2E7D32),
                                    Color(0xFF388E3C)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(children: [
                                const Icon(Icons.account_balance_wallet,
                                    color: Colors.white, size: 28),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Earnings',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11)),
                                    Text(
                                        '₹${_totalEarnings.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18)),
                                  ],
                                ),
                              ]),
                            ),
                          ),
                        ],
                      ),
              ),

              // ── Active Trip Banner ──
              if (_activeTrip != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF57C00), Color(0xFFFF9800)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFFF57C00).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping,
                            color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Active Trip',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                '${_activeTrip!['source_name'] ?? _activeTrip!['start_location'] ?? 'Start'} → '
                                '${_activeTrip!['destination_name'] ?? _activeTrip!['dest_location'] ?? 'End'}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_activeTrip!['total_distance_km']?.toStringAsFixed(1) ?? '?'} km · '
                                '${(_activeTrip!['status'] as String? ?? 'scheduled').toUpperCase()}',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios,
                            color: Colors.white70, size: 16),
                      ],
                    ),
                  ),
                ),

              // No active trip fallback
              if (_activeTrip == null && !_loadingStats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[100],
                    ),
                    child: Center(
                      child: Text(
                        'No active trip assigned',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Payments shortcut
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.gridItemBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.currency_rupee, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Payments',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const ServiceGrid(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
