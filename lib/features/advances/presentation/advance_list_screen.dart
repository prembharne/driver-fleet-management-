import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'advance_request_screen.dart';

class AdvanceListScreen extends StatefulWidget {
  const AdvanceListScreen({super.key});

  @override
  State<AdvanceListScreen> createState() => _AdvanceListScreenState();
}

class _AdvanceListScreenState extends State<AdvanceListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('advance_requests')
          .select()
          .eq('driver_id', userId)
          .order('created_at', ascending: false);
      if (mounted) setState(() => _requests = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Error fetching advances: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved': return Icons.check_circle;
      case 'rejected': return Icons.cancel;
      default: return Icons.access_time_filled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advance Requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvanceRequestScreen()));
          _fetchRequests();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payment, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No advance requests yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchRequests,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final req = _requests[index];
                      final status = req['status'] as String? ?? 'pending';
                      final date = DateTime.tryParse(req['created_at'] ?? '');
                      final dateStr = date != null
                          ? '${date.day}/${date.month}/${date.year}'
                          : '';
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status).withOpacity(0.1),
                            child: Icon(_statusIcon(status), color: _statusColor(status)),
                          ),
                          title: Row(
                            children: [
                              Text(req['purpose'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('₹${req['amount']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((req['remarks'] ?? '').isNotEmpty)
                                Text(req['remarks'], style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(status.toUpperCase(),
                                        style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const Spacer(),
                                  Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              if (status == 'rejected' && (req['rejection_reason'] ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Reason: ${req['rejection_reason']}',
                                      style: const TextStyle(color: Colors.red, fontSize: 11)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
