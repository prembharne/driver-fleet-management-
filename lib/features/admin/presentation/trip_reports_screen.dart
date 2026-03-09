import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

/// Admin screen: Trip history with KM details and export to Excel/PDF
class TripReportsScreen extends StatefulWidget {
  const TripReportsScreen({super.key});

  @override
  State<TripReportsScreen> createState() => _TripReportsScreenState();
}

class _TripReportsScreenState extends State<TripReportsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;
  DateTime? _filterFrom;
  DateTime? _filterTo;

  // Summary stats
  int _totalTrips = 0;
  double _totalKm = 0.0;
  int _completedTrips = 0;
  int _activeTrips = 0;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase
          .from('trips')
          .select()
          .order('started_at', ascending: false);

      final response = await query;
      final trips = List<Map<String, dynamic>>.from(response);

      // Apply date filters client-side
      List<Map<String, dynamic>> filteredTrips = trips;
      if (_filterFrom != null) {
        filteredTrips = filteredTrips.where((t) {
          final startedAt = DateTime.tryParse(t['started_at'] ?? '');
          return startedAt != null && startedAt.isAfter(_filterFrom!);
        }).toList();
      }
      if (_filterTo != null) {
        filteredTrips = filteredTrips.where((t) {
          final startedAt = DateTime.tryParse(t['started_at'] ?? '');
          return startedAt != null &&
              startedAt.isBefore(_filterTo!.add(const Duration(days: 1)));
        }).toList();
      }

      // Calculate stats
      double totalKm = 0;
      int completed = 0;
      int active = 0;
      for (final trip in filteredTrips) {
        totalKm += (trip['total_distance_km'] ?? 0.0).toDouble();
        if (trip['status'] == 'completed') completed++;
        if (trip['status'] == 'active') active++;
      }

      setState(() {
        _trips = filteredTrips;
        _totalTrips = filteredTrips.length;
        _totalKm = totalKm;
        _completedTrips = completed;
        _activeTrips = active;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading trips: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _filterFrom != null && _filterTo != null
          ? DateTimeRange(start: _filterFrom!, end: _filterTo!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE53935),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterFrom = picked.start;
        _filterTo = picked.end;
      });
      _loadTrips();
    }
  }

  void _clearFilters() {
    setState(() {
      _filterFrom = null;
      _filterTo = null;
    });
    _loadTrips();
  }

  // ─── Export to CSV/Excel ─────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    if (_trips.isEmpty) {
      _showSnackbar('No trips to export', isError: true);
      return;
    }

    try {
      final List<List<String>> rows = [
        [
          'Trip ID',
          'Driver ID',
          'Start Location',
          'End Location',
          'Distance (KM)',
          'Status',
          'Started At',
          'Completed At',
        ],
      ];

      for (final trip in _trips) {
        rows.add([
          (trip['id'] ?? '').toString(),
          (trip['driver_id'] ?? '').toString(),
          (trip['start_location'] ?? '').toString(),
          (trip['end_location'] ?? '').toString(),
          (trip['total_distance_km'] ?? 0.0).toStringAsFixed(2),
          (trip['status'] ?? '').toString(),
          _formatDateTime(trip['started_at']),
          _formatDateTime(trip['completed_at']),
        ]);
      }

      final csvData = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/trip_report_$timestamp.csv');
      await file.writeAsString(csvData);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Trip KM Report',
        text: 'Trip report exported on ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
      );

      _showSnackbar('CSV report exported successfully');
    } catch (e) {
      _showSnackbar('Error exporting CSV: $e', isError: true);
    }
  }

  // ─── Export to PDF ──────────────────────────────────────────────────────

  Future<void> _exportPDF() async {
    if (_trips.isEmpty) {
      _showSnackbar('No trips to export', isError: true);
      return;
    }

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Trip KM Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
              if (_filterFrom != null && _filterTo != null)
                pw.Text(
                  'Period: ${DateFormat('dd MMM yyyy').format(_filterFrom!)} - ${DateFormat('dd MMM yyyy').format(_filterTo!)}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text('Total Trips: $_totalTrips', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(width: 16),
                  pw.Text('Total KM: ${_totalKm.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(width: 16),
                  pw.Text('Completed: $_completedTrips', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
            ],
          ),
          build: (context) {
            return [
              pw.TableHelper.fromTextArray(
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellPadding: const pw.EdgeInsets.all(6),
                headers: [
                  'S.No',
                  'Driver ID',
                  'Start Location',
                  'End Location',
                  'Distance (KM)',
                  'Status',
                  'Started At',
                  'Completed At',
                ],
                data: List.generate(_trips.length, (index) {
                  final trip = _trips[index];
                  return [
                    '${index + 1}',
                    (trip['driver_id'] ?? '').toString(),
                    (trip['start_location'] ?? '-').toString(),
                    (trip['end_location'] ?? '-').toString(),
                    (trip['total_distance_km'] ?? 0.0).toStringAsFixed(2),
                    (trip['status'] ?? '').toString(),
                    _formatDateTime(trip['started_at']),
                    _formatDateTime(trip['completed_at']),
                  ];
                }),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/trip_report_$timestamp.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Trip KM Report (PDF)',
        text: 'Trip report exported on ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
      );

      _showSnackbar('PDF report exported successfully');
    } catch (e) {
      _showSnackbar('Error exporting PDF: $e', isError: true);
    }
  }

  String _formatDateTime(dynamic dateStr) {
    if (dateStr == null) return '-';
    final dt = DateTime.tryParse(dateStr.toString());
    if (dt == null) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Reports'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.headset_mic_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary stats
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStatChip(
                  Icons.receipt_long,
                  '$_totalTrips',
                  'Trips',
                  const Color(0xFFE53935),
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.straighten,
                  _totalKm.toStringAsFixed(1),
                  'KM',
                  const Color(0xFF1976D2),
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.check_circle,
                  '$_completedTrips',
                  'Done',
                  const Color(0xFF388E3C),
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.play_circle,
                  '$_activeTrips',
                  'Active',
                  const Color(0xFFF57C00),
                ),
              ],
            ),
          ),

          // Filter bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _filterFrom != null
                              ? const Color(0xFFE53935)
                              : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: _filterFrom != null
                                ? const Color(0xFFE53935)
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _filterFrom != null && _filterTo != null
                                  ? '${DateFormat('dd MMM').format(_filterFrom!)} - ${DateFormat('dd MMM').format(_filterTo!)}'
                                  : 'Select date range',
                              style: TextStyle(
                                fontSize: 13,
                                color: _filterFrom != null
                                    ? const Color(0xFFE53935)
                                    : Colors.grey[600],
                                fontWeight: _filterFrom != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (_filterFrom != null)
                            GestureDetector(
                              onTap: _clearFilters,
                              child: const Icon(Icons.close, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildExportButton(
                  icon: Icons.table_chart_outlined,
                  label: 'CSV',
                  color: const Color(0xFF388E3C),
                  onTap: _exportExcel,
                ),
                const SizedBox(width: 8),
                _buildExportButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  color: const Color(0xFFE53935),
                  onTap: _exportPDF,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Trip list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _trips.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 56,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No trips found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try changing the date filter',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTrips,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _trips.length,
                          itemBuilder: (context, index) {
                            return _buildTripRow(_trips[index], index + 1);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripRow(Map<String, dynamic> trip, int index) {
    final status = trip['status'] ?? 'unknown';
    final distance = (trip['total_distance_km'] ?? 0.0).toDouble();
    final startedAt = DateTime.tryParse(trip['started_at'] ?? '');
    final completedAt = DateTime.tryParse(trip['completed_at'] ?? '');

    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = Colors.green;
        break;
      case 'paused':
        statusColor = Colors.orange;
        break;
      case 'completed':
        statusColor = const Color(0xFF1976D2);
        break;
      default:
        statusColor = Colors.grey;
    }

    String duration = '-';
    if (startedAt != null && completedAt != null) {
      final diff = completedAt.difference(startedAt);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      duration = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Driver: ${trip['driver_id'] ?? '-'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _buildTripStat(
                Icons.straighten,
                '${distance.toStringAsFixed(2)} km',
              ),
              const SizedBox(width: 16),
              _buildTripStat(Icons.timer, duration),
              const SizedBox(width: 16),
              _buildTripStat(
                Icons.access_time,
                startedAt != null
                    ? DateFormat('dd/MM HH:mm').format(startedAt)
                    : '-',
              ),
            ],
          ),

          // Location
          if (trip['start_location'] != null || trip['end_location'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.green[400]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${trip['start_location'] ?? '-'}  →  ${trip['end_location'] ?? '-'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
