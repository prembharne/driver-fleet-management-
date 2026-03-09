import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin screen to review, approve, or reject documents submitted by drivers.
/// Documents are locked once submitted — driver cannot edit pending/verified docs.
/// Uses Supabase for data + storage.
class AdminDocumentReviewScreen extends StatefulWidget {
  const AdminDocumentReviewScreen({super.key});

  @override
  State<AdminDocumentReviewScreen> createState() => _AdminDocumentReviewScreenState();
}

class _AdminDocumentReviewScreenState extends State<AdminDocumentReviewScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  
  bool _loading = true;
  List<Map<String, dynamic>> _docs = [];
  String _filterStatus = 'all';

  static const _bg = Color(0xFF0F1117);
  static const _card = Color(0xFF1C1F2A);

  late TabController _tabController;
  final List<String> _tabs = ['All', 'Pending', 'Verified', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _filterStatus = ['all', 'pending', 'verified', 'rejected'][_tabController.index];
        });
      }
    });
    _fetchDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchDocuments() async {
    setState(() => _loading = true);
    try {
      // Fetch documents from Supabase
      final querySnapshot = await _supabase
          .from('documents')
          .select('*')
          .order('updated_at', ascending: false);

      // ── Batch-fetch all unique driver profiles in ONE call ──
      final Set<String> driverIds = {};
      for (final data in querySnapshot) {
        final id = data['driver_id'] as String?;
        if (id != null && id.isNotEmpty) driverIds.add(id);
      }

      final Map<String, Map<String, dynamic>> profileCache = {};
      if (driverIds.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('profiles')
              .select('*')
              .inFilter('id', driverIds.toList());
          for (final p in profiles) {
            profileCache[p['id'] as String] = p;
          }
        } catch (e) {
          debugPrint('Error batch-fetching profiles: $e');
        }
      }

      final docs = <Map<String, dynamic>>[];
      for (var data in querySnapshot) {
        final driverId = data['driver_id'] as String?;
        if (driverId != null && profileCache.containsKey(driverId)) {
          data['driver_profile'] = profileCache[driverId];
        }
        docs.add(data);
      }

      if (mounted) {
        setState(() {
          _docs = docs;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch docs error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterStatus == 'all') return _docs;
    return _docs.where((d) => (d['status'] as String?) == _filterStatus).toList();
  }

  Future<void> _updateStatus(String docId, String newStatus, {String? rejectionReason}) async {
    try {
      final update = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (rejectionReason != null) update['rejection_reason'] = rejectionReason;
      
      await _supabase.from('documents').update(update).eq('id', docId);
      await _fetchDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newStatus == 'verified' ? '✅ Document approved!' : '❌ Document rejected.'),
          backgroundColor: newStatus == 'verified' ? Colors.green : Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showRejectDialog(String docId) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Reject Document', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Reason for rejection...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(docId, 'rejected', rejectionReason: ctrl.text.trim());
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  /// Get document image URL from Supabase Storage
  String? _getDocumentUrl(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    return filePath;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Document Review', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchDocuments),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF4F8EF7),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDocuments,
              child: filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.folder_off_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('No documents found',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16)),
                      ]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _DocCard(
                        doc: filtered[i],
                        getDocumentUrl: _getDocumentUrl,
                        onApprove: () => _updateStatus(filtered[i]['id'] as String, 'verified'),
                        onReject: () => _showRejectDialog(filtered[i]['id'] as String),
                      ),
                    ),
            ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final String? Function(String?) getDocumentUrl;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DocCard({
    required this.doc, 
    required this.getDocumentUrl,
    required this.onApprove, 
    required this.onReject
  });

  static const _card = Color(0xFF1C1F2A);

  Color _statusColor(String? s) {
    switch (s) {
      case 'verified': return Colors.green;
      case 'rejected': return Colors.red;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'verified': return Icons.check_circle_rounded;
      case 'rejected': return Icons.cancel_rounded;
      case 'pending': return Icons.hourglass_top_rounded;
      default: return Icons.help_outline;
    }
  }

  String _docTypeLabel(String? type) {
    switch (type) {
      case 'pan': return 'PAN Card';
      case 'aadhaar': return 'Aadhaar Card';
      case 'license': return 'Driving License';
      case 'rc': return 'Vehicle RC Book';
      default: return type ?? 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = doc['status'] as String?;
    final profile = doc['driver_profile'] as Map<String, dynamic>?;
    final driverName = profile?['full_name'] as String? ?? 'Unknown Driver';
    final phone = profile?['phone_number'] as String? ?? '';
    final docNumber = doc['document_number'] as String? ?? 'N/A';
    final expiryDate = doc['expiry_date'] as String?;
    final rejReason = doc['rejection_reason'] as String?;
    final sc = _statusColor(status);
    final filePath = doc['file_path'] as String?;
    final docUrl = getDocumentUrl(filePath);

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sc.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            // Document thumbnail
            if (docUrl != null)
              GestureDetector(
                onTap: () => _showImageDialog(context, docUrl),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: Colors.white54),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: sc.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_statusIcon(status), color: sc, size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_docTypeLabel(doc['type'] as String?),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(driverName, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sc.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sc.withOpacity(0.4)),
              ),
              child: Text((status ?? 'unknown').toUpperCase(),
                  style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 12),
          // Details row
          Wrap(spacing: 16, runSpacing: 6, children: [
            _chip(Icons.tag, 'Doc #: $docNumber'),
            if (expiryDate != null) _chip(Icons.event, 'Expiry: $expiryDate'),
          ]),
          if (rejReason != null && rejReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text('Reason: $rejReason',
                    style: const TextStyle(color: Colors.red, fontSize: 12))),
              ]),
            ),
          ],
          // Action buttons — only for pending docs
          if (status == 'pending') ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  label: const Text('Reject', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(40),
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.white38),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}
