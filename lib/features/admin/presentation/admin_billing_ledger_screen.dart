import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminBillingLedgerScreen extends StatefulWidget {
  const AdminBillingLedgerScreen({super.key});

  @override
  State<AdminBillingLedgerScreen> createState() => _AdminBillingLedgerScreenState();
}

class _AdminBillingLedgerScreenState extends State<AdminBillingLedgerScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _billingData = [];
  String? _error;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _fetchBillingData();
  }

  Future<void> _fetchBillingData() async {
    setState(() => _isLoading = true);
    try {
      final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final end   = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

      // Fetch Price Per KM first
      double rate = 15.0;
      final settingsRes = await _supabase.from('app_settings').select('value').eq('key', 'price_per_km').maybeSingle();
      if (settingsRes != null) {
        rate = double.tryParse(settingsRes['value'].toString()) ?? 15.0;
      }

      // Fetch billing data from Supabase 
      final snapshot = await _supabase
          .from('trips')
          .select('*')
          .eq('status', 'completed')
          .gte('completed_at', start.toIso8601String())
          .lt('completed_at', end.toIso8601String())
          .order('created_at', ascending: false);
      
      // Group by vehicle and calculate totals
      final Map<String, Map<String, dynamic>> groupedData = {};
      
      for (var trip in snapshot) {
        final vehicleNumber = trip['vehicle_number'] as String? ?? 'Unknown';
        if (!groupedData.containsKey(vehicleNumber)) {
          groupedData[vehicleNumber] = {
            'vehicle_number': vehicleNumber,
            'total_trips': 0,
            'total_km_billed': 0.0,
            'rate': rate,
            'billing_month': _selectedMonth.toIso8601String(),
          };
        }
        groupedData[vehicleNumber]!['total_trips'] = 
            (groupedData[vehicleNumber]!['total_trips'] as int) + 1;
        
        final distance = trip['total_distance_km'] ?? trip['distance_km'];
        if (distance != null) {
          groupedData[vehicleNumber]!['total_km_billed'] = 
              (groupedData[vehicleNumber]!['total_km_billed'] as double) + 
              ((distance is num) ? (distance as num).toDouble() : 0.0);
        }
      }

      setState(() {
        _billingData = groupedData.values.toList();
        _isLoading = false;
      });
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
    // Premium psychology color palette
    const primaryBg = Color(0xFFF0F2F5); 
    const cardBg = Colors.white;
    const accentColor = Color(0xFF6366F1);
    const headerColor = Color(0xFF1E293B);

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        title: const Text(
          'Monthly Billing Ledger',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => _selectMonth(context),
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            label: Text(
              DateFormat('MMM yyyy').format(_selectedMonth),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _billingData.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No billing records found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 350,
                          mainAxisExtent: 220,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: _billingData.length,
                        itemBuilder: (context, index) {
                          final data = _billingData[index];
                          final dateRaw = data['billing_month'];
                          final dateStr = dateRaw != null
                              ? DateFormat('MMMM yyyy').format(DateTime.parse(dateRaw.toString()))
                              : 'Unknown';

                          return Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1E293B),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.car_rental, color: Colors.indigoAccent, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          data['vehicle_number']?.toString() ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      _buildStatRow(
                                        Icons.calendar_today_outlined, 
                                        'Billing Period', 
                                        dateStr,
                                        Colors.blueGrey,
                                      ),
                                      const Divider(height: 24, thickness: 0.5),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildSimpleStat(
                                              'Trips', 
                                              data['total_trips']?.toString() ?? '0',
                                              accentColor,
                                            ),
                                          ),
                                          _divider(),
                                          Expanded(
                                            child: _buildSimpleStat(
                                              'Distance', 
                                              '${(data['total_km_billed'] as num?)?.toStringAsFixed(1) ?? '0.0'}',
                                              const Color(0xFF10B981),
                                            ),
                                          ),
                                          _divider(),
                                          Expanded(
                                            child: _buildSimpleStat(
                                              'Amount', 
                                              '₹${((data['total_km_billed'] as double) * (data['rate'] as double)).toStringAsFixed(0)}',
                                              accentColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2023),
      lastDate: DateTime(2101),
      helpText: 'SELECT BILLING MONTH',
    );
    if (picked != null && picked != _selectedMonth) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      _fetchBillingData();
    }
  }

  Widget _divider() => Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.15));

  Widget _buildStatRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _buildSimpleStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            color: Colors.blueGrey,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
