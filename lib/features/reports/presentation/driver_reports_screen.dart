import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Driver-facing monthly report screen.
/// Shows total trips, total KM, total advance taken, and delays for a selected month.
class DriverReportsScreen extends StatefulWidget {
  const DriverReportsScreen({super.key});

  @override
  State<DriverReportsScreen> createState() => _DriverReportsScreenState();
}

class _DriverReportsScreenState extends State<DriverReportsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Aggregated data
  int _totalTrips = 0;
  double _totalKm = 0;
  double _totalAdvance = 0;
  int _totalIssues = 0;
  List<Map<String, dynamic>> _trips = [];
  double _pricePerKm = 15.0; // Default fallback

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _loadSettings() async {
    try {
      final res = await _supabase.from('app_settings').select('value').eq('key', 'price_per_km').maybeSingle();
      if (res != null) {
        _pricePerKm = double.tryParse(res['value'].toString()) ?? 15.0;
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _fetchReportData() async {
    setState(() => _isLoading = true);
    await _loadSettings();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

      // Fetch trips
      final tripsData = await _supabase
          .from('trips')
          .select()
          .eq('driver_id', userId)
          .gte('started_at', start.toIso8601String())
          .lt('started_at', end.toIso8601String())
          .order('started_at', ascending: false);

      final trips = List<Map<String, dynamic>>.from(tripsData);

      // Fetch advances
      final advData = await _supabase
          .from('advance_requests')
          .select('amount')
          .eq('driver_id', userId)
          .eq('status', 'approved')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      // Fetch issues
      final issueData = await _supabase
          .from('trip_issues')
          .select('id')
          .eq('driver_id', userId)
          .gte('reported_at', start.toIso8601String())
          .lt('reported_at', end.toIso8601String());

      double totalKm = 0;
      for (final t in trips) {
        totalKm += (t['total_distance_km'] as num?)?.toDouble() ?? 0;
      }

      double totalAdv = 0;
      for (final a in advData) {
        // The driver effectively pays 10% interest. 
        // If the request was for 40000, they received 36000 but we deduct the full 40000 
        // from their gross earnings to account for the interest fee.
        totalAdv += (a['amount'] as num).toDouble();
      }

      if (mounted) {
        setState(() {
          _trips = trips;
          _totalTrips = trips.length;
          _totalKm = totalKm;
          _totalAdvance = totalAdv;
          _totalIssues = (issueData as List).length;
        });
      }
    } catch (e) {
      debugPrint('Report error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Select Month',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
      _fetchReportData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            label: Text(monthLabel, style: const TextStyle(color: Colors.white)),
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchReportData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // KPI Cards
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      _kpiCard('Total Trips', '$_totalTrips', Icons.local_shipping, Colors.blue),
                      _kpiCard('Total KM', '${_totalKm.toStringAsFixed(1)} km', Icons.straighten, Colors.green),
                      _kpiCard('Advance Taken', '₹${_totalAdvance.toStringAsFixed(0)}', Icons.payment, Colors.orange),
                      _kpiCard('Issues Reported', '$_totalIssues', Icons.warning_amber, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Net Payable Full-Width Card
                  Builder(builder: (context) {
                    final grossEarnings = _totalKm * _pricePerKm;
                    final netPayable = grossEarnings - _totalAdvance;
                    final isNegative = netPayable < 0;

                    return Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A237E), Color(0xFF303F9F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: Colors.white70),
                              SizedBox(width: 8),
                              Text('Net Payable Earnings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isNegative 
                              ? '-₹${netPayable.abs().toStringAsFixed(0)} (Owed)'
                              : '₹${netPayable.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: isNegative ? Colors.orange : Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Gross (₹${grossEarnings.toStringAsFixed(0)}) - Advances Paid after 10% Int. (₹${_totalAdvance.toStringAsFixed(0)})',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 24),
                  const Text('Trip Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  if (_trips.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No trips this month', style: TextStyle(color: Colors.grey)),
                    ))
                  else
                    ..._trips.map((t) {
                      final date = DateTime.tryParse(t['started_at'] ?? '');
                      final dateStr = date != null ? DateFormat('dd MMM, hh:mm a').format(date) : '';
                      final km = (t['total_distance_km'] as num?)?.toStringAsFixed(1) ?? '0.0';
                      final dest = t['dest_location'] ?? 'Unknown';
                      final status = t['status'] as String? ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: const Icon(Icons.route, color: Colors.blue),
                          title: Text(dest, overflow: TextOverflow.ellipsis),
                          subtitle: Text(dateStr),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$km km', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(status, style: TextStyle(fontSize: 11, color: status == 'completed' ? Colors.green : Colors.orange)),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}
