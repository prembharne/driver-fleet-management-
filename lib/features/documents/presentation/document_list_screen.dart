import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'document_upload_screen.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  Map<String, Map<String, dynamic>> _docStatus = {};

  final List<Map<String, String>> _requiredDocs = [
    {'type': 'pan', 'label': 'PAN Card'},
    {'type': 'aadhaar', 'label': 'Aadhaar Card'},
    {'type': 'license', 'label': 'Driving License'},
    {'type': 'rc', 'label': 'Vehicle RC Book'},
    {'type': 'number_plate', 'label': 'Vehicle Number Plate Photo'},
    {'type': 'driver_photo', 'label': 'Driver Self Photo'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
  }

  Future<void> _fetchDocuments() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final userId = user.id;

      // Fetch documents from Supabase
      final response = await _supabase
          .from('documents')
          .select('*')
          .eq('driver_id', userId);

      final Map<String, Map<String, dynamic>> statusMap = {};
      for (var data in response) {
        statusMap[data['type'] as String] = Map<String, dynamic>.from(data);
      }

      if (mounted) {
        setState(() {
          _docStatus = statusMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching docs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Returns true if the driver is LOCKED from editing/submitting this doc.
  /// Locked = status is 'pending' or 'verified'.
  bool _isLocked(String? status) =>
      status == 'pending' || status == 'verified';

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'verified':  return Colors.green;
      case 'rejected':  return Colors.red;
      case 'pending':   return Colors.orange;
      default:          return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'verified':  return Icons.check_circle_rounded;
      case 'rejected':  return Icons.cancel_rounded;
      case 'pending':   return Icons.hourglass_top_rounded;
      default:          return Icons.upload_file_rounded;
    }
  }

  String _lockMessage(String? status) {
    if (status == 'verified') return 'Approved ✓ — contact admin to make changes';
    if (status == 'pending')  return 'Under review — cannot edit until outcome is known';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDocuments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Once submitted, documents cannot be changed until the admin reviews them.',
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _requiredDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final docType = _requiredDocs[index]['type']!;
                      final label = _requiredDocs[index]['label']!;
                      final doc = _docStatus[docType];
                      final status = doc?['status'] as String?;
                      final locked = _isLocked(status);

                      return Card(
                        elevation: locked ? 0 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: locked
                                ? _getStatusColor(status).withOpacity(0.4)
                                : Colors.transparent,
                          ),
                        ),
                        color: locked ? Colors.grey.shade50 : Colors.white,
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor:
                                _getStatusColor(status).withOpacity(0.12),
                            child: Icon(
                              _getStatusIcon(status),
                              color: _getStatusColor(status),
                            ),
                          ),
                          title: Text(label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: locked ? Colors.black54 : Colors.black87,
                              )),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (status == 'rejected') ...[
                                Text('Rejected: ${doc?['rejection_reason'] ?? 'No reason given'}',
                                    style: const TextStyle(color: Colors.red, fontSize: 12)),
                                const Text('Tap to re-submit',
                                    style: TextStyle(color: Colors.blue, fontSize: 11)),
                              ] else if (status != null) ...[
                                Text(status.toUpperCase(),
                                    style: TextStyle(
                                        color: _getStatusColor(status), fontSize: 12)),
                                if (locked)
                                  Text(_lockMessage(status),
                                      style: const TextStyle(color: Colors.black38, fontSize: 11)),
                              ] else
                                const Text('Tap to upload',
                                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          trailing: locked
                              ? Icon(Icons.lock_rounded,
                                  color: _getStatusColor(status).withOpacity(0.7), size: 20)
                              : const Icon(Icons.chevron_right),
                          onTap: locked
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(_lockMessage(status)),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: _getStatusColor(status),
                                  ));
                                }
                              : () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DocumentUploadScreen(
                                        docType: docType,
                                        label: label,
                                        existingDoc: doc,
                                      ),
                                    ),
                                  );
                                  _fetchDocuments();
                                },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
