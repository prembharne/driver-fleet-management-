import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../tracking/presentation/tracking_screen.dart';

/// Shows a persistent banner whenever the logged-in driver has a trip
/// with status 'scheduled' (assigned by admin but not yet started).
/// Uses Supabase Realtime so it updates instantly without polling.
/// Also includes periodic polling as fallback for when realtime fails.
class AssignedTripBanner extends StatefulWidget {
  const AssignedTripBanner({super.key});

  @override
  State<AssignedTripBanner> createState() => _AssignedTripBannerState();
}

class _AssignedTripBannerState extends State<AssignedTripBanner>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _trip;
  bool _loading = true;
  RealtimeChannel? _channel;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  Timer? _pollingTimer;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _fetchTrip();
    _subscribeRealtime();
    _startPolling();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _channel?.unsubscribe();
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Start periodic polling as fallback for realtime
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('[AssignedTripBanner] Periodic polling triggered (retry: $_retryCount)');
      _fetchTrip();
    });
  }

  Future<void> _fetchTrip() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      debugPrint('[AssignedTripBanner] No user ID - not logged in');
      if (mounted) setState(() => _loading = false);
      return;
    }

    debugPrint('[AssignedTripBanner] Fetching trip for driver: $uid');
    
    try {
      // Check auth session status
      final session = _supabase.auth.currentSession;
      debugPrint('[AssignedTripBanner] Session expires at: ${session?.expiresAt}');
      
      if (session == null) {
        debugPrint('[AssignedTripBanner] No active session - attempting refresh');
        try {
          final refreshed = await _supabase.auth.refreshSession();
          debugPrint('[AssignedTripBanner] Session refresh result: ${refreshed.session != null ? "success" : "failed"}');
        } catch (e) {
          debugPrint('[AssignedTripBanner] Session refresh error: $e');
        }
      }

      final data = await _supabase
          .from('trips')
          .select()
          .eq('driver_id', uid)
          .filter('status', 'in', '(assigned,active,scheduled)')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      debugPrint('[AssignedTripBanner] Query result: ${data != null ? "trip found" : "no trip"}');
      if (data != null) {
        debugPrint('[AssignedTripBanner] Trip details - start: ${data['start_location']}, end: ${data['dest_location']}, status: ${data['status']}');
      }
      
      if (mounted) {
        setState(() { _trip = data; _loading = false; });
        _retryCount = 0; // Reset retry count on success
      }
    } catch (e) {
      debugPrint('[AssignedTripBanner] Error fetching trip: $e');
      _retryCount++;
      
      if (_retryCount < _maxRetries) {
        debugPrint('[AssignedTripBanner] Retrying... ($_retryCount/$_maxRetries)');
        await Future.delayed(Duration(seconds: 2 * _retryCount));
        if (mounted) _fetchTrip();
      } else {
        debugPrint('[AssignedTripBanner] Max retries reached');
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _subscribeRealtime() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    debugPrint('[AssignedTripBanner] Subscribing to realtime for driver: $uid');

    _channel = _supabase
        .channel('assigned_trip_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: uid,
          ),
          callback: (payload) {
            debugPrint('[AssignedTripBanner] Realtime update received: ${payload.eventType}');
            // Re-fetch whenever any row changes for this driver
            _fetchTrip();
          },
        )
        .subscribe((state, [error]) {
          debugPrint('[AssignedTripBanner] Realtime subscription state: $state');
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _trip == null) return const SizedBox.shrink();

    final from = _trip!['start_location'] as String? ?? 'Unknown origin';
    final to   = _trip!['dest_location']  as String? ?? 'Unknown destination';

    return ScaleTransition(
      scale: _pulseAnim,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TrackingScreen()),
        ).then((_) => _fetchTrip()), // refresh when returning
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withOpacity(0.45),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Pulsing icon badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                // Text info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🚨 New Trip Assigned!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$from  →  $to',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Arrow
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_forward_ios,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
