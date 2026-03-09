import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Technical Support screen — drivers can submit support tickets
/// and view their existing ticket history.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _supabase = Supabase.instance.client;
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _tickets = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Fetch the driver's existing support tickets.
  Future<void> _fetchTickets() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      final response = await _supabase
          .from('support_tickets')
          .select('*')
          .eq('driver_id', uid)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching tickets: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Submit a new support ticket.
  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      await _supabase.from('support_tickets').insert({
        'driver_id': uid,
        'subject': _subjectController.text.trim(),
        'description': _descriptionController.text.trim(),
        'status': 'open',
      });

      _subjectController.clear();
      _descriptionController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ticket submitted successfully!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pop(context); // Close the dialog
        _fetchTickets();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Show the create ticket dialog.
  void _showCreateTicketDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report an Issue'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g., App not loading GPS',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a subject' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe your issue in detail...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please describe the issue' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitTicket,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }

  /// Psychology-based status colors.
  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
      case 'closed':
        return const Color(0xFF2E7D32); // Green — resolved/safe
      case 'in_progress':
        return const Color(0xFF1565C0); // Blue — being handled
      default:
        return const Color(0xFFF57C00); // Amber — awaiting action
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Technical Support'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTicketDialog,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.support_agent, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No support tickets yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to report an issue',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchTickets,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final ticket = _tickets[index];
                      final status = ticket['status'] as String? ?? 'open';
                      final createdAt = ticket['created_at'] as String?;
                      String dateStr = '';
                      if (createdAt != null) {
                        final date = DateTime.tryParse(createdAt);
                        if (date != null) {
                          dateStr = '${date.day}/${date.month}/${date.year}';
                        }
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status).withOpacity(0.12),
                            child: Icon(
                              status == 'resolved' || status == 'closed'
                                  ? Icons.check_circle
                                  : status == 'in_progress'
                                      ? Icons.autorenew
                                      : Icons.error_outline,
                              color: _statusColor(status),
                            ),
                          ),
                          title: Text(
                            ticket['subject'] ?? 'No Subject',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dateStr.isNotEmpty)
                                Text(dateStr, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  status.replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
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
