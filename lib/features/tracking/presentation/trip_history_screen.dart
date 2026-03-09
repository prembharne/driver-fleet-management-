import 'package:flutter/material.dart';
import 'package:driver_app/features/tracking/services/tracking_service.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  final TrackingService _trackingService = TrackingService.instance;
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _isLoading = true);
    final driverId = _trackingService.currentDriverId;
    if (driverId == null) {
      setState(() {
        _trips = [];
        _isLoading = false;
      });
      return;
    }
    final trips = await _trackingService.getTripHistory(driverId);
    setState(() {
      _trips = trips;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrips,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTrips,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _trips.length,
                    itemBuilder: (context, index) {
                      return _buildTripCard(_trips[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No trips yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your completed trips will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final status = trip['status'] ?? 'unknown';
    final distance = (trip['total_distance_km'] ?? 0.0).toDouble();
    final startedAt = trip['started_at'] != null
        ? DateTime.tryParse(trip['started_at'])
        : null;
    final completedAt = trip['completed_at'] != null
        ? DateTime.tryParse(trip['completed_at'])
        : null;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'active':
        statusColor = Colors.green;
        statusIcon = Icons.play_circle;
        break;
      case 'paused':
        statusColor = Colors.orange;
        statusIcon = Icons.pause_circle;
        break;
      case 'completed':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    String duration = '--';
    if (startedAt != null && completedAt != null) {
      final diff = completedAt.difference(startedAt);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      duration = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (startedAt != null)
                  Text(
                    '${startedAt.day}/${startedAt.month}/${startedAt.year}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTripStat(
                  Icons.straighten,
                  '${distance.toStringAsFixed(2)} km',
                  'Distance',
                ),
                _buildTripStat(Icons.timer, duration, 'Duration'),
                _buildTripStat(
                  Icons.access_time,
                  startedAt != null
                      ? '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}'
                      : '--:--',
                  'Started',
                ),
              ],
            ),

            // Location info
            if (trip['start_location'] != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.green[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'From: ${trip['start_location']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (trip['end_location'] != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.flag, size: 16, color: Colors.red[400]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'To: ${trip['end_location']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.grey[500]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
