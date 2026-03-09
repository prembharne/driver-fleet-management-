import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAdvanceDashboard extends StatefulWidget {
  const AdminAdvanceDashboard({super.key});

  @override
  State<AdminAdvanceDashboard> createState() => _AdminAdvanceDashboardState();
}

class _AdminAdvanceDashboardState extends State<AdminAdvanceDashboard> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> snapshot;
      
      if (_filter == 'all') {
        snapshot = await _supabase
            .from('advance_requests')
            .select('*')
            .order('created_at', ascending: false);
      } else {
        snapshot = await _supabase
            .from('advance_requests')
            .select('*')
            .eq('status', _filter)
            .order('created_at', ascending: false);
      }

      // ── Batch-fetch all unique driver profiles in ONE call ──
      final Set<String> driverIds = {};
      for (final data in snapshot) {
        final id = data['driver_id'] as String?;
        if (id != null && id.isNotEmpty) driverIds.add(id);
      }

      final Map<String, String> nameCache = {};
      if (driverIds.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', driverIds.toList());
          for (final p in profiles) {
            nameCache[p['id'] as String] = p['full_name'] as String? ?? 'Unknown Driver';
          }
        } catch (e) {
          debugPrint('Error batch-fetching profiles: $e');
        }
      }

      final requests = <Map<String, dynamic>>[];
      for (var data in snapshot) {
        final driverId = data['driver_id'] as String? ?? '';
        requests.add({
          'id': data['id'],
          ...data,
          'driver_name': nameCache[driverId] ?? 'Unknown Driver',
        });
      }

      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      debugPrint('Error fetching advances: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String id, String status, {String? reason}) async {
    try {
      final update = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (reason != null) update['rejection_reason'] = reason;
      
      await _supabase.from('advance_requests').update(update).eq('id', id);
      _fetchRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRejectDialog(String id) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rejection Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter reason...', border: OutlineInputBorder()),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _updateStatus(id, 'rejected', reason: controller.text);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  /// Psychology-based colors: green = safety/approval, red = alert/rejection,
  /// amber = caution/awaiting action.
  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return const Color(0xFF2E7D32); // Calm green — safety
      case 'rejected': return const Color(0xFFC62828); // Strong red — alert
      default: return const Color(0xFFF57C00);         // Warm amber — caution
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Advance Requests'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['pending', 'approved', 'rejected', 'all'].map((f) {
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.toUpperCase()),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _fetchRequests();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, size: 56, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No $_filter requests', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _fetchRequests,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final req = _requests[index];
                      final status = req['status'] as String? ?? 'pending';
                      final driverName = req['driver_name'] ?? 'Unknown Driver';
                      final amount = req['amount'];
                      final purpose = req['purpose'] ?? '';
                      final remarks = req['remarks'] ?? '';

                      // Format date
                      final createdAt = req['created_at'];
                      String dateStr = '';
                      if (createdAt != null && createdAt is String) {
                        final date = DateTime.tryParse(createdAt);
                        if (date != null) {
                          dateStr = '${date.day}/${date.month}/${date.year}';
                        }
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Header row: driver name + status chip ──
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                              child: Row(
                                children: [
                                  // Driver avatar
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: _statusColor(status).withOpacity(0.15),
                                    child: Icon(Icons.person, color: _statusColor(status), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(driverName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                        if (dateStr.isNotEmpty)
                                          Text(dateStr, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  // Status chip with psychology colors
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 20),
                            // ── Detail rows ──
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: Row(
                                children: [
                                  // Amount
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Requested', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                        const SizedBox(height: 2),
                                        Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1565C0))),
                                      ],
                                    ),
                                  ),
                                  // Final Payout 
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Payout (After 10%)', style: TextStyle(color: Colors.orange[800], fontSize: 11)),
                                        const SizedBox(height: 2),
                                        Text('₹${(amount as num).toDouble() * 0.90}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                                      ],
                                    ),
                                  ),
                                  // Purpose
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Purpose', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                        const SizedBox(height: 2),
                                        Text(purpose, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (remarks.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: Text('Remarks: $remarks', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic)),
                              ),
                            // ── Action buttons for pending ──
                            if (status == 'pending')
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showRejectDialog(req['id']),
                                        icon: const Icon(Icons.close, size: 18),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _updateStatus(req['id'], 'approved'),
                                        icon: const Icon(Icons.check, size: 18),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2E7D32),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const SizedBox(height: 14),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
