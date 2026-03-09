import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:driver_fleet_admin/features/admin/utils/file_download.dart';

/// Admin-facing monthly report screen.
/// Shows all drivers' trips, KM, advances, and issues for a selected month.
/// Human-psychology color system: calm, trust-inspiring, data-readable.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  int _totalTrips = 0;
  double _totalKm = 0;
  double _totalAdvance = 0;
  int _totalIssues = 0;
  List<Map<String, dynamic>> _driverStats = [];

  // ── Psychology-based palette (light, calming, trustworthy) ──
  static const _bg         = Color(0xFFF4F6F9);   // Soft cool-grey bg — reduces anxiety
  static const _surface    = Color(0xFFFFFFFF);   // Pure white surface — clarity
  static const _headerBg   = Color(0xFF1E293B);   // Deep slate header — authority
  static const _cardBorder = Color(0xFFE2E8F0);   // Light grey border — subtle structure

  // KPI accent colors — chosen for emotional association
  static const _blue   = Color(0xFF2563EB); // Trust & reliability (Total Trips)
  static const _green  = Color(0xFF059669); // Growth & progress (KM)
  static const _amber  = Color(0xFFD97706); // Caution & attention (Advances)
  static const _red    = Color(0xFFDC2626); // Alert & urgency (Issues)
  static const _indigo = Color(0xFF4F46E5); // Premium & depth (hero card)
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
      final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

      // ── PARALLEL fetch — all 3 queries run simultaneously ──
      final results = await Future.wait([
        _supabase.from('trips').select('*')
            .eq('status', 'completed')
            .gte('completed_at', start.toIso8601String())
            .lt('completed_at', end.toIso8601String()),
        _supabase.from('advance_requests').select('*')
            .eq('status', 'approved')
            .gte('created_at', start.toIso8601String())
            .lt('created_at', end.toIso8601String()),
        _supabase.from('trip_issues').select('*')
            .gte('reported_at', start.toIso8601String())
            .lt('reported_at', end.toIso8601String()),
      ]);

      final tripsSnapshot = results[0] as List;
      final advSnapshot   = results[1] as List;
      final issueSnapshot = results[2] as List;

      // ── Collect unique driver IDs first ──
      final Set<String> driverIds = {};
      for (final t in tripsSnapshot) {
        final id = t['driver_id'] as String? ?? '';
        if (id.isNotEmpty) driverIds.add(id);
      }

      // ── SINGLE batch query for all driver profiles ──
      final Map<String, String> nameCache = {};
      if (driverIds.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', driverIds.toList());
          for (final p in profiles) {
            nameCache[p['id'] as String] = p['full_name'] as String? ?? 'Unknown';
          }
        } catch (e) {
          debugPrint('Error batch-fetching profiles: $e');
        }
      }

      // ── Process trips (no more API calls inside loop) ──
      double totalKm = 0;
      double totalAdv = 0;
      final Map<String, Map<String, dynamic>> driverMap = {};

      for (final t in tripsSnapshot) {
        final km = (t['total_distance_km'] as num?)?.toDouble() ?? 0;
        totalKm += km;
        final driverId = t['driver_id'] as String? ?? '';
        final name = nameCache[driverId] ?? 'Unknown';

        driverMap.putIfAbsent(driverId, () => {'name': name, 'trips': 0, 'km': 0.0, 'earnings': 0.0});
        driverMap[driverId]!['trips'] = (driverMap[driverId]!['trips'] as int) + 1;
        driverMap[driverId]!['km'] = (driverMap[driverId]!['km'] as double) + km;
        driverMap[driverId]!['earnings'] = (driverMap[driverId]!['km'] as double) * _pricePerKm;
      }

      for (final a in advSnapshot) {
        // The total amount requested is the debt to be deducted
        totalAdv += (a['amount'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        for (final d in driverMap.keys) {
          double driverAdvDebt = 0;
          for (final a in advSnapshot) {
            if (a['driver_id'] == d) {
              driverAdvDebt += (a['amount'] as num?)?.toDouble() ?? 0;
            }
          }
          driverMap[d]!['net_payout'] = (driverMap[d]!['earnings'] as double) - driverAdvDebt;
          driverMap[d]!['advance_taken'] = driverAdvDebt;
        }

        setState(() {
          _totalTrips   = tripsSnapshot.length;
          _totalKm      = totalKm;
          _totalAdvance = totalAdv;
          _totalIssues  = issueSnapshot.length;
          _driverStats  = driverMap.values.toList()
            ..sort((a, b) => (b['km'] as double).compareTo(a['km'] as double));
        });
      }
    } catch (e) {
      debugPrint('Admin report error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    // Generate list of last 12 months for a COMPACT selection (no more giant datepicker)
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      return DateTime(now.year, now.month - i);
    });

    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final offset = button != null ? button.localToGlobal(Offset.zero) : Offset.zero;

    final picked = await showMenu<DateTime>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx + 200, offset.dy + 80, 20, 0),
      color: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      items: months.map((m) {
        final label = DateFormat('MMMM yyyy').format(m);
        final isSelected = m.year == _selectedMonth.year && m.month == _selectedMonth.month;
        return PopupMenuItem<DateTime>(
          value: m,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: isSelected ? _indigo : Colors.grey[400],
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? _indigo : _headerBg,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    if (picked != null && mounted) {
      if (picked.year != _selectedMonth.year || picked.month != _selectedMonth.month) {
        setState(() => _selectedMonth = DateTime(picked.year, picked.month));
        _fetchReportData();
      }
    }
  }

  void _exportCsv() {
    final monthLabel = DateFormat('MMMM_yyyy').format(_selectedMonth);
    final buf = StringBuffer();
    buf.writeln('Fleet Monthly Report — ${DateFormat('MMMM yyyy').format(_selectedMonth)}');
    buf.writeln('Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    buf.writeln();
    buf.writeln('SUMMARY');
    buf.writeln('Total Trips,$_totalTrips');
    buf.writeln('Total KM,${_totalKm.toStringAsFixed(2)}');
    buf.writeln('Advances Paid (₹),${_totalAdvance.toStringAsFixed(2)}');
    buf.writeln('Issues,$_totalIssues');
    buf.writeln();
    buf.writeln('DRIVER BREAKDOWN');
    buf.writeln('Driver Name,Trips,KM Driven,Advance+10%,Net Payout');
    for (final d in _driverStats) {
      buf.writeln('${d['name']},${d['trips']},${(d['km'] as double).toStringAsFixed(2)},${(d['advance_taken'] as double).toStringAsFixed(2)},${(d['net_payout'] as double).toStringAsFixed(2)}');
    }
    try {
      downloadCsv(buf.toString(), 'fleet_report_$monthLabel.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('✅ CSV downloaded'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Export error: $e');
    }
  }

  void _printReport() => printPage();

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _headerBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Monthly Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_month, color: Colors.white70, size: 18),
            label: Text(monthLabel, style: const TextStyle(color: Colors.white70)),
            onPressed: _pickMonth,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white70),
            tooltip: 'Export CSV',
            onPressed: _isLoading ? null : _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded, color: Colors.white70),
            tooltip: 'Print',
            onPressed: _isLoading ? null : _printReport,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : RefreshIndicator(
          onRefresh: _fetchReportData,
              color: _indigo,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Month banner ──
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _pickMonth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.calendar_month, color: _indigo, size: 16),
                          const SizedBox(width: 6),
                          Text(monthLabel,
                              style: TextStyle(
                                  color: _headerBg, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, color: Colors.grey[500], size: 18),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── KPI Cards ──
                  isWide
                      ? Row(children: [
                          Expanded(child: _KpiCard(label: 'Total Trips', value: '$_totalTrips', icon: Icons.local_shipping_rounded, color: _blue, bgColor: const Color(0xFFEFF6FF))),
                          const SizedBox(width: 14),
                          Expanded(child: _KpiCard(label: 'Total KM', value: '${_totalKm.toStringAsFixed(1)} km', icon: Icons.route_rounded, color: _green, bgColor: const Color(0xFFECFDF5))),
                          const SizedBox(width: 14),
                          Expanded(child: _KpiCard(label: 'Advances Paid', value: '₹${_totalAdvance.toStringAsFixed(0)}', icon: Icons.payments_rounded, color: _amber, bgColor: const Color(0xFFFFFBEB))),
                          const SizedBox(width: 14),
                          Expanded(child: _KpiCard(label: 'Issues', value: '$_totalIssues', icon: Icons.warning_rounded, color: _red, bgColor: const Color(0xFFFEF2F2))),
                        ])
                      : GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.55,
                          children: [
                            _KpiCard(label: 'Total Trips', value: '$_totalTrips', icon: Icons.local_shipping_rounded, color: _blue, bgColor: const Color(0xFFEFF6FF)),
                            _KpiCard(label: 'Total KM', value: '${_totalKm.toStringAsFixed(1)} km', icon: Icons.route_rounded, color: _green, bgColor: const Color(0xFFECFDF5)),
                            _KpiCard(label: 'Advances Paid', value: '₹${_totalAdvance.toStringAsFixed(0)}', icon: Icons.payments_rounded, color: _amber, bgColor: const Color(0xFFFFFBEB)),
                            _KpiCard(label: 'Issues', value: '$_totalIssues', icon: Icons.warning_rounded, color: _red, bgColor: const Color(0xFFFEF2F2)),
                          ],
                        ),
                  const SizedBox(height: 16),

                  // ── Hero Summary Card ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF6D28D9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _indigo.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insights_rounded, color: Colors.white, size: 40),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Fleet Overview', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text('${_totalKm.toStringAsFixed(1)} km',
                                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                              const Text('Total KM driven this month', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: Colors.white70),
                          onPressed: _exportCsv,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Driver list header ──
                  Row(children: [
                    Text('Working Drivers',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: _headerBg)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${_driverStats.length} drivers',
                          style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ── Driver list ──
                  if (_driverStats.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: Column(children: [
                        Icon(Icons.bar_chart_outlined, size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No trip data this month',
                            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                      ]),
                    )
                  else
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: _buildDriverCards(),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDriverCards() {
    final maxKm = (_driverStats.isNotEmpty ? _driverStats.first['km'] as double : 1.0).clamp(1.0, double.infinity);

    // Rank badge colors
    final rankColors = [const Color(0xFFFFD700), const Color(0xFF94A3B8), const Color(0xFFCD7F32)];
    final rankBgs    = [const Color(0xFFFFFBEB), const Color(0xFFF8FAFC), const Color(0xFFFFF7ED)];

    return List.generate(_driverStats.length, (i) {
      final d    = _driverStats[i];
      final km   = d['km'] as double;
      final progress = km / maxKm;
      final net  = (d['net_payout'] as double?) ?? 0.0;
      final adv  = (d['advance_taken'] as double?) ?? 0.0;
      final rankColor = i < 3 ? rankColors[i] : Colors.grey;
      final rankBg    = i < 3 ? rankBgs[i]    : const Color(0xFFF1F5F9);

      return Container(
        width: 280, // Card width
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Rank
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _headerBg.withOpacity(0.02),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: rankBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: rankColor.withOpacity(0.4)),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: rankColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Rank #${i + 1}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (i == 0)
                    const Icon(Icons.stars, color: Color(0xFFFFD700), size: 16),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name & Total Trips
                  // Name & Total Trips (Adjusted font size & padding for 'long looks')
                  SizedBox(
                    height: 24,
                    child: Text(
                      d['name'] as String,
                      style: TextStyle(
                        color: _headerBg,
                        fontWeight: FontWeight.w700,
                        fontSize: 15, // Slightly smaller than 16 for better fit
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d['trips']} Total Trips',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(_indigo.withOpacity(0.6)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Key Metrics Row
                  Row(
                    children: [
                      // KM Capsule
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${km.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  color: _green,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const Text(
                                'KM',
                                style: TextStyle(
                                  color: _green,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Payout Capsule
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: net < 0 ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '₹${net.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: net < 0 ? _amber : _blue,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                net < 0 ? 'DUE' : 'PAYOUT',
                                style: TextStyle(
                                  color: net < 0 ? _amber : _blue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  if (adv > 0) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_edu, size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          'Adv. Taken: ₹${adv.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── KPI Card ───────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bgColor;
  const _KpiCard({required this.label, required this.value, required this.icon, required this.color, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bgColor),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 12),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]),
    );
  }
}

void printPage() {
  // Placeholder for print functionality
}
