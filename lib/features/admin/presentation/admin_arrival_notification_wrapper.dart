import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Admin-side widget that listens for driver arrivals via Supabase.
/// Shows a stacked notification banner when drivers arrive at destinations.
/// Wrap this around the admin dashboard body to enable live notifications.
class ArrivalNotificationWrapper extends StatefulWidget {
  final Widget child;
  const ArrivalNotificationWrapper({super.key, required this.child});

  @override
  State<ArrivalNotificationWrapper> createState() => _ArrivalNotificationWrapperState();
}

class _ArrivalNotificationWrapperState extends State<ArrivalNotificationWrapper> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _tripsSubscription;

  // List of active arrival alerts
  final List<_ArrivalAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _subscribeToArrivals();
  }

  @override
  void dispose() {
    _tripsSubscription?.unsubscribe();
    super.dispose();
  }

  void _subscribeToArrivals() {
    // Listen for trips with status 'arrived' using Supabase realtime
    _tripsSubscription = _supabase
        .channel('public:trips')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'status',
            value: 'arrived',
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record == null) return;
            
            // Fetch driver name
            String driverName = 'Driver';
            String outletName = record['destination_name'] as String? ?? 'Destination';
            final lat  = record['current_lat'] as double?;
            final lng  = record['current_lng'] as double?;
            
            final driverId = record['driver_id'];
            if (driverId != null) {
              try {
                final profileDoc = await _supabase
                    .from('profiles')
                    .select('full_name')
                    .eq('id', driverId)
                    .maybeSingle();
                if (profileDoc != null) {
                  driverName = profileDoc['full_name'] ?? 'Driver';
                }
              } catch (_) {}
            }

            if (mounted) {
              final alertId = record['id'] as String;
              setState(() {
                _alerts.add(_ArrivalAlert(
                  id: alertId,
                  driverName: driverName,
                  outletName: outletName,
                  arrivedLat: lat,
                  arrivedLng: lng,
                  timestamp: DateTime.now(),
                ));
              });

              // Auto-dismiss after 30 seconds
              Future.delayed(const Duration(seconds: 30), () {
                if (mounted) {
                  setState(() => _alerts.removeWhere((a) => a.id == alertId));
                }
              });
            }
          },
        )
        .subscribe();
  }

  void _dismissAlert(String id) {
    setState(() => _alerts.removeWhere((a) => a.id == id));
  }

  void _openMaps(double? lat, double? lng) async {
    if (lat != null && lng != null) {
      final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_alerts.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Column(
              children: _alerts.map((alert) => _AlertBanner(
                alert: alert,
                onDismiss: () => _dismissAlert(alert.id),
                onOpenMap: () => _openMaps(alert.arrivedLat, alert.arrivedLng),
              )).toList(),
            ),
          ),
      ],
    );
  }
}

class _ArrivalAlert {
  final String id;
  final String driverName;
  final String outletName;
  final double? arrivedLat;
  final double? arrivedLng;
  final DateTime timestamp;

  _ArrivalAlert({
    required this.id,
    required this.driverName,
    required this.outletName,
    this.arrivedLat,
    this.arrivedLng,
    required this.timestamp,
  });
}

class _AlertBanner extends StatelessWidget {
  final _ArrivalAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onOpenMap;

  const _AlertBanner({
    required this.alert,
    required this.onDismiss,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade800,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.driverName} has arrived!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  alert.outletName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (alert.arrivedLat != null && alert.arrivedLng != null)
            IconButton(
              icon: const Icon(Icons.map, color: Colors.white),
              onPressed: onOpenMap,
              tooltip: 'View on Map',
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
